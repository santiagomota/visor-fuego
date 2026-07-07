source("R/utils.R", encoding = "UTF-8")

AEMET_BASE <- "https://opendata.aemet.es/opendata"

fire_endpoints <- function(days = 1:7, areas = c("p", "b", "c"), products = c("estimado", "previsto")) {
  products <- intersect(products, c("estimado", "previsto"))
  out <- list()

  if ("estimado" %in% products) {
    out$estimated <- tibble::tibble(
      tipo = "estimado",
      dia = NA_integer_,
      area = areas,
      endpoint = sprintf("/api/incendios/mapasriesgo/estimado/area/%s", areas)
    )
  }

  if ("previsto" %in% products) {
    out$forecast <- tidyr::crossing(
      dia = days,
      area = areas
    ) |>
      dplyr::mutate(
        tipo = "previsto",
        endpoint = sprintf("/api/incendios/mapasriesgo/previsto/dia/%s/area/%s", dia, area)
      ) |>
      dplyr::select(tipo, dia, area, endpoint)
  }

  dplyr::bind_rows(out)
}

build_aemet_api_url <- function(endpoint, api_key) {
  sep <- if (grepl("\\?", endpoint)) "&" else "?"
  paste0(AEMET_BASE, endpoint, sep, "api_key=", utils::URLencode(api_key, reserved = TRUE))
}

curl_fetch_raw <- function(url, api_key = NULL, user_agent = "visor-fuego/0.7", timeout = 60, connecttimeout = 20, retries = 2) {
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

    headers <- c(`User-Agent` = user_agent)
    if (!is.null(api_key) && nzchar(api_key)) {
      headers <- c(headers, api_key = api_key)
    }
    do.call(curl::handle_setheaders, c(list(handle = h), as.list(headers)))

    resp <- tryCatch(
      curl::curl_fetch_memory(url, handle = h),
      error = function(e) e
    )

    if (!inherits(resp, "error")) return(resp)

    last_error <- resp
    if (attempt <= retries) Sys.sleep(min(2 ^ (attempt - 1L), 4))
  }

  stop(conditionMessage(last_error), call. = FALSE)
}

raw_to_text_candidates <- function(raw) {
  if (length(raw) == 0) return(character())

  txt0 <- tryCatch(rawToChar(raw, multiple = FALSE), error = function(e) "")
  if (!nzchar(txt0)) return(character())

  convert_one <- function(from) {
    tryCatch(
      iconv(txt0, from = from, to = "UTF-8", sub = "byte"),
      warning = function(w) suppressWarnings(iconv(txt0, from = from, to = "UTF-8", sub = "byte")),
      error = function(e) NA_character_
    )
  }

  candidates <- c(
    convert_one("UTF-8"),
    convert_one("latin1"),
    convert_one("CP1252")
  )

  candidates <- candidates[!is.na(candidates)]
  candidates <- candidates[nzchar(candidates)]
  unique(candidates)
}

parse_aemet_json_raw <- function(raw, http_status = NA_integer_) {
  candidates <- raw_to_text_candidates(raw)

  for (txt in candidates) {
    txt <- sub("^\ufeff", "", trimws(txt))
    if (!nzchar(txt)) next

    parsed <- tryCatch(
      jsonlite::fromJSON(txt, simplifyVector = TRUE),
      error = function(e) NULL
    )
    if (!is.null(parsed)) return(parsed)
  }

  preview <- if (length(candidates) > 0) substr(candidates[[1]], 1, 500) else ""
  list(
    estado = http_status,
    descripcion = paste("Respuesta de AEMET no interpretable como JSON:", preview)
  )
}

request_aemet_metadata <- function(endpoint, api_key) {
  url <- build_aemet_api_url(endpoint, api_key)

  # Usamos curl a bajo nivel para evitar que las cabeceras no UTF-8 de AEMET
  # provoquen errores en httr2/curl al intentar parsearlas como texto.
  resp <- curl_fetch_raw(url, api_key = api_key, user_agent = "visor-fuego/0.7", timeout = 60, connecttimeout = 20, retries = 2)
  http_status <- resp$status_code

  body <- parse_aemet_json_raw(resp$content, http_status = http_status)

  if (http_status >= 400) {
    msg <- body$descripcion %||% paste("HTTP", http_status)
    return(list(ok = FALSE, http_status = http_status, estado = body$estado %||% http_status, descripcion = msg))
  }

  estado <- suppressWarnings(as.integer(body$estado %||% http_status))
  if (!is.na(estado) && estado != 200L) {
    return(list(
      ok = FALSE,
      http_status = http_status,
      estado = estado,
      descripcion = body$descripcion %||% "Respuesta de AEMET sin datos"
    ))
  }

  body$ok <- TRUE
  body$http_status <- http_status
  body
}

safe_url_extension <- function(url) {
  url_path <- strsplit(url, "\\?")[[1]][1]
  ext <- tolower(tools::file_ext(basename(url_path)))
  allowed <- c("png", "jpg", "jpeg", "webp", "gif", "tif", "tiff", "zip", "json", "geojson", "xml", "kml", "gml")
  if (nzchar(ext) && ext %in% allowed) ext else NA_character_
}

download_aemet_data_url <- function(datos_url, out_stem) {
  resp <- curl_fetch_raw(datos_url, api_key = NULL, user_agent = "visor-fuego/0.7", timeout = 120, connecttimeout = 30, retries = 2)

  status <- resp$status_code
  if (status >= 400) {
    stop("Error HTTP ", status, " descargando recurso AEMET", call. = FALSE)
  }

  body_raw <- resp$content

  url_ext <- safe_url_extension(datos_url)
  ext <- if (!is.na(url_ext)) url_ext else sniff_file_extension(body_raw, fallback = "bin")

  out <- file.path("data/raw/aemet", paste0(out_stem, ".", ext))
  fs::dir_create(dirname(out))
  writeBin(body_raw, out)

  normalise_downloaded_extension(out)
}

manifest_row <- function(tipo, dia, area, endpoint, status, descripcion = NA_character_,
                         datos_url = NA_character_, metadatos_url = NA_character_, estado = NA_integer_,
                         http_status = NA_integer_, file = NA_character_, file_type = NA_character_,
                         date = Sys.Date()) {
  tibble::tibble(
    downloaded_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    date = as.character(as.Date(date)),
    status = status,
    tipo = tipo,
    dia = dia,
    area = area,
    area_label = area_label(area),
    endpoint = endpoint,
    datos_url = datos_url,
    metadatos_url = metadatos_url,
    descripcion = descripcion,
    estado = estado,
    http_status = http_status,
    file = file,
    file_type = file_type
  )
}

download_one_fire_product <- function(tipo, dia, area, endpoint, api_key, date = Sys.Date()) {
  message("AEMET: ", tipo, " ", area_label(area), if (!is.na(dia)) paste0(" día ", dia) else "")

  meta <- request_aemet_metadata(endpoint, api_key)

  if (!isTRUE(meta$ok)) {
    msg <- meta$descripcion %||% "Sin datos"
    message("  - sin datos: ", msg)
    return(manifest_row(
      tipo = tipo, dia = dia, area = area, endpoint = endpoint,
      status = "missing",
      descripcion = msg,
      estado = meta$estado %||% NA_integer_,
      http_status = meta$http_status %||% NA_integer_,
      date = date
    ))
  }

  datos_url <- meta$datos %||% NA_character_

  if (is.na(datos_url) || !nzchar(datos_url)) {
    return(manifest_row(
      tipo = tipo, dia = dia, area = area, endpoint = endpoint,
      status = "error",
      descripcion = "La respuesta de AEMET no incluye campo 'datos'",
      estado = meta$estado %||% NA_integer_,
      http_status = meta$http_status %||% NA_integer_,
      date = date
    ))
  }

  stem <- paste(
    "aemet_incendios",
    format(as.Date(date), "%Y%m%d"),
    area,
    tipo,
    if (!is.na(dia)) paste0("d", dia) else "hoy",
    sep = "_"
  )

  file <- tryCatch(
    download_aemet_data_url(datos_url, stem),
    error = function(e) {
      message("  - error descarga: ", conditionMessage(e))
      NA_character_
    }
  )

  if (is.na(file) || !file.exists(file)) {
    return(manifest_row(
      tipo = tipo, dia = dia, area = area, endpoint = endpoint,
      status = "error",
      descripcion = "No se pudo descargar el recurso indicado por AEMET",
      datos_url = datos_url,
      metadatos_url = meta$metadatos %||% NA_character_,
      estado = meta$estado %||% NA_integer_,
      http_status = meta$http_status %||% NA_integer_,
      date = date
    ))
  }

  ft <- infer_file_type(file)
  message("  - descargado: ", file, " [", ft, "]")

  manifest_row(
    tipo = tipo,
    dia = dia,
    area = area,
    endpoint = endpoint,
    status = "downloaded",
    descripcion = meta$descripcion %||% NA_character_,
    datos_url = datos_url,
    metadatos_url = meta$metadatos %||% NA_character_,
    estado = meta$estado %||% NA_integer_,
    http_status = meta$http_status %||% NA_integer_,
    file = file,
    file_type = ft,
    date = date
  )
}

use_previous_downloads_after_errors <- function(new_manifest, old_manifest) {
  if (is.null(old_manifest) || nrow(old_manifest) == 0) return(new_manifest)
  if (!all(c("date", "tipo", "dia", "area", "status", "file") %in% names(old_manifest))) return(new_manifest)

  char_cols <- intersect(c("status", "file", "file_type", "datos_url", "metadatos_url", "descripcion"), names(new_manifest))
  new_manifest <- new_manifest |> dplyr::mutate(dplyr::across(dplyr::all_of(char_cols), as.character))
  char_cols_old <- intersect(c("status", "file", "file_type", "datos_url", "metadatos_url", "descripcion"), names(old_manifest))
  old_manifest <- old_manifest |> dplyr::mutate(dplyr::across(dplyr::all_of(char_cols_old), as.character))

  old_good <- old_manifest |>
    dplyr::filter(status %in% c("downloaded", "cached")) |>
    dplyr::filter(!is.na(file), file.exists(file)) |>
    dplyr::select(
      date, tipo, dia, area,
      cache_file = file,
      cache_file_type = file_type,
      cache_datos_url = datos_url,
      cache_metadatos_url = metadatos_url
    ) |>
    dplyr::distinct(date, tipo, dia, area, .keep_all = TRUE)

  if (nrow(old_good) == 0) return(new_manifest)

  out <- new_manifest |>
    dplyr::left_join(old_good, by = c("date", "tipo", "dia", "area")) |>
    dplyr::mutate(
      use_cache = status == "error" & !is.na(cache_file),
      status = dplyr::if_else(use_cache, "cached", status),
      descripcion = dplyr::if_else(use_cache, paste0("Usando descarga cacheada tras error: ", descripcion), descripcion),
      file = dplyr::if_else(use_cache, cache_file, file),
      file_type = dplyr::if_else(use_cache, cache_file_type, file_type),
      datos_url = dplyr::if_else(use_cache & !is.na(cache_datos_url), cache_datos_url, datos_url),
      metadatos_url = dplyr::if_else(use_cache & !is.na(cache_metadatos_url), cache_metadatos_url, metadatos_url)
    ) |>
    dplyr::select(-cache_file, -cache_file_type, -cache_datos_url, -cache_metadatos_url, -use_cache)

  out
}
