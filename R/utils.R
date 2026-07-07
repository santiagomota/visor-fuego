`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
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

file_extension_from_response <- function(resp, fallback = "bin") {
  cd <- httr2::resp_header(resp, "content-disposition")
  if (!is.null(cd) && grepl("filename=", cd, ignore.case = TRUE)) {
    filename <- sub('.*filename="?([^";]+)"?.*', "\\1", cd)
    ext <- tools::file_ext(filename)
    if (nzchar(ext)) return(tolower(ext))
  }

  ct <- httr2::resp_content_type(resp) %||% ""
  ct <- tolower(ct)

  dplyr::case_when(
    grepl("png", ct) ~ "png",
    grepl("jpeg|jpg", ct) ~ "jpg",
    grepl("gif", ct) ~ "gif",
    grepl("tiff|geotiff", ct) ~ "tif",
    grepl("zip", ct) ~ "zip",
    grepl("json", ct) ~ "json",
    TRUE ~ fallback
  )
}

infer_file_type <- function(path) {
  ext <- tolower(tools::file_ext(path))

  dplyr::case_when(
    ext %in% c("png", "jpg", "jpeg", "gif", "webp") ~ "image",
    ext %in% c("tif", "tiff", "asc", "grd", "nc") ~ "raster",
    ext %in% c("zip") ~ "zip",
    ext %in% c("json", "geojson") ~ "json",
    TRUE ~ "unknown"
  )
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
    p = "Península",
    b = "Baleares",
    c = "Canarias"
  )
  unname(labels[[area]] %||% area)
}
