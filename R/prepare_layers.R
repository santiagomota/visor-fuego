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

allow_aemet_png_overlay <- function() {
  tolower(Sys.getenv("AEMET_ALLOW_PNG_OVERLAY", unset = "false")) %in% c("1", "true", "yes", "si", "sí")
}

# Leaflet usa EPSG:3857/Web Mercator para la vista del mapa. Si se genera un PNG
# directamente desde un raster EPSG:4326 y se estira con L.imageOverlay(), el ajuste
# puede desviarse ligeramente en áreas grandes. Por defecto reproyectamos a 3857
# antes de generar el PNG y luego pasamos a Leaflet los bounds equivalentes en lon/lat.
aemet_leaflet_projection <- function() {
  value <- tolower(trimws(Sys.getenv("AEMET_LEAFLET_PROJECTION", unset = "3857")))
  if (value %in% c("3857", "epsg:3857", "webmercator", "web_mercator", "mercator")) {
    return("EPSG:3857")
  }
  if (value %in% c("4326", "epsg:4326", "lonlat", "lon_lat", "geographic", "wgs84")) {
    return("EPSG:4326")
  }
  warning("AEMET_LEAFLET_PROJECTION no reconocido: ", value, ". Uso EPSG:3857.", call. = FALSE)
  "EPSG:3857"
}

read_numeric_env <- function(name, default = 0) {
  value <- suppressWarnings(as.numeric(Sys.getenv(name, unset = as.character(default))))
  if (length(value) == 0 || is.na(value)) default else value
}

include_orphan_aemet_raw <- function() {
  tolower(Sys.getenv("AEMET_INCLUDE_ORPHAN_RAW", unset = "false")) %in% c("1", "true", "yes", "si", "sí")
}

clean_aemet_web_assets <- function(out_dirs = c("assets/aemet", "docs/assets/aemet")) {
  clean <- tolower(Sys.getenv("AEMET_CLEAN_WEB_ASSETS", unset = "true")) %in% c("1", "true", "yes", "si", "sí")
  if (!clean) return(invisible(FALSE))

  for (d in out_dirs) {
    if (fs::dir_exists(d)) {
      old <- tryCatch(
        fs::dir_ls(
          d,
          regexp = "(aemet_|layers\\.json$).*(png|jpg|jpeg|webp|gif|geojson|json)$|layers\\.json$",
          recurse = FALSE,
          type = "file"
        ),
        error = function(e) character()
      )
      if (length(old) > 0) fs::file_delete(old)
    }
    fs::dir_create(d)
  }

  invisible(TRUE)
}

# Orden de presentación en el selector Leaflet: primero Península y Baleares,
# luego Baleares si existe como producto independiente, y finalmente Canarias.
aemet_area_display_rank <- function(area) {
  rank <- dplyr::case_when(
    area == "p" ~ 1L,
    area == "b" ~ 2L,
    area == "c" ~ 3L,
    TRUE ~ 99L
  )
  as.integer(rank)
}

valid_date_sort_rank <- function(valid_date, today = Sys.Date()) {
  d <- suppressWarnings(as.Date(valid_date))
  ifelse(
    is.na(d),
    999999L,
    dplyr::case_when(
      d == today ~ 0L,
      d > today ~ as.integer(d - today),
      TRUE ~ 10000L + as.integer(today - d)
    )
  ) |>
    as.integer()
}

apply_bounds_nudge <- function(bounds) {
  lon <- read_numeric_env("AEMET_BOUNDS_NUDGE_LON", 0)
  lat <- read_numeric_env("AEMET_BOUNDS_NUDGE_LAT", 0)
  if (identical(lon, 0) && identical(lat, 0)) return(bounds)

  list(
    list(bounds[[1]][[1]] + lat, bounds[[1]][[2]] + lon),
    list(bounds[[2]][[1]] + lat, bounds[[2]][[2]] + lon)
  )
}

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

extent_vector <- function(r) {
  ev <- as.vector(terra::ext(r)) # xmin, xmax, ymin, ymax
  stats::setNames(as.numeric(ev), c("xmin", "xmax", "ymin", "ymax"))
}

extent_to_leaflet_bounds <- function(r, crs_hint = terra::crs(r)) {
  ev <- extent_vector(r)

  if (grepl("3857", crs_hint, fixed = TRUE)) {
    # Un PNG en Web Mercator debe estirarse en la proyección interna de Leaflet.
    # Transformamos solo las esquinas del rectángulo proyectado de vuelta a lon/lat
    # para suministrar LatLngBounds a L.imageOverlay().
    pts <- terra::vect(
      data.frame(x = c(ev[["xmin"]], ev[["xmax"]]), y = c(ev[["ymin"]], ev[["ymax"]])),
      geom = c("x", "y"),
      crs = "EPSG:3857"
    )
    pts_4326 <- terra::project(pts, "EPSG:4326")
    xy <- terra::crds(pts_4326)
    bounds <- list(
      list(as.numeric(min(xy[, 2])), as.numeric(min(xy[, 1]))),
      list(as.numeric(max(xy[, 2])), as.numeric(max(xy[, 1])))
    )
  } else {
    # Caso EPSG:4326 u otra proyección lon/lat ya normalizada.
    bounds <- list(
      list(as.numeric(ev[["ymin"]]), as.numeric(ev[["xmin"]])),
      list(as.numeric(ev[["ymax"]]), as.numeric(ev[["xmax"]]))
    )
  }

  apply_bounds_nudge(bounds)
}

project_for_leaflet <- function(r, target_crs = aemet_leaflet_projection()) {
  source_crs <- terra::crs(r)
  if (is.na(source_crs) || !nzchar(source_crs)) {
    stop("Raster sin CRS", call. = FALSE)
  }

  if (grepl(sub("EPSG:", "", target_crs, fixed = TRUE), source_crs, fixed = TRUE)) {
    return(r)
  }

  terra::project(r, target_crs, method = "near")
}

write_spatraster_png <- function(file, out_png) {
  r_source <- terra::rast(file)

  crs_txt <- terra::crs(r_source)
  if (is.na(crs_txt) || !nzchar(crs_txt)) {
    stop("Raster sin CRS: ", file, call. = FALSE)
  }

  target_crs <- aemet_leaflet_projection()
  r_render <- project_for_leaflet(r_source, target_crs = target_crs)
  r_render <- r_render[[1]]

  m <- terra::as.matrix(r_render, wide = TRUE)
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

  res <- terra::res(r_render)

  list(
    url = out_png,
    bounds = extent_to_leaflet_bounds(r_render, crs_hint = target_crs),
    values = vals,
    colours = unname(palette),
    labels = label_for_values(vals),
    source_crs = crs_txt,
    render_crs = target_crs,
    source_extent = extent_vector(r_source),
    render_extent = extent_vector(r_render),
    ncol = terra::ncol(r_render),
    nrow = terra::nrow(r_render),
    resolution_x = as.numeric(res[1]),
    resolution_y = as.numeric(res[2])
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

prepare_image_layer <- function(row, file = row$file, file_type = row$file_type, out_dir = "assets/aemet") {
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
    if (!allow_aemet_png_overlay()) {
      stop("Imagen AEMET no georreferenciada descartada: ", file, call. = FALSE)
    }

    out_file <- file.path(out_dir, paste0(layer_id, ".", ext))
    fs::file_copy(file, out_file, overwrite = TRUE)

    layer_url <- sub("^docs/", "", out_file)
    bounds <- area_bounds(row$area)
    labels <- risk_labels
    colours <- risk_palette
    layer_kind <- "image"
    source_crs <- NA_character_
    render_crs <- NA_character_
    source_extent <- c(xmin = NA_real_, xmax = NA_real_, ymin = NA_real_, ymax = NA_real_)
    render_extent <- c(xmin = NA_real_, xmax = NA_real_, ymin = NA_real_, ymax = NA_real_)
    raster_ncol <- NA_integer_
    raster_nrow <- NA_integer_
    raster_res_x <- NA_real_
    raster_res_y <- NA_real_
  } else if (file_type == "raster") {
    out_file <- file.path(out_dir, paste0(layer_id, ".png"))
    raster_info <- write_spatraster_png(file, out_file)

    layer_url <- sub("^docs/", "", out_file)
    bounds <- raster_info$bounds
    labels <- raster_info$labels
    colours <- raster_info$colours
    layer_kind <- "image"
    source_crs <- raster_info$source_crs
    render_crs <- raster_info$render_crs
    source_extent <- raster_info$source_extent
    render_extent <- raster_info$render_extent
    raster_ncol <- raster_info$ncol
    raster_nrow <- raster_info$nrow
    raster_res_x <- raster_info$resolution_x
    raster_res_y <- raster_info$resolution_y
  } else if (file_type == "json" && is_probably_geojson(file)) {
    out_file <- file.path(out_dir, paste0(layer_id, ".geojson"))
    fs::file_copy(file, out_file, overwrite = TRUE)

    layer_url <- sub("^docs/", "", out_file)
    bounds <- area_bounds(row$area)
    labels <- risk_labels
    colours <- risk_palette
    layer_kind <- "geojson"
    source_crs <- NA_character_
    render_crs <- NA_character_
    source_extent <- c(xmin = NA_real_, xmax = NA_real_, ymin = NA_real_, ymax = NA_real_)
    render_extent <- c(xmin = NA_real_, xmax = NA_real_, ymin = NA_real_, ymax = NA_real_)
    raster_ncol <- NA_integer_
    raster_nrow <- NA_integer_
    raster_res_x <- NA_real_
    raster_res_y <- NA_real_
  } else {
    stop("Formato no soportado para visor web: ", file, " [", file_type, "]", call. = FALSE)
  }

  tibble::tibble(
    layer_id = layer_id,
    layer_kind = layer_kind,
    date = row$date,
    issue_date = row$issue_date %||% NA_character_,
    valid_date = row$valid_date %||% row$date,
    tipo = row$tipo,
    dia = row$dia,
    forecast_day = row$forecast_day %||% row$dia,
    forecast_label = row$forecast_label %||% ifelse(is.na(row$dia), NA_character_, paste0("D+", row$dia)),
    area = row$area,
    area_label = row$area_label,
    file_type = file_type,
    source_file = file,
    url = layer_url,
    bounds_json = as.character(jsonlite::toJSON(bounds, auto_unbox = TRUE)),
    source_crs = source_crs,
    render_crs = render_crs,
    source_extent_json = as.character(jsonlite::toJSON(as.list(source_extent), auto_unbox = TRUE)),
    render_extent_json = as.character(jsonlite::toJSON(as.list(render_extent), auto_unbox = TRUE)),
    raster_ncol = raster_ncol,
    raster_nrow = raster_nrow,
    raster_res_x = raster_res_x,
    raster_res_y = raster_res_y,
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
    dplyr::filter(candidate_type %in% c("image", "raster", "json")) |>
    dplyr::filter(allow_aemet_png_overlay() | candidate_type != "image")
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
        dplyr::filter(candidate_type %in% c("image", "raster", "json")) |>
        dplyr::filter(allow_aemet_png_overlay() | candidate_type != "image")
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
    "^aemet_incendios_([0-9]{8})_([pbc])_(estimado|previsto)_(d[0-9]+|hoy)\\.(png|jpg|jpeg|webp|gif|tif|tiff|zip|json|geojson|bin)$"
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
    issue_date = NA_character_,
    valid_date = as.character(as.Date(date_txt, format = "%Y%m%d")),
    status = "downloaded",
    tipo = tipo,
    dia = dia,
    forecast_day = dia,
    forecast_label = ifelse(is.na(dia), NA_character_, paste0("D+", dia)),
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
    dplyr::filter(file_type %in% c("image", "raster", "zip", "json")) |>
    dplyr::filter(allow_aemet_png_overlay() | file_type != "image")
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

  if (include_orphan_aemet_raw()) {
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
  } else {
    message("AEMET: no se incorporan ficheros huérfanos de data/raw/aemet. Define AEMET_INCLUDE_ORPHAN_RAW=true solo para diagnóstico.")
  }

  clean_aemet_web_assets()

  supported <- discover_supported_files(manifest)

  if (nrow(supported) == 0) {
    message("No hay capas raster/geojson válidas que preparar")
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
  fs::dir_create("assets/aemet")
  fs::dir_create("docs/assets/aemet")

  layers <- layers |>
    dplyr::mutate(
      valid_date = dplyr::coalesce(valid_date, date),
      area_display_rank = aemet_area_display_rank(area),
      valid_date_display_rank = valid_date_sort_rank(valid_date),
      tipo_display_rank = dplyr::case_when(
        tipo == "previsto" ~ 1L,
        tipo == "estimado" ~ 2L,
        TRUE ~ 99L
      )
    ) |>
    dplyr::arrange(
      area_display_rank,
      valid_date_display_rank,
      tipo_display_rank,
      dplyr::coalesce(as.integer(dia), 0L),
      dplyr::desc(issue_date),
      layer_id
    ) |>
    dplyr::select(-area_display_rank, -valid_date_display_rank, -tipo_display_rank)

  readr::write_csv(layers, "data/processed/layers.csv")

  json_layers <- layers |>
    dplyr::mutate(
      bounds = purrr::map(bounds_json, jsonlite::fromJSON),
      legend_labels = strsplit(legend_labels, "\\|", fixed = FALSE),
      legend_colours = strsplit(legend_colours, "\\|", fixed = FALSE)
    ) |>
    dplyr::select(-bounds_json)

  # Guardamos el catálogo fuera de docs/. Quarto puede limpiar docs/ durante el render,
  # así que index.qmd debe leer de data/processed/layers.json y los assets fuente
  # deben vivir en assets/aemet/. El directorio docs/ se genera después.
  jsonlite::write_json(
    json_layers,
    "data/processed/layers.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )

  jsonlite::write_json(
    json_layers,
    "assets/aemet/layers.json",
    dataframe = "rows",
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )

  # Copia opcional para inspección local si docs/ ya existe; no se usa como fuente
  # principal porque Quarto puede recrear docs/.
  try(
    jsonlite::write_json(
      json_layers,
      "docs/assets/aemet/layers.json",
      dataframe = "rows",
      auto_unbox = TRUE,
      pretty = TRUE,
      null = "null"
    ),
    silent = TRUE
  )

  message("Capas web generadas: ", nrow(layers))
  layers
}
