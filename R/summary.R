source("R/utils.R", encoding = "UTF-8")
source("R/admin.R", encoding = "UTF-8")

read_firms_processed <- function() {
  path <- "data/processed/firms_active_fires.csv"
  if (!file.exists(path) || file.info(path)$size == 0) return(tibble::tibble())

  x <- tryCatch(
    readr::read_csv(path, show_col_types = FALSE),
    error = function(e) tibble::tibble()
  )

  if (nrow(x) == 0 || !all(c("longitude", "latitude") %in% names(x))) {
    return(tibble::tibble())
  }

  x |>
    dplyr::mutate(
      longitude = suppressWarnings(as.numeric(longitude)),
      latitude = suppressWarnings(as.numeric(latitude)),
      frp = suppressWarnings(as.numeric(frp)),
      age_hours = suppressWarnings(as.numeric(age_hours)),
      acq_datetime_utc = as.character(acq_datetime_utc)
    ) |>
    dplyr::filter(!is.na(longitude), !is.na(latitude))
}

fires_to_sf <- function(fires) {
  if (nrow(fires) == 0 || !requireNamespace("sf", quietly = TRUE)) return(NULL)
  sf::st_as_sf(fires, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
}

safe_numeric_max <- function(x) {
  value <- suppressWarnings(max(x, na.rm = TRUE))
  if (length(value) == 0 || is.infinite(value)) NA_real_ else value
}

safe_numeric_min <- function(x) {
  value <- suppressWarnings(min(x, na.rm = TRUE))
  if (length(value) == 0 || is.infinite(value)) NA_real_ else value
}

safe_character_max <- function(x) {
  values <- as.character(x)
  values <- values[!is.na(values) & nzchar(values)]
  if (length(values) == 0) NA_character_ else max(values)
}

summarise_firms_by_admin <- function(fires_sf, admin_sf, level_label) {
  if (is.null(fires_sf) || is.null(admin_sf) || nrow(fires_sf) == 0 || nrow(admin_sf) == 0) {
    return(tibble::tibble())
  }

  admin_simple <- admin_sf |>
    dplyr::select(admin_level, admin_id, admin_name)

  joined <- tryCatch(
    sf::st_join(fires_sf, admin_simple, join = sf::st_intersects, left = FALSE),
    error = function(e) {
      warning("No se pudo cruzar FIRMS con ", level_label, ": ", conditionMessage(e), call. = FALSE)
      NULL
    }
  )
  if (is.null(joined) || nrow(joined) == 0) return(tibble::tibble())

  joined |>
    sf::st_drop_geometry() |>
    dplyr::mutate(
      admin_level = level_label,
      frp = suppressWarnings(as.numeric(frp)),
      age_hours = suppressWarnings(as.numeric(age_hours))
    ) |>
    dplyr::group_by(admin_level, admin_id, admin_name) |>
    dplyr::summarise(
      n_focos = dplyr::n(),
      n_ultimas_6h = sum(!is.na(age_hours) & age_hours <= 6),
      n_ultimas_12h = sum(!is.na(age_hours) & age_hours <= 12),
      n_ultimas_24h = sum(!is.na(age_hours) & age_hours <= 24),
      n_ultimas_48h = sum(!is.na(age_hours) & age_hours <= 48),
      frp_total_mw = round(sum(frp, na.rm = TRUE), 1),
      frp_media_mw = round(mean(frp, na.rm = TRUE), 1),
      frp_max_mw = round(safe_numeric_max(frp), 1),
      edad_min_h = round(safe_numeric_min(age_hours), 1),
      ultima_deteccion_utc = safe_character_max(acq_datetime_utc),
      sensores = paste(sort(unique(stats::na.omit(source_dataset))), collapse = ", "),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      frp_media_mw = dplyr::if_else(is.nan(frp_media_mw), NA_real_, frp_media_mw),
      alerta_operativa = dplyr::case_when(
        n_ultimas_6h > 0 & frp_total_mw >= 100 ~ "alta",
        n_ultimas_6h > 0 ~ "media",
        n_ultimas_24h > 0 ~ "seguimiento",
        TRUE ~ "informativa"
      )
    ) |>
    dplyr::arrange(
      dplyr::desc(n_ultimas_6h),
      dplyr::desc(n_focos),
      dplyr::desc(frp_total_mw),
      admin_name
    )
}

read_effis_burnt_areas_for_summary <- function() {
  if (!requireNamespace("sf", quietly = TRUE)) return(NULL)

  candidates <- c(
    "assets/effis_ba/effis_burnt_areas.geojson",
    "data/processed/effis_burnt_areas.geojson"
  )

  for (path in candidates) {
    if (!file.exists(path) || file.info(path)$size == 0) next

    x <- tryCatch(sf::st_read(path, quiet = TRUE), error = function(e) NULL)
    if (is.null(x) || nrow(x) == 0) next

    x <- force_wgs84_lonlat(x)
    if (!"effis_area_ha" %in% names(x)) {
      x$effis_area_ha <- suppressWarnings(as.numeric(x$AREA_HA %||% NA_real_))
    }
    if (!"effis_date" %in% names(x)) {
      x$effis_date <- as.character(x$FIREDATE %||% NA_character_)
    }

    return(
      x |>
        dplyr::mutate(
          effis_area_ha = suppressWarnings(as.numeric(effis_area_ha)),
          effis_date = suppressWarnings(as.Date(effis_date))
        )
    )
  }

  NULL
}

summarise_effis_by_admin <- function(effis_sf, admin_sf, level_label, today = Sys.Date()) {
  if (is.null(effis_sf) || is.null(admin_sf) || nrow(effis_sf) == 0 || nrow(admin_sf) == 0) {
    return(tibble::tibble())
  }

  # Se asigna cada perímetro a un único territorio usando un punto interior.
  # Esto evita duplicar superficies cuando una geometría toca más de un límite.
  effis_points <- tryCatch(
    effis_sf |>
      sf::st_make_valid() |>
      sf::st_transform(3035) |>
      sf::st_point_on_surface() |>
      sf::st_transform(4326),
    error = function(e) {
      warning("No se pudieron preparar puntos EFFIS: ", conditionMessage(e), call. = FALSE)
      NULL
    }
  )
  if (is.null(effis_points) || nrow(effis_points) == 0) return(tibble::tibble())

  admin_simple <- admin_sf |>
    dplyr::select(admin_level, admin_id, admin_name)

  joined <- tryCatch(
    sf::st_join(effis_points, admin_simple, join = sf::st_intersects, left = FALSE),
    error = function(e) {
      warning("No se pudo cruzar EFFIS con ", level_label, ": ", conditionMessage(e), call. = FALSE)
      NULL
    }
  )
  if (is.null(joined) || nrow(joined) == 0) return(tibble::tibble())

  joined |>
    sf::st_drop_geometry() |>
    dplyr::mutate(
      admin_level = level_label,
      effis_area_ha = suppressWarnings(as.numeric(effis_area_ha)),
      effis_date = suppressWarnings(as.Date(effis_date)),
      effis_age_days = as.integer(today - effis_date)
    ) |>
    dplyr::group_by(admin_level, admin_id, admin_name) |>
    dplyr::summarise(
      n_effis_30d = sum(!is.na(effis_age_days) & effis_age_days >= 0 & effis_age_days <= 30),
      effis_area_ha_30d = round(sum(
        dplyr::if_else(
          !is.na(effis_age_days) & effis_age_days >= 0 & effis_age_days <= 30,
          dplyr::coalesce(effis_area_ha, 0),
          0
        ),
        na.rm = TRUE
      ), 1),
      n_effis_90d = sum(!is.na(effis_age_days) & effis_age_days >= 0 & effis_age_days <= 90),
      effis_area_ha_90d = round(sum(
        dplyr::if_else(
          !is.na(effis_age_days) & effis_age_days >= 0 & effis_age_days <= 90,
          dplyr::coalesce(effis_area_ha, 0),
          0
        ),
        na.rm = TRUE
      ), 1),
      ultima_area_quemada = {
        values <- effis_date[!is.na(effis_date)]
        if (length(values) == 0) as.Date(NA) else max(values)
      },
      .groups = "drop"
    )
}

representative_admin_points <- function(admin_sf) {
  if (is.null(admin_sf) || nrow(admin_sf) == 0) return(NULL)

  points <- tryCatch(
    admin_sf |>
      sf::st_make_valid() |>
      sf::st_transform(3035) |>
      sf::st_point_on_surface() |>
      sf::st_transform(4326),
    error = function(e) NULL
  )
  if (is.null(points)) return(NULL)

  coords <- sf::st_coordinates(points)
  tibble::tibble(
    admin_id = as.character(points$admin_id),
    representative_lon = as.numeric(coords[, 1]),
    representative_lat = as.numeric(coords[, 2])
  )
}

complete_territorial_summary <- function(
  admin_sf,
  firms_summary,
  effis_summary,
  level_label,
  parent_sf = NULL
) {
  if (is.null(admin_sf) || nrow(admin_sf) == 0) return(tibble::tibble())

  base <- admin_sf |>
    sf::st_drop_geometry() |>
    dplyr::transmute(
      admin_level = level_label,
      admin_id = as.character(admin_id),
      admin_name = as.character(admin_name)
    )

  points <- representative_admin_points(admin_sf)
  if (!is.null(points)) {
    base <- dplyr::left_join(base, points, by = "admin_id")
  } else {
    base$representative_lon <- NA_real_
    base$representative_lat <- NA_real_
  }

  if (!is.null(parent_sf) && nrow(parent_sf) > 0 && !is.null(points)) {
    points_sf <- sf::st_as_sf(
      points,
      coords = c("representative_lon", "representative_lat"),
      crs = 4326,
      remove = FALSE
    )
    parent_simple <- parent_sf |>
      dplyr::transmute(
        parent_admin_id = as.character(admin_id),
        parent_admin_name = as.character(admin_name)
      )

    parent_join <- tryCatch(
      sf::st_join(points_sf, parent_simple, join = sf::st_intersects, left = TRUE) |>
        sf::st_drop_geometry() |>
        dplyr::select(admin_id, parent_admin_id, parent_admin_name),
      error = function(e) NULL
    )

    if (!is.null(parent_join)) {
      base <- dplyr::left_join(base, parent_join, by = "admin_id")
    }
  }

  if (nrow(firms_summary) > 0) {
    base <- dplyr::left_join(
      base,
      firms_summary |> dplyr::select(-admin_level, -admin_name),
      by = "admin_id"
    )
  }

  if (nrow(effis_summary) > 0) {
    base <- dplyr::left_join(
      base,
      effis_summary |> dplyr::select(-admin_level, -admin_name),
      by = "admin_id"
    )
  }

  integer_fields <- c(
    "n_focos", "n_ultimas_6h", "n_ultimas_12h", "n_ultimas_24h",
    "n_ultimas_48h", "n_effis_30d", "n_effis_90d"
  )
  numeric_fields <- c(
    "frp_total_mw", "frp_media_mw", "frp_max_mw",
    "effis_area_ha_30d", "effis_area_ha_90d"
  )

  for (field in integer_fields) {
    if (!field %in% names(base)) base[[field]] <- 0L
    base[[field]][is.na(base[[field]])] <- 0L
    base[[field]] <- as.integer(base[[field]])
  }

  for (field in numeric_fields) {
    if (!field %in% names(base)) base[[field]] <- 0
    base[[field]][is.na(base[[field]])] <- 0
    base[[field]] <- round(as.numeric(base[[field]]), 1)
  }

  if (!"edad_min_h" %in% names(base)) base$edad_min_h <- NA_real_
  if (!"ultima_deteccion_utc" %in% names(base)) base$ultima_deteccion_utc <- NA_character_
  if (!"sensores" %in% names(base)) base$sensores <- ""
  if (!"alerta_operativa" %in% names(base)) base$alerta_operativa <- "sin actividad"
  if (!"ultima_area_quemada" %in% names(base)) base$ultima_area_quemada <- as.Date(NA)

  base$sensores[is.na(base$sensores)] <- ""
  base$alerta_operativa[is.na(base$alerta_operativa) | !nzchar(base$alerta_operativa)] <- "sin actividad"

  base |>
    dplyr::arrange(admin_name)
}

write_territorial_summary <- function(ccaa, provincias, generated_at_utc) {
  readr::write_csv(ccaa, "data/processed/territorial_summary_ccaa.csv")
  readr::write_csv(provincias, "data/processed/territorial_summary_provincias.csv")
  readr::write_csv(ccaa, "assets/summary/territorial_summary_ccaa.csv")
  readr::write_csv(provincias, "assets/summary/territorial_summary_provincias.csv")

  payload <- list(
    generated_at_utc = generated_at_utc,
    methodology = list(
      aemet = "Nivel estimado en el punto representativo interior del territorio para la capa seleccionada.",
      firms = "Detecciones asignadas por intersección puntual con límites GISCO/NUTS.",
      effis = "Áreas asignadas al territorio que contiene el punto representativo de cada perímetro, para evitar duplicidades."
    ),
    ccaa = ccaa,
    provincias = provincias
  )

  jsonlite::write_json(
    payload,
    "data/processed/territorial_summary.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null"
  )
  jsonlite::write_json(
    payload,
    "assets/summary/territorial_summary.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null"
  )
}

make_dashboard_summary <- function() {
  fs::dir_create("data/processed")
  fs::dir_create("assets/summary")

  fires <- read_firms_processed()
  fires_sf <- fires_to_sf(fires)

  nuts2 <- read_admin_layer("data/processed/admin_nuts2_ccaa.geojson")
  nuts3 <- read_admin_layer("data/processed/admin_nuts3_provincias.geojson")

  ccaa <- summarise_firms_by_admin(fires_sf, nuts2, "ccaa")
  provincias <- summarise_firms_by_admin(fires_sf, nuts3, "provincia")

  readr::write_csv(ccaa, "data/processed/firms_summary_ccaa.csv")
  readr::write_csv(provincias, "data/processed/firms_summary_provincias.csv")
  readr::write_csv(ccaa, "assets/summary/firms_summary_ccaa.csv")
  readr::write_csv(provincias, "assets/summary/firms_summary_provincias.csv")

  effis <- read_effis_burnt_areas_for_summary()
  effis_ccaa <- summarise_effis_by_admin(effis, nuts2, "ccaa")
  effis_provincias <- summarise_effis_by_admin(effis, nuts3, "provincia")

  territorial_ccaa <- complete_territorial_summary(
    nuts2,
    ccaa,
    effis_ccaa,
    "ccaa"
  )
  territorial_provincias <- complete_territorial_summary(
    nuts3,
    provincias,
    effis_provincias,
    "provincia",
    parent_sf = nuts2
  )

  latest <- if (nrow(fires) > 0 && "acq_datetime_utc" %in% names(fires)) {
    safe_character_max(fires$acq_datetime_utc)
  } else {
    NA_character_
  }

  generated_at_utc <- format(
    as.POSIXct(Sys.time(), tz = "UTC"),
    "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  )

  overview <- tibble::tibble(
    generated_at_utc = generated_at_utc,
    n_firms = nrow(fires),
    n_firms_6h = if (nrow(fires) > 0) sum(!is.na(fires$age_hours) & fires$age_hours <= 6) else 0L,
    n_firms_12h = if (nrow(fires) > 0) sum(!is.na(fires$age_hours) & fires$age_hours <= 12) else 0L,
    n_firms_24h = if (nrow(fires) > 0) sum(!is.na(fires$age_hours) & fires$age_hours <= 24) else 0L,
    n_firms_48h = if (nrow(fires) > 0) sum(!is.na(fires$age_hours) & fires$age_hours <= 48) else 0L,
    frp_total_mw = if (nrow(fires) > 0) round(sum(fires$frp, na.rm = TRUE), 1) else 0,
    ultima_deteccion_utc = latest,
    n_ccaa_con_focos = nrow(ccaa),
    n_provincias_con_focos = nrow(provincias)
  )

  readr::write_csv(overview, "data/processed/dashboard_summary.csv")
  readr::write_csv(overview, "assets/summary/dashboard_summary.csv")

  dashboard_payload <- list(
    overview = overview,
    ccaa = ccaa,
    provincias = provincias
  )

  jsonlite::write_json(
    dashboard_payload,
    "data/processed/dashboard_summary.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null"
  )
  jsonlite::write_json(
    dashboard_payload,
    "assets/summary/dashboard_summary.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null"
  )

  write_territorial_summary(
    territorial_ccaa,
    territorial_provincias,
    generated_at_utc
  )

  message(
    "Resumen operativo: focos=", nrow(fires),
    "; CCAA activas=", nrow(ccaa),
    "; provincias activas=", nrow(provincias),
    "; territorios publicados=", nrow(territorial_ccaa) + nrow(territorial_provincias)
  )

  invisible(list(
    overview = overview,
    ccaa = ccaa,
    provincias = provincias,
    territorial_ccaa = territorial_ccaa,
    territorial_provincias = territorial_provincias
  ))
}
