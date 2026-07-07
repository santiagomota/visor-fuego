source("R/utils.R", encoding = "UTF-8")

AEMET_BASE <- "https://opendata.aemet.es/opendata"

parse_csv_env <- function(name, default) {
  value <- Sys.getenv(name, unset = default)
  value <- strsplit(value, ",")[[1]]
  trimws(value[nzchar(trimws(value))])
}

fire_endpoints <- function(days = 1:7,
                           areas = c("p", "b", "c"),
                           products = c("previsto", "estimado")) {
  products <- intersect(products, c("previsto", "estimado"))

  pieces <- list()

  if ("estimado" %in% products) {
    pieces$estimated <- tibble::tibble(
      tipo = "estimado",
      dia = NA_integer_,
      area = areas,
      endpoint = sprintf("/api/incendios/mapasriesgo/estimado/area/%s", areas)
    )
  }

  if ("previsto" %in% products) {
    pieces$forecast <- tidyr::crossing(
      dia = days,
      area = areas
    ) |>
      dplyr::mutate(
        tipo = "previsto",
        endpoint = sprintf("/api/incendios/mapasriesgo/previsto/dia/%s/area/%s", dia, area)
      ) |>
      dplyr::select(tipo, dia, area, endpoint)
  }

  dplyr::bind_rows(pieces)
}

request_aemet_metadata <- function(endpoint, api_key) {
  url <- paste0(AEMET_BASE, endpoint)

  resp <- suppressWarnings(
    httr2::request(url) |>
      httr2::req_headers(
        api_key = api_key,
        `User-Agent` = "visor-fuego/0.2"
      ) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_timeout(60) |>
      httr2::req_perform()
  )

  status <- httr2::resp_status(resp)

  body <- tryCatch(
    httr2::resp_body_json(resp, simplifyVector = TRUE),
    error = function(e) {
      list(
        estado = status,
        descripcion = paste("No se pudo leer JSON de metadatos:", conditionMessage(e))
      )
    }
  )

  body$http_status <- status
  body
}

metadata_is_available <- function(meta) {
  http_ok <- isTRUE(as.integer(meta$http_status %||% 0L) < 400L)
  aemet_ok <- is.null(meta$estado) || isTRUE(as.integer(meta$estado) == 200L)
  has_data <- !is.null(meta$datos) && length(meta$datos) == 1L && !is.na(meta$datos) && nzchar(meta$datos)
  http_ok && aemet_ok && has_data
}

download_aemet_data_url <- function(datos_url, out_stem) {
  resp <- suppressWarnings(
    httr2::request(datos_url) |>
      httr2::req_headers(`User-Agent` = "visor-fuego/0.2") |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_timeout(120) |>
      httr2::req_perform()
  )

  status <- httr2::resp_status(resp)
  if (status >= 400) {
    stop("Error HTTP ", status, " descargando recurso AEMET", call. = FALSE)
  }

  # Si AEMET devuelve URL con extensión, la priorizamos.
  url_ext <- tools::file_ext(basename(strsplit(datos_url, "\\?")[[1]][1]))
  ext <- if (nzchar(url_ext)) tolower(url_ext) else file_extension_from_response(resp)

  out <- file.path("data/raw/aemet", paste0(out_stem, ".", ext))
  fs::dir_create(dirname(out))
  writeBin(httr2::resp_body_raw(resp), out)
  out
}

manifest_row <- function(tipo, dia, area, endpoint, meta, file = NA_character_,
                         status = "missing", note = NA_character_) {
  tibble::tibble(
    downloaded_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    date = as.character(Sys.Date()),
    tipo = tipo,
    dia = dia,
    area = area,
    area_label = area_label(area),
    endpoint = endpoint,
    datos_url = meta$datos %||% NA_character_,
    metadatos_url = meta$metadatos %||% NA_character_,
    descripcion = meta$descripcion %||% note %||% NA_character_,
    estado = suppressWarnings(as.integer(meta$estado %||% NA_integer_)),
    http_status = suppressWarnings(as.integer(meta$http_status %||% NA_integer_)),
    status = status,
    file = file,
    file_type = if (!is.na(file) && nzchar(file)) infer_file_type(file) else NA_character_
  )
}

download_one_fire_product <- function(tipo, dia, area, endpoint, api_key, date = Sys.Date()) {
  label <- paste0(tipo, " ", area_label(area), if (!is.na(dia)) paste0(" día ", dia) else "")
  message("AEMET: ", label)

  meta <- request_aemet_metadata(endpoint, api_key)

  if (!metadata_is_available(meta)) {
    desc <- meta$descripcion %||% "sin datos disponibles"
    message("  - sin datos: ", desc)
    return(manifest_row(
      tipo = tipo,
      dia = dia,
      area = area,
      endpoint = endpoint,
      meta = meta,
      status = "missing",
      note = desc
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

  file <- download_aemet_data_url(meta$datos, stem)

  manifest_row(
    tipo = tipo,
    dia = dia,
    area = area,
    endpoint = endpoint,
    meta = meta,
    file = file,
    status = "downloaded"
  )
}
