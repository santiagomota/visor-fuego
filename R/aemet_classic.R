source("R/utils.R", encoding = "UTF-8")

AEMET_CLASSIC_BASE <- "https://www.aemet.es"
AEMET_CLASSIC_INCENDIOS <- "https://www.aemet.es/es/eltiempo/prediccion/incendios"
AEMET_CLASSIC_DOWNLOAD <- "https://www.aemet.es/es/api-eltiempo/incendios/download"

classic_handle <- function(user_agent = "visor-fuego-aemet-classic/0.6.19") {
  if (!requireNamespace("curl", quietly = TRUE)) {
    stop("Falta el paquete R 'curl'. Instala con install.packages('curl').", call. = FALSE)
  }
  h <- curl::new_handle()
  curl::handle_setopt(
    h,
    useragent = user_agent,
    timeout = 120,
    connecttimeout = 30,
    followlocation = TRUE,
    ssl_verifypeer = TRUE,
    cookiefile = "",
    cookiejar = ""
  )
  invisible(h)
}

classic_fetch_memory <- function(url, handle = classic_handle(), referer = AEMET_CLASSIC_INCENDIOS,
                                 accept = "*/*", out_file = NULL) {
  curl::handle_setheaders(
    handle,
    `Accept` = accept,
    `Referer` = referer,
    `Accept-Language` = "es-ES,es;q=0.9,en;q=0.7",
    `Cache-Control` = "no-cache"
  )
  resp <- curl::curl_fetch_memory(url, handle = handle)
  if (!is.null(out_file)) {
    fs::dir_create(dirname(out_file))
    writeBin(resp$content, out_file)
  }
  resp
}

headers_list_safe <- function(resp) {
  out <- tryCatch(curl::parse_headers_list(resp$headers), error = function(e) list())
  if (length(out) == 0) out <- list()
  out
}

response_content_type <- function(resp) {
  h <- headers_list_safe(resp)
  h[["content-type"]] %||% h[["Content-Type"]] %||% NA_character_
}

response_content_disposition <- function(resp) {
  h <- headers_list_safe(resp)
  h[["content-disposition"]] %||% h[["Content-Disposition"]] %||% NA_character_
}

response_extension <- function(resp, fallback = "bin") {
  cd <- response_content_disposition(resp)
  fn <- content_disposition_filename(cd)
  if (!is.na(fn)) {
    ext <- tolower(tools::file_ext(fn))
    if (nzchar(ext)) return(ext)
  }
  sniff_file_extension(resp$content, fallback = fallback)
}

raw_preview_text <- function(raw, n = 300) {
  if (length(raw) == 0) return(NA_character_)
  txt <- tryCatch(rawToChar(raw[seq_len(min(length(raw), n))], multiple = FALSE), error = function(e) "")
  txt <- suppressWarnings(iconv(txt, from = "latin1", to = "UTF-8", sub = "byte"))
  gsub("[\r\n\t]+", " ", txt)
}

parse_classic_tif_filename <- function(file) {
  base <- basename(file)
  m <- stringr::str_match(base, "^down_([0-9]{8})_peligro_([pc])_D([0-9]{2})\\.tif$")
  if (is.na(m[1, 1])) return(NULL)

  issue_date <- as.Date(m[1, 2], format = "%Y%m%d")
  classic_d <- as.integer(m[1, 4])

  # En el paquete clásico, YYYYMMDD identifica la fecha del mapa D00.
  # La serie D00..D07 representa días consecutivos: D00 = YYYYMMDD,
  # D01 = YYYYMMDD + 1, etc. La web de AEMET etiqueta los mapas como fechas
  # civiles 00-24h, por lo que no se debe sumar un día adicional por defecto.
  #
  # El índice operativo que mostramos al usuario sigue siendo Día 1, Día 2, ...
  # para D00, D01, ... respectivamente. Es decir:
  #   down_20260709_..._D00 -> válido 2026-07-09 -> Día 1
  #   down_20260709_..._D01 -> válido 2026-07-10 -> Día 2
  #
  # La variable permite corregir un cambio futuro de convención sin tocar código,
  # pero el valor recomendado desde v0.5.36 es 0.
  valid_start_offset_days <- suppressWarnings(as.integer(Sys.getenv(
    "AEMET_CLASSIC_VALID_START_OFFSET_DAYS",
    "0"
  )))
  if (is.na(valid_start_offset_days)) valid_start_offset_days <- 0L

  forecast_lead_days <- classic_d + valid_start_offset_days
  valid_date <- issue_date + forecast_lead_days
  display_day <- classic_d + 1L

  tibble::tibble(
    issue_date = as.character(issue_date),
    valid_date = as.character(valid_date),
    date = as.character(valid_date),
    area = m[1, 3],
    dia = display_day,
    forecast_day = display_day,
    forecast_label = paste0("Día ", display_day),
    original_file = as.character(file)
  )
}

classic_download_archive <- function(out_dir = "data/raw/aemet_classic", attempt = 1L) {
  fs::dir_create(out_dir)
  fs::dir_create(file.path(out_dir, "responses"))

  h <- classic_handle()

  message("Abriendo página clásica de AEMET para inicializar sesión...")
  try(
    classic_fetch_memory(
      AEMET_CLASSIC_INCENDIOS,
      handle = h,
      referer = "https://www.aemet.es/",
      accept = "text/html,application/xhtml+xml,application/xml,*/*;q=0.8",
      out_file = file.path(out_dir, "aemet_incendios_page.html")
    ),
    silent = TRUE
  )

  # Evitamos que un proxy/CDN entregue el mismo paquete almacenado de una
  # ejecución anterior. El endpoint ignora parámetros desconocidos y la marca
  # temporal fuerza una URL distinta en cada intento.
  cache_buster <- sprintf("%s-%s", as.integer(Sys.time()), as.integer(attempt))
  download_url <- paste0(AEMET_CLASSIC_DOWNLOAD, "?_visor_fuego=", cache_buster)

  message("Descargando paquete SIG AEMET clásico (intento ", attempt, ")...")
  accept_header <- "application/gzip,application/x-gzip,application/tar,image/tiff,image/geotiff,application/geotiff,application/octet-stream,*/*;q=0.2"
  resp <- tryCatch(
    classic_fetch_memory(
      download_url,
      handle = h,
      referer = AEMET_CLASSIC_INCENDIOS,
      accept = accept_header
    ),
    error = function(e) e
  )

  # Defensa: si AEMET deja de aceptar parámetros extra en el endpoint, usamos
  # inmediatamente la URL limpia. No renunciamos al cache-busting por un cambio
  # de servidor, pero tampoco rompemos la descarga por ese motivo.
  if (inherits(resp, "error") || resp$status_code >= 400) {
    warning("AEMET: el intento con cache-busting no fue aceptado; se prueba la URL directa.", call. = FALSE)
    resp <- classic_fetch_memory(
      AEMET_CLASSIC_DOWNLOAD,
      handle = h,
      referer = AEMET_CLASSIC_INCENDIOS,
      accept = accept_header
    )
  }

  if (resp$status_code >= 400) {
    stop("AEMET clásico respondió HTTP ", resp$status_code, ": ", raw_preview_text(resp$content, 500), call. = FALSE)
  }

  ext <- response_extension(resp, fallback = "bin")
  raw_path <- file.path(out_dir, "responses", paste0("aemet_classic_incendios_download.", ext))
  writeBin(resp$content, raw_path)
  normalise_downloaded_extension(raw_path)
}

extract_classic_geotiffs <- function(archive_path, out_dir = "data/raw/aemet_classic/extracted") {
  # IMPORTANTE: el nombre del paquete descargado es estable. Si reutilizamos el
  # mismo directorio de extracción, pueden quedar GeoTIFFs de ejecuciones
  # anteriores y el visor acaba mezclando fechas antiguas con las actuales.
  # Desde v0.5.37 limpiamos siempre el directorio de extracción de esta descarga.
  if (fs::dir_exists(out_dir)) {
    fs::dir_delete(out_dir)
  }
  fs::dir_create(out_dir)

  candidates <- extract_aemet_archive(archive_path, out_dir = out_dir)

  if (length(candidates) == 0 && infer_file_type(archive_path) == "raster") {
    candidates <- archive_path
  }

  tifs <- candidates[
    tolower(tools::file_ext(candidates)) %in% c("tif", "tiff") |
      vapply(candidates, infer_file_type, character(1)) == "raster"
  ]

  tifs <- unique(as.character(tifs[file.exists(tifs)]))

  meta <- purrr::map(tifs, parse_classic_tif_filename) |>
    purrr::compact() |>
    dplyr::bind_rows()

  if (nrow(meta) == 0) {
    stop("No se han encontrado GeoTIFFs con patrón down_YYYYMMDD_peligro_[p|c]_Dxx.tif en el paquete AEMET clásico.", call. = FALSE)
  }

  keep_latest <- tolower(Sys.getenv(
    "AEMET_CLASSIC_KEEP_LATEST_ISSUE_ONLY",
    "true"
  )) %in% c("1", "true", "yes", "si", "sí")

  if (keep_latest && nrow(meta) > 0 && "issue_date" %in% names(meta)) {
    latest_issue <- max(as.Date(meta$issue_date), na.rm = TRUE)
    if (is.finite(as.numeric(latest_issue))) {
      old_n <- nrow(meta)
      meta <- meta |>
        dplyr::filter(as.Date(issue_date) == latest_issue)
      if (old_n != nrow(meta)) {
        message(
          "AEMET clásico: se conservan solo los GeoTIFFs de la emisión más reciente: ",
          latest_issue,
          " (", nrow(meta), " de ", old_n, ")"
        )
      }
    }
  }

  # Nos quedamos con un único fichero por área/día dentro de la emisión vigente.
  # El endpoint directo trae todos los D00..D07 para Península/Baleares (p) y
  # Canarias (c), sin necesidad de probar parámetros adicionales.
  meta |>
    dplyr::arrange(area, valid_date, dia, original_file) |>
    dplyr::distinct(area, dia, .keep_all = TRUE)
}


aemet_today_madrid <- function() {
  as.Date(format(Sys.time(), tz = "Europe/Madrid", format = "%Y-%m-%d"))
}

classic_integer_env <- function(name, default, minimum = 0L, maximum = Inf) {
  value <- suppressWarnings(as.integer(Sys.getenv(name, unset = as.character(default))))
  if (is.na(value)) value <- as.integer(default)
  value <- max(as.integer(minimum), value)
  if (is.finite(maximum)) value <- min(as.integer(maximum), value)
  value
}

classic_true_env <- function(name, default = TRUE) {
  value <- tolower(trimws(Sys.getenv(name, unset = if (isTRUE(default)) "true" else "false")))
  value %in% c("1", "true", "yes", "y", "si", "sí", "on")
}

copy_classic_style_files <- function(extract_root, raw_dir = "data/raw/aemet") {
  style_dir <- file.path(raw_dir, "styles")
  if (fs::dir_exists(style_dir)) fs::dir_delete(style_dir)
  fs::dir_create(style_dir)

  if (!fs::dir_exists(extract_root)) return(character())
  style_files <- tryCatch(
    fs::dir_ls(extract_root, recurse = TRUE, type = "file", regexp = "\\.([sS][lL][dD]|[qQ][mM][lL])$"),
    error = function(e) character()
  )
  if (length(style_files) == 0) {
    message("AEMET clásico: el paquete no contiene ficheros SLD/QML detectables.")
    return(character())
  }

  copied <- character()
  for (file in unique(style_files)) {
    dest <- file.path(style_dir, basename(file))
    if (file.exists(dest)) {
      stem <- tools::file_path_sans_ext(basename(file))
      ext <- tools::file_ext(file)
      dest <- file.path(style_dir, paste0(stem, "_", length(copied) + 1L, ".", ext))
    }
    fs::file_copy(file, dest, overwrite = TRUE)
    copied <- c(copied, dest)
  }
  message("AEMET clásico: estilos SLD/QML copiados: ", length(copied))
  copied
}

write_aemet_download_status <- function(issue_date, attempts, raw_dir = "data/raw/aemet") {
  today <- aemet_today_madrid()
  issue <- suppressWarnings(as.Date(issue_date))
  age_days <- if (is.na(issue)) NA_integer_ else as.integer(today - issue)
  freshness <- if (is.na(age_days)) {
    "unknown"
  } else if (age_days <= 0L) {
    "today"
  } else if (age_days == 1L) {
    "yesterday"
  } else {
    "stale"
  }

  payload <- list(
    generated_at_utc = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    today_madrid = as.character(today),
    issue_date = if (is.na(issue)) NA_character_ else as.character(issue),
    issue_age_days = age_days,
    freshness = freshness,
    attempts = as.integer(attempts),
    provider = "classic"
  )
  fs::dir_create("data/processed")
  fs::dir_create("assets/aemet")
  jsonlite::write_json(payload, "data/processed/aemet_status.json", auto_unbox = TRUE, pretty = TRUE, null = "null")
  jsonlite::write_json(payload, "assets/aemet/status.json", auto_unbox = TRUE, pretty = TRUE, null = "null")
  payload
}

install_classic_geotiffs <- function(tif_meta, raw_dir = "data/raw/aemet") {
  fs::dir_create(raw_dir)

  clean_raw <- tolower(Sys.getenv(
    "AEMET_CLASSIC_CLEAN_RAW_BEFORE_INSTALL",
    "true"
  )) %in% c("1", "true", "yes", "si", "sí")

  if (clean_raw) {
    # Evita que queden productos AEMET antiguos en data/raw/aemet. Si permanecen,
    # prepare_layers_for_web() puede descubrirlos como huérfanos o mezclarlos con
    # el manifest actual, generando fechas antiguas en el selector Leaflet.
    old_classic <- tryCatch(
      fs::dir_ls(
        raw_dir,
        regexp = "aemet_incendios_.*\\.(png|jpg|jpeg|webp|gif|tif|tiff|zip|json|geojson|bin)$",
        recurse = FALSE,
        type = "file"
      ),
      error = function(e) character()
    )
    if (length(old_classic) > 0) {
      message("AEMET clásico: eliminando productos antiguos en ", raw_dir, ": ", length(old_classic))
      fs::file_delete(old_classic)
    }
  }

  purrr::pmap_dfr(tif_meta, function(issue_date, valid_date, date, area, dia, forecast_day, forecast_label, original_file) {
    valid_compact <- format(as.Date(valid_date), "%Y%m%d")
    out_file <- file.path(
      raw_dir,
      sprintf("aemet_incendios_%s_%s_previsto_d%s.tif", valid_compact, area, dia)
    )
    fs::file_copy(original_file, out_file, overwrite = TRUE)

    tibble::tibble(
      downloaded_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      date = as.character(valid_date),
      issue_date = as.character(issue_date),
      valid_date = as.character(valid_date),
      status = "downloaded",
      tipo = "previsto",
      dia = as.integer(dia),
      forecast_day = as.integer(forecast_day),
      forecast_label = as.character(forecast_label),
      area = as.character(area),
      area_label = area_label(area),
      endpoint = "/es/api-eltiempo/incendios/download",
      datos_url = AEMET_CLASSIC_DOWNLOAD,
      metadatos_url = NA_character_,
      descripcion = paste0(
        "AEMET clásico: paquete SIG GeoTIFF extraído de /es/api-eltiempo/incendios/download; ",
        "fecha de emisión ", issue_date, "; válido para ", valid_date, "; ", forecast_label
      ),
      estado = 200L,
      http_status = 200L,
      file = as.character(out_file),
      file_type = "raster"
    )
  }) |>
    normalise_manifest_types()
}

download_aemet_classic_incendios <- function(out_dir = "data/raw/aemet_classic", raw_dir = "data/raw/aemet") {
  max_attempts <- classic_integer_env("AEMET_CLASSIC_RETRIES", 3L, minimum = 1L, maximum = 6L)
  retry_seconds <- classic_integer_env("AEMET_CLASSIC_RETRY_SECONDS", 45L, minimum = 0L, maximum = 600L)
  max_issue_age <- classic_integer_env("AEMET_CLASSIC_MAX_ISSUE_AGE_DAYS", 1L, minimum = 0L, maximum = 7L)
  prefer_today <- classic_true_env("AEMET_CLASSIC_PREFER_TODAY_ISSUE", TRUE)
  today <- aemet_today_madrid()

  tif_meta <- NULL
  extract_root <- NULL
  used_attempt <- 0L

  for (attempt in seq_len(max_attempts)) {
    used_attempt <- attempt
    archive_path <- classic_download_archive(out_dir = out_dir, attempt = attempt)
    message("Paquete descargado: ", archive_path, " [", infer_file_type(archive_path), "]")

    extract_root <- file.path(out_dir, "extracted", tools::file_path_sans_ext(basename(archive_path)))
    candidate_meta <- extract_classic_geotiffs(archive_path, out_dir = extract_root)
    latest_issue <- max(as.Date(candidate_meta$issue_date), na.rm = TRUE)
    issue_age <- as.integer(today - latest_issue)

    message(
      "AEMET emisión descargada: ", latest_issue,
      " · hoy Madrid: ", today,
      " · antigüedad: ", issue_age, " día(s)"
    )

    tif_meta <- candidate_meta
    if (!prefer_today || is.na(issue_age) || issue_age <= 0L || attempt >= max_attempts) break

    message(
      "AEMET: todavía no se ha obtenido una emisión de hoy. ",
      "Se reintentará en ", retry_seconds, " s (", attempt + 1L, "/", max_attempts, ")."
    )
    if (retry_seconds > 0L) Sys.sleep(retry_seconds)
  }

  if (is.null(tif_meta) || nrow(tif_meta) == 0) {
    stop("No se obtuvieron GeoTIFFs AEMET válidos tras los reintentos.", call. = FALSE)
  }

  latest_issue <- max(as.Date(tif_meta$issue_date), na.rm = TRUE)
  issue_age <- as.integer(today - latest_issue)
  if (!is.na(issue_age) && issue_age > max_issue_age) {
    stop(
      "La última emisión AEMET descargada es demasiado antigua: ", latest_issue,
      " (", issue_age, " días; máximo permitido ", max_issue_age, ").",
      call. = FALSE
    )
  }
  if (!is.na(issue_age) && issue_age == 1L) {
    warning(
      "AEMET: la última salida disponible del paquete SIG sigue siendo de ayer (", latest_issue,
      "). Se publica porque contiene mapas válidos para hoy, pero se registra el aviso.",
      call. = FALSE
    )
  }

  copy_classic_style_files(extract_root, raw_dir = raw_dir)
  message("GeoTIFFs AEMET encontrados: ", nrow(tif_meta))

  manifest <- install_classic_geotiffs(tif_meta, raw_dir = raw_dir)
  readr::write_csv(manifest, file.path(raw_dir, "manifest.csv"))
  message("Manifest guardado en ", file.path(raw_dir, "manifest.csv"))

  status <- write_aemet_download_status(latest_issue, attempts = used_attempt, raw_dir = raw_dir)
  message(
    "AEMET estado: emisión ", status$issue_date,
    " · actualidad ", status$freshness,
    " · intentos ", status$attempts
  )

  summary <- manifest |>
    dplyr::count(area_label, valid_date, dia, file_type) |>
    dplyr::arrange(area_label, valid_date, dia)
  print(summary, n = Inf)

  invisible(manifest)
}

install_classic_probe_geotiffs <- function(contents_csv = "data/raw/aemet_classic_probe/classic_archive_contents.csv",
                                           preferred_label = "direct_1",
                                           raw_dir = "data/raw/aemet") {
  if (!file.exists(contents_csv)) {
    stop("No existe ", contents_csv, ". Ejecuta scripts/20_extract_classic_archives.R o usa la descarga clásica directa.", call. = FALSE)
  }

  contents <- readr::read_csv(contents_csv, show_col_types = FALSE)
  if (!"extracted_file" %in% names(contents)) {
    stop("El CSV no contiene columna extracted_file: ", contents_csv, call. = FALSE)
  }

  x <- contents |>
    dplyr::filter(file_type == "raster", tolower(ext) %in% c("tif", "tiff"), file.exists(extracted_file))

  if ("label" %in% names(x) && any(x$label == preferred_label, na.rm = TRUE)) {
    x <- x |> dplyr::filter(label == preferred_label)
  }

  tif_meta <- purrr::map(x$extracted_file, parse_classic_tif_filename) |>
    purrr::compact() |>
    dplyr::bind_rows() |>
    dplyr::arrange(area, valid_date, dia, original_file) |>
    dplyr::distinct(issue_date, area, dia, .keep_all = TRUE)

  if (nrow(tif_meta) == 0) {
    stop("No se encontraron GeoTIFFs AEMET válidos en ", contents_csv, call. = FALSE)
  }

  manifest <- install_classic_geotiffs(tif_meta, raw_dir = raw_dir)
  readr::write_csv(manifest, file.path(raw_dir, "manifest.csv"))
  message("GeoTIFFs instalados desde probe clásico: ", nrow(manifest))
  message("Manifest guardado en ", file.path(raw_dir, "manifest.csv"))
  invisible(manifest)
}
