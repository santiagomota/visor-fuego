source("R/utils.R", encoding = "UTF-8")

AEMET_BASE <- "https://opendata.aemet.es/opendata"

fire_endpoints <- function(days = 1:7, areas = c("p", "b", "c")) {
  estimated <- tibble::tibble(
    tipo = "estimado",
    dia = NA_integer_,
    area = areas,
    endpoint = sprintf("/api/incendios/mapasriesgo/estimado/area/%s", areas)
  )

  forecast <- tidyr::crossing(
    dia = days,
    area = areas
  ) |>
    dplyr::mutate(
      tipo = "previsto",
      endpoint = sprintf("/api/incendios/mapasriesgo/previsto/dia/%s/area/%s", dia, area)
    ) |>
    dplyr::select(tipo, dia, area, endpoint)

  dplyr::bind_rows(estimated, forecast)
}

request_aemet_metadata <- function(endpoint, api_key) {
  url <- paste0(AEMET_BASE, endpoint)

  resp <- httr2::request(url) |>
    httr2::req_headers(
      api_key = api_key,
      `User-Agent` = "visor-fuego/0.1"
    ) |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_perform()

  status <- httr2::resp_status(resp)
  body <- httr2::resp_body_json(resp, simplifyVector = TRUE)

  if (status >= 400) {
    stop("Error HTTP ", status, " consultando ", endpoint, call. = FALSE)
  }

  if (!is.null(body$estado) && as.integer(body$estado) != 200L) {
    stop("AEMET respondió estado ", body$estado, ": ", body$descripcion %||% "sin descripción", call. = FALSE)
  }

  body
}

download_aemet_data_url <- function(datos_url, out_stem) {
  resp <- httr2::request(datos_url) |>
    httr2::req_headers(`User-Agent` = "visor-fuego/0.1") |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_perform()

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

download_one_fire_product <- function(tipo, dia, area, endpoint, api_key, date = Sys.Date()) {
  message("AEMET: ", tipo, " ", area_label(area), if (!is.na(dia)) paste0(" día ", dia) else "")

  meta <- request_aemet_metadata(endpoint, api_key)
  datos_url <- meta$datos %||% NA_character_

  if (is.na(datos_url) || !nzchar(datos_url)) {
    stop("La respuesta de AEMET no incluye campo 'datos' para ", endpoint, call. = FALSE)
  }

  stem <- paste(
    "aemet_incendios",
    format(as.Date(date), "%Y%m%d"),
    area,
    tipo,
    if (!is.na(dia)) paste0("d", dia) else "hoy",
    sep = "_"
  )

  file <- download_aemet_data_url(datos_url, stem)

  tibble::tibble(
    downloaded_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    date = as.character(as.Date(date)),
    tipo = tipo,
    dia = dia,
    area = area,
    area_label = area_label(area),
    endpoint = endpoint,
    datos_url = datos_url,
    metadatos_url = meta$metadatos %||% NA_character_,
    descripcion = meta$descripcion %||% NA_character_,
    estado = meta$estado %||% NA_integer_,
    file = file,
    file_type = infer_file_type(file)
  )
}
