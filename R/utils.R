`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}


normalise_manifest_types <- function(x) {
  if (is.null(x) || !is.data.frame(x) || nrow(x) == 0) return(x)

  char_cols <- intersect(
    c(
      "downloaded_at", "date", "issue_date", "valid_date", "status", "tipo", "area", "area_label",
      "endpoint", "datos_url", "metadatos_url", "descripcion", "forecast_label",
      "file", "file_type"
    ),
    names(x)
  )

  if (length(char_cols) > 0) {
    x <- x |>
      dplyr::mutate(dplyr::across(dplyr::all_of(char_cols), ~ as.character(.x)))
  }

  if ("dia" %in% names(x)) {
    x$dia <- suppressWarnings(as.integer(x$dia))
  }
  if ("forecast_day" %in% names(x)) {
    x$forecast_day <- suppressWarnings(as.integer(x$forecast_day))
  }
  if ("estado" %in% names(x)) {
    x$estado <- suppressWarnings(as.integer(x$estado))
  }
  if ("http_status" %in% names(x)) {
    x$http_status <- suppressWarnings(as.integer(x$http_status))
  }

  x
}

check_required_packages <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    stop(
      "Faltan paquetes R: ", paste(missing, collapse = ", "),
      "\nInstala con install.packages(c(",
      paste(sprintf('"%s"', missing), collapse = ", "), "))",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

safe_slug <- function(x) {
  x |>
    stringr::str_to_lower() |>
    stringr::str_replace_all("[^a-z0-9]+", "_") |>
    stringr::str_replace_all("(^_|_$)", "")
}

content_disposition_filename <- function(cd) {
  if (is.null(cd) || !nzchar(cd)) return(NA_character_)

  # RFC 5987: filename*=UTF-8''nombre.ext
  if (grepl("filename\\*=", cd, ignore.case = TRUE)) {
    fn <- sub(".*filename\\*=[^']*''([^;]+).*", "\\1", cd, ignore.case = TRUE)
    fn <- utils::URLdecode(fn)
    if (nzchar(fn) && !identical(fn, cd)) return(fn)
  }

  if (grepl("filename=", cd, ignore.case = TRUE)) {
    fn <- sub('.*filename="?([^";]+)"?.*', "\\1", cd, ignore.case = TRUE)
    fn <- utils::URLdecode(fn)
    if (nzchar(fn) && !identical(fn, cd)) return(fn)
  }

  NA_character_
}

raw_starts_with <- function(raw, signature) {
  # readBin(..., what = "raw") devuelve valores raw; as.integer() los pasa a 0:255.
  # Usamos comparación numérica, no identical(), porque c(0x89, ...) crea numeric
  # y identical(integer, numeric) es FALSE aunque los valores coincidan.
  length(raw) >= length(signature) &&
    all(as.integer(raw[seq_along(signature)]) == as.integer(signature))
}

sniff_file_extension <- function(raw, fallback = "bin") {
  if (raw_starts_with(raw, c(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))) {
    return("png")
  }
  if (raw_starts_with(raw, c(0xFF, 0xD8, 0xFF))) {
    return("jpg")
  }
  if (raw_starts_with(raw, c(0x52, 0x49, 0x46, 0x46)) && length(raw) >= 12 &&
      rawToChar(raw[9:12], multiple = FALSE) == "WEBP") {
    return("webp")
  }
  if (raw_starts_with(raw, c(0x1F, 0x8B))) {
    return("gz")
  }
  if (raw_starts_with(raw, c(0x50, 0x4B, 0x03, 0x04)) || raw_starts_with(raw, c(0x50, 0x4B, 0x05, 0x06)) || raw_starts_with(raw, c(0x50, 0x4B, 0x07, 0x08))) {
    return("zip")
  }
  # Los .tar no tienen firma al principio. El marcador POSIX "ustar" aparece
  # en los bytes 258:262. Esto es relevante porque AEMET parece devolver
  # paquetes .tar.gz desde el endpoint clásico de descarga SIG.
  if (length(raw) >= 262) {
    tar_magic <- tryCatch(rawToChar(raw[258:262], multiple = FALSE), error = function(e) "")
    if (identical(tar_magic, "ustar")) return("tar")
  }
  if (raw_starts_with(raw, c(0x49, 0x49, 0x2A, 0x00)) || raw_starts_with(raw, c(0x4D, 0x4D, 0x00, 0x2A)) ||
      raw_starts_with(raw, c(0x49, 0x49, 0x2B, 0x00)) || raw_starts_with(raw, c(0x4D, 0x4D, 0x00, 0x2B))) {
    return("tif")
  }
  if (length(raw) >= 1) {
    prefix <- tryCatch(
      rawToChar(raw[seq_len(min(length(raw), 4096))], multiple = FALSE),
      error = function(e) ""
    )
    prefix_utf8 <- suppressWarnings(enc2utf8(prefix))
    prefix_latin1 <- suppressWarnings(iconv(prefix, from = "latin1", to = "UTF-8", sub = "byte"))
    prefix <- trimws(paste(prefix_utf8, prefix_latin1, sep = "\n"))
    prefix_low <- tolower(prefix)

    if (startsWith(trimws(prefix), "{") || startsWith(trimws(prefix), "[")) return("json")
    if (grepl("<svg", prefix_low, fixed = TRUE)) return("svg")
    if (grepl("<kml", prefix_low, fixed = TRUE) || grepl("<gml", prefix_low, fixed = TRUE)) return("xml")
    if (grepl("<!doctype html", prefix_low, fixed = TRUE) || grepl("<html", prefix_low, fixed = TRUE)) return("html")
  }
  fallback
}

file_extension_from_response <- function(resp, body_raw = NULL, fallback = "bin") {
  cd <- httr2::resp_header(resp, "content-disposition")
  filename <- content_disposition_filename(cd)
  if (!is.na(filename)) {
    ext <- tools::file_ext(filename)
    if (nzchar(ext)) return(tolower(ext))
  }

  # Si AEMET no informa bien el nombre, el Content-Type suele ser lo único disponible.
  ct <- httr2::resp_content_type(resp) %||% ""
  ct <- tolower(ct)

  ext_from_ct <- dplyr::case_when(
    grepl("png", ct) ~ "png",
    grepl("jpeg|jpg", ct) ~ "jpg",
    grepl("gif", ct) ~ "gif",
    grepl("tiff|geotiff", ct) ~ "tif",
    grepl("zip|compressed", ct) ~ "zip",
    grepl("geojson", ct) ~ "geojson",
    grepl("json", ct) ~ "json",
    grepl("svg", ct) ~ "svg",
    grepl("xml|kml|gml", ct) ~ "xml",
    grepl("html", ct) ~ "html",
    TRUE ~ NA_character_
  )
  if (!is.na(ext_from_ct)) return(ext_from_ct)

  if (!is.null(body_raw)) return(sniff_file_extension(body_raw, fallback = fallback))
  fallback
}

decompress_gzip_file <- function(path, keep_gz = TRUE) {
  if (is.na(path) || !file.exists(path)) return(path)

  size <- file.info(path)$size
  if (is.na(size) || size <= 0) return(path)

  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, what = "raw", n = size)

  if (!raw_starts_with(raw, c(0x1F, 0x8B))) return(path)

  payload <- tryCatch(
    memDecompress(raw, type = "gzip"),
    error = function(e) NULL
  )

  if (is.null(payload) || length(payload) == 0) return(path)

  inner_ext <- sniff_file_extension(payload[seq_len(min(length(payload), 4096))], fallback = "bin")
  if (!nzchar(inner_ext) || inner_ext %in% c("gz", "unknown")) {
    inner_ext <- "bin"
  }

  base <- tools::file_path_sans_ext(path)
  out <- paste0(base, ".", inner_ext)
  writeBin(payload, out)

  if (!keep_gz) {
    try(unlink(path), silent = TRUE)
  }

  out
}

infer_file_type <- function(path) {
  if (is.na(path) || !file.exists(path)) return(NA_character_)

  ext <- tolower(tools::file_ext(path))
  if (ext == "gz") {
    normalised <- decompress_gzip_file(path, keep_gz = TRUE)
    if (!identical(normalised, path) && file.exists(normalised)) {
      return(infer_file_type(normalised))
    }
    return("gzip")
  }
  if (ext %in% c("png", "jpg", "jpeg", "gif", "webp", "svg")) return("image")
  if (ext %in% c("tif", "tiff", "asc", "grd", "nc")) return("raster")
  if (ext %in% c("zip")) return("zip")
  if (ext %in% c("tar")) return("archive")
  if (ext %in% c("json", "geojson")) return("json")
  if (ext %in% c("kml", "gml", "xml")) return("xml")

  # Fallback por cabecera binaria, útil cuando AEMET devuelve application/octet-stream.
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, what = "raw", n = min(file.info(path)$size, 4096))
  sniffed <- sniff_file_extension(raw, fallback = "unknown")

  if (identical(sniffed, "gz")) {
    normalised <- decompress_gzip_file(path, keep_gz = TRUE)
    if (!identical(normalised, path) && file.exists(normalised)) {
      return(infer_file_type(normalised))
    }
    return("gzip")
  }

  dplyr::case_when(
    sniffed %in% c("png", "jpg", "jpeg", "gif", "webp", "svg") ~ "image",
    sniffed %in% c("tif", "tiff", "asc", "grd", "nc") ~ "raster",
    sniffed == "zip" ~ "zip",
    sniffed == "tar" ~ "archive",
    sniffed %in% c("json", "geojson") ~ "json",
    sniffed == "xml" ~ "xml",
    sniffed == "html" ~ "html",
    TRUE ~ "unknown"
  )
}

normalise_downloaded_extension <- function(path) {
  if (is.na(path) || !file.exists(path)) return(path)

  ext <- tolower(tools::file_ext(path))

  if (identical(ext, "gz")) {
    return(decompress_gzip_file(path, keep_gz = TRUE))
  }

  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, what = "raw", n = min(file.info(path)$size, 4096))
  sniffed <- sniff_file_extension(raw, fallback = ext %||% "bin")

  if (identical(sniffed, "gz")) {
    return(decompress_gzip_file(path, keep_gz = TRUE))
  }

  if (nzchar(ext) && !ext %in% c("bin", "unknown", "txt", "text")) return(path)

  if (!nzchar(sniffed) || sniffed %in% c("bin", "unknown")) return(path)

  new_path <- paste0(tools::file_path_sans_ext(path), ".", sniffed)
  if (!identical(path, new_path)) fs::file_move(path, new_path)
  new_path
}


extract_aemet_archive <- function(path, out_dir = NULL) {
  if (is.na(path) || !file.exists(path)) return(character())
  ext <- tolower(tools::file_ext(path))
  type <- infer_file_type(path)

  if (is.null(out_dir)) {
    out_dir <- file.path(dirname(path), paste0(tools::file_path_sans_ext(basename(path)), "_extracted"))
  }
  fs::dir_create(out_dir)

  extracted <- character()

  if (identical(ext, "gz") || identical(type, "gzip")) {
    norm <- decompress_gzip_file(path, keep_gz = TRUE)
    if (!identical(norm, path) && file.exists(norm)) {
      return(extract_aemet_archive(norm, out_dir = out_dir))
    }
  }

  if (identical(type, "zip") || identical(ext, "zip")) {
    extracted <- tryCatch({
      utils::unzip(path, exdir = out_dir)
      fs::dir_ls(out_dir, recurse = TRUE, type = "file")
    }, error = function(e) character())
  } else if (identical(type, "archive") || identical(ext, "tar")) {
    extracted <- tryCatch({
      utils::untar(path, exdir = out_dir)
      fs::dir_ls(out_dir, recurse = TRUE, type = "file")
    }, error = function(e) character())
  }

  as.character(extracted)
}

find_geospatial_files <- function(paths) {
  if (length(paths) == 0) return(tibble::tibble())
  paths <- as.character(paths)
  paths <- paths[file.exists(paths)]
  if (length(paths) == 0) return(tibble::tibble())

  tibble::tibble(file = paths) |>
    dplyr::mutate(
      ext = tolower(tools::file_ext(file)),
      file_type = vapply(file, infer_file_type, character(1)),
      size_bytes = as.numeric(file.info(file)$size),
      is_geospatial = file_type %in% c("raster", "zip", "json", "xml") |
        ext %in% c("tif", "tiff", "asc", "grd", "nc", "geojson", "json", "kml", "gml", "gpkg", "shp")
    ) |>
    dplyr::filter(is_geospatial)
}

area_bounds <- function(area) {
  # Bounds aproximados en WGS84 para superponer imágenes no georreferenciadas.
  # Leaflet usa [[lat_min, lon_min], [lat_max, lon_max]].
  bounds <- list(
    p = list(list(35.70, -10.20), list(44.55, 4.80)),
    b = list(list(38.45, 0.70), list(40.25, 4.75)),
    c = list(list(27.35, -18.50), list(29.70, -13.10))
  )

  bounds[[area]] %||% bounds[["p"]]
}

area_label <- function(area) {
  labels <- c(
    p = "Península y Baleares",
    b = "Baleares",
    c = "Canarias"
  )
  unname(labels[[area]] %||% area)
}
