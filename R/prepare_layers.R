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

label_for_values <- function(vals) {
  vals <- sort(unique(vals))
  if (length(vals) == 5) return(c("Bajo", "Moderado", "Alto", "Muy alto", "Extremo"))
  if (length(vals) <= length(risk_labels)) return(risk_labels[seq_along(vals)])
  paste("Nivel", vals)
}

write_spatraster_png <- function(file, out_png) {
  r <- terra::rast(file)

  crs_txt <- terra::crs(r)
  if (is.na(crs_txt) || !nzchar(crs_txt)) {
    stop("Raster sin CRS: ", file, call. = FALSE)
  }

  if (!grepl("4326", crs_txt, fixed = TRUE)) {
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
  ev <- as.vector(e) # xmin, xmax, ymin, ymax

  list(
    url = out_png,
    bounds = list(
      list(as.numeric(ev[3]), as.numeric(ev[1])),
      list(as.numeric(ev[4]), as.numeric(ev[2]))
    ),
    values = vals,
    colours = unname(palette),
    labels = label_for_values(vals)
  )
}

is_probably_geojson <- function(file) {
  if (!file.exists(file)) return(FALSE)
  ext <- tolower(tools::file_ext(file))
  if (ext == "geojson") return(TRUE)
  if (ext != "json") return(FALSE)
  txt <- readLines(file, n = 25, warn = FALSE, encoding = "UTF-8")
  any(grepl('"type"\\s*:\\s*"FeatureCollection"', txt)) ||
    any(grepl('"type"\\s*:\\s*"Feature"', txt))
}

prepare_image_layer <- function(row, file = row$file, file_type = row$file_type, out_dir = "docs/assets/aemet") {
  ext <- tolower(tools::file_ext(file))
  layer_id <- paste(
    "aemet",
    row$date,
    row$area,
    row$tipo,
    ifelse(is.na(row$dia), "hoy", paste0("d", row$dia)),
    tools::file_path_sans_ext(basename(file)),
    sep = "_"
  ) |>
    safe_slug()

  fs::dir_create(out_dir)

  if (file_type == "image") {
    out_file <- file.path(out_dir, paste0(layer_id, ".", ext))
    fs::file_copy(file, out_file, overwrite = TRUE)

    layer_url <- sub("^docs/", "", out_file)
    bounds <- area_bounds(row$area)
    labels <- risk_labels
    colours <- risk_palette
    layer_kind <- "image"
  } else if (file_type == "raster") {
    out_file <- file.path(out_dir, paste0(layer_id, ".png"))
    raster_info <- write_spatraster_png(file, out_file)

    layer_url <- sub("^docs/", "", out_file)
    bounds <- raster_info$bounds
    labels <- raster_info$labels
    colours <- raster_info$colours
    layer_kind <- "image"
  } else if (file_type == "json" && is_probably_geojson(file)) {
    out_file <- file.path(out_dir, paste0(layer_id, ".geojson"))
    fs::file_copy(file, out_file, overwrite = TRUE)

    layer_url <- sub("^docs/", "", out_file)
    bounds <- area_bounds(row$area)
    labels <- risk_labels
    colours <- risk_palette
    layer_kind <- "geojson"
  } else {
    stop("Formato no soportado para visor web: ", file, " [", file_type, "]", call. = FALSE)
  }

  tibble::tibble(
    layer_id = layer_id,
    layer_kind = layer_kind,
    date = row$date,
    tipo = row$tipo,
    dia = row$dia,
    area = row$area,
    area_label = row$area_label,
    file_type = file_type,
    source_file = file,
    url = layer_url,
    bounds_json = as.character(jsonlite::toJSON(bounds, auto_unbox = TRUE)),
    legend_labels = paste(labels, collapse = "|"),
    legend_colours = paste(colours, collapse = "|")
  )
}

extract_zip_candidates <- function(zip_file) {
  extract_dir <- file.path("data/raw/aemet/extracted", tools::file_path_sans_ext(basename(zip_file)))
  fs::dir_create(extract_dir)
  utils::unzip(zip_file, exdir = extract_dir)

  files <- fs::dir_ls(extract_dir, recurse = TRUE, type = "file")
  tibble::tibble(
    candidate_file = as.character(files),
    candidate_type = vapply(files, infer_file_type, character(1))
  ) |>
    dplyr::filter(candidate_type %in% c("image", "raster", "json"))
}

discover_supported_files <- function(manifest) {
  manifest <- manifest |>
    dplyr::filter(status %in% c("downloaded", "cached", NA_character_) | is.na(status)) |>
    dplyr::filter(!is.na(file), file.exists(file))

  if (nrow(manifest) == 0) return(tibble::tibble())

  purrr::map_dfr(seq_len(nrow(manifest)), function(i) {
    row <- manifest[i, ]
    file <- normalise_downloaded_extension(row$file)
    ft <- infer_file_type(file)

    if (ft == "zip") {
      candidates <- extract_zip_candidates(file)
      if (nrow(candidates) == 0) return(tibble::tibble())
      candidates |>
        dplyr::mutate(row_index = i)
    } else {
      tibble::tibble(
        row_index = i,
        candidate_file = file,
        candidate_type = ft
      ) |>
        dplyr::filter(candidate_type %in% c("image", "raster", "json"))
    }
  }) |>
    dplyr::left_join(
      manifest |>
        dplyr::mutate(row_index = dplyr::row_number()),
      by = "row_index"
    )
}


parse_aemet_filename <- function(file) {
  base <- basename(file)
  m <- stringr::str_match(
    base,
    "^aemet_incendios_(\\d{8})_([pbc])_(estimado|previsto)_(d\\d+|hoy)\\.(png|jpg|jpeg|webp|gif|tif|tiff|zip|json|geojson|bin)$"
  )

  if (is.na(m[1, 1])) return(NULL)

  date_txt <- m[1, 2]
  area <- m[1, 3]
  tipo <- m[1, 4]
  dia_txt <- m[1, 5]
  dia <- if (identical(dia_txt, "hoy")) NA_integer_ else as.integer(sub("^d", "", dia_txt))

  tibble::tibble(
    downloaded_at = NA_character_,
    date = as.character(as.Date(date_txt, format = "%Y%m%d")),
    status = "downloaded",
    tipo = tipo,
    dia = dia,
    area = area,
    area_label = area_label(area),
    endpoint = NA_character_,
    datos_url = NA_character_,
    metadatos_url = NA_character_,
    descripcion = "Descubierto en data/raw/aemet sin entrada en manifest",
    estado = NA_integer_,
    http_status = NA_integer_,
    file = as.character(file),
    file_type = infer_file_type(file)
  )
}

discover_orphan_raw_downloads <- function(manifest) {
  if (!fs::dir_exists("data/raw/aemet")) return(tibble::tibble())

  files <- fs::dir_ls(
    "data/raw/aemet",
    regexp = "\\.(png|jpg|jpeg|webp|gif|tif|tiff|zip|json|geojson|bin)$",
    recurse = FALSE,
    type = "file"
  )

  if (length(files) == 0) return(tibble::tibble())

  normalised <- vapply(as.character(files), normalise_downloaded_extension, character(1))

  rows <- purrr::map(normalised, parse_aemet_filename) |>
    purrr::compact() |>
    dplyr::bind_rows()

  if (nrow(rows) == 0) return(rows)

  existing_files <- unique(stats::na.omit(manifest$file))
  rows |>
    dplyr::filter(!file %in% existing_files) |>
    dplyr::filter(file_type %in% c("image", "raster", "zip", "json"))
}

prepare_layers_for_web <- function(manifest_file = "data/raw/aemet/manifest.csv") {
  if (!file.exists(manifest_file)) {
    message("No existe manifest de AEMET: ", manifest_file)
    return(tibble::tibble())
  }

  manifest <- readr::read_csv(manifest_file, show_col_types = FALSE) |>
    normalise_manifest_types()

  if (nrow(manifest) == 0) {
    message("Manifest vacío")
    return(tibble::tibble())
  }

  if (!"status" %in% names(manifest)) manifest$status <- "downloaded"

  orphan_rows <- discover_orphan_raw_downloads(manifest) |>
    normalise_manifest_types()
  if (nrow(orphan_rows) > 0) {
    message("Capas encontradas en data/raw/aemet fuera del manifest: ", nrow(orphan_rows))
    manifest <- dplyr::bind_rows(
      normalise_manifest_types(manifest),
      normalise_manifest_types(orphan_rows)
    ) |>
      normalise_manifest_types()
  }

  supported <- discover_supported_files(manifest)

  if (nrow(supported) == 0) {
    message("No hay capas image/raster/geojson válidas que preparar")
    message("Tipos descargados en manifest: ", paste(unique(manifest$file_type), collapse = ", "))
    return(tibble::tibble())
  }

  layers <- purrr::map_dfr(seq_len(nrow(supported)), function(i) {
    tryCatch(
      prepare_image_layer(
        row = supported[i, ],
        file = supported$candidate_file[i],
        file_type = supported$candidate_type[i]
      ),
      error = function(e) {
        warning("No se pudo preparar ", supported$candidate_file[i], ": ", conditionMessage(e))
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

  message("Capas web generadas: ", nrow(layers))
  layers
}
