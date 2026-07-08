source("R/utils.R", encoding = "UTF-8")

AEMET_CLASSIC_BASE <- "https://www.aemet.es"
AEMET_CLASSIC_INCENDIOS <- "https://www.aemet.es/es/eltiempo/prediccion/incendios"
AEMET_CLASSIC_DOWNLOAD <- "https://www.aemet.es/es/api-eltiempo/incendios/download"

classic_handle <- function(user_agent = "visor-fuego-aemet-classic/0.5.14") {
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
  m <- stringr::str_match(base, "^down_(\\d{8})_peligro_([pc])_D(\\d{2})\\.tif$")
  if (is.na(m[1, 1])) return(NULL)

  tibble::tibble(
    date = as.character(as.Date(m[1, 2], format = "%Y%m%d")),
    area = m[1, 3],
    dia = as.integer(m[1, 4]),
    original_file = as.character(file)
  )
}

classic_download_archive <- function(out_dir = "data/raw/aemet_classic") {
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

  message("Descargando paquete SIG AEMET clásico...")
  resp <- classic_fetch_memory(
    AEMET_CLASSIC_DOWNLOAD,
    handle = h,
    referer = AEMET_CLASSIC_INCENDIOS,
    accept = "application/gzip,application/x-gzip,application/tar,image/tiff,image/geotiff,application/geotiff,application/octet-stream,*/*;q=0.2"
  )

  if (resp$status_code >= 400) {
    stop("AEMET clásico respondió HTTP ", resp$status_code, ": ", raw_preview_text(resp$content, 500), call. = FALSE)
  }

  ext <- response_extension(resp, fallback = "bin")
  raw_path <- file.path(out_dir, "responses", paste0("aemet_classic_incendios_download.", ext))
  writeBin(resp$content, raw_path)
  normalise_downloaded_extension(raw_path)
}

extract_classic_geotiffs <- function(archive_path, out_dir = "data/raw/aemet_classic/extracted") {
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

  # Nos quedamos con un único fichero por fecha/área/día. El endpoint directo trae
  # todos los D00..D07 para Península/Baleares (p) y Canarias (c), sin necesidad
  # de probar parámetros adicionales.
  meta |>
    dplyr::arrange(area, dia, original_file) |>
    dplyr::distinct(date, area, dia, .keep_all = TRUE)
}

install_classic_geotiffs <- function(tif_meta, raw_dir = "data/raw/aemet") {
  fs::dir_create(raw_dir)

  purrr::pmap_dfr(tif_meta, function(date, area, dia, original_file) {
    date_compact <- format(as.Date(date), "%Y%m%d")
    out_file <- file.path(
      raw_dir,
      sprintf("aemet_incendios_%s_%s_previsto_d%s.tif", date_compact, area, dia)
    )
    fs::file_copy(original_file, out_file, overwrite = TRUE)

    tibble::tibble(
      downloaded_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      date = as.character(date),
      status = "downloaded",
      tipo = "previsto",
      dia = as.integer(dia),
      area = as.character(area),
      area_label = area_label(area),
      endpoint = "/es/api-eltiempo/incendios/download",
      datos_url = AEMET_CLASSIC_DOWNLOAD,
      metadatos_url = NA_character_,
      descripcion = "AEMET clásico: paquete SIG GeoTIFF extraído de /es/api-eltiempo/incendios/download",
      estado = 200L,
      http_status = 200L,
      file = as.character(out_file),
      file_type = "raster"
    )
  }) |>
    normalise_manifest_types()
}

download_aemet_classic_incendios <- function(out_dir = "data/raw/aemet_classic", raw_dir = "data/raw/aemet") {
  archive_path <- classic_download_archive(out_dir = out_dir)
  message("Paquete descargado: ", archive_path, " [", infer_file_type(archive_path), "]")

  tif_meta <- extract_classic_geotiffs(
    archive_path,
    out_dir = file.path(out_dir, "extracted", tools::file_path_sans_ext(basename(archive_path)))
  )
  message("GeoTIFFs AEMET encontrados: ", nrow(tif_meta))

  manifest <- install_classic_geotiffs(tif_meta, raw_dir = raw_dir)
  readr::write_csv(manifest, file.path(raw_dir, "manifest.csv"))
  message("Manifest guardado en ", file.path(raw_dir, "manifest.csv"))

  summary <- manifest |>
    dplyr::count(area_label, dia, file_type) |>
    dplyr::arrange(area_label, dia)
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
    dplyr::arrange(area, dia, original_file) |>
    dplyr::distinct(date, area, dia, .keep_all = TRUE)

  if (nrow(tif_meta) == 0) {
    stop("No se encontraron GeoTIFFs AEMET válidos en ", contents_csv, call. = FALSE)
  }

  manifest <- install_classic_geotiffs(tif_meta, raw_dir = raw_dir)
  readr::write_csv(manifest, file.path(raw_dir, "manifest.csv"))
  message("GeoTIFFs instalados desde probe clásico: ", nrow(manifest))
  message("Manifest guardado en ", file.path(raw_dir, "manifest.csv"))
  invisible(manifest)
}
