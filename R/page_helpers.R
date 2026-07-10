# Helpers compartidos para páginas Quarto del visor-fuego.
# Mantener sin dependencias pesadas: readr, dplyr, tibble, stringr y jsonlite ya se usan en el proyecto.

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x)) || !nzchar(paste(x, collapse = ""))) y else x
}

vf_load_packages <- function() {
  pkgs <- c("readr", "dplyr", "tibble", "stringr", "knitr")
  invisible(lapply(pkgs, function(pkg) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Falta el paquete R requerido: %s", pkg), call. = FALSE)
    }
  }))
}

vf_first_existing <- function(paths) {
  paths <- paths[!is.na(paths) & nzchar(paths)]
  found <- paths[file.exists(paths)]
  if (length(found) == 0) return(NA_character_)
  found[[1]]
}

vf_read_csv <- function(paths, col_types = readr::cols(.default = readr::col_guess())) {
  vf_load_packages()
  path <- vf_first_existing(paths)
  if (is.na(path)) return(tibble::tibble())
  out <- tryCatch(
    readr::read_csv(path, col_types = col_types, show_col_types = FALSE),
    error = function(e) tibble::tibble(.read_error = conditionMessage(e), .path = path)
  )
  attr(out, "source_path") <- path
  out
}

vf_as_date <- function(x) {
  if (is.null(x)) return(as.Date(character()))
  if (inherits(x, "Date")) return(x)
  x_chr <- as.character(x)
  x_chr[!nzchar(x_chr)] <- NA_character_
  suppressWarnings(as.Date(substr(x_chr, 1, 10)))
}

vf_int <- function(x) {
  suppressWarnings(as.integer(x))
}

vf_chr <- function(x, fallback = NA_character_) {
  if (is.null(x)) return(rep(fallback, 0))
  out <- as.character(x)
  out[is.na(out) | !nzchar(out)] <- fallback
  out
}

vf_has_cols <- function(x, cols) {
  all(cols %in% names(x))
}

vf_get_col <- function(df, name, default = NA_character_) {
  if (name %in% names(df)) return(df[[name]])
  rep(default, nrow(df))
}

vf_safe_max_date <- function(x) {
  d <- vf_as_date(x)
  d <- d[!is.na(d)]
  if (length(d) == 0) return(as.Date(NA))
  max(d)
}

vf_safe_min_date <- function(x) {
  d <- vf_as_date(x)
  d <- d[!is.na(d)]
  if (length(d) == 0) return(as.Date(NA))
  min(d)
}

vf_area_label <- function(area) {
  area <- as.character(area)
  dplyr::case_when(
    area %in% c("p", "peninsula", "península", "peninsula_baleares") ~ "Península y Baleares",
    area %in% c("b", "baleares", "illes_balears") ~ "Baleares",
    area %in% c("c", "canarias") ~ "Canarias",
    is.na(area) | !nzchar(area) ~ "Sin área",
    TRUE ~ area
  )
}

vf_parse_aemet_filename <- function(x) {
  x <- basename(as.character(x))
  # aemet_incendios_YYYYMMDD_p_previsto_d0.tif/png
  m1 <- stringr::str_match(x, "aemet_incendios_([0-9]{8})_([a-z])_previsto_d([0-9]+)")
  # down_YYYYMMDD_peligro_p_D00.tif
  m2 <- stringr::str_match(x, "down_([0-9]{8})_peligro_([a-z])_D([0-9]+)")
  issue_raw <- ifelse(!is.na(m1[, 2]), m1[, 2], m2[, 2])
  area <- ifelse(!is.na(m1[, 3]), m1[, 3], m2[, 3])
  day_raw <- ifelse(!is.na(m1[, 4]), m1[, 4], m2[, 4])
  issue_date <- suppressWarnings(as.Date(issue_raw, format = "%Y%m%d"))
  classic_d <- suppressWarnings(as.integer(day_raw))
  tibble::tibble(
    parsed_issue_date = issue_date,
    parsed_area = area,
    parsed_forecast_day = classic_d
  )
}

vf_normalise_aemet_layers <- function(layers) {
  vf_load_packages()
  if (nrow(layers) == 0) return(layers)

  source_col <- dplyr::coalesce(
    if ("source_file" %in% names(layers)) as.character(layers$source_file) else NA_character_,
    if ("url" %in% names(layers)) as.character(layers$url) else NA_character_,
    if ("file" %in% names(layers)) as.character(layers$file) else NA_character_
  )

  parsed <- vf_parse_aemet_filename(source_col)

  if (!"issue_date" %in% names(layers)) layers$issue_date <- NA_character_
  if (!"valid_date" %in% names(layers)) layers$valid_date <- NA_character_
  if (!"date" %in% names(layers)) layers$date <- NA_character_
  if (!"forecast_day" %in% names(layers)) layers$forecast_day <- NA_integer_
  if (!"forecast_label" %in% names(layers)) layers$forecast_label <- NA_character_
  if (!"area" %in% names(layers)) layers$area <- NA_character_
  if (!"area_label" %in% names(layers)) layers$area_label <- NA_character_

  issue_date <- vf_as_date(layers$issue_date)
  valid_date <- vf_as_date(layers$valid_date)
  date_col <- vf_as_date(layers$date)

  issue_date[is.na(issue_date)] <- parsed$parsed_issue_date[is.na(issue_date)]
  valid_date[is.na(valid_date)] <- date_col[is.na(valid_date)]
  valid_date[is.na(valid_date)] <- parsed$parsed_issue_date[is.na(valid_date)]

  forecast_day <- vf_int(layers$forecast_day)
  forecast_day[is.na(forecast_day)] <- parsed$parsed_forecast_day[is.na(forecast_day)]

  area <- as.character(layers$area)
  area[is.na(area) | !nzchar(area)] <- parsed$parsed_area[is.na(area) | !nzchar(area)]

  forecast_label <- as.character(layers$forecast_label)
  missing_label <- is.na(forecast_label) | !nzchar(forecast_label)
  forecast_label[missing_label & !is.na(forecast_day)] <- paste0("Día ", forecast_day[missing_label & !is.na(forecast_day)] + 1L)

  layers$issue_date <- issue_date
  layers$valid_date <- valid_date
  layers$date <- valid_date
  layers$forecast_day <- forecast_day
  layers$forecast_label <- forecast_label
  layers$area <- area
  layers$area_label <- dplyr::coalesce(
    as.character(layers$area_label),
    vf_area_label(area)
  )
  layers$area_label[is.na(layers$area_label) | !nzchar(layers$area_label)] <- vf_area_label(area[is.na(layers$area_label) | !nzchar(layers$area_label)])
  layers
}

vf_latest_aemet_layers <- function(layers) {
  layers <- vf_normalise_aemet_layers(layers)
  if (nrow(layers) == 0) return(layers)
  latest_issue <- vf_safe_max_date(layers$issue_date)
  if (!is.na(latest_issue)) {
    layers <- dplyr::filter(layers, .data$issue_date == latest_issue)
  }
  layers
}

vf_aemet_overview <- function(layers) {
  vf_load_packages()
  layers <- vf_normalise_aemet_layers(layers)
  latest <- vf_latest_aemet_layers(layers)
  tibble::tibble(
    indicador = c(
      "Capas AEMET en catálogo",
      "Capas AEMET de última emisión",
      "Última emisión",
      "Primera fecha válida",
      "Última fecha válida",
      "Áreas disponibles"
    ),
    valor = c(
      as.character(nrow(layers)),
      as.character(nrow(latest)),
      as.character(vf_safe_max_date(latest$issue_date)),
      as.character(vf_safe_min_date(latest$valid_date)),
      as.character(vf_safe_max_date(latest$valid_date)),
      paste(sort(unique(stats::na.omit(latest$area_label))), collapse = ", ")
    )
  )
}

vf_status_table <- function() {
  vf_load_packages()
  aemet <- vf_read_csv(c("data/processed/layers.csv", "assets/aemet/layers.csv"))
  aemet_latest <- vf_latest_aemet_layers(aemet)
  firms <- vf_read_csv(c("data/processed/firms_active_fires.csv", "data/processed/firms.csv", "assets/firms/firms_active_fires.csv"))
  alerts <- vf_read_csv(c("data/processed/operational_alerts.csv", "assets/alerts/operational_alerts.csv"))
  effis <- vf_read_csv(c("data/processed/effis_layers.csv", "assets/effis/effis_layers.csv"))
  history <- vf_read_csv(c("data/processed/dashboard_history.csv", "assets/history/dashboard_history.csv"))

  tibble::tibble(
    fuente = c("AEMET", "FIRMS", "Alertas", "EFFIS", "Histórico"),
    estado = c(
      if (nrow(aemet_latest) > 0) "OK" else "Sin capas",
      if (nrow(firms) > 0) "OK" else "Sin detecciones/archivo",
      if (nrow(alerts) > 0) "OK" else "Sin alertas/archivo",
      if (nrow(effis) > 0) "OK" else "Desactivado o sin capa actual",
      if (nrow(history) > 0) "OK" else "Sin histórico"
    ),
    filas = c(nrow(aemet_latest), nrow(firms), nrow(alerts), nrow(effis), nrow(history)),
    archivo = c(
      attr(aemet, "source_path") %||% "-",
      attr(firms, "source_path") %||% "-",
      attr(alerts, "source_path") %||% "-",
      attr(effis, "source_path") %||% "-",
      attr(history, "source_path") %||% "-"
    )
  )
}

vf_kable <- function(x, caption = NULL, digits = 2) {
  vf_load_packages()
  if (nrow(x) == 0) {
    return(knitr::asis_output("_Sin datos disponibles._\n"))
  }
  knitr::kable(x, caption = caption, digits = digits)
}

vf_history_date_column <- function(history) {
  candidates <- c("snapshot_date", "date", "render_date", "fecha", "updated_at")
  found <- candidates[candidates %in% names(history)]
  if (length(found) == 0) return(NA_character_)
  found[[1]]
}

vf_numeric_metric_columns <- function(history) {
  if (nrow(history) == 0) return(character())
  names(history)[vapply(history, is.numeric, logical(1))]
}
