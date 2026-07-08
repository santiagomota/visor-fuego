source("R/utils.R", encoding = "UTF-8")

history_days_to_keep <- function() {
  x <- suppressWarnings(as.integer(Sys.getenv("HISTORY_KEEP_DAYS", unset = "90")))
  if (is.na(x) || x <= 0) x <- 90L
  x
}

history_mode <- function() {
  mode <- tolower(Sys.getenv("HISTORY_MODE", unset = "daily_latest"))
  if (!mode %in% c("daily_latest", "append_runs")) mode <- "daily_latest"
  mode
}

read_csv_empty <- function(path) {
  if (!file.exists(path) || file.info(path)$size == 0) return(tibble::tibble())
  tryCatch(readr::read_csv(path, show_col_types = FALSE), error = function(e) tibble::tibble())
}

as_num0 <- function(x) {
  out <- suppressWarnings(as.numeric(x))
  ifelse(is.na(out), 0, out)
}

current_snapshot_from_outputs <- function() {
  overview <- read_csv_empty("data/processed/dashboard_summary.csv")
  alerts <- read_csv_empty("data/processed/operational_alerts.csv")
  alerts_summary <- read_csv_empty("data/processed/operational_alerts_summary.csv")
  ccaa <- read_csv_empty("data/processed/firms_summary_ccaa.csv")
  provincias <- read_csv_empty("data/processed/firms_summary_provincias.csv")
  firms <- read_csv_empty("data/processed/firms_active_fires.csv")
  layers <- read_csv_empty("data/processed/layers.csv")

  now_utc <- as.POSIXct(Sys.time(), tz = "UTC")
  generated_at <- format(now_utc, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  if (nrow(overview) > 0) {
    ov <- overview[1, ]
  } else {
    ov <- tibble::tibble(
      n_firms = nrow(firms),
      n_firms_6h = if (nrow(firms) > 0 && "age_hours" %in% names(firms)) sum(!is.na(as_num0(firms$age_hours)) & as_num0(firms$age_hours) <= 6) else 0L,
      n_firms_24h = if (nrow(firms) > 0 && "age_hours" %in% names(firms)) sum(!is.na(as_num0(firms$age_hours)) & as_num0(firms$age_hours) <= 24) else 0L,
      frp_total_mw = if (nrow(firms) > 0 && "frp" %in% names(firms)) round(sum(as_num0(firms$frp), na.rm = TRUE), 1) else 0,
      ultima_deteccion_utc = NA_character_,
      n_ccaa_con_focos = nrow(ccaa),
      n_provincias_con_focos = nrow(provincias)
    )
  }

  n_alerts <- nrow(alerts)
  n_alertas_altas <- if (n_alerts > 0 && "alerta_operativa" %in% names(alerts)) sum(alerts$alerta_operativa == "alta", na.rm = TRUE) else 0L
  n_alertas_medias <- if (n_alerts > 0 && "alerta_operativa" %in% names(alerts)) sum(alerts$alerta_operativa == "media", na.rm = TRUE) else 0L
  n_alertas_seguimiento <- if (n_alerts > 0 && "alerta_operativa" %in% names(alerts)) sum(alerts$alerta_operativa == "seguimiento", na.rm = TRUE) else 0L
  max_alert_score <- if (n_alerts > 0 && "score" %in% names(alerts)) suppressWarnings(max(as.numeric(alerts$score), na.rm = TRUE)) else NA_real_
  if (is.infinite(max_alert_score)) max_alert_score <- NA_real_

  n_aemet_layers <- nrow(layers)
  aemet_date <- if (n_aemet_layers > 0 && "date" %in% names(layers)) paste(sort(unique(stats::na.omit(as.character(layers$date)))), collapse = ",") else NA_character_

  tibble::tibble(
    snapshot_date = format(as.Date(now_utc), "%Y-%m-%d"),
    generated_at_utc = generated_at,
    aemet_date = aemet_date,
    n_aemet_layers = n_aemet_layers,
    n_firms = as.integer(as_num0(ov$n_firms)[1]),
    n_firms_6h = as.integer(as_num0(ov$n_firms_6h)[1]),
    n_firms_24h = as.integer(as_num0(ov$n_firms_24h)[1]),
    frp_total_mw = round(as_num0(ov$frp_total_mw)[1], 1),
    ultima_deteccion_utc = if ("ultima_deteccion_utc" %in% names(ov)) as.character(ov$ultima_deteccion_utc[1]) else NA_character_,
    n_ccaa_con_focos = as.integer(as_num0(ov$n_ccaa_con_focos)[1]),
    n_provincias_con_focos = as.integer(as_num0(ov$n_provincias_con_focos)[1]),
    n_alertas = as.integer(n_alerts),
    n_alertas_altas = as.integer(n_alertas_altas),
    n_alertas_medias = as.integer(n_alertas_medias),
    n_alertas_seguimiento = as.integer(n_alertas_seguimiento),
    max_alert_score = round(max_alert_score, 1),
    top_provincia = if (nrow(provincias) > 0 && "admin_name" %in% names(provincias)) as.character(provincias$admin_name[1]) else NA_character_,
    top_provincia_focos = if (nrow(provincias) > 0 && "n_focos" %in% names(provincias)) as.integer(as_num0(provincias$n_focos)[1]) else NA_integer_,
    top_ccaa = if (nrow(ccaa) > 0 && "admin_name" %in% names(ccaa)) as.character(ccaa$admin_name[1]) else NA_character_,
    top_ccaa_focos = if (nrow(ccaa) > 0 && "n_focos" %in% names(ccaa)) as.integer(as_num0(ccaa$n_focos)[1]) else NA_integer_
  )
}

history_column_types <- function() {
  list(
    snapshot_date = "character",
    generated_at_utc = "character",
    aemet_date = "character",
    n_aemet_layers = "integer",
    n_firms = "integer",
    n_firms_6h = "integer",
    n_firms_24h = "integer",
    frp_total_mw = "numeric",
    ultima_deteccion_utc = "character",
    n_ccaa_con_focos = "integer",
    n_provincias_con_focos = "integer",
    n_alertas = "integer",
    n_alertas_altas = "integer",
    n_alertas_medias = "integer",
    n_alertas_seguimiento = "integer",
    max_alert_score = "numeric",
    top_provincia = "character",
    top_provincia_focos = "integer",
    top_ccaa = "character",
    top_ccaa_focos = "integer"
  )
}

empty_history_tbl <- function() {
  types <- history_column_types()
  out <- lapply(types, function(type) {
    switch(
      type,
      character = character(),
      integer = integer(),
      numeric = numeric(),
      logical()
    )
  })
  tibble::as_tibble(out)
}

ensure_history_columns <- function(x) {
  types <- history_column_types()

  if (nrow(x) == 0 && ncol(x) == 0) {
    return(empty_history_tbl())
  }

  for (col in names(types)) {
    if (!col %in% names(x)) {
      n <- nrow(x)
      x[[col]] <- switch(
        types[[col]],
        character = rep(NA_character_, n),
        integer = rep(NA_integer_, n),
        numeric = rep(NA_real_, n),
        rep(NA, n)
      )
    }
  }

  x
}

normalise_history <- function(x) {
  x <- ensure_history_columns(x)

  # Muy importante: también normalizamos los históricos vacíos.
  # Si no, tibble/readr pueden dejar columnas de solo NA como logical y
  # bind_rows() falla al añadir el primer snapshot real.
  if (nrow(x) == 0) {
    return(empty_history_tbl())
  }

  x |>
    dplyr::mutate(
      snapshot_date = as.character(snapshot_date),
      generated_at_utc = as.character(generated_at_utc),
      aemet_date = as.character(aemet_date),
      ultima_deteccion_utc = as.character(ultima_deteccion_utc),
      top_provincia = as.character(top_provincia),
      top_ccaa = as.character(top_ccaa),
      dplyr::across(
        dplyr::any_of(c(
          "n_aemet_layers", "n_firms", "n_firms_6h", "n_firms_24h",
          "n_ccaa_con_focos", "n_provincias_con_focos", "n_alertas",
          "n_alertas_altas", "n_alertas_medias", "n_alertas_seguimiento",
          "top_provincia_focos", "top_ccaa_focos"
        )),
        ~ suppressWarnings(as.integer(.x))
      ),
      dplyr::across(dplyr::any_of(c("frp_total_mw", "max_alert_score")), ~ suppressWarnings(as.numeric(.x)))
    ) |>
    dplyr::select(dplyr::all_of(names(history_column_types())))
}

normalise_admin_history <- function(x) {
  if (nrow(x) == 0 && ncol(x) == 0) return(tibble::tibble())

  char_cols <- intersect(
    c("snapshot_date", "admin_level", "admin_id", "admin_name", "country", "source"),
    names(x)
  )
  num_cols <- intersect(
    c("n_focos", "n_focos_6h", "n_focos_24h", "frp_total_mw", "frp_max_mw", "age_min_hours", "age_mean_hours"),
    names(x)
  )

  x |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(char_cols), as.character),
      dplyr::across(dplyr::all_of(num_cols), ~ suppressWarnings(as.numeric(.x)))
    )
}

update_dashboard_history <- function() {
  fs::dir_create("data/processed")
  fs::dir_create("assets/history")

  hist_path <- "data/processed/dashboard_history.csv"
  hist_assets_path <- "assets/history/dashboard_history.csv"

  hist <- read_csv_empty(hist_path)
  snapshot <- current_snapshot_from_outputs()

  combined <- dplyr::bind_rows(normalise_history(hist), normalise_history(snapshot))

  if (nrow(combined) > 0) {
    keep_days <- history_days_to_keep()
    min_date <- as.Date(Sys.Date()) - keep_days
    combined <- combined |>
      dplyr::mutate(.date = suppressWarnings(as.Date(snapshot_date))) |>
      dplyr::filter(is.na(.date) | .date >= min_date)

    if (history_mode() == "daily_latest") {
      combined <- combined |>
        dplyr::arrange(snapshot_date, generated_at_utc) |>
        dplyr::group_by(snapshot_date) |>
        dplyr::slice_tail(n = 1) |>
        dplyr::ungroup()
    }

    combined <- combined |>
      dplyr::select(-.date) |>
      dplyr::arrange(snapshot_date, generated_at_utc)
  }

  readr::write_csv(combined, hist_path)
  readr::write_csv(combined, hist_assets_path)

  jsonlite::write_json(
    combined,
    "data/processed/dashboard_history.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
  jsonlite::write_json(
    combined,
    "assets/history/dashboard_history.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )

  update_admin_history(snapshot$snapshot_date)

  message("Histórico actualizado: ", nrow(combined), " registros; modo=", history_mode())
  invisible(combined)
}

update_admin_history <- function(snapshot_date = format(Sys.Date(), "%Y-%m-%d")) {
  fs::dir_create("data/processed")
  fs::dir_create("assets/history")

  prov <- read_csv_empty("data/processed/firms_summary_provincias.csv")
  ccaa <- read_csv_empty("data/processed/firms_summary_ccaa.csv")

  add_snapshot <- function(x) {
    if (nrow(x) == 0) return(tibble::tibble())
    x |>
      dplyr::mutate(snapshot_date = as.character(snapshot_date)) |>
      dplyr::select(snapshot_date, dplyr::everything())
  }

  append_history <- function(current, path, assets_path) {
    hist <- normalise_admin_history(read_csv_empty(path))
    current <- normalise_admin_history(add_snapshot(current))

    combined <- dplyr::bind_rows(hist, current)

    if (nrow(combined) == 0) {
      readr::write_csv(combined, path)
      readr::write_csv(combined, assets_path)
      return(invisible(combined))
    }

    combined <- combined |>
      dplyr::mutate(snapshot_date = as.character(snapshot_date))

    if (nrow(combined) > 0 && history_mode() == "daily_latest") {
      keys <- intersect(c("snapshot_date", "admin_level", "admin_id"), names(combined))
      if (length(keys) == 3) {
        combined <- combined |>
          dplyr::group_by(dplyr::across(dplyr::all_of(keys))) |>
          dplyr::slice_tail(n = 1) |>
          dplyr::ungroup()
      }
    }

    if (nrow(combined) > 0) {
      min_date <- as.Date(Sys.Date()) - history_days_to_keep()
      combined <- combined |>
        dplyr::mutate(.date = suppressWarnings(as.Date(snapshot_date))) |>
        dplyr::filter(is.na(.date) | .date >= min_date) |>
        dplyr::select(-.date)
    }

    readr::write_csv(combined, path)
    readr::write_csv(combined, assets_path)
    invisible(combined)
  }

  append_history(prov, "data/processed/firms_summary_provincias_history.csv", "assets/history/firms_summary_provincias_history.csv")
  append_history(ccaa, "data/processed/firms_summary_ccaa_history.csv", "assets/history/firms_summary_ccaa_history.csv")
}
