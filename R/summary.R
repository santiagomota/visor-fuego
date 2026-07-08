source("R/utils.R", encoding = "UTF-8")
source("R/admin.R", encoding = "UTF-8")

read_firms_processed <- function() {
  path <- "data/processed/firms_active_fires.csv"
  if (!file.exists(path) || file.info(path)$size == 0) return(tibble::tibble())
  x <- tryCatch(readr::read_csv(path, show_col_types = FALSE), error = function(e) tibble::tibble())
  if (nrow(x) == 0 || !all(c("longitude", "latitude") %in% names(x))) return(tibble::tibble())
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
      n_ultimas_24h = sum(!is.na(age_hours) & age_hours <= 24),
      frp_total_mw = round(sum(frp, na.rm = TRUE), 1),
      frp_max_mw = round(suppressWarnings(max(frp, na.rm = TRUE)), 1),
      edad_min_h = round(suppressWarnings(min(age_hours, na.rm = TRUE)), 1),
      ultima_deteccion_utc = suppressWarnings(max(acq_datetime_utc, na.rm = TRUE)),
      sensores = paste(sort(unique(stats::na.omit(source_dataset))), collapse = ", "),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      frp_max_mw = dplyr::if_else(is.infinite(frp_max_mw), NA_real_, frp_max_mw),
      edad_min_h = dplyr::if_else(is.infinite(edad_min_h), NA_real_, edad_min_h),
      alerta_operativa = dplyr::case_when(
        n_ultimas_6h > 0 & frp_total_mw >= 100 ~ "alta",
        n_ultimas_6h > 0 ~ "media",
        n_ultimas_24h > 0 ~ "seguimiento",
        TRUE ~ "informativa"
      )
    ) |>
    dplyr::arrange(dplyr::desc(n_ultimas_6h), dplyr::desc(n_focos), dplyr::desc(frp_total_mw), admin_name)
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

  latest <- if (nrow(fires) > 0 && "acq_datetime_utc" %in% names(fires)) suppressWarnings(max(fires$acq_datetime_utc, na.rm = TRUE)) else NA_character_
  overview <- tibble::tibble(
    generated_at_utc = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    n_firms = nrow(fires),
    n_firms_6h = if (nrow(fires) > 0 && "age_hours" %in% names(fires)) sum(!is.na(fires$age_hours) & fires$age_hours <= 6) else 0L,
    n_firms_24h = if (nrow(fires) > 0 && "age_hours" %in% names(fires)) sum(!is.na(fires$age_hours) & fires$age_hours <= 24) else 0L,
    frp_total_mw = if (nrow(fires) > 0 && "frp" %in% names(fires)) round(sum(fires$frp, na.rm = TRUE), 1) else 0,
    ultima_deteccion_utc = ifelse(length(latest) == 0 || is.infinite(latest), NA_character_, as.character(latest)),
    n_ccaa_con_focos = nrow(ccaa),
    n_provincias_con_focos = nrow(provincias)
  )

  readr::write_csv(overview, "data/processed/dashboard_summary.csv")
  readr::write_csv(overview, "assets/summary/dashboard_summary.csv")

  jsonlite::write_json(
    list(
      overview = overview,
      ccaa = ccaa,
      provincias = provincias
    ),
    "data/processed/dashboard_summary.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
  jsonlite::write_json(
    list(
      overview = overview,
      ccaa = ccaa,
      provincias = provincias
    ),
    "assets/summary/dashboard_summary.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )

  message("Resumen operativo: focos=", nrow(fires), "; CCAA=", nrow(ccaa), "; provincias=", nrow(provincias))
  invisible(list(overview = overview, ccaa = ccaa, provincias = provincias))
}
