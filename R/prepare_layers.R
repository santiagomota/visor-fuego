source("R/utils.R", encoding = "UTF-8")

risk_palette <- c(
  "#2c7bb6", # muy bajo / bajo
  "#abd9e9",
  "#ffffbf",
  "#fdae61",
  "#d7191c",
  "#7f0000"
)

risk_labels <- c(
  "Muy bajo",
  "Bajo",
  "Moderado",
  "Alto",
  "Muy alto",
  "Extremo"
)

hex_to_rgba <- function(hex, alpha = 1) {
  rgb <- grDevices::col2rgb(hex) / 255
  c(rgb[, 1], alpha)
}

write_spatraster_png <- function(file, out_png) {
  r <- terra::rast(file)

  if (is.na(terra::crs(r, describe = TRUE)$code[1]) && is.na(terra::crs(r))) {
    stop("Raster sin CRS: ", file, call. = FALSE)
  }

  if (!grepl("4326", terra::crs(r), fixed = TRUE)) {
    r <- terra::project(r, "EPSG:4326", method = "near")
  }

  r <- r[[1]]
  m <- terra::as.matrix(r, wide = TRUE)
  vals <- sort(unique(as.vector(m[!is.na(m)])))

  if (length(vals) == 0) {
    stop("Raster sin valores válidos: ", file, call. = FALSE)
  }

  palette <- risk_palette[seq_len(min(length(vals), length(risk_palette)))]
  if (length(vals) > length(palette)) {
    palette <- grDevices::hcl.colors(length(vals), palette = "Inferno")
  }
  names(palette) <- as.character(vals)

  nr <- nrow(m)
  nc <- ncol(m)
  arr <- array(0, dim = c(nr, nc, 4))

  for (v in vals) {
    idx <- which(m == v, arr.ind = TRUE)
    if (nrow(idx) > 0) {
      rgba <- hex_to_rgba(palette[[as.character(v)]], alpha = 0.80)
      for (k in seq_len(4)) {
        arr[cbind(idx[, 1], idx[, 2], k)] <- rgba[k]
      }
    }
  }

  fs::dir_create(dirname(out_png))
  png::writePNG(arr, target = out_png)

  e <- terra::ext(r)

  list(
    url = out_png,
    bounds = list(
      list(as.numeric(e$ymin), as.numeric(e$xmin)),
      list(as.numeric(e$ymax), as.numeric(e$xmax))
    ),
    values = vals,
    colours = unname(palette),
    labels = risk_labels[seq_along(vals)]
  )
}

prepare_image_layer <- function(row, out_dir = "docs/assets/aemet") {
  file <- row$file
  ext <- tolower(tools::file_ext(file))
  layer_id <- paste(
    "aemet",
    row$date,
    row$area,
    row$tipo,
    ifelse(is.na(row$dia), "hoy", paste0("d", row$dia)),
    sep = "_"
  ) |>
    safe_slug()

  fs::dir_create(out_dir)

  if (row$file_type == "image") {
    out_file <- file.path(out_dir, paste0(layer_id, ".", ext))
    fs::file_copy(file, out_file, overwrite = TRUE)

    layer_url <- sub("^docs/", "", out_file)
    bounds <- area_bounds(row$area)
    labels <- risk_labels
    colours <- risk_palette
  } else if (row$file_type == "raster") {
    out_file <- file.path(out_dir, paste0(layer_id, ".png"))
    raster_info <- write_spatraster_png(file, out_file)

    layer_url <- sub("^docs/", "", out_file)
    bounds <- raster_info$bounds
    labels <- raster_info$labels
    colours <- raster_info$colours
  } else {
    stop("Formato no soportado para visor web: ", file, call. = FALSE)
  }

  tibble::tibble(
    layer_id = layer_id,
    date = row$date,
    tipo = row$tipo,
    dia = row$dia,
    area = row$area,
    area_label = row$area_label,
    file_type = row$file_type,
    source_file = file,
    url = layer_url,
    bounds_json = jsonlite::toJSON(bounds, auto_unbox = TRUE),
    legend_labels = paste(labels, collapse = "|"),
    legend_colours = paste(colours, collapse = "|")
  )
}

prepare_layers_for_web <- function(manifest_file = "data/raw/aemet/manifest.csv") {
  if (!file.exists(manifest_file)) {
    message("No existe manifest de AEMET: ", manifest_file)
    return(tibble::tibble())
  }

  manifest <- readr::read_csv(manifest_file, show_col_types = FALSE)

  if (nrow(manifest) == 0) {
    message("Manifest vacío")
    return(tibble::tibble())
  }

  supported <- manifest |>
    dplyr::filter(file_type %in% c("image", "raster"), file.exists(file))

  if (nrow(supported) == 0) {
    message("No hay capas image/raster válidas que preparar")
    return(tibble::tibble())
  }

  layers <- purrr::map_dfr(seq_len(nrow(supported)), function(i) {
    tryCatch(
      prepare_image_layer(supported[i, ]),
      error = function(e) {
        warning("No se pudo preparar ", supported$file[i], ": ", conditionMessage(e))
        NULL
      }
    )
  })

  fs::dir_create("data/processed")
  fs::dir_create("docs/assets/aemet")

  readr::write_csv(layers, "data/processed/layers.csv")

  json_layers <- layers |>
    dplyr::mutate(
      bounds = purrr::map(bounds_json, jsonlite::fromJSON),
      legend_labels = strsplit(legend_labels, "\\|", fixed = FALSE),
      legend_colours = strsplit(legend_colours, "\\|", fixed = FALSE)
    ) |>
    dplyr::select(-bounds_json)

  jsonlite::write_json(
    json_layers,
    "docs/assets/aemet/layers.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )

  layers
}
