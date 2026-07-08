#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(xml2)
  library(dplyr)
  library(readr)
  library(stringr)
  library(purrr)
  library(tibble)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x)) || !nzchar(paste(x, collapse = ""))) y else x

out_dir <- "data/raw/effis"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

split_env <- function(name, default) {
  x <- Sys.getenv(name, unset = default)
  values <- trimws(strsplit(x, ",", fixed = TRUE)[[1]])
  values <- values[nzchar(values)]
  unique(values)
}

base_urls <- split_env("EFFIS_WMS_BASES", Sys.getenv("EFFIS_WMS_BASE", "https://ies-ows.jrc.ec.europa.eu/effis"))
versions <- split_env("EFFIS_WMS_VERSIONS", "1.1.1,1.3.0")
patterns <- Sys.getenv("EFFIS_LAYER_PATTERNS", "fwi|fire.*danger|danger|ecmwf007|ecmwf|mf010")
max_probe <- as.integer(Sys.getenv("EFFIS_TIME_PROBE_MAX", "160"))
probe_bbox <- Sys.getenv("EFFIS_BBOX", "-18.0,27.0,42.0,72.0")
probe_width <- as.integer(Sys.getenv("EFFIS_WIDTH", "1600"))
probe_height <- as.integer(Sys.getenv("EFFIS_HEIGHT", "1200"))
formats <- split_env("EFFIS_PROBE_FORMATS", "image/png,image/tiff")
ref_date <- as.Date(Sys.getenv("EFFIS_REFERENCE_DATE", as.character(Sys.Date())))
past_days <- as.integer(Sys.getenv("EFFIS_TIME_PAST_DAYS", "10"))
future_days <- as.integer(Sys.getenv("EFFIS_TIME_FUTURE_DAYS", "16"))
max_times_per_layer <- as.integer(Sys.getenv("EFFIS_TIME_MAX_PER_LAYER", "8"))
if (is.na(max_probe) || max_probe < 1) max_probe <- 160L
if (is.na(past_days) || past_days < 0) past_days <- 10L
if (is.na(future_days) || future_days < 0) future_days <- 16L
if (is.na(max_times_per_layer) || max_times_per_layer < 1) max_times_per_layer <- 8L
if (is.na(probe_width) || probe_width < 100) probe_width <- 1600L
if (is.na(probe_height) || probe_height < 100) probe_height <- 1200L

build_wms_url <- function(base_url, params) {
  encode_wms_value <- function(x) {
    x <- utils::URLencode(as.character(x), reserved = FALSE)
    x <- gsub("%2C", ",", x, ignore.case = TRUE)
    x <- gsub("%2F", "/", x, ignore.case = TRUE)
    x <- gsub("%3A", ":", x, ignore.case = TRUE)
    x
  }
  vals <- vapply(params, function(x) paste(as.character(x), collapse = ","), character(1))
  keep <- !is.na(vals)
  qs <- paste0(names(params)[keep], "=", vapply(vals[keep], encode_wms_value, character(1)))
  paste0(base_url, ifelse(grepl("\\?", base_url), "&", "?"), paste(qs, collapse = "&"))
}

cap_url <- function(base_url, version) {
  build_wms_url(base_url, list(SERVICE = "WMS", VERSION = version, REQUEST = "GetCapabilities"))
}

get_caps <- function(base_url, version) {
  dest <- file.path(out_dir, sprintf("effis_getcapabilities_%s_%s.xml", gsub("[^A-Za-z0-9]+", "_", base_url), gsub("\\.", "_", version)))
  url <- cap_url(base_url, version)
  err <- NA_character_
  ok <- tryCatch({
    utils::download.file(url, destfile = dest, mode = "wb", quiet = TRUE)
    TRUE
  }, error = function(e) { err <<- conditionMessage(e); FALSE })
  if (!ok || !file.exists(dest) || file.size(dest) == 0) {
    return(tibble(base_url = base_url, version = version, caps_file = dest, ok = FALSE, error = err))
  }
  tibble(base_url = base_url, version = version, caps_file = dest, ok = TRUE, error = NA_character_)
}

extract_layers <- function(caps_row) {
  if (!isTRUE(caps_row$ok)) return(tibble())
  doc <- xml2::read_xml(caps_row$caps_file)
  xml2::xml_ns_strip(doc)
  layer_nodes <- xml2::xml_find_all(doc, ".//Layer[Name]")
  map_dfr(layer_nodes, function(node) {
    layer <- xml_text(xml_find_first(node, "./Name"), trim = TRUE)
    title <- xml_text(xml_find_first(node, "./Title"), trim = TRUE)
    dim_nodes <- xml_find_all(node, "./Dimension[translate(@name,'TIME','time')='time'] | ./Extent[translate(@name,'TIME','time')='time']")
    time_text <- paste(xml_text(dim_nodes, trim = TRUE), collapse = ",")
    default_time <- paste(xml_attr(dim_nodes, "default"), collapse = ",")
    styles <- xml_text(xml_find_all(node, "./Style/Name"), trim = TRUE)
    styles <- unique(styles[nzchar(styles)])
    styles_text <- paste(styles, collapse = ",")
    bbox_node <- xml_find_first(node, "./EX_GeographicBoundingBox")
    bbox <- NA_character_
    if (!inherits(bbox_node, "xml_missing")) {
      west <- xml_text(xml_find_first(bbox_node, "./westBoundLongitude"), trim = TRUE)
      south <- xml_text(xml_find_first(bbox_node, "./southBoundLatitude"), trim = TRUE)
      east <- xml_text(xml_find_first(bbox_node, "./eastBoundLongitude"), trim = TRUE)
      north <- xml_text(xml_find_first(bbox_node, "./northBoundLatitude"), trim = TRUE)
      bbox <- paste(west, south, east, north, sep = ",")
    }
    txt <- str_to_lower(paste(layer, title, sep = " "))
    candidate <- str_detect(txt, regex(patterns, ignore_case = TRUE))
    # Evita query layers como primera opción: suelen ser para GetFeatureInfo.
    score <- 0L
    score <- score + ifelse(grepl("fwi", txt, ignore.case = TRUE), 100L, 0L)
    score <- score + ifelse(grepl("ecmwf007\\.fwi$|mf010\\.fwi$|ecmwf\\.fwi\\.fwi$", layer, ignore.case = TRUE), 120L, 0L)
    score <- score + ifelse(grepl("danger", txt, ignore.case = TRUE), 20L, 0L)
    score <- score - ifelse(grepl("query|nuts", layer, ignore.case = TRUE), 100L, 0L)
    tibble(
      base_url = caps_row$base_url,
      version = caps_row$version,
      layer = layer,
      title = title,
      styles = styles_text,
      time_text = time_text,
      default_time = default_time,
      advertised_bbox = bbox,
      has_time = nzchar(time_text),
      candidate = candidate,
      candidate_score = score
    )
  })
}

parse_sane_time_tokens <- function(x, default_time = NA_character_, max_dates = 8) {
  win_start <- ref_date - past_days
  win_end <- ref_date + future_days
  out <- character()

  safe_date <- function(z) {
    z <- trimws(as.character(z))
    z[is.na(z)] <- ""
    # WMS TIME puede traer intervalos, horas, CURRENT, min/max, etc.
    # Nos quedamos solo con patrones ISO YYYY-MM-DD válidos.
    m <- stringr::str_extract(z, "[0-9]{4}-[0-9]{2}-[0-9]{2}")
    suppressWarnings(as.Date(m))
  }

  add_dates <- function(d) {
    d <- safe_date(d)
    d <- unique(d[!is.na(d)])
    d <- d[d >= win_start & d <= win_end]
    if (length(d)) out <<- c(out, as.character(d))
  }

  add_window <- function() {
    # Ventana operativa realista. Evita usar el final de intervalos abiertos
    # tipo 2099-12-31 que algunos GetCapabilities anuncian como fecha máxima.
    c(
      as.character(seq(ref_date, ref_date - min(past_days, 7L), by = "-1 day")),
      as.character(seq(ref_date + 1, ref_date + min(future_days, 9L), by = "day"))
    )
  }

  # Primero defaults si son fechas sensatas.
  if (!is.na(default_time) && nzchar(default_time)) {
    add_dates(strsplit(default_time, ",", fixed = TRUE)[[1]])
  }

  if (!is.na(x) && nzchar(x)) {
    parts <- trimws(strsplit(x, ",", fixed = TRUE)[[1]])
    for (p in parts) {
      if (!nzchar(p)) next
      if (stringr::str_detect(p, "/")) {
        seg <- strsplit(p, "/", fixed = TRUE)[[1]]
        if (length(seg) >= 2) {
          start <- safe_date(seg[1])
          end <- safe_date(seg[2])
          if (length(start) && length(end) && !is.na(start) && !is.na(end)) {
            a <- max(start, win_start)
            b <- min(end, win_end)
            if (!is.na(a) && !is.na(b) && a <= b) {
              add_dates(seq(a, b, by = "day"))
            }
          }
        }
      } else {
        add_dates(p)
      }
    }
  }

  out <- unique(out)
  if (length(out) == 0) out <- add_window()

  d <- safe_date(out)
  keep <- !is.na(d)
  out <- out[keep]
  d <- d[keep]
  if (length(out) == 0) {
    out <- add_window()
    d <- safe_date(out)
  }

  ord <- order(abs(as.numeric(d - ref_date)), d, decreasing = FALSE)
  out <- unique(out[ord])
  out[seq_len(min(max_dates, length(out)))]
}

classify_file <- function(path) {
  if (!file.exists(path) || file.size(path) == 0) return("missing")
  raw <- readBin(path, "raw", n = 16)
  hex <- paste(format(raw), collapse = " ")
  if (startsWith(hex, "89 50 4e 47")) return("image")
  if (startsWith(hex, "49 49 2a 00") || startsWith(hex, "4d 4d 00 2a")) return("raster")
  if (startsWith(hex, "3c 3f 78 6d 6c") || startsWith(hex, "3c 53 65 72")) return("xml")
  "unknown"
}

xml_message <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  txt <- tryCatch(readLines(path, warn = FALSE, encoding = "UTF-8"), error = function(e) character())
  txt <- paste(txt, collapse = " ")
  if (!nzchar(txt)) return(NA_character_)
  m <- gregexpr("<ServiceException[^>]*>(.*?)</ServiceException>", txt, perl = TRUE, ignore.case = TRUE)[[1]]
  if (m[1] > 0) {
    parts <- regmatches(txt, list(m))[[1]]
    parts <- gsub("<[^>]+>", " ", parts)
    return(gsub("\\s+", " ", trimws(paste(parts, collapse = " | "))))
  }
  gsub("\\s+", " ", trimws(gsub("<[^>]+>", " ", txt)))
}

image_score <- function(path, file_type) {
  if (file_type == "image" && requireNamespace("png", quietly = TRUE)) {
    img <- tryCatch(png::readPNG(path), error = function(e) NULL)
    if (is.null(img)) return(tibble(has_visual = FALSE, visual_score = 0, note = "png read failed"))
    d <- dim(img)
    if (length(d) == 2) {
      vals <- as.numeric(img); vals <- vals[is.finite(vals)]
      rng <- if (length(vals)) diff(range(vals, na.rm = TRUE)) else 0
      return(tibble(has_visual = is.finite(rng) && rng > 0.01, visual_score = stats::sd(vals, na.rm = TRUE), note = "png gray"))
    }
    if (length(d) == 3) {
      rgb <- img[, , seq_len(min(3, d[3])), drop = FALSE]
      alpha <- if (d[3] >= 4) img[, , 4] else matrix(1, d[1], d[2])
      mask <- is.finite(alpha) & alpha > 0.02
      if (!any(mask, na.rm = TRUE)) return(tibble(has_visual = FALSE, visual_score = 0, note = "png alpha empty"))
      vals <- unlist(lapply(seq_len(min(3, d[3])), function(k) as.numeric(rgb[, , k][mask])), use.names = FALSE)
      vals <- vals[is.finite(vals)]
      rng <- if (length(vals)) diff(range(vals, na.rm = TRUE)) else 0
      return(tibble(has_visual = is.finite(rng) && rng > 0.01, visual_score = stats::sd(vals, na.rm = TRUE), note = paste0("png rgb; range=", signif(rng, 4))))
    }
    return(tibble(has_visual = FALSE, visual_score = 0, note = "png bad dims"))
  }
  if (file_type == "raster" && requireNamespace("terra", quietly = TRUE)) {
    r <- tryCatch(terra::rast(path), error = function(e) NULL)
    if (is.null(r)) return(tibble(has_visual = FALSE, visual_score = 0, note = "terra read failed"))
    s <- tryCatch(terra::global(r[[seq_len(min(terra::nlyr(r), 3L))]], c("min", "max"), na.rm = TRUE), error = function(e) NULL)
    if (is.null(s)) return(tibble(has_visual = FALSE, visual_score = 0, note = "terra stats failed"))
    rng <- suppressWarnings(max(s$max - s$min, na.rm = TRUE))
    if (!is.finite(rng)) rng <- 0
    return(tibble(has_visual = rng > 0.01, visual_score = rng, note = paste0("raster range=", signif(rng, 4))))
  }
  tibble(has_visual = FALSE, visual_score = 0, note = file_type)
}

parse_bbox <- function(value) {
  z <- suppressWarnings(as.numeric(strsplit(value, ",")[[1]] |> trimws()))
  if (length(z) != 4 || any(is.na(z))) stop("BBOX inválido: ", value, call. = FALSE)
  names(z) <- c("xmin", "ymin", "xmax", "ymax")
  z
}

bbox_for_wms <- function(value, version) {
  b <- parse_bbox(value)
  vals <- if (identical(version, "1.3.0")) c(b["ymin"], b["xmin"], b["ymax"], b["xmax"]) else c(b["xmin"], b["ymin"], b["xmax"], b["ymax"])
  paste(formatC(vals, format = "f", digits = 6, drop0trailing = TRUE), collapse = ",")
}

message("Descargando GetCapabilities EFFIS...")
caps <- tidyr::crossing(base_url = base_urls, version = versions) |>
  purrr::pmap_dfr(function(base_url, version) get_caps(base_url, version))
readr::write_csv(caps, file.path(out_dir, "effis_capabilities_probe.csv"))

layers <- purrr::pmap_dfr(caps, function(base_url, version, caps_file, ok, error) {
  extract_layers(tibble(base_url = base_url, version = version, caps_file = caps_file, ok = ok))
})

readr::write_csv(layers, file.path(out_dir, "effis_available_layers_with_time.csv"))

candidates <- layers |>
  filter(candidate, has_time) |>
  mutate(time_tokens = purrr::map2(time_text, default_time, parse_sane_time_tokens, max_dates = max_times_per_layer)) |>
  tidyr::unnest(time_tokens, keep_empty = FALSE) |>
  mutate(time_date = suppressWarnings(as.Date(substr(time_tokens, 1, 10)))) |>
  arrange(desc(candidate_score), abs(as.numeric(time_date - ref_date)), base_url, version, layer)

readr::write_csv(candidates, file.path(out_dir, "effis_candidate_times.csv"))

message("Capas candidatas con TIME sensato guardadas en data/raw/effis/effis_candidate_times.csv")
print(candidates |> select(base_url, version, layer, title, styles, default_time, time_tokens, time_date, candidate_score) |> head(60), n = 60, width = 220)

if (nrow(candidates) == 0) stop("No hay capas candidatas con TIME en GetCapabilities.")

style_rows <- candidates |>
  mutate(style_list = purrr::map(styles, function(s) {
    x <- if (is.na(s) || !nzchar(s)) character() else strsplit(s, ",")[[1]] |> trimws()
    unique(c("", x[nzchar(x)]))[seq_len(min(3L, length(unique(c("", x[nzchar(x)])))))]
  })) |>
  tidyr::unnest(style_list, keep_empty = TRUE) |>
  rename(style = style_list)

probe_grid <- style_rows |>
  group_by(base_url, version, layer, title, time_tokens) |>
  slice_head(n = 1) |>
  ungroup() |>
  tidyr::crossing(format = formats) |>
  arrange(desc(candidate_score), abs(as.numeric(time_date - ref_date)), layer, version, format) |>
  head(max_probe)

probe_one <- function(base_url, version, layer, time_token, format, style, idx) {
  crs_param <- if (version == "1.3.0") "CRS" else "SRS"
  params <- list(
    LAYERS = layer, FORMAT = format, TRANSPARENT = "true", SINGLETILE = "false",
    SERVICE = "wms", VERSION = version, REQUEST = "GetMap", STYLES = style %||% "",
    BBOX = bbox_for_wms(probe_bbox, version), WIDTH = probe_width, HEIGHT = probe_height,
    TIME = time_token, EXCEPTIONS = "application/vnd.ogc.se_xml"
  )
  params[[crs_param]] <- "EPSG:4326"
  url <- build_wms_url(base_url, params)
  ext <- if (format == "image/png") "png" else "tif"
  dest <- file.path(out_dir, sprintf("effis_time_probe_%03d_%s_%s_%s.%s", idx, gsub("[^A-Za-z0-9]+", "_", layer), gsub("[^0-9A-Za-z]+", "_", time_token), ifelse(nzchar(style %||% ""), gsub("[^A-Za-z0-9]+", "_", style), "default"), ext))
  err <- NA_character_
  ok <- tryCatch({ utils::download.file(url, destfile = dest, mode = "wb", quiet = TRUE); TRUE }, error = function(e) { err <<- conditionMessage(e); FALSE })
  ft <- classify_file(dest)
  score <- image_score(dest, ft)
  msg <- if (identical(ft, "xml")) xml_message(dest) else score$note
  tibble(base_url = base_url, version = version, layer = layer, time = time_token, style = style %||% "",
         format = format, file = dest, file_type = ft, size_bytes = if (file.exists(dest)) file.size(dest) else NA_real_,
         has_visual = score$has_visual, visual_score = score$visual_score, note = msg, error = err, url = url)
}

message("Probando TIME alrededor de ", ref_date, " y estilos de GetCapabilities...")
probes <- purrr::pmap_dfr(probe_grid |> mutate(idx = row_number()), function(base_url, version, layer, title, styles, time_text, default_time, advertised_bbox, has_time, candidate, candidate_score, time_tokens, time_date, style, format, idx, ...) {
  probe_one(base_url, version, layer, time_tokens, format, style, idx)
})

readr::write_csv(probes, file.path(out_dir, "effis_time_probe.csv"))
message("Resumen probe guardado en data/raw/effis/effis_time_probe.csv")
print(probes |> count(layer, time, style, version, format, file_type, has_visual, note) |> arrange(desc(has_visual), layer, desc(time)) , n = Inf, width = 220)

best <- probes |> filter(has_visual) |> arrange(abs(as.numeric(as.Date(substr(time, 1, 10)) - ref_date)), desc(visual_score)) |> slice(1)
if (nrow(best)) {
  message("\nMejor candidato visual:")
  print(best |> select(base_url, version, layer, time, style, format, file, visual_score, url), width = 220)
} else {
  message("\nNo se encontró ningún candidato visual. Revisa data/raw/effis/effis_candidate_times.csv y effis_time_probe.csv")
  message("Sugerencia: prueba EFFIS_REFERENCE_DATE=2021-12-08 Rscript scripts/27_inspect_effis_times.R para validar el ejemplo oficial histórico.")
}
