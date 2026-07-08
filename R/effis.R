source("R/utils.R", encoding = "UTF-8")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

# -----------------------------------------------------------------------------
# Configuración
# -----------------------------------------------------------------------------

effis_enabled <- function() {
  tolower(Sys.getenv("EFFIS_ENABLE", unset = "true")) %in% c("true", "1", "yes", "si", "sí")
}

effis_render_mode <- function() {
  mode <- tolower(trimws(Sys.getenv("EFFIS_RENDER_MODE", unset = "static")))
  if (!mode %in% c("static", "wms", "both", "off")) mode <- "static"
  mode
}

effis_wms_base <- function() {
  Sys.getenv("EFFIS_WMS_BASE", unset = "https://maps.effis.emergency.copernicus.eu/effis")
}

effis_wms_bases <- function() {
  configured <- Sys.getenv("EFFIS_WMS_BASES", unset = "")
  bases <- if (nzchar(trimws(configured))) {
    strsplit(configured, ",")[[1]] |> trimws()
  } else {
    c(
      effis_wms_base(),
      # Endpoint histórico que todavía aparece en ejemplos y preguntas WMS-T.
      "https://ies-ows.jrc.ec.europa.eu/effis"
    )
  }
  unique(bases[nzchar(bases)])
}

effis_wms_versions <- function() {
  x <- strsplit(Sys.getenv("EFFIS_WMS_VERSIONS", unset = Sys.getenv("EFFIS_WMS_VERSION", unset = "1.1.1")), ",")[[1]] |> trimws()
  x <- x[nzchar(x)]
  unique(c(x, "1.1.1", "1.3.0"))
}

effis_wms_version <- function() {
  effis_wms_versions()[1]
}

effis_wms_crs <- function() {
  Sys.getenv("EFFIS_WMS_CRS", unset = "EPSG:4326")
}

effis_wms_format <- function() {
  Sys.getenv("EFFIS_WMS_FORMAT", unset = "image/tiff")
}

effis_probe_formats <- function() {
  x <- strsplit(Sys.getenv("EFFIS_PROBE_FORMATS", unset = "image/png,image/tiff"), ",")[[1]] |> trimws()
  unique(x[nzchar(x)])
}

effis_static_formats <- function() {
  x <- strsplit(Sys.getenv("EFFIS_STATIC_FORMATS", unset = "image/png,image/tiff"), ",")[[1]] |> trimws()
  unique(x[nzchar(x)])
}

effis_opacity <- function() {
  x <- suppressWarnings(as.numeric(Sys.getenv("EFFIS_OPACITY", unset = "0.55")))
  if (is.na(x)) x <- 0.55
  max(0, min(1, x))
}

effis_zindex <- function() {
  x <- suppressWarnings(as.integer(Sys.getenv("EFFIS_ZINDEX", unset = "430")))
  if (is.na(x)) x <- 430L
  x
}

effis_fallback_days <- function() {
  x <- suppressWarnings(as.integer(Sys.getenv("EFFIS_FALLBACK_DAYS", unset = "7")))
  if (is.na(x) || x < 0) x <- 7L
  x
}

effis_max_dates <- function() {
  x <- suppressWarnings(as.integer(Sys.getenv("EFFIS_MAX_DATES", unset = "10")))
  if (is.na(x) || x < 1) x <- 10L
  x
}

effis_static_width <- function() {
  x <- suppressWarnings(as.integer(Sys.getenv("EFFIS_WIDTH", unset = "1600")))
  if (is.na(x) || x < 100) x <- 1600L
  x
}

effis_static_height <- function() {
  x <- suppressWarnings(as.integer(Sys.getenv("EFFIS_HEIGHT", unset = "1200")))
  if (is.na(x) || x < 100) x <- 1200L
  x
}

effis_layer_config_base <- function() {
  layers <- strsplit(Sys.getenv("EFFIS_WMS_LAYERS", unset = "ecmwf007.fwi"), ",")[[1]] |> trimws()
  labels <- strsplit(Sys.getenv("EFFIS_WMS_LABELS", unset = "EFFIS - FWI"), ",")[[1]] |> trimws()
  layers <- layers[nzchar(layers)]

  if (length(layers) == 0) return(tibble::tibble())

  if (length(labels) < length(layers)) {
    labels <- c(labels, paste("EFFIS", seq_along(layers))[(length(labels) + 1):length(layers)])
  }
  labels <- labels[seq_along(layers)]

  tibble::tibble(layer = layers, label = labels)
}

# -----------------------------------------------------------------------------
# Fechas: primero se intenta leer la dimensión TIME de GetCapabilities. Esto es
# más fiable que asumir que EFFIS ya tiene datos para la fecha de hoy.
# -----------------------------------------------------------------------------

build_query_url <- function(base_url, query) {
  # Construcción manual de URL para WMS. Algunos servidores WMS/MapServer son
  # sensibles a parámetros como BBOX cuando las comas se codifican como %2C.
  # Dejamos sin escapar los separadores WMS habituales: coma, slash y dos puntos.
  # Esto reproduce la forma de los ejemplos oficiales de EFFIS.
  keys <- names(query)
  vals <- vapply(query, function(x) paste(as.character(x), collapse = ","), character(1))
  encode_wms_value <- function(x) {
    x <- utils::URLencode(x, reserved = FALSE)
    x <- gsub("%2C", ",", x, ignore.case = TRUE)
    x <- gsub("%2F", "/", x, ignore.case = TRUE)
    x <- gsub("%3A", ":", x, ignore.case = TRUE)
    x
  }
  keep <- !is.na(vals)
  keys <- keys[keep]
  vals <- vals[keep]
  pairs <- paste0(keys, "=", vapply(vals, encode_wms_value, character(1)))
  sep <- if (grepl("\\?", base_url)) "&" else "?"
  paste0(base_url, sep, paste(pairs, collapse = "&"))
}

format_wms_number <- function(x) {
  x <- as.numeric(x)
  ifelse(is.na(x), NA_character_, formatC(x, format = "f", digits = 6, drop0trailing = TRUE))
}

extract_ogc_exception <- function(body) {
  if (length(body) == 0) return(NA_character_)
  txt <- tryCatch(rawToChar(body, multiple = FALSE), error = function(e) "")
  if (!nzchar(txt)) return(NA_character_)
  txt <- suppressWarnings(enc2utf8(txt))
  # Extrae textos de <ServiceException> y, como respaldo, compacta el XML.
  m <- gregexpr("<ServiceException[^>]*>(.*?)</ServiceException>", txt, perl = TRUE, ignore.case = TRUE)[[1]]
  if (m[1] > 0) {
    parts <- regmatches(txt, list(m))[[1]]
    parts <- gsub("<[^>]+>", " ", parts)
    parts <- gsub("\\s+", " ", trimws(parts))
    parts <- parts[nzchar(parts)]
    if (length(parts) > 0) return(paste(unique(parts), collapse = " | "))
  }
  compact <- gsub("\\s+", " ", trimws(gsub("<[^>]+>", " ", txt)))
  if (nzchar(compact)) compact else NA_character_
}

effis_fetch_capabilities <- function(base_url, version = "1.1.1", out_dir = "data/raw/effis") {
  fs::dir_create(out_dir)
  slug <- safe_slug(paste("effis_getcapabilities", base_url, version, sep = "_"))
  cap_file <- file.path(out_dir, paste0(slug, ".xml"))

  resp <- tryCatch(
    httr2::request(base_url) |>
      httr2::req_url_query(SERVICE = "wms", REQUEST = "GetCapabilities", VERSION = version) |>
      httr2::req_user_agent("visor-fuego/0.5.29") |>
      httr2::req_timeout(120) |>
      httr2::req_perform(),
    error = function(e) e
  )

  if (inherits(resp, "error")) {
    return(list(ok = FALSE, file = cap_file, text = NA_character_, status = NA_integer_, content_type = NA_character_, message = conditionMessage(resp)))
  }

  body <- httr2::resp_body_raw(resp)
  writeBin(body, cap_file)
  txt <- tryCatch(rawToChar(body, multiple = FALSE), error = function(e) NA_character_)
  list(
    ok = httr2::resp_status(resp) < 400,
    file = cap_file,
    text = txt,
    status = httr2::resp_status(resp),
    content_type = httr2::resp_content_type(resp) %||% NA_character_,
    message = NA_character_
  )
}

effis_extract_layer_section <- function(cap_text, layer) {
  if (is.na(cap_text) || !nzchar(cap_text)) return(NA_character_)
  idx <- regexpr(paste0("<Name>\\s*", gsub("\\.", "\\\\.", layer), "\\s*</Name>"), cap_text, ignore.case = TRUE, perl = TRUE)
  if (idx[1] < 0) return(NA_character_)
  start <- max(1L, idx[1] - 10000L)
  end <- min(nchar(cap_text), idx[1] + 50000L)
  substr(cap_text, start, end)
}

effis_extract_time_dates <- function(cap_text, layer) {
  sec <- effis_extract_layer_section(cap_text, layer)
  if (is.na(sec) || !nzchar(sec)) return(character())
  # Admite dimensiones con listas de fechas, intervalos tipo start/end/P1D y
  # timestamps ISO. Nos quedamos con las fechas ISO presentes en el bloque.
  m <- gregexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}", sec, perl = TRUE)[[1]]
  if (m[1] < 0) return(character())
  dates <- regmatches(sec, list(m))[[1]]
  unique(dates)
}

effis_date_candidates_for <- function(layer, base_url = NULL) {
  explicit <- Sys.getenv("EFFIS_DATE", unset = "")
  if (nzchar(trimws(explicit))) {
    dates <- strsplit(explicit, ",")[[1]] |> trimws()
    return(unique(dates[nzchar(dates)]))
  }

  bases <- base_url %||% effis_wms_bases()
  cap_dates <- character()
  for (b in bases) {
    for (v in c("1.1.1", "1.3.0")) {
      cap <- tryCatch(effis_fetch_capabilities(b, version = v), error = function(e) NULL)
      if (!is.null(cap) && isTRUE(cap$ok)) {
        cap_dates <- c(cap_dates, effis_extract_time_dates(cap$text, layer))
      }
    }
  }

  cap_dates <- unique(cap_dates[nzchar(cap_dates)])
  cap_dates <- cap_dates[!is.na(as.Date(cap_dates))]
  if (length(cap_dates) > 0) {
    # Para previsiones puede haber días futuros; evitamos fechas absurdamente lejanas
    # y damos prioridad a la más reciente disponible.
    d <- as.Date(cap_dates)
    keep <- !is.na(d) & d >= Sys.Date() - 60 & d <= Sys.Date() + 16
    cap_dates <- cap_dates[keep]
    if (length(cap_dates) > 0) {
      ord <- order(as.Date(cap_dates), decreasing = TRUE)
      return(unique(cap_dates[ord])[seq_len(min(effis_max_dates(), length(unique(cap_dates))))])
    }
  }

  days <- seq.int(0L, effis_fallback_days())
  as.character(Sys.Date() - days)
}

effis_date_candidates <- function() {
  cfg <- effis_layer_config_base()
  if (nrow(cfg) == 0) return(character())
  unique(unlist(lapply(cfg$layer, effis_date_candidates_for), use.names = FALSE))
}

# -----------------------------------------------------------------------------
# BBOX y construcción de peticiones
# -----------------------------------------------------------------------------

parse_effis_bbox_value <- function(value) {
  parts <- strsplit(value, ",")[[1]] |> trimws()
  nums <- suppressWarnings(as.numeric(parts))
  if (length(nums) != 4 || any(is.na(nums))) {
    stop("BBOX EFFIS inválido: ", value, call. = FALSE)
  }
  names(nums) <- c("xmin", "ymin", "xmax", "ymax")
  nums
}

parse_effis_bbox <- function(value = Sys.getenv("EFFIS_BBOX", unset = "-18,27,42,72")) {
  parse_effis_bbox_value(value)
}

effis_bbox_candidates <- function() {
  explicit <- Sys.getenv("EFFIS_BBOXES", unset = "")
  vals <- if (nzchar(trimws(explicit))) {
    strsplit(explicit, "\\|")[[1]] |> trimws()
  } else {
    # 1) BBOX oficial del ejemplo EFFIS, 2) Península/Canarias amplia para el visor.
    c(Sys.getenv("EFFIS_BBOX", unset = "-18,27,42,72"), "-19,27,5,44.6")
  }
  vals <- unique(vals[nzchar(vals)])
  tibble::tibble(
    bbox_label = paste0("bbox", seq_along(vals)),
    bbox = vals
  )
}

effis_bbox_to_leaflet_bounds <- function(bbox) {
  list(
    list(as.numeric(bbox[["ymin"]]), as.numeric(bbox[["xmin"]])),
    list(as.numeric(bbox[["ymax"]]), as.numeric(bbox[["xmax"]]))
  )
}

effis_bbox_for_wms <- function(bbox, version = "1.1.1", crs = "EPSG:4326") {
  # WMS 1.3.0 con EPSG:4326 usa orden lat,lon. WMS 1.1.1 usa lon,lat.
  if (identical(version, "1.3.0") && toupper(crs) %in% c("EPSG:4326", "4326")) {
    vals <- c(bbox[["ymin"]], bbox[["xmin"]], bbox[["ymax"]], bbox[["xmax"]])
  } else {
    vals <- c(bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]])
  }
  paste(format_wms_number(vals), collapse = ",")
}

build_effis_getmap_query <- function(layer, date, bbox = parse_effis_bbox(), format = effis_wms_format(), version = effis_wms_version()) {
  crs <- effis_wms_crs()
  q <- list(
    LAYERS = layer,
    FORMAT = format,
    TRANSPARENT = "true",
    SINGLETILE = "false",
    SERVICE = "wms",
    VERSION = version,
    REQUEST = "GetMap",
    STYLES = "",
    BBOX = effis_bbox_for_wms(bbox, version = version, crs = crs),
    WIDTH = effis_static_width(),
    HEIGHT = effis_static_height(),
    TIME = date,
    EXCEPTIONS = "application/vnd.ogc.se_xml"
  )
  if (identical(version, "1.3.0")) q$CRS <- crs else q$SRS <- crs
  q
}

effis_request_matrix <- function(formats = effis_static_formats()) {
  layers <- effis_layer_config_base()
  if (nrow(layers) == 0) return(tibble::tibble())

  purrr::map_dfr(seq_len(nrow(layers)), function(i) {
    layer <- layers$layer[i]
    label <- layers$label[i]
    dates <- effis_date_candidates_for(layer)
    if (length(dates) == 0) return(tibble::tibble())

    tidyr::expand_grid(
      base_url = effis_wms_bases(),
      version = effis_wms_versions(),
      fmt = formats,
      date = dates,
      effis_bbox_candidates()
    ) |>
      dplyr::mutate(layer = layer, label = label) |>
      dplyr::select(layer, label, date, base_url, version, fmt, bbox_label, bbox)
  })
}

# -----------------------------------------------------------------------------
# Lectura y clasificación de respuestas GetMap
# -----------------------------------------------------------------------------

first_hex_effis <- function(path, n = 32) {
  if (is.na(path) || !file.exists(path)) return(NA_character_)
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, "raw", n = n)
  paste(sprintf("%02x", as.integer(raw)), collapse = " ")
}

effis_array_visual_summary <- function(img, min_range = 1e-4, min_visible = 10) {
  dims <- dim(img)
  if (is.null(dims)) {
    vals <- suppressWarnings(as.numeric(img))
    vals <- vals[is.finite(vals)]
    if (length(vals) == 0) return(list(ok = FALSE, n = 0, visual_range = NA_real_, message = "sin valores finitos"))
    vr <- diff(range(vals, na.rm = TRUE))
    return(list(ok = length(vals) >= min_visible && is.finite(vr) && vr > min_range, n = as.numeric(length(vals)), visual_range = as.numeric(vr), message = NA_character_))
  }

  if (length(dims) == 2) {
    vals <- suppressWarnings(as.numeric(img))
    vals <- vals[is.finite(vals)]
    if (length(vals) == 0) return(list(ok = FALSE, n = 0, visual_range = NA_real_, message = "matriz sin valores finitos"))
    vr <- diff(range(vals, na.rm = TRUE))
    return(list(ok = length(vals) >= min_visible && is.finite(vr) && vr > min_range, n = as.numeric(length(vals)), visual_range = as.numeric(vr), message = NA_character_))
  }

  if (length(dims) != 3) {
    return(list(ok = FALSE, n = 0, visual_range = NA_real_, message = paste("dimensiones no esperadas:", paste(dims, collapse = "x"))))
  }

  rgb_n <- min(3L, dims[3])
  rgb <- img[, , seq_len(rgb_n), drop = FALSE]
  alpha <- if (dims[3] >= 4) img[, , 4] else matrix(1, nrow = dims[1], ncol = dims[2])
  mask <- is.finite(alpha) & alpha > 0.01
  n <- sum(mask, na.rm = TRUE)
  if (!is.finite(n) || n < min_visible) {
    return(list(ok = FALSE, n = as.numeric(n), visual_range = NA_real_, message = "sin píxeles visibles por alfa"))
  }

  # Extraemos los canales RGB solo en la máscara visible, conservando la lógica
  # aunque haya 1, 2, 3 o 4 bandas. Una imagen completamente negra/blanca/opaca
  # ya no se considera un overlay válido.
  vals <- unlist(lapply(seq_len(rgb_n), function(k) as.numeric(rgb[, , k][mask])), use.names = FALSE)
  vals <- vals[is.finite(vals)]
  if (length(vals) == 0) return(list(ok = FALSE, n = as.numeric(n), visual_range = NA_real_, message = "sin RGB finito en píxeles visibles"))
  vr <- diff(range(vals, na.rm = TRUE))
  ok <- is.finite(vr) && vr > min_range
  msg <- if (ok) NA_character_ else paste0("imagen visible pero sin variación RGB real; rango=", signif(vr, 4))
  list(ok = ok, n = as.numeric(n), visual_range = as.numeric(vr), message = msg)
}

probe_png_pixels <- function(file) {
  img <- tryCatch(png::readPNG(file), error = function(e) e)
  if (inherits(img, "error")) return(list(ok = FALSE, n = NA_real_, message = conditionMessage(img)))
  info <- effis_array_visual_summary(img)
  list(ok = isTRUE(info$ok), n = as.numeric(info$n), message = info$message)
}

probe_raster_pixels <- function(file) {
  r <- tryCatch(terra::rast(file), error = function(e) e)
  if (inherits(r, "error")) return(list(ok = FALSE, n = NA_real_, message = conditionMessage(r)))
  nlyr <- terra::nlyr(r)
  max_layers <- min(3L, nlyr)
  n <- tryCatch(as.numeric(terra::global(!is.na(r[[1]]), "sum", na.rm = TRUE)[1, 1]), error = function(e) NA_real_)
  mm <- tryCatch(terra::minmax(r[[seq_len(max_layers)]]), error = function(e) NULL)
  if (is.null(mm)) {
    return(list(ok = is.finite(n) && n > 0, n = as.numeric(n), message = NA_character_))
  }
  ranges <- suppressWarnings(as.numeric(mm[2, ] - mm[1, ]))
  visual_range <- max(ranges, na.rm = TRUE)
  if (!is.finite(visual_range)) visual_range <- NA_real_
  ok <- is.finite(n) && n > 0 && is.finite(visual_range) && visual_range > 1e-4
  msg <- if (ok) NA_character_ else paste0("raster sin variación visual; rango=", signif(visual_range, 4), "; pixeles_validos=", signif(n, 6))
  list(ok = ok, n = as.numeric(n), message = msg)
}

classify_effis_body <- function(body, content_type = NA_character_, preferred_ext = "bin") {
  ext <- sniff_file_extension(body[seq_len(min(length(body), 4096))], fallback = "bin")
  ct <- tolower(content_type %||% "")
  if (ext == "bin" && grepl("tiff|geotiff", ct)) ext <- "tif"
  if (ext == "bin" && grepl("png", ct)) ext <- "png"
  if (ext == "bin" && grepl("xml|ogc.se_xml|vnd.ogc", ct)) ext <- "xml"
  file_type <- dplyr::case_when(
    ext %in% c("png", "jpg", "jpeg", "gif", "webp") ~ "image",
    ext %in% c("tif", "tiff") ~ "raster",
    ext %in% c("xml", "html", "json", "gz", "zip") ~ ext,
    TRUE ~ "unknown"
  )
  list(ext = ext %||% preferred_ext, file_type = file_type)
}

probe_effis_getmap_row <- function(row, out_dir = "data/raw/effis") {
  fs::dir_create(out_dir)
  bbox_num <- parse_effis_bbox_value(row$bbox)
  query <- build_effis_getmap_query(
    layer = row$layer,
    date = row$date,
    bbox = bbox_num,
    format = row$fmt,
    version = row$version
  )
  url <- build_query_url(row$base_url, query)

  slug <- safe_slug(paste(row$layer, row$date, row$fmt, row$version, row$bbox_label, safe_slug(row$base_url), sep = "_"))
  preferred_ext <- if (grepl("tiff|geotiff", row$fmt, ignore.case = TRUE)) "tif" else "png"
  file <- file.path(out_dir, paste0("effis_getmap_", slug, ".", preferred_ext))

  # Usamos la URL ya construida para evitar que httr2 re-codifique las comas de BBOX.
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_user_agent("visor-fuego/0.5.29") |>
      httr2::req_timeout(120) |>
      httr2::req_perform(),
    error = function(e) e
  )

  if (inherits(resp, "error")) {
    return(tibble::tibble(
      layer = row$layer, label = row$label, date = row$date, base_url = row$base_url,
      version = row$version, format = row$fmt, bbox_label = row$bbox_label, bbox = as.character(row$bbox),
      wms_bbox = query$BBOX, url = url, status_code = NA_integer_, content_type = NA_character_, size_bytes = NA_real_,
      file = NA_character_, ext = NA_character_, file_type = "error", has_pixels = NA,
      non_empty_pixels = NA_real_, first_hex = NA_character_, message = conditionMessage(resp)
    ))
  }

  status <- httr2::resp_status(resp)
  ct <- httr2::resp_content_type(resp) %||% NA_character_
  body <- httr2::resp_body_raw(resp)
  cls <- classify_effis_body(body, ct, preferred_ext = preferred_ext)

  file <- sub(paste0("\\.", preferred_ext, "$"), paste0(".", cls$ext), file)
  writeBin(body, file)

  non_empty <- NA_real_
  msg <- NA_character_
  has_pixels <- FALSE
  if (identical(cls$file_type, "image")) {
    p <- probe_png_pixels(file)
    has_pixels <- p$ok
    non_empty <- p$n
    msg <- p$message
  } else if (identical(cls$file_type, "raster")) {
    p <- probe_raster_pixels(file)
    has_pixels <- p$ok
    non_empty <- p$n
    msg <- p$message
  } else if (length(body) > 0) {
    msg <- extract_ogc_exception(body)
    if (is.na(msg) || !nzchar(msg)) {
      txt <- tryCatch(rawToChar(body[seq_len(min(length(body), 2000))], multiple = FALSE), error = function(e) "")
      msg <- gsub("\\s+", " ", trimws(txt))
    }
  }

  tibble::tibble(
    layer = row$layer, label = row$label, date = row$date, base_url = row$base_url,
    version = row$version, format = row$fmt, bbox_label = row$bbox_label, bbox = as.character(row$bbox),
    wms_bbox = query$BBOX, url = url, status_code = status, content_type = ct, size_bytes = length(body), file = file,
    ext = cls$ext, file_type = cls$file_type, has_pixels = isTRUE(has_pixels),
    non_empty_pixels = non_empty, first_hex = first_hex_effis(file), message = msg
  )
}

# -----------------------------------------------------------------------------
# Catálogo local / Leaflet
# -----------------------------------------------------------------------------

effis_read_local_catalog <- function() {
  candidates <- c(
    "data/processed/effis_layers.json",
    "assets/effis/layers.json",
    "docs/assets/effis/layers.json"
  )

  for (path in candidates) {
    if (file.exists(path) && file.info(path)$size > 2) {
      x <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) list())
      if (length(x) > 0) {
        attr(x, "source_path") <- path
        return(x)
      }
    }
  }

  x <- list()
  attr(x, "source_path") <- NA_character_
  x
}

effis_static_layers_json <- function() {
  if (!effis_enabled()) return("[]")
  if (!effis_render_mode() %in% c("static", "both")) return("[]")
  layers <- effis_read_local_catalog()
  jsonlite::toJSON(layers, auto_unbox = TRUE, null = "null")
}

effis_static_overlay_groups <- function() {
  if (!effis_enabled()) return(character())
  if (!effis_render_mode() %in% c("static", "both")) return(character())
  layers <- effis_read_local_catalog()
  if (length(layers) == 0) return(character())
  unique(vapply(layers, function(x) as.character(x$group_label %||% x$label %||% "EFFIS"), character(1)))
}

effis_make_wms_options <- function(row) {
  opts <- leaflet::WMSTileOptions(
    format = "image/png",
    transparent = TRUE,
    version = row$version,
    styles = "",
    time = row$date,
    uppercase = TRUE,
    opacity = effis_opacity(),
    pane = "effisPane"
  )
  if (toupper(effis_wms_crs()) %in% c("EPSG:4326", "4326")) {
    opts$crs <- htmlwidgets::JS("L.CRS.EPSG4326")
  }
  opts
}

effis_layer_config <- function() {
  cfg <- effis_layer_config_base()
  if (nrow(cfg) == 0) return(cfg)
  dates <- effis_date_candidates()
  if (length(dates) == 0) return(tibble::tibble())
  tidyr::expand_grid(cfg, date = dates) |>
    dplyr::mutate(
      group_label = paste0(label, " · ", date),
      base_url = effis_wms_base(),
      version = effis_wms_version(),
      crs = effis_wms_crs(),
      format = effis_wms_format(),
      opacity = effis_opacity(),
      zindex = effis_zindex()
    )
}

add_effis_wms_layers <- function(map) {
  if (!effis_enabled()) return(map)
  if (!effis_render_mode() %in% c("wms", "both")) return(map)
  cfg <- effis_layer_config()
  if (nrow(cfg) == 0) return(map)
  map <- leaflet::addMapPane(map, "effisPane", zIndex = effis_zindex())
  for (i in seq_len(nrow(cfg))) {
    map <- leaflet::addWMSTiles(
      map,
      baseUrl = cfg$base_url[i],
      layers = cfg$layer[i],
      group = cfg$group_label[i],
      options = effis_make_wms_options(cfg[i, ]),
      attribution = "EFFIS/Copernicus EMS"
    )
  }
  map
}

add_effis_layers <- function(map) {
  add_effis_wms_layers(map)
}

effis_overlay_groups <- function() {
  if (!effis_enabled()) return(character())
  mode <- effis_render_mode()
  groups <- character()
  if (mode %in% c("wms", "both")) {
    cfg <- effis_layer_config()
    if (nrow(cfg) > 0) groups <- c(groups, cfg$group_label)
  }
  if (mode %in% c("static", "both")) {
    groups <- c(groups, effis_static_overlay_groups())
  }
  unique(groups)
}

# -----------------------------------------------------------------------------
# Conversión a PNG estático
# -----------------------------------------------------------------------------

normalise_rgb_band <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  mx <- max(x, na.rm = TRUE)
  if (!is.finite(mx)) return(x)
  if (mx > 1.5) x <- x / 255
  pmax(0, pmin(1, x))
}


clamp_png_array <- function(x) {
  # pmin()/pmax() pueden perder atributos de dimensión en algunos casos.
  # png::writePNG() necesita conservar una matriz o array 3D/4D; por eso
  # guardamos dim()/dimnames() y los restauramos explícitamente.
  d <- dim(x)
  dn <- dimnames(x)
  storage.mode(x) <- "double"
  x[!is.finite(x)] <- 0
  x <- pmin(1, pmax(0, x))
  if (!is.null(d)) dim(x) <- d
  if (!is.null(dn)) dimnames(x) <- dn
  x
}

write_effis_png_array <- function(arr, target) {
  arr <- clamp_png_array(arr)
  d <- dim(arr)
  if (is.null(d) || !length(d) %in% c(2L, 3L)) {
    stop(
      "PNG EFFIS inválido: el objeto tiene dimensiones ",
      if (is.null(d)) "NULL" else paste(d, collapse = "x"),
      ".",
      call. = FALSE
    )
  }
  fs::dir_create(dirname(target))
  png::writePNG(arr, target = target)
  invisible(target)
}

effis_png_info <- function(png_file, bbox) {
  img <- tryCatch(png::readPNG(png_file), error = function(e) e)
  if (inherits(img, "error")) {
    return(list(ok = FALSE, message = conditionMessage(img)))
  }
  dims <- dim(img)
  if (length(dims) == 2) {
    nc <- ncol(img); nr <- nrow(img)
  } else if (length(dims) == 3) {
    nr <- dims[1]; nc <- dims[2]
  } else {
    return(list(ok = FALSE, message = paste("PNG con dimensiones no esperadas:", paste(dims, collapse = "x"))))
  }
  vis <- effis_array_visual_summary(img)
  list(
    ok = isTRUE(vis$ok),
    ncol = as.integer(nc),
    nrow = as.integer(nr),
    non_empty_pixels = as.numeric(vis$n),
    bounds = effis_bbox_to_leaflet_bounds(bbox),
    message = vis$message
  )
}

try_effis_gdal_translate_png <- function(src_file, png_file, bbox = parse_effis_bbox()) {
  fs::dir_create(dirname(png_file))
  tmp_png <- tempfile(pattern = "effis_gdal_", fileext = ".png")
  msgs <- character()

  gdal_option_sets <- list(
    c("-of", "PNG"),
    c("-of", "PNG", "-ot", "Byte", "-scale")
  )

  if (requireNamespace("sf", quietly = TRUE)) {
    for (opts in gdal_option_sets) {
      tmp_png <- tempfile(pattern = "effis_gdal_", fileext = ".png")
      ok <- tryCatch({
        sf::gdal_utils(
          util = "translate",
          source = src_file,
          destination = tmp_png,
          options = opts,
          quiet = TRUE
        )
        TRUE
      }, error = function(e) {
        msgs <<- c(msgs, paste0("sf::gdal_utils ", paste(opts, collapse = " "), ": ", conditionMessage(e)))
        FALSE
      })
      if (ok && file.exists(tmp_png) && file.info(tmp_png)$size > 0) {
        info <- effis_png_info(tmp_png, bbox)
        if (isTRUE(info$ok)) {
          file.copy(tmp_png, png_file, overwrite = TRUE)
          return(info)
        }
        msgs <- c(msgs, paste0("PNG generado por GDAL sin píxeles [", paste(opts, collapse = " "), "]: ", info$message %||% "sin detalle"))
      }
    }
  }

  gdal_bin <- Sys.which("gdal_translate")
  if (nzchar(gdal_bin)) {
    for (opts in gdal_option_sets) {
      tmp_png2 <- tempfile(pattern = "effis_gdal_cli_", fileext = ".png")
      out <- tryCatch(
        system2(gdal_bin, args = c(opts, src_file, tmp_png2), stdout = TRUE, stderr = TRUE),
        error = function(e) {
          msgs <<- c(msgs, paste0("gdal_translate ", paste(opts, collapse = " "), ": ", conditionMessage(e)))
          character()
        }
      )
      if (length(out) > 0) msgs <- c(msgs, paste("gdal_translate", paste(opts, collapse = " "), paste(out, collapse = " | ")))
      if (file.exists(tmp_png2) && file.info(tmp_png2)$size > 0) {
        info <- effis_png_info(tmp_png2, bbox)
        if (isTRUE(info$ok)) {
          file.copy(tmp_png2, png_file, overwrite = TRUE)
          return(info)
        }
        msgs <- c(msgs, paste0("PNG generado por gdal_translate sin píxeles [", paste(opts, collapse = " "), "]: ", info$message %||% "sin detalle"))
      }
    }
  }

  stop("No se pudo convertir el raster EFFIS a PNG con GDAL. ", paste(unique(msgs[nzchar(msgs)]), collapse = " || "), call. = FALSE)
}

write_effis_png_from_file <- function(src_file, png_file, bbox = parse_effis_bbox(), opacity_alpha = 1) {
  ext <- infer_file_type(src_file)
  fs::dir_create(dirname(png_file))

  if (identical(ext, "image")) {
    # Si el WMS ya devuelve PNG útil, lo usamos directamente. Es más robusto que
    # intentar convertir TIFFs WMS que a veces llegan como paletas/tiles difíciles
    # de leer con terra/GDAL local.
    img <- tryCatch(png::readPNG(src_file), error = function(e) e)
    if (inherits(img, "error")) {
      ok_copy <- file.copy(src_file, png_file, overwrite = TRUE)
      if (!isTRUE(ok_copy)) stop("No se pudo copiar PNG EFFIS: ", src_file, call. = FALSE)
      return(list(ncol = NA_integer_, nrow = NA_integer_, non_empty_pixels = as.numeric(file.info(png_file)$size), bounds = effis_bbox_to_leaflet_bounds(bbox)))
    }

    if (length(dim(img)) == 2) {
      nr <- nrow(img); nc <- ncol(img)
      arr <- array(0, dim = c(nr, nc, 4))
      arr[, , 1] <- img
      arr[, , 2] <- img
      arr[, , 3] <- img
      arr[, , 4] <- as.numeric(!is.na(img) & img > 0.01) * opacity_alpha
      img <- arr
    } else if (length(dim(img)) == 3 && dim(img)[3] < 4) {
      nr <- dim(img)[1]; nc <- dim(img)[2]
      arr <- array(0, dim = c(nr, nc, 4))
      arr[, , 1] <- img[, , 1]
      arr[, , 2] <- if (dim(img)[3] >= 2) img[, , 2] else img[, , 1]
      arr[, , 3] <- if (dim(img)[3] >= 3) img[, , 3] else img[, , 1]
      alpha <- apply(arr[, , 1:3, drop = FALSE], c(1, 2), sum, na.rm = TRUE) > 0.01
      arr[, , 4] <- as.numeric(alpha) * opacity_alpha
      img <- arr
    } else if (length(dim(img)) == 3 && dim(img)[3] >= 4) {
      img[, , 4] <- img[, , 4] * opacity_alpha
    } else {
      stop("PNG EFFIS con dimensiones no esperadas: ", paste(dim(img), collapse = "x"), call. = FALSE)
    }

    img[is.na(img)] <- 0
    vis <- effis_array_visual_summary(img)
    if (!isTRUE(vis$ok)) {
      stop("PNG EFFIS recibido sin contenido visual real: ", vis$message %||% "sin detalle", call. = FALSE)
    }
    write_effis_png_array(img, png_file)
    return(list(ncol = dim(img)[2], nrow = dim(img)[1], non_empty_pixels = as.numeric(vis$n), bounds = effis_bbox_to_leaflet_bounds(bbox)))
  }

  # Para TIFFs WMS coloreados/paletizados, gdal_translate suele ser más fiable
  # que reconstruir RGBA manualmente con terra. Si falla, mantenemos el fallback
  # raster→RGBA que ya teníamos.
  gdal_info <- tryCatch(
    try_effis_gdal_translate_png(src_file, png_file, bbox = bbox),
    error = function(e) e
  )
  if (!inherits(gdal_info, "error")) return(gdal_info)
  gdal_message <- conditionMessage(gdal_info)

  r <- terra::rast(src_file)
  try(terra::ext(r) <- terra::ext(bbox[["xmin"]], bbox[["xmax"]], bbox[["ymin"]], bbox[["ymax"]]), silent = TRUE)
  try(terra::crs(r) <- effis_wms_crs(), silent = TRUE)
  nlyr <- terra::nlyr(r)

  if (nlyr >= 3) {
    mats <- lapply(seq_len(3), function(i) terra::as.matrix(r[[i]], wide = TRUE))
    nr <- nrow(mats[[1]]); nc <- ncol(mats[[1]])

    # Máscara de datos válidos antes de normalizar. En algunos TIFF WMS de
    # EFFIS los canales RGB llegan coloreados, pero la banda alfa es 0 en toda
    # la imagen; si respetamos ese alfa, el PNG final queda completamente
    # transparente aunque el raster tenga datos. Por eso guardamos una máscara
    # independiente de píxeles finitos/no-NA.
    valid_mask <- matrix(FALSE, nrow = nr, ncol = nc)
    for (mm in mats) {
      valid_mask <- valid_mask | matrix(!is.na(mm), nrow = nr, ncol = nc)
    }

    rr <- normalise_rgb_band(mats[[1]])
    gg <- normalise_rgb_band(mats[[2]])
    bb <- normalise_rgb_band(mats[[3]])
    arr <- array(0, dim = c(nr, nc, 4))
    arr[, , 1] <- matrix(rr, nrow = nr, ncol = nc)
    arr[, , 2] <- matrix(gg, nrow = nr, ncol = nc)
    arr[, , 3] <- matrix(bb, nrow = nr, ncol = nc)

    rgb_visible <- (arr[, , 1] + arr[, , 2] + arr[, , 3]) > 0.01

    if (nlyr >= 4) {
      alpha <- normalise_rgb_band(terra::as.matrix(r[[4]], wide = TRUE))
      alpha <- matrix(alpha, nrow = nr, ncol = nc)
      alpha_visible <- is.finite(sum(alpha > 0.01, na.rm = TRUE)) && sum(alpha > 0.01, na.rm = TRUE) > 0
      if (alpha_visible) {
        arr[, , 4] <- alpha * opacity_alpha
      } else {
        # Fallback clave para EFFIS: alfa WMS vacío, pero RGB/datos presentes.
        # Usamos RGB si existe y, si no, los píxeles con datos válidos.
        arr[, , 4] <- as.numeric(valid_mask) * opacity_alpha
      }
    } else {
      # Sin banda alfa: hacemos visibles los píxeles con RGB o datos válidos.
      arr[, , 4] <- as.numeric(valid_mask) * opacity_alpha
    }

    # Si la imagen queda totalmente transparente, forzamos visibilidad donde
    # haya datos válidos. Esto evita rechazar rasters categóricos con valor 0.
    if (sum(arr[, , 4] > 0.01, na.rm = TRUE) <= 0 && any(valid_mask, na.rm = TRUE)) {
      arr[, , 4] <- as.numeric(valid_mask) * opacity_alpha
    }
  } else {
    m <- terra::as.matrix(r[[1]], wide = TRUE)
    vals <- as.vector(m[!is.na(m)])
    if (length(vals) == 0) stop("Raster EFFIS sin valores válidos: ", src_file, call. = FALSE)
    pal_fun <- grDevices::colorRampPalette(grDevices::hcl.colors(64, palette = "YlOrRd", rev = FALSE))
    pal <- pal_fun(64)
    rng <- range(vals, na.rm = TRUE)
    scaled <- round((m - rng[1]) / max(1e-9, diff(rng)) * 63) + 1
    scaled[is.na(scaled)] <- NA_integer_
    nr <- nrow(m); nc <- ncol(m)
    arr <- array(0, dim = c(nr, nc, 4))
    for (idx in stats::na.omit(unique(as.integer(scaled)))) {
      pos <- which(scaled == idx, arr.ind = TRUE)
      rgb <- grDevices::col2rgb(pal[idx]) / 255
      arr[cbind(pos[, 1], pos[, 2], 1)] <- rgb[1, 1]
      arr[cbind(pos[, 1], pos[, 2], 2)] <- rgb[2, 1]
      arr[cbind(pos[, 1], pos[, 2], 3)] <- rgb[3, 1]
      arr[cbind(pos[, 1], pos[, 2], 4)] <- opacity_alpha
    }
  }
  arr[is.na(arr)] <- 0
  vis <- effis_array_visual_summary(arr)
  if (!isTRUE(vis$ok)) {
    stop("PNG EFFIS sin contenido visual real: ", vis$message %||% "sin detalle", call. = FALSE)
  }
  fs::dir_create(dirname(png_file))
  write_effis_png_array(arr, png_file)
  list(ncol = dim(arr)[2], nrow = dim(arr)[1], non_empty_pixels = as.numeric(vis$n), bounds = effis_bbox_to_leaflet_bounds(bbox))
}

prepare_effis_static_assets <- function() {
  if (!effis_enabled()) {
    message("EFFIS_ENABLE=false; no se preparan assets EFFIS.")
    return(tibble::tibble())
  }

  fs::dir_create("data/raw/effis")
  fs::dir_create("data/processed")
  fs::dir_create("assets/effis")
  fs::dir_create("docs/assets/effis")

  reqs <- effis_request_matrix(formats = effis_static_formats())
  if (nrow(reqs) == 0) {
    message("Sin peticiones EFFIS candidatas.")
    return(tibble::tibble())
  }

  # Limitador defensivo para no hacer demasiadas llamadas si hay muchas fechas en TIME.
  max_req <- suppressWarnings(as.integer(Sys.getenv("EFFIS_MAX_REQUESTS", unset = "120")))
  if (is.na(max_req) || max_req < 1) max_req <- 120L
  reqs <- reqs |> dplyr::slice_head(n = max_req)

  attempts <- purrr::map_dfr(seq_len(nrow(reqs)), function(i) probe_effis_getmap_row(reqs[i, ], out_dir = "data/raw/effis"))
  readr::write_csv(attempts, "data/raw/effis/effis_download_attempts.csv")

  ok <- attempts |>
    dplyr::filter(status_code == 200, has_pixels %in% TRUE, file_type %in% c("raster", "image"), !is.na(file), file.exists(file)) |>
    dplyr::mutate(
      conversion_priority = dplyr::case_when(
        file_type == "image" & grepl("png", format, ignore.case = TRUE) ~ 3L,
        file_type == "image" ~ 2L,
        file_type == "raster" ~ 1L,
        TRUE ~ 0L
      )
    ) |>
    dplyr::arrange(layer, dplyr::desc(conversion_priority), dplyr::desc(as.Date(date)), dplyr::desc(non_empty_pixels))

  if (nrow(ok) == 0) {
    message("No se ha podido descargar ningún EFFIS útil. Revisa data/raw/effis/effis_download_attempts.csv")
    print(attempts |> dplyr::count(status_code, base_url, version, format, file_type, has_pixels), n = Inf)
    return(tibble::tibble())
  }

  conversion_log <- list()
  layers <- purrr::map_dfr(split(ok, ok$layer), function(df) {
    df <- df |>
      dplyr::arrange(dplyr::desc(conversion_priority), dplyr::desc(as.Date(date)), dplyr::desc(non_empty_pixels))
    for (i in seq_len(nrow(df))) {
      row <- df[i, ]
      bbox <- parse_effis_bbox_value(row$bbox)
      slug <- safe_slug(paste(row$layer, row$date, row$version, row$bbox_label, row$file_type, sep = "_"))
      out_png <- file.path("assets/effis", paste0("effis_", slug, ".png"))
      info <- tryCatch(write_effis_png_from_file(row$file, out_png, bbox = bbox, opacity_alpha = 1), error = function(e) e)
      if (inherits(info, "error")) {
        conversion_log[[length(conversion_log) + 1L]] <<- tibble::tibble(
          layer = row$layer, date = row$date, file = row$file, file_type = row$file_type,
          format = row$format, bbox = row$bbox, error = conditionMessage(info)
        )
        next
      }
      if (is.na(info$non_empty_pixels) || info$non_empty_pixels <= 0) {
        conversion_log[[length(conversion_log) + 1L]] <<- tibble::tibble(
          layer = row$layer, date = row$date, file = row$file, file_type = row$file_type,
          format = row$format, bbox = row$bbox, error = "PNG final sin píxeles visibles"
        )
        next
      }
      return(tibble::tibble(
        layer_id = paste0("effis_", slug),
        layer = row$layer,
        label = row$label,
        group_label = paste0(row$label, " · ", row$date),
        date = row$date,
        source_file = row$file,
        url = sub("^docs/", "", out_png),
        bounds_json = as.character(jsonlite::toJSON(info$bounds, auto_unbox = TRUE)),
        opacity = effis_opacity(),
        zindex = effis_zindex(),
        ncol = info$ncol,
        nrow = info$nrow,
        non_empty_pixels = info$non_empty_pixels,
        bbox = row$bbox,
        wms_bbox = row$wms_bbox,
        source_url = row$url,
        base_url = row$base_url,
        version = row$version,
        format = row$format,
        file_type = row$file_type
      ))
    }
    tibble::tibble()
  })

  conversion_errors <- if (length(conversion_log) > 0) dplyr::bind_rows(conversion_log) else tibble::tibble()
  readr::write_csv(conversion_errors, "data/raw/effis/effis_conversion_errors.csv")

  if (nrow(layers) == 0) {
    message("Se descargaron respuestas EFFIS con píxeles, pero no se pudo generar ningún PNG final.")
    if (nrow(conversion_errors) > 0) {
      message("Errores de conversión guardados en: data/raw/effis/effis_conversion_errors.csv")
      print(conversion_errors |> dplyr::select(layer, date, file_type, format, bbox, error) |> dplyr::slice_head(n = 20), width = 180)
    }
    return(layers)
  }

  json_layers <- layers |>
    dplyr::mutate(bounds = purrr::map(bounds_json, jsonlite::fromJSON)) |>
    dplyr::select(-bounds_json)

  readr::write_csv(layers, "data/processed/effis_layers.csv")
  jsonlite::write_json(json_layers, "data/processed/effis_layers.json", dataframe = "rows", auto_unbox = TRUE, pretty = TRUE, null = "null")
  jsonlite::write_json(json_layers, "assets/effis/layers.json", dataframe = "rows", auto_unbox = TRUE, pretty = TRUE, null = "null")
  try(jsonlite::write_json(json_layers, "docs/assets/effis/layers.json", dataframe = "rows", auto_unbox = TRUE, pretty = TRUE, null = "null"), silent = TRUE)

  message("Capas EFFIS estáticas generadas: ", nrow(layers))
  print(layers |> dplyr::select(layer, date, base_url, version, format, bbox, wms_bbox, non_empty_pixels, url), width = 160)
  layers
}

# -----------------------------------------------------------------------------
# v0.5.25: descubrimiento automático de nombres de capa EFFIS
# -----------------------------------------------------------------------------
# El servicio EFFIS puede cambiar nombres de capa respecto a ejemplos antiguos.
# Si LAYERS=ecmwf007.fwi devuelve "Invalid layer(s)", se leen las capas reales
# de GetCapabilities y se prueban automáticamente las candidatas FWI/fire danger.

effis_layer_name_patterns <- function() {
  pat <- Sys.getenv(
    "EFFIS_LAYER_PATTERNS",
    unset = "fwi|fire.*danger|danger|ecmwf|meteo|forecast|fwiforecast"
  )
  pats <- strsplit(pat, "\\|")[[1]] |> trimws()
  pats[nzchar(pats)]
}

effis_max_layers <- function() {
  x <- suppressWarnings(as.integer(Sys.getenv("EFFIS_MAX_LAYERS", unset = "6")))
  if (is.na(x) || x < 1) x <- 12L
  x
}

effis_extract_layer_names_from_capabilities <- function(cap_text, base_url = NA_character_, version = NA_character_) {
  if (is.na(cap_text) || !nzchar(cap_text)) return(tibble::tibble())
  m <- gregexpr("<Name>\\s*([^<]+)\\s*</Name>", cap_text, perl = TRUE, ignore.case = TRUE)[[1]]
  if (m[1] < 0) return(tibble::tibble())
  names_raw <- regmatches(cap_text, list(m))[[1]]
  starts <- as.integer(m)
  lens <- attr(m, "match.length")
  names <- gsub("</?Name[^>]*>", "", names_raw, ignore.case = TRUE)
  names <- gsub("\\s+", " ", trimws(names))
  titles <- vapply(seq_along(starts), function(i) {
    s <- max(1L, starts[i] - 300L)
    e <- min(nchar(cap_text), starts[i] + lens[i] + 800L)
    block <- substr(cap_text, s, e)
    tm <- regexpr("<Title>\\s*([^<]+)\\s*</Title>", block, perl = TRUE, ignore.case = TRUE)
    if (tm[1] < 0) return(NA_character_)
    title_raw <- regmatches(block, tm)
    title <- gsub("</?Title[^>]*>", "", title_raw, ignore.case = TRUE)
    gsub("\\s+", " ", trimws(title))
  }, character(1))

  bad <- is.na(names) | !nzchar(names) |
    grepl("^(WMS|OGC|EPSG:|CRS:|default|style)$", names, ignore.case = TRUE)

  tibble::tibble(
    base_url = base_url,
    version = version,
    layer = names[!bad],
    title = titles[!bad]
  ) |>
    dplyr::distinct(base_url, version, layer, .keep_all = TRUE)
}

effis_layer_candidate_score <- function(layer, title = NA_character_) {
  txt <- paste(layer %||% "", title %||% "")
  score <- rep(0L, length(txt))
  add <- function(pattern, value) {
    score <<- score + ifelse(grepl(pattern, txt, ignore.case = TRUE, perl = TRUE), value, 0L)
  }
  add("\\bfwi\\b|fire.?weather.?index", 100L)
  # Las capas *.danger_index aparecen en GetCapabilities, pero en GetMap pueden
  # devolver rasters sin contenido visual. Para el overlay del visor preferimos
  # el FWI renderizado directamente (*.fwi).
  add("(^|\\.)fwi\\.fwi$|ecmwf007\\.fwi$|mf010\\.fwi$", 160L)
  add("fire.*danger|danger", 40L)
  add("danger_index", -140L)
  add("ecmwf", 40L)
  add("forecast|forecasts|prediction", 20L)
  add("meteo.?france|meteofrance", 10L)
  add("fuel|burnt|active|perimeter|population|settlement", -20L)
  score
}

effis_available_layers <- function(out_dir = "data/raw/effis", refresh = FALSE) {
  fs::dir_create(out_dir)
  out_csv <- file.path(out_dir, "effis_available_layers.csv")
  if (!refresh && file.exists(out_csv) && file.info(out_csv)$size > 0) {
    x <- tryCatch(readr::read_csv(out_csv, show_col_types = FALSE), error = function(e) NULL)
    if (!is.null(x) && nrow(x) > 0) return(x)
  }

  all_layers <- purrr::map_dfr(effis_wms_bases(), function(base_url) {
    purrr::map_dfr(effis_wms_versions(), function(version) {
      cap <- tryCatch(effis_fetch_capabilities(base_url, version = version, out_dir = out_dir), error = function(e) NULL)
      if (is.null(cap) || !isTRUE(cap$ok)) return(tibble::tibble())
      effis_extract_layer_names_from_capabilities(cap$text, base_url = base_url, version = version)
    })
  })

  if (nrow(all_layers) == 0) {
    readr::write_csv(tibble::tibble(), out_csv)
    return(all_layers)
  }

  pats <- effis_layer_name_patterns()
  pat <- paste(pats, collapse = "|")
  all_layers <- all_layers |>
    dplyr::mutate(
      title = dplyr::coalesce(title, ""),
      candidate_score = effis_layer_candidate_score(layer, title),
      candidate = candidate_score > 0 | grepl(pat, paste(layer, title), ignore.case = TRUE, perl = TRUE)
    ) |>
    dplyr::arrange(dplyr::desc(candidate), dplyr::desc(candidate_score), layer)

  readr::write_csv(all_layers, out_csv)
  all_layers
}

effis_discovered_layer_config <- function() {
  layers <- effis_available_layers()
  if (nrow(layers) == 0) return(tibble::tibble())
  cand <- layers |>
    dplyr::filter(candidate %in% TRUE) |>
    dplyr::arrange(dplyr::desc(candidate_score), layer) |>
    dplyr::distinct(layer, .keep_all = TRUE) |>
    dplyr::slice_head(n = effis_max_layers())
  if (nrow(cand) == 0) return(tibble::tibble())
  tibble::tibble(
    layer = cand$layer,
    label = ifelse(nzchar(cand$title), paste0("EFFIS - ", cand$title), paste0("EFFIS - ", cand$layer))
  )
}

# Sobrescribe la configuración base anterior. Acepta:
#   EFFIS_WMS_LAYERS=auto
#   EFFIS_WMS_LAYERS=ecmwf007.fwi  -> si no existe, se reemplaza por candidatas.
effis_layer_config_base <- function() {
  configured_raw <- Sys.getenv("EFFIS_WMS_LAYERS", unset = "auto")
  configured <- strsplit(configured_raw, ",")[[1]] |> trimws()
  configured <- configured[nzchar(configured)]

  use_auto <- length(configured) == 0 || any(tolower(configured) %in% c("auto", "discover", "discovery"))
  if (use_auto) {
    auto <- effis_discovered_layer_config()
    if (nrow(auto) > 0) return(auto)
    return(tibble::tibble(layer = "ecmwf007.fwi", label = "EFFIS - FWI"))
  }

  labels <- strsplit(Sys.getenv("EFFIS_WMS_LABELS", unset = ""), ",")[[1]] |> trimws()
  if (length(labels) < length(configured)) {
    labels <- c(labels, paste0("EFFIS - ", configured)[(length(labels) + 1):length(configured)])
  }
  labels <- labels[seq_along(configured)]
  labels[!nzchar(labels)] <- paste0("EFFIS - ", configured[!nzchar(labels)])

  cfg <- tibble::tibble(layer = configured, label = labels)
  avail <- tryCatch(effis_available_layers(), error = function(e) tibble::tibble())
  if (nrow(avail) > 0) {
    valid <- cfg$layer %in% avail$layer
    if (!all(valid)) {
      bad <- paste(cfg$layer[!valid], collapse = ", ")
      message("EFFIS: capa(s) no presentes en GetCapabilities: ", bad)
      auto <- effis_discovered_layer_config()
      cfg <- cfg[valid, , drop = FALSE]
      if (nrow(auto) > 0) cfg <- dplyr::bind_rows(cfg, auto)
      cfg <- cfg |> dplyr::distinct(layer, .keep_all = TRUE) |> dplyr::slice_head(n = effis_max_layers())
    }
  }
  cfg
}
