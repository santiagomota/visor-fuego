#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")
source("R/prepare_layers.R", encoding = "UTF-8")

check_required_packages(c("readr", "dplyr", "purrr", "tibble", "terra", "jsonlite", "fs", "png"))

layers_file <- "data/processed/layers.csv"
if (!file.exists(layers_file)) {
  stop("No existe ", layers_file, ". Ejecuta primero: Rscript scripts/02_prepare_web_assets.R", call. = FALSE)
}

layers <- readr::read_csv(layers_file, show_col_types = FALSE)
if (nrow(layers) == 0) {
  stop("layers.csv está vacío", call. = FALSE)
}


parse_bounds_matrix <- function(bounds_json) {
  b <- tryCatch(jsonlite::fromJSON(bounds_json), error = function(e) NULL)
  if (is.null(b)) return(matrix(NA_real_, nrow = 2, ncol = 2))
  if (is.matrix(b) || is.data.frame(b)) {
    m <- as.matrix(b)
  } else {
    m <- matrix(unlist(b), ncol = 2, byrow = TRUE)
  }
  if (!all(dim(m) == c(2, 2))) return(matrix(NA_real_, nrow = 2, ncol = 2))
  storage.mode(m) <- "numeric"
  m
}

asset_path <- function(url) {
  if (is.na(url) || !nzchar(url)) return(NA_character_)
  candidates <- c(url, file.path("assets", sub("^assets/", "", url)), file.path("docs", url))
  candidates[file.exists(candidates)][1] %||% candidates[1]
}

inspect_one <- function(row) {
  src <- row$source_file %||% NA_character_
  r <- NULL
  source_ok <- !is.na(src) && file.exists(src) && identical(row$file_type, "raster")
  if (source_ok) {
    r <- tryCatch(terra::rast(src), error = function(e) NULL)
  }

  url_path <- asset_path(row$url)
  png_dim <- c(NA_integer_, NA_integer_)
  if (!is.na(url_path) && file.exists(url_path)) {
    img <- tryCatch(png::readPNG(url_path, info = TRUE), error = function(e) NULL)
    if (!is.null(img)) png_dim <- dim(img)[2:1]
  }

  bounds <- parse_bounds_matrix(row$bounds_json)

  tibble::tibble(
    layer_id = row$layer_id,
    date = row$date,
    area = row$area,
    dia = row$dia,
    source_file = src,
    source_exists = source_ok,
    source_crs_detected = if (!is.null(r)) terra::crs(r) else NA_character_,
    render_crs = row$render_crs %||% NA_character_,
    png_file = url_path,
    png_exists = !is.na(url_path) && file.exists(url_path),
    png_width = as.integer(png_dim[1]),
    png_height = as.integer(png_dim[2]),
    bounds_south = as.numeric(bounds[1, 1]),
    bounds_west = as.numeric(bounds[1, 2]),
    bounds_north = as.numeric(bounds[2, 1]),
    bounds_east = as.numeric(bounds[2, 2]),
    source_xmin = if (!is.null(r)) as.numeric(extent_vector(r)[["xmin"]]) else NA_real_,
    source_xmax = if (!is.null(r)) as.numeric(extent_vector(r)[["xmax"]]) else NA_real_,
    source_ymin = if (!is.null(r)) as.numeric(extent_vector(r)[["ymin"]]) else NA_real_,
    source_ymax = if (!is.null(r)) as.numeric(extent_vector(r)[["ymax"]]) else NA_real_
  )
}

diag <- purrr::map_dfr(seq_len(nrow(layers)), function(i) inspect_one(layers[i, ]))

fs::dir_create("data/processed")
readr::write_csv(diag, "data/processed/aemet_alignment_diagnostics.csv")

message("Diagnóstico guardado en: data/processed/aemet_alignment_diagnostics.csv")
message("Capas: ", nrow(diag))
message("render_crs:")
print(diag |> dplyr::count(render_crs), n = Inf)
message("PNG generados:")
print(diag |> dplyr::count(png_exists, png_width, png_height), n = Inf)

if (any(grepl("4326", diag$render_crs %||% "", fixed = TRUE), na.rm = TRUE)) {
  message("Sugerencia: regenera con AEMET_LEAFLET_PROJECTION=3857 para reducir discrepancias en Leaflet.")
}
