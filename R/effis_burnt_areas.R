# Copernicus / EFFIS Burnt Areas helpers
# v0.6.10

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x)) || !nzchar(paste(x, collapse = ""))) y else x
}

effis_ba_bool <- function(name, default = FALSE) {
  x <- tolower(trimws(Sys.getenv(name, unset = if (isTRUE(default)) "true" else "false")))
  x %in% c("1", "true", "yes", "y", "si", "sí", "on")
}

effis_ba_num <- function(name, default) {
  x <- suppressWarnings(as.numeric(Sys.getenv(name, unset = as.character(default))))
  ifelse(is.na(x), default, x)
}

effis_ba_config <- function() {
  list(
    enable = effis_ba_bool("EFFIS_BA_ENABLE", TRUE),
    url = Sys.getenv(
      "EFFIS_BA_URL",
      unset = "https://maps.effis.emergency.copernicus.eu/effis?outputformat=SHAPEZIP&request=getfeature&service=WFS&typename=ms:modis.ba.poly&version=1.1.0"
    ),
    bbox = Sys.getenv("EFFIS_BA_BBOX", unset = "-19,27,5,44.6"),
    max_days = effis_ba_num("EFFIS_BA_MAX_DAYS", 90),
    min_area_ha = effis_ba_num("EFFIS_BA_MIN_AREA_HA", 5),
    simplify_m = effis_ba_num("EFFIS_BA_SIMPLIFY_M", 100),
    raw_dir = Sys.getenv("EFFIS_BA_RAW_DIR", unset = "data/raw/effis_ba"),
    processed_dir = Sys.getenv("EFFIS_BA_PROCESSED_DIR", unset = "data/processed"),
    assets_dir = Sys.getenv("EFFIS_BA_ASSETS_DIR", unset = "assets/effis_ba"),
    timeout = effis_ba_num("EFFIS_BA_TIMEOUT_SECONDS", 900),
    retries = as.integer(effis_ba_num("EFFIS_BA_RETRIES", 2))
  )
}

effis_ba_parse_bbox <- function(x) {
  vals <- suppressWarnings(as.numeric(strsplit(x, ",")[[1]]))
  if (length(vals) != 4 || any(is.na(vals))) {
    stop("EFFIS_BA_BBOX debe tener formato xmin,ymin,xmax,ymax", call. = FALSE)
  }
  vals
}

effis_ba_download <- function(cfg = effis_ba_config()) {
  dir.create(cfg$raw_dir, recursive = TRUE, showWarnings = FALSE)
  zip_file <- file.path(cfg$raw_dir, "effis_burnt_areas.zip")
  meta_file <- file.path(cfg$raw_dir, "effis_burnt_areas_download.json")

  if (!isTRUE(cfg$enable)) {
    message("EFFIS_BA_ENABLE=false; se omite descarga EFFIS Burnt Areas")
    return(invisible(zip_file))
  }

  if (!requireNamespace("curl", quietly = TRUE)) {
    stop("Falta el paquete R 'curl'", call. = FALSE)
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Falta el paquete R 'jsonlite'", call. = FALSE)
  }

  ok <- FALSE
  last_error <- NULL
  for (i in seq_len(max(1L, cfg$retries))) {
    message("Descargando EFFIS Burnt Areas [intento ", i, "/", cfg$retries, "]...")
    tmp <- tempfile(fileext = ".zip")
    res <- tryCatch({
      h <- curl::new_handle(timeout = cfg$timeout, connecttimeout = 60)
      curl::curl_download(cfg$url, tmp, handle = h, quiet = FALSE, mode = "wb")
      TRUE
    }, error = function(e) {
      last_error <<- conditionMessage(e)
      FALSE
    })
    if (isTRUE(res) && file.exists(tmp) && file.info(tmp)$size > 1024) {
      file.copy(tmp, zip_file, overwrite = TRUE)
      ok <- TRUE
      break
    }
  }

  meta <- list(
    source = "Copernicus/EFFIS Burnt Areas WFS",
    url = cfg$url,
    downloaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    file = zip_file,
    ok = ok,
    error = last_error
  )
  jsonlite::write_json(meta, meta_file, pretty = TRUE, auto_unbox = TRUE)

  if (!ok) {
    stop("No se pudo descargar EFFIS Burnt Areas: ", last_error %||% "respuesta vacía", call. = FALSE)
  }

  message("EFFIS Burnt Areas descargado: ", zip_file, " (", round(file.info(zip_file)$size / 1024^2, 2), " MB)")
  invisible(zip_file)
}

effis_ba_first_existing <- function(paths) {
  paths[file.exists(paths)][1] %||% NA_character_
}

effis_ba_read_zip <- function(zip_file, extract_dir) {
  if (!requireNamespace("sf", quietly = TRUE)) stop("Falta el paquete R 'sf'", call. = FALSE)
  dir.create(extract_dir, recursive = TRUE, showWarnings = FALSE)
  unlink(list.files(extract_dir, full.names = TRUE, all.files = TRUE, no.. = TRUE), recursive = TRUE, force = TRUE)
  utils::unzip(zip_file, exdir = extract_dir)

  candidates <- list.files(extract_dir, recursive = TRUE, full.names = TRUE)
  shp <- candidates[grepl("\\.shp$", candidates, ignore.case = TRUE)]
  sqlite <- candidates[grepl("\\.(sqlite|sqlite3|gpkg)$", candidates, ignore.case = TRUE)]

  if (length(shp) > 0) {
    message("Leyendo Shapefile EFFIS: ", shp[1])
    x <- sf::st_read(shp[1], quiet = TRUE, stringsAsFactors = FALSE)
    return(x)
  }

  if (length(sqlite) > 0) {
    message("Leyendo SpatiaLite/GPKG EFFIS: ", sqlite[1])
    layers <- sf::st_layers(sqlite[1])
    layer <- layers$name[1]
    x <- sf::st_read(sqlite[1], layer = layer, quiet = TRUE, stringsAsFactors = FALSE)
    return(x)
  }

  stop("No se encontró .shp/.sqlite/.gpkg dentro del ZIP EFFIS", call. = FALSE)
}

effis_ba_find_col <- function(x, patterns) {
  nms <- names(x)
  nms_no_geom <- setdiff(nms, attr(x, "sf_column") %||% character())
  nms_l <- tolower(nms_no_geom)
  for (pat in patterns) {
    idx <- grep(pat, nms_l, perl = TRUE)
    if (length(idx) > 0) return(nms_no_geom[idx[1]])
  }
  NA_character_
}

effis_ba_as_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  x <- as.character(x)
  # Extrae YYYY-MM-DD o YYYY/MM/DD o YYYYMMDD si existe.
  iso <- stringr::str_extract(x, "[0-9]{4}[-/][0-9]{2}[-/][0-9]{2}")
  compact <- stringr::str_extract(x, "[0-9]{8}")
  out <- suppressWarnings(as.Date(gsub("/", "-", iso)))
  idx <- is.na(out) & !is.na(compact)
  out[idx] <- suppressWarnings(as.Date(compact[idx], format = "%Y%m%d"))
  out
}

effis_ba_prepare <- function(cfg = effis_ba_config()) {
  if (!requireNamespace("sf", quietly = TRUE)) stop("Falta el paquete R 'sf'", call. = FALSE)
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Falta el paquete R 'dplyr'", call. = FALSE)
  if (!requireNamespace("readr", quietly = TRUE)) stop("Falta el paquete R 'readr'", call. = FALSE)
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Falta el paquete R 'jsonlite'", call. = FALSE)
  if (!requireNamespace("stringr", quietly = TRUE)) stop("Falta el paquete R 'stringr'", call. = FALSE)

  zip_file <- file.path(cfg$raw_dir, "effis_burnt_areas.zip")
  if (!file.exists(zip_file)) stop("No existe ", zip_file, ". Ejecuta scripts/29_download_effis_burnt_areas.R", call. = FALSE)

  dir.create(cfg$processed_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(cfg$assets_dir, recursive = TRUE, showWarnings = FALSE)

  x <- effis_ba_read_zip(zip_file, file.path(cfg$raw_dir, "extracted"))
  if (nrow(x) == 0) stop("El dataset EFFIS Burnt Areas no contiene entidades", call. = FALSE)

  # Normaliza CRS y geometrías.
  if (is.na(sf::st_crs(x))) {
    warning("EFFIS Burnt Areas sin CRS declarado; se asume EPSG:4326")
    sf::st_crs(x) <- 4326
  }
  x <- suppressWarnings(sf::st_make_valid(x))
  x <- sf::st_transform(x, 4326)

  date_col <- effis_ba_find_col(x, c("^date$", "fire.*date", "initial.*date", "start.*date", "final.*date", "last.*update", "date"))
  area_col <- effis_ba_find_col(x, c("area.*ha", "ha$", "burn.*area", "area"))
  id_col <- effis_ba_find_col(x, c("^id$", "fire.*id", "event.*id", "id"))
  name_col <- effis_ba_find_col(x, c("name", "place", "location", "country"))

  if (!is.na(date_col)) {
    x$effis_date <- effis_ba_as_date(x[[date_col]])
  } else {
    x$effis_date <- as.Date(NA)
  }
  if (!is.na(area_col)) {
    x$effis_area_ha <- suppressWarnings(as.numeric(x[[area_col]]))
  } else {
    # Si no hay campo de área, calcula el área aproximada en LAEA Europe.
    x_laea <- sf::st_transform(x, 3035)
    x$effis_area_ha <- as.numeric(sf::st_area(x_laea)) / 10000
  }
  x$effis_id <- if (!is.na(id_col)) as.character(x[[id_col]]) else sprintf("effis_ba_%05d", seq_len(nrow(x)))
  x$effis_label <- if (!is.na(name_col)) as.character(x[[name_col]]) else x$effis_id

  bbox <- effis_ba_parse_bbox(cfg$bbox)
  bbox_poly <- sf::st_as_sfc(sf::st_bbox(c(xmin = bbox[1], ymin = bbox[2], xmax = bbox[3], ymax = bbox[4]), crs = sf::st_crs(4326)))
  keep_bbox <- lengths(sf::st_intersects(x, bbox_poly)) > 0
  x <- x[keep_bbox, ]

  if (nrow(x) > 0 && any(!is.na(x$effis_date)) && is.finite(cfg$max_days) && cfg$max_days > 0) {
    cutoff <- Sys.Date() - cfg$max_days
    x <- x[is.na(x$effis_date) | x$effis_date >= cutoff, ]
  }
  if (nrow(x) > 0 && is.finite(cfg$min_area_ha) && cfg$min_area_ha > 0) {
    x <- x[is.na(x$effis_area_ha) | x$effis_area_ha >= cfg$min_area_ha, ]
  }

  # Reduce campos y complejidad geométrica para la publicación web.
  base_cols <- c("effis_id", "effis_label", "effis_date", "effis_area_ha")
  optional_cols <- intersect(c(date_col, area_col, id_col, name_col, "country", "Country", "CNTR_CODE", "NUTS_ID"), names(x))
  keep_cols <- unique(c(base_cols, optional_cols, attr(x, "sf_column")))
  x_web <- x[, intersect(keep_cols, names(x)), drop = FALSE]

  if (nrow(x_web) > 0 && is.finite(cfg$simplify_m) && cfg$simplify_m > 0) {
    x_web <- sf::st_transform(x_web, 3035)
    x_web <- sf::st_simplify(x_web, dTolerance = cfg$simplify_m, preserveTopology = TRUE)
    x_web <- suppressWarnings(sf::st_make_valid(x_web))
    x_web <- sf::st_transform(x_web, 4326)
  }

  # Solo se publica una copia del GeoJSON. El resumen tabular permanece en
  # data/processed, pero la geometría web vive exclusivamente en assets/.
  legacy_processed_geojson <- file.path(cfg$processed_dir, "effis_burnt_areas.geojson")
  asset_geojson <- file.path(cfg$assets_dir, "effis_burnt_areas.geojson")
  processed_summary <- file.path(cfg$processed_dir, "effis_burnt_areas_summary.csv")
  asset_summary_json <- file.path(cfg$assets_dir, "summary.json")

  if (file.exists(legacy_processed_geojson)) unlink(legacy_processed_geojson)
  if (file.exists(asset_geojson)) unlink(asset_geojson)

  if (nrow(x_web) > 0) {
    sf::st_write(x_web, asset_geojson, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
  } else {
    empty_fc <- '{"type":"FeatureCollection","features":[]}'
    writeLines(empty_fc, asset_geojson, useBytes = TRUE)
  }

  summary <- tibble::tibble(
    source = "Copernicus/EFFIS Burnt Areas",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    n_features = nrow(x_web),
    max_date = if (nrow(x_web) > 0 && any(!is.na(x_web$effis_date))) as.character(max(x_web$effis_date, na.rm = TRUE)) else NA_character_,
    min_date = if (nrow(x_web) > 0 && any(!is.na(x_web$effis_date))) as.character(min(x_web$effis_date, na.rm = TRUE)) else NA_character_,
    total_area_ha = if (nrow(x_web) > 0) round(sum(x_web$effis_area_ha, na.rm = TRUE), 2) else 0,
    bbox = cfg$bbox,
    max_days = cfg$max_days,
    min_area_ha = cfg$min_area_ha,
    simplify_m = cfg$simplify_m,
    raw_zip = zip_file,
    asset_geojson = asset_geojson
  )
  readr::write_csv(summary, processed_summary)
  jsonlite::write_json(as.list(summary[1, ]), asset_summary_json, pretty = TRUE, auto_unbox = TRUE)

  message("EFFIS Burnt Areas preparado: ", nrow(x_web), " entidades")
  print(summary)
  invisible(list(data = x_web, summary = summary))
}
