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

firms_curl_fetch_raw <- function(url, user_agent = "visor-fuego/0.6.6", timeout = 120, connecttimeout = 30, retries = 2) {
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
    bright_ti4 = double(),
    scan = double(),
    track = double(),
    acq_date = character(),
    acq_time = character(),
    satellite = character(),
    instrument = character(),
    confidence = character(),
    version = character(),
    bright_ti5 = double(),
    frp = double(),
    daynight = character(),
    source_dataset = character(),
    acq_datetime_utc = character(),
    age_hours = double(),
    longitude = double(),
    latitude = double()
  )
}

firms_empty_output <- function() {
  tibble::tibble(
    bright_ti4 = double(),
    scan = double(),
    track = double(),
    acq_date = character(),
    acq_time = character(),
    satellite = character(),
    instrument = character(),
    confidence = character(),
    version = character(),
    bright_ti5 = double(),
    frp = double(),
    daynight = character(),
    source_dataset = character(),
    acq_datetime_utc = character(),
    age_hours = double(),
    confidence_label = character(),
    popup_label = character(),
    longitude = double(),
    latitude = double()
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
    # Todas las columnas se leen inicialmente como texto. Las respuestas de dos
    # sensores pueden contener tablas vacías o pequeñas diferencias de inferencia;
    # la conversión a tipos canónicos se hace después en normalise_firms().
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
  usable <- purrr::keep(
    results,
    function(x) is.data.frame(x) && nrow(x) > 0
  )

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
  if (nrow(fires) == 0) {
    return(list(type = "FeatureCollection", features = list()))
  }

  props_cols <- setdiff(names(fires), c("longitude", "latitude"))
  features <- purrr::map(seq_len(nrow(fires)), function(i) {
    props <- as.list(fires[i, props_cols, drop = FALSE])
    props <- lapply(props, function(v) {
      if (length(v) == 0 || is.na(v)) NULL else unname(v)
    })
    list(
      type = "Feature",
      geometry = list(
        type = "Point",
        coordinates = c(fires$longitude[i], fires$latitude[i])
      ),
      properties = props
    )
  })

  list(type = "FeatureCollection", features = features)
}

write_empty_firms_outputs <- function(reason = "Sin datos") {
  fs::dir_create("data/processed")
  fs::dir_create("assets/firms")
  empty <- firms_empty_output()
  readr::write_csv(empty, "data/processed/firms_active_fires.csv")
  geo <- list(type = "FeatureCollection", features = list(), note = reason)
  jsonlite::write_json(geo, "data/processed/firms_active_fires.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")
  jsonlite::write_json(geo, "assets/firms/firms_active_fires.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(empty)
}

download_firms_active_fires <- function() {
  map_key <- Sys.getenv("FIRMS_MAP_KEY", unset = "")
  if (!nzchar(map_key)) {
    message("FIRMS_MAP_KEY no definida: se omite NASA FIRMS y se genera capa vacía.")
    return(write_empty_firms_outputs("FIRMS_MAP_KEY no definida"))
  }

  bbox <- parse_firms_bbox()
  days <- firms_day_range()
  sources <- firms_sources()
  date <- Sys.getenv("FIRMS_DATE", unset = "")

  fs::dir_create("data/raw/firms")
  fs::dir_create("data/processed")
  fs::dir_create("assets/firms")

  results <- purrr::map(sources, function(source) {
    message("NASA FIRMS: ", source, " · últimos ", days, " días")
    url <- build_firms_area_url(map_key, source, bbox, days, date = date)
    stamp <- format(Sys.Date(), "%Y%m%d")
    raw_path <- file.path("data/raw/firms", sprintf("firms_%s_%sdays_%s.csv", source, days, stamp))

    resp <- tryCatch(firms_curl_fetch_raw(url), error = function(e) e)
    if (inherits(resp, "error")) {
      warning("Fallo descargando FIRMS ", source, ": ", conditionMessage(resp), call. = FALSE)
      return(firms_empty_normalised())
    }
    if (resp$status_code >= 400) {
      warning("FIRMS respondió HTTP ", resp$status_code, " para ", source, call. = FALSE)
      return(firms_empty_normalised())
    }

    writeBin(resp$content, raw_path)
    out <- read_firms_csv_safely(raw_path) |>
      normalise_firms(source)
    message("NASA FIRMS: ", source, " · detecciones válidas: ", nrow(out))
    out
  })

  downloaded <- bind_firms_sources(results)

  if (nrow(downloaded) == 0) {
    message("NASA FIRMS: no hay detecciones para el área/periodo seleccionado.")
    return(write_empty_firms_outputs("Sin detecciones FIRMS"))
  }

  # Deduplicación conservadora: sensor + coordenadas + fecha/hora.
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

  readr::write_csv(fires, "data/processed/firms_active_fires.csv")
  geo <- firms_to_geojson(fires)
  jsonlite::write_json(geo, "data/processed/firms_active_fires.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")
  jsonlite::write_json(geo, "assets/firms/firms_active_fires.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")

  message("NASA FIRMS: detecciones preparadas: ", nrow(fires))
  fires
}
