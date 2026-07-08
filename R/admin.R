source("R/utils.R", encoding = "UTF-8")

admin_enabled <- function() {
  tolower(Sys.getenv("ADMIN_ENABLE", unset = "true")) %in% c("true", "1", "yes", "si", "sí")
}

admin_nuts_year <- function() {
  Sys.getenv("ADMIN_NUTS_YEAR", unset = "2021")
}

admin_resolution <- function() {
  # GISCO usa 01M, 03M, 10M, 20M, 60M. Para Leaflet y GitHub Pages,
  # 10M suele ser un buen equilibrio entre detalle y tamaño.
  value <- Sys.getenv("ADMIN_RESOLUTION", unset = "10")
  value <- toupper(trimws(value))
  value <- sub("M$", "", value)
  value_int <- suppressWarnings(as.integer(value))
  if (is.na(value_int) || !value_int %in% c(1L, 3L, 10L, 20L, 60L)) {
    warning("ADMIN_RESOLUTION no válida: ", value, ". Se usa 10M.", call. = FALSE)
    value_int <- 10L
  }
  sprintf("%02dM", value_int)
}

admin_raw_download <- function() {
  tolower(Sys.getenv("ADMIN_DOWNLOAD_MODE", unset = "gisco_4326"))
}

empty_feature_collection <- function(note = "Sin datos") {
  list(type = "FeatureCollection", features = list(), note = note)
}

write_empty_admin_outputs <- function(reason = "Límites administrativos no disponibles") {
  fs::dir_create("data/processed")
  fs::dir_create("assets/admin")

  empty_geo <- empty_feature_collection(reason)
  jsonlite::write_json(empty_geo, "data/processed/admin_nuts2_ccaa.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")
  jsonlite::write_json(empty_geo, "data/processed/admin_nuts3_provincias.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")
  jsonlite::write_json(empty_geo, "assets/admin/admin_nuts2_ccaa.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")
  jsonlite::write_json(empty_geo, "assets/admin/admin_nuts3_provincias.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")

  readr::write_csv(tibble::tibble(), "data/processed/admin_nuts2_ccaa.csv")
  readr::write_csv(tibble::tibble(), "data/processed/admin_nuts3_provincias.csv")
  invisible(FALSE)
}

looks_lonlat_bbox <- function(x) {
  if (is.null(x) || nrow(x) == 0 || !requireNamespace("sf", quietly = TRUE)) return(FALSE)
  bb <- sf::st_bbox(x)
  all(is.finite(as.numeric(bb))) &&
    bb[["xmin"]] >= -180 && bb[["xmax"]] <= 180 &&
    bb[["ymin"]] >= -90 && bb[["ymax"]] <= 90
}

# Leaflet y GeoJSON esperan coordenadas lon/lat en WGS84. Esta versión evita
# descargar en EPSG:3035: usa directamente GeoJSON 4326 de GISCO y solo
# transforma cuando el CRS del objeto indica explícitamente otra proyección.
force_wgs84_lonlat <- function(x, assume_if_missing = 4326) {
  if (!requireNamespace("sf", quietly = TRUE)) return(x)
  if (is.null(x) || nrow(x) == 0) return(x)

  crs <- sf::st_crs(x)

  if (is.na(crs)) {
    # GeoJSON debería ser lon/lat WGS84. Si no hay CRS pero el bbox está en
    # rango geográfico, fijamos 4326 sin transformar. Si no, avisamos y usamos
    # el CRS indicado como último recurso.
    if (looks_lonlat_bbox(x)) {
      sf::st_crs(x) <- 4326
    } else {
      warning(
        "La capa administrativa no tiene CRS y su bbox no parece lon/lat; ",
        "se asignará EPSG:", assume_if_missing, ".",
        call. = FALSE
      )
      sf::st_crs(x) <- assume_if_missing
    }
  }

  epsg <- sf::st_crs(x)$epsg
  if (!isTRUE(!is.na(epsg) && epsg == 4326)) {
    x <- sf::st_transform(x, 4326)
  }

  x
}

assert_admin_bbox_spain <- function(x, label = "admin") {
  if (is.null(x) || nrow(x) == 0 || !requireNamespace("sf", quietly = TRUE)) return(invisible(FALSE))
  x <- force_wgs84_lonlat(x)
  bb <- sf::st_bbox(x)
  bbox_txt <- paste(round(as.numeric(bb), 4), collapse = ", ")
  message("BBOX ", label, " EPSG:4326: ", bbox_txt)

  # Rango amplio para España, Canarias, Ceuta y Melilla.
  plausible <- bb[["xmin"]] > -20.5 && bb[["xmax"]] < 6.5 &&
    bb[["ymin"]] > 26 && bb[["ymax"]] < 45.5

  if (!plausible) {
    stop(
      "BBOX no plausible para España en EPSG:4326 [", label, "]: ", bbox_txt,
      ". Esto indica un problema de CRS/ejes; no se publican esos límites.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

normalise_nuts <- function(x, level_label) {
  if (nrow(x) == 0) return(x)

  name_col <- dplyr::case_when(
    "NAME_LATN" %in% names(x) ~ "NAME_LATN",
    "NUTS_NAME" %in% names(x) ~ "NUTS_NAME",
    "name_latn" %in% names(x) ~ "name_latn",
    "NAME_ENGL" %in% names(x) ~ "NAME_ENGL",
    TRUE ~ NA_character_
  )

  if (!"NUTS_ID" %in% names(x)) {
    stop("La capa NUTS no contiene columna NUTS_ID.", call. = FALSE)
  }

  if (is.na(name_col)) {
    x$admin_name <- as.character(x$NUTS_ID)
  } else {
    x$admin_name <- as.character(x[[name_col]])
  }

  x |>
    dplyr::mutate(
      admin_level = level_label,
      admin_id = as.character(NUTS_ID),
      admin_name = as.character(admin_name)
    ) |>
    dplyr::select(admin_level, admin_id, admin_name, dplyr::everything())
}

filter_spain_nuts <- function(x, level) {
  if (nrow(x) == 0) return(x)
  if ("LEVL_CODE" %in% names(x)) {
    x <- x |> dplyr::filter(as.integer(LEVL_CODE) == as.integer(level))
  }
  if ("CNTR_CODE" %in% names(x)) {
    x <- x |> dplyr::filter(.data$CNTR_CODE == "ES")
  } else if ("NUTS_ID" %in% names(x)) {
    x <- x |> dplyr::filter(grepl("^ES", .data$NUTS_ID))
  }
  x
}

gisco_direct_url <- function(level, year, resolution) {
  base <- Sys.getenv(
    "ADMIN_GISCO_BASE_URL",
    unset = "https://gisco-services.ec.europa.eu/distribution/v2/nuts/geojson"
  )
  file <- sprintf("NUTS_RG_%s_%s_4326_LEVL_%s.geojson", resolution, year, level)
  paste0(sub("/$", "", base), "/", file)
}

download_file_if_needed <- function(url, dest, overwrite = FALSE) {
  fs::dir_create(dirname(dest))
  if (file.exists(dest) && file.info(dest)$size > 0 && !overwrite) return(dest)

  tmp <- tempfile(fileext = ".geojson")
  ok <- FALSE

  if (requireNamespace("curl", quietly = TRUE)) {
    ok <- tryCatch({
      curl::curl_download(url, tmp, quiet = TRUE, handle = curl::new_handle(useragent = "visor-fuego/0.5.3"))
      TRUE
    }, error = function(e) FALSE)
  }

  if (!ok) {
    ok <- tryCatch({
      utils::download.file(url, tmp, quiet = TRUE, mode = "wb")
      TRUE
    }, error = function(e) FALSE)
  }

  if (!ok || !file.exists(tmp) || file.info(tmp)$size == 0) {
    stop("No se pudo descargar ", url, call. = FALSE)
  }

  file.copy(tmp, dest, overwrite = TRUE)
  dest
}

read_gisco_nuts_direct <- function(level, year, resolution) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("Falta el paquete sf.", call. = FALSE)
  }

  url <- gisco_direct_url(level = level, year = year, resolution = resolution)
  raw_path <- file.path(
    "data/raw/admin",
    sprintf("NUTS_RG_%s_%s_4326_LEVL_%s.geojson", resolution, year, level)
  )

  message("GISCO/NUTS: leyendo EPSG:4326 directo: ", url)
  download_file_if_needed(url, raw_path, overwrite = FALSE)

  x <- sf::st_read(raw_path, quiet = TRUE, stringsAsFactors = FALSE)
  x <- force_wgs84_lonlat(x, assume_if_missing = 4326)
  filter_spain_nuts(x, level = level)
}

read_gisco_nuts_fallback <- function(level, year, resolution) {
  if (!requireNamespace("giscoR", quietly = TRUE)) {
    stop("Falta giscoR y falló la descarga directa.", call. = FALSE)
  }
  message("GISCO/NUTS: fallback giscoR en EPSG:4326, nivel ", level)
  x <- giscoR::gisco_get_nuts(
    country = "ES",
    nuts_level = level,
    year = year,
    resolution = sub("M$", "", resolution),
    epsg = 4326
  )
  x <- force_wgs84_lonlat(x, assume_if_missing = 4326)
  filter_spain_nuts(x, level = level)
}

read_gisco_nuts <- function(level, year, resolution) {
  direct <- tryCatch(
    read_gisco_nuts_direct(level = level, year = year, resolution = resolution),
    error = function(e) e
  )
  if (!inherits(direct, "error")) return(direct)

  warning("Descarga directa GISCO falló: ", conditionMessage(direct), call. = FALSE)
  read_gisco_nuts_fallback(level = level, year = year, resolution = resolution)
}

clean_admin_geometry <- function(x, level_label) {
  if (is.null(x) || nrow(x) == 0) return(x)

  x <- normalise_nuts(x, level_label)
  x <- force_wgs84_lonlat(x, assume_if_missing = 4326)
  x <- sf::st_make_valid(x)
  x <- suppressWarnings(sf::st_collection_extract(x, "POLYGON"))
  x <- force_wgs84_lonlat(x, assume_if_missing = 4326)
  x
}

write_admin_layer <- function(x, geojson_processed, geojson_assets, csv_path, label) {
  if (is.null(x) || nrow(x) == 0) return(invisible(FALSE))
  assert_admin_bbox_spain(x, label)
  sf::st_write(x, geojson_processed, delete_dsn = TRUE, quiet = TRUE)
  sf::st_write(x, geojson_assets, delete_dsn = TRUE, quiet = TRUE)
  readr::write_csv(
    sf::st_drop_geometry(x) |>
      dplyr::select(admin_level, admin_id, admin_name),
    csv_path
  )
  invisible(TRUE)
}

download_admin_boundaries <- function() {
  if (!admin_enabled()) {
    message("ADMIN_ENABLE=false: se omiten límites administrativos.")
    return(write_empty_admin_outputs("ADMIN_ENABLE=false"))
  }
  if (!requireNamespace("sf", quietly = TRUE)) {
    warning("Falta el paquete 'sf'. Se omiten límites administrativos.", call. = FALSE)
    return(write_empty_admin_outputs("Falta paquete sf"))
  }

  fs::dir_create("data/raw/admin")
  fs::dir_create("data/processed")
  fs::dir_create("assets/admin")

  year <- admin_nuts_year()
  resolution <- admin_resolution()

  message("GISCO/NUTS: España NUTS2/NUTS3, año ", year, ", resolución ", resolution, ", EPSG:4326 directo")

  nuts2 <- tryCatch(read_gisco_nuts(level = 2, year = year, resolution = resolution), error = function(e) e)
  if (inherits(nuts2, "error")) {
    warning("No se pudieron preparar CCAA NUTS2: ", conditionMessage(nuts2), call. = FALSE)
    nuts2 <- sf::st_sf(geometry = sf::st_sfc(crs = 4326))
  }

  nuts3 <- tryCatch(read_gisco_nuts(level = 3, year = year, resolution = resolution), error = function(e) e)
  if (inherits(nuts3, "error")) {
    warning("No se pudieron preparar provincias NUTS3: ", conditionMessage(nuts3), call. = FALSE)
    nuts3 <- sf::st_sf(geometry = sf::st_sfc(crs = 4326))
  }

  if (nrow(nuts2) == 0 && nrow(nuts3) == 0) {
    return(write_empty_admin_outputs("GISCO no devolvió límites"))
  }

  if (nrow(nuts2) > 0) {
    nuts2 <- clean_admin_geometry(nuts2, "ccaa")
    write_admin_layer(
      nuts2,
      "data/processed/admin_nuts2_ccaa.geojson",
      "assets/admin/admin_nuts2_ccaa.geojson",
      "data/processed/admin_nuts2_ccaa.csv",
      "NUTS2 CCAA"
    )
  }

  if (nrow(nuts3) > 0) {
    nuts3 <- clean_admin_geometry(nuts3, "provincia")
    write_admin_layer(
      nuts3,
      "data/processed/admin_nuts3_provincias.geojson",
      "assets/admin/admin_nuts3_provincias.geojson",
      "data/processed/admin_nuts3_provincias.csv",
      "NUTS3 provincias"
    )
  }

  message("GISCO/NUTS: límites preparados en EPSG:4326 lon/lat")
  invisible(TRUE)
}

read_admin_layer <- function(path) {
  if (!file.exists(path) || file.info(path)$size == 0) return(NULL)
  if (!requireNamespace("sf", quietly = TRUE)) return(NULL)
  x <- tryCatch(sf::st_read(path, quiet = TRUE), error = function(e) NULL)
  if (is.null(x) || nrow(x) == 0) return(NULL)
  force_wgs84_lonlat(x, assume_if_missing = 4326)
}

diagnose_admin_boundaries <- function() {
  if (!requireNamespace("sf", quietly = TRUE)) {
    message("Falta sf; no se puede diagnosticar NUTS.")
    return(invisible(FALSE))
  }

  paths <- c(
    NUTS2 = "data/processed/admin_nuts2_ccaa.geojson",
    NUTS3 = "data/processed/admin_nuts3_provincias.geojson"
  )

  for (nm in names(paths)) {
    path <- paths[[nm]]
    cat("\n", nm, ": ", path, "\n", sep = "")
    if (!file.exists(path)) {
      cat("  No existe\n")
      next
    }
    x <- sf::st_read(path, quiet = TRUE)
    cat("  Filas:", nrow(x), "\n")
    cat("  CRS:", sf::st_crs(x)$input, "\n")
    x <- force_wgs84_lonlat(x, assume_if_missing = 4326)
    bb <- sf::st_bbox(x)
    cat("  BBOX EPSG:4326:", paste(round(as.numeric(bb), 4), collapse = ", "), "\n")
    if (nrow(x) > 0 && "admin_name" %in% names(x)) {
      cat("  Ejemplos:", paste(head(x$admin_name, 5), collapse = " · "), "\n")
    }
  }

  invisible(TRUE)
}
