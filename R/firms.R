source("R/utils.R", encoding = "UTF-8")

firms_default_bbox <- function() {
  # España peninsular, Baleares y Canarias, con margen operativo.
  c(west = -19, south = 27, east = 5, north = 44.6)
}

parse_firms_bbox <- function(x = Sys.getenv("FIRMS_BBOX", unset = "")) {
  if (!nzchar(x)) return(firms_default_bbox())
  vals <- suppressWarnings(as.numeric(strsplit(x, ",")[[1]] |> trimws()))
  if (length(vals) != 4 || any(is.na(vals))) {
    warning("FIRMS_BBOX no válido; usando bbox por defecto", call. = FALSE)
    return(firms_default_bbox())
  }
  names(vals) <- c("west", "south", "east", "north")
  vals
}

firms_sources <- function() {
  env <- Sys.getenv("FIRMS_SOURCES", unset = "VIIRS_SNPP_NRT,VIIRS_NOAA20_NRT")
  out <- strsplit(env, ",")[[1]] |> trimws()
  out[nzchar(out)]
}

firms_day_range <- function() {
  days <- suppressWarnings(as.integer(Sys.getenv("FIRMS_DAYS", unset = "2")))
  if (is.na(days)) days <- 2L
  max(1L, min(5L, days))
}

firms_preserve_last_on_empty <- function() {
  tolower(trimws(Sys.getenv("FIRMS_PRESERVE_LAST_ON_EMPTY", unset = "true"))) %in%
    c("1", "true", "yes", "y", "si", "sí", "on")
}

firms_max_preserved_age_hours <- function() {
  value <- suppressWarnings(as.numeric(Sys.getenv("FIRMS_MAX_PRESERVED_AGE_HOURS", unset = "72")))
  if (!is.finite(value) || value < 1) value <- 72
  value
}

firms_curl_fetch_raw <- function(url, user_agent = "visor-fuego/0.6.24", timeout = 120, connecttimeout = 30, retries = 2) {
  if (!requireNamespace("curl", quietly = TRUE)) {
    stop("Falta el paquete R 'curl'. Instala con install.packages('curl').", call. = FALSE)
  }

  last_error <- NULL
  for (attempt in seq_len(retries + 1L)) {
    h <- curl::new_handle()
    curl::handle_setopt(
      h,
      useragent = user_agent,
      timeout = timeout,
      connecttimeout = connecttimeout,
      followlocation = TRUE,
      ssl_verifypeer = TRUE
    )
    resp <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) e)
    if (!inherits(resp, "error")) return(resp)
    last_error <- resp
    if (attempt <= retries) Sys.sleep(min(2 ^ (attempt - 1L), 4))
  }
  stop(conditionMessage(last_error), call. = FALSE)
}

build_firms_area_url <- function(map_key, source, bbox, days, date = Sys.getenv("FIRMS_DATE", unset = "")) {
  bbox_txt <- paste(unname(bbox), collapse = ",")
  base <- sprintf(
    "https://firms.modaps.eosdis.nasa.gov/api/area/csv/%s/%s/%s/%s",
    utils::URLencode(map_key, reserved = TRUE),
    utils::URLencode(source, reserved = TRUE),
    bbox_txt,
    days
  )
  if (nzchar(date)) paste0(base, "/", date) else base
}

firms_empty_normalised <- function() {
  tibble::tibble(
    bright_ti4 = double(), scan = double(), track = double(),
    acq_date = character(), acq_time = character(), satellite = character(),
    instrument = character(), confidence = character(), version = character(),
    bright_ti5 = double(), frp = double(), daynight = character(),
    source_dataset = character(), acq_datetime_utc = character(), age_hours = double(),
    longitude = double(), latitude = double()
  )
}

firms_empty_output <- function() {
  tibble::tibble(
    bright_ti4 = double(), scan = double(), track = double(),
    acq_date = character(), acq_time = character(), satellite = character(),
    instrument = character(), confidence = character(), version = character(),
    bright_ti5 = double(), frp = double(), daynight = character(),
    source_dataset = character(), acq_datetime_utc = character(), age_hours = double(),
    confidence_label = character(), popup_label = character(),
    longitude = double(), latitude = double()
  )
}

read_firms_csv_safely <- function(path) {
  if (!file.exists(path) || file.info(path)$size == 0) return(tibble::tibble())

  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (!nzchar(trimws(txt))) return(tibble::tibble())
  if (grepl("^No data", trimws(txt), ignore.case = TRUE)) return(tibble::tibble())
  if (!grepl("latitude", txt, ignore.case = TRUE) || !grepl("longitude", txt, ignore.case = TRUE)) {
    warning("La respuesta de FIRMS no parece CSV de detecciones: ", substr(txt, 1, 160), call. = FALSE)
    return(tibble::tibble())
  }

  tryCatch(
    readr::read_csv(
      path,
      col_types = readr::cols(.default = readr::col_character()),
      show_col_types = FALSE,
      progress = FALSE
    ),
    error = function(e) {
      warning("No se pudo leer CSV FIRMS ", path, ": ", conditionMessage(e), call. = FALSE)
      tibble::tibble()
    }
  )
}

normalise_firms_time <- function(x) {
  value <- suppressWarnings(as.integer(x))
  ifelse(is.na(value), NA_character_, sprintf("%04d", value))
}

parse_firms_datetime <- function(acq_date, acq_time) {
  hhmm <- normalise_firms_time(acq_time)
  hh <- substr(hhmm, 1, 2)
  mm <- substr(hhmm, 3, 4)
  as.POSIXct(
    paste(acq_date, paste0(hh, ":", mm, ":00")),
    tz = "UTC",
    format = "%Y-%m-%d %H:%M:%S"
  )
}

normalise_firms <- function(x, source) {
  if (!is.data.frame(x) || nrow(x) == 0) return(firms_empty_normalised())

  names(x) <- tolower(names(x))
  if (!all(c("latitude", "longitude") %in% names(x))) {
    warning("FIRMS ", source, " no contiene latitude/longitude; se omite.", call. = FALSE)
    return(firms_empty_normalised())
  }

  required <- c(
    "bright_ti4", "scan", "track", "acq_date", "acq_time", "satellite",
    "instrument", "confidence", "version", "bright_ti5", "frp", "daynight",
    "latitude", "longitude"
  )
  for (column in setdiff(required, names(x))) x[[column]] <- NA_character_

  acq_time <- normalise_firms_time(x$acq_time)
  dt <- parse_firms_datetime(x$acq_date, acq_time)
  now_utc <- as.POSIXct(Sys.time(), tz = "UTC")

  tibble::tibble(
    bright_ti4 = suppressWarnings(as.numeric(x$bright_ti4)),
    scan = suppressWarnings(as.numeric(x$scan)),
    track = suppressWarnings(as.numeric(x$track)),
    acq_date = as.character(x$acq_date),
    acq_time = acq_time,
    satellite = as.character(x$satellite),
    instrument = as.character(x$instrument),
    confidence = as.character(x$confidence),
    version = as.character(x$version),
    bright_ti5 = suppressWarnings(as.numeric(x$bright_ti5)),
    frp = suppressWarnings(as.numeric(x$frp)),
    daynight = as.character(x$daynight),
    source_dataset = as.character(source),
    acq_datetime_utc = format(dt, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    age_hours = round(as.numeric(difftime(now_utc, dt, units = "hours")), 1),
    longitude = suppressWarnings(as.numeric(x$longitude)),
    latitude = suppressWarnings(as.numeric(x$latitude))
  ) |>
    dplyr::filter(!is.na(longitude), !is.na(latitude)) |>
    dplyr::arrange(dplyr::desc(acq_datetime_utc))
}

bind_firms_sources <- function(results) {
  usable <- purrr::keep(results, function(x) is.data.frame(x) && nrow(x) > 0)
  if (length(usable) == 0) return(firms_empty_normalised())
  dplyr::bind_rows(usable)
}

confidence_label <- function(x) {
  dplyr::case_when(
    is.na(x) ~ "sin dato",
    tolower(as.character(x)) == "l" ~ "baja",
    tolower(as.character(x)) == "n" ~ "nominal",
    tolower(as.character(x)) == "h" ~ "alta",
    TRUE ~ as.character(x)
  )
}

firms_to_geojson <- function(fires) {
  if (nrow(fires) == 0) return(list(type = "FeatureCollection", features = list()))

  props_cols <- setdiff(names(fires), c("longitude", "latitude"))
  features <- purrr::map(seq_len(nrow(fires)), function(i) {
    props <- as.list(fires[i, props_cols, drop = FALSE])
    props <- lapply(props, function(v) if (length(v) == 0 || is.na(v)) NULL else unname(v))
    list(
      type = "Feature",
      geometry = list(type = "Point", coordinates = c(fires$longitude[i], fires$latitude[i])),
      properties = props
    )
  })

  list(type = "FeatureCollection", features = features)
}

refresh_firms_age <- function(fires) {
  if (!is.data.frame(fires) || nrow(fires) == 0 || !"acq_datetime_utc" %in% names(fires)) return(fires)
  dt <- as.POSIXct(fires$acq_datetime_utc, tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
  fires$age_hours <- round(as.numeric(difftime(as.POSIXct(Sys.time(), tz = "UTC"), dt, units = "hours")), 1)
  fires
}

normalise_existing_firms_output <- function(x) {
  if (!is.data.frame(x) || nrow(x) == 0) return(firms_empty_output())
  template <- firms_empty_output()
  for (nm in setdiff(names(template), names(x))) x[[nm]] <- NA
  x <- x[, names(template), drop = FALSE]
  numeric_cols <- c("bright_ti4", "scan", "track", "bright_ti5", "frp", "age_hours", "longitude", "latitude")
  for (nm in numeric_cols) x[[nm]] <- suppressWarnings(as.numeric(x[[nm]]))
  char_cols <- setdiff(names(template), numeric_cols)
  for (nm in char_cols) x[[nm]] <- as.character(x[[nm]])
  refresh_firms_age(tibble::as_tibble(x))
}

read_previous_firms_snapshot <- function() {
  candidates <- c(
    "assets/firms/firms_active_fires.csv",
    "data/processed/firms_active_fires.csv"
  )
  for (path in candidates) {
    if (!file.exists(path) || file.info(path)$size <= 0) next
    x <- tryCatch(readr::read_csv(path, show_col_types = FALSE), error = function(e) NULL)
    if (!is.null(x) && nrow(x) > 0 && all(c("longitude", "latitude", "acq_datetime_utc") %in% names(x))) {
      x <- normalise_existing_firms_output(x)
      attr(x, "source_path") <- path
      return(x)
    }
  }
  x <- firms_empty_output()
  attr(x, "source_path") <- NA_character_
  x
}

latest_firms_observation <- function(fires) {
  if (!is.data.frame(fires) || nrow(fires) == 0 || !"acq_datetime_utc" %in% names(fires)) return(NA_character_)
  dt <- as.POSIXct(fires$acq_datetime_utc, tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
  if (all(is.na(dt))) return(NA_character_)
  format(max(dt, na.rm = TRUE), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

write_firms_status <- function(status, source_status = list()) {
  fs::dir_create("assets/firms")
  fs::dir_create("data/processed")
  payload <- c(
    list(
      generated_at_utc = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ),
    status,
    list(sources = source_status)
  )
  jsonlite::write_json(payload, "assets/firms/status.json", auto_unbox = TRUE, pretty = TRUE, null = "null")
  jsonlite::write_json(payload, "data/processed/firms_status.json", auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(payload)
}

write_firms_outputs <- function(fires, note = NULL, status = list(), source_status = list()) {
  fs::dir_create("data/processed")
  fs::dir_create("assets/firms")
  fires <- normalise_existing_firms_output(fires)

  readr::write_csv(fires, "data/processed/firms_active_fires.csv")
  readr::write_csv(fires, "assets/firms/firms_active_fires.csv")

  geo <- firms_to_geojson(fires)
  if (!is.null(note) && nzchar(note)) geo$note <- note
  jsonlite::write_json(geo, "data/processed/firms_active_fires.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")
  jsonlite::write_json(geo, "assets/firms/firms_active_fires.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")

  status <- c(
    list(
      n_detections = nrow(fires),
      last_observation_utc = latest_firms_observation(fires)
    ),
    status
  )
  write_firms_status(status, source_status = source_status)
  invisible(fires)
}

write_empty_firms_outputs <- function(reason = "Sin datos", source_status = list()) {
  write_firms_outputs(
    firms_empty_output(),
    note = reason,
    status = list(download_status = "empty", used_previous = FALSE, reason = reason),
    source_status = source_status
  )
}

preserve_previous_firms_if_allowed <- function(previous, reason, source_status = list()) {
  if (!firms_preserve_last_on_empty() || !is.data.frame(previous) || nrow(previous) == 0) return(NULL)

  previous <- refresh_firms_age(previous)
  latest_age <- suppressWarnings(min(previous$age_hours, na.rm = TRUE))
  if (!is.finite(latest_age)) return(NULL)
  max_age <- firms_max_preserved_age_hours()
  if (latest_age > max_age) {
    warning(
      "NASA FIRMS: el último snapshot válido tiene ", round(latest_age, 1),
      " h (> ", max_age, " h); no se conserva.", call. = FALSE
    )
    return(NULL)
  }

  source_path <- attr(previous, "source_path") %||% "snapshot anterior"
  warning(
    "NASA FIRMS: la descarga actual no contiene detecciones utilizables. ",
    "Se conserva el último snapshot válido (", nrow(previous), " detecciones; ", source_path, ").",
    call. = FALSE
  )
  write_firms_outputs(
    previous,
    note = paste0("Snapshot FIRMS anterior conservado: ", reason),
    status = list(
      download_status = "stale_preserved",
      used_previous = TRUE,
      reason = reason,
      previous_source = as.character(source_path),
      max_preserved_age_hours = max_age
    ),
    source_status = source_status
  )
}

download_firms_active_fires <- function() {
  previous <- read_previous_firms_snapshot()
  map_key <- Sys.getenv("FIRMS_MAP_KEY", unset = "")
  if (!nzchar(map_key)) {
    message("FIRMS_MAP_KEY no definida: se omite NASA FIRMS.")
    preserved <- preserve_previous_firms_if_allowed(previous, "FIRMS_MAP_KEY no definida")
    if (!is.null(preserved)) return(preserved)
    return(write_empty_firms_outputs("FIRMS_MAP_KEY no definida"))
  }

  bbox <- parse_firms_bbox()
  days <- firms_day_range()
  sources <- firms_sources()
  date <- Sys.getenv("FIRMS_DATE", unset = "")

  fs::dir_create("data/raw/firms")
  fs::dir_create("data/processed")
  fs::dir_create("assets/firms")

  source_results <- purrr::map(sources, function(source) {
    message("NASA FIRMS: ", source, " · últimos ", days, " días")
    url <- build_firms_area_url(map_key, source, bbox, days, date = date)
    stamp <- format(Sys.Date(), "%Y%m%d")
    raw_path <- file.path("data/raw/firms", sprintf("firms_%s_%sdays_%s.csv", source, days, stamp))

    resp <- tryCatch(firms_curl_fetch_raw(url), error = function(e) e)
    if (inherits(resp, "error")) {
      msg <- conditionMessage(resp)
      warning("Fallo descargando FIRMS ", source, ": ", msg, call. = FALSE)
      return(list(data = firms_empty_normalised(), status = "network_error", detail = msg))
    }
    if (resp$status_code >= 400) {
      msg <- paste0("HTTP ", resp$status_code)
      warning("FIRMS respondió ", msg, " para ", source, call. = FALSE)
      return(list(data = firms_empty_normalised(), status = "http_error", detail = msg))
    }

    writeBin(resp$content, raw_path)
    raw_tbl <- read_firms_csv_safely(raw_path)
    out <- normalise_firms(raw_tbl, source)
    state <- if (nrow(out) > 0) "ok" else "valid_empty"
    message("NASA FIRMS: ", source, " · detecciones válidas: ", nrow(out), " · estado: ", state)
    list(data = out, status = state, detail = paste0("HTTP ", resp$status_code), n = nrow(out))
  })

  results <- purrr::map(source_results, "data")
  downloaded <- bind_firms_sources(results)
  source_status <- stats::setNames(
    purrr::map(source_results, function(x) list(status = x$status, detail = x$detail, n = x$n %||% 0L)),
    sources
  )

  if (nrow(downloaded) == 0) {
    reason <- paste0(
      "Sin detecciones utilizables en la descarga actual; estados: ",
      paste(paste0(sources, "=", purrr::map_chr(source_results, "status")), collapse = ", ")
    )
    preserved <- preserve_previous_firms_if_allowed(previous, reason, source_status = source_status)
    if (!is.null(preserved)) return(preserved)
    message("NASA FIRMS: no hay detecciones para el área/periodo seleccionado y no existe snapshot reciente conservable.")
    return(write_empty_firms_outputs(reason, source_status = source_status))
  }

  fires <- downloaded |>
    dplyr::mutate(
      confidence_label = confidence_label(confidence),
      popup_label = paste0(
        "<strong>NASA FIRMS</strong><br>",
        "Sensor: ", source_dataset, "<br>",
        "Fecha UTC: ", acq_datetime_utc, "<br>",
        "Confianza: ", confidence_label, "<br>",
        "FRP: ", ifelse(is.na(frp), "s/d", paste0(frp, " MW"))
      )
    ) |>
    dplyr::distinct(source_dataset, longitude, latitude, acq_datetime_utc, .keep_all = TRUE) |>
    dplyr::select(
      bright_ti4, scan, track, acq_date, acq_time, satellite, instrument,
      confidence, version, bright_ti5, frp, daynight, source_dataset,
      acq_datetime_utc, age_hours, confidence_label, popup_label,
      longitude, latitude
    )

  write_firms_outputs(
    fires,
    status = list(download_status = "fresh", used_previous = FALSE, reason = "Descarga FIRMS correcta"),
    source_status = source_status
  )
  message("NASA FIRMS: detecciones preparadas: ", nrow(fires))
  fires
}
