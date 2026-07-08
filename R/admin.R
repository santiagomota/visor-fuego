source("R/utils.R", encoding = "UTF-8")

admin_enabled <- function() {
  tolower(Sys.getenv("ADMIN_ENABLE", unset = "true")) %in% c("true", "1", "yes", "si", "sí")
}

admin_nuts_year <- function() {
  Sys.getenv("ADMIN_NUTS_YEAR", unset = "2021")
}

admin_resolution <- function() {
  Sys.getenv("ADMIN_RESOLUTION", unset = "10")
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

# Leaflet y GeoJSON esperan coordenadas lon/lat en WGS84. Para evitar
# problemas de eje/proyección con las descargas de GISCO, las geometrías se
# descargan preferentemente en EPSG:3035 y se transforman explícitamente aquí.
force_wgs84_lonlat <- function(x, assume_if_missing = 3035) {
  if (!requireNamespace("sf", quietly = TRUE)) return(x)
  if (is.null(x) || nrow(x) == 0) return(x)

  crs <- sf::st_crs(x)
  if (is.na(crs)) {
    # Si el bbox no parece lon/lat, asumimos LAEA Europe (EPSG:3035), que es
    # la proyección nativa habitual de GISCO para Europa.
    bb <- sf::st_bbox(x)
    looks_lonlat <- is.finite(bb[["xmin"]]) && is.finite(bb[["xmax"]]) &&
      is.finite(bb[["ymin"]]) && is.finite(bb[["ymax"]]) &&
      bb[["xmin"]] >= -180 && bb[["xmax"]] <= 180 && bb[["ymin"]] >= -90 && bb[["ymax"]] <= 90
    sf::st_crs(x) <- if (looks_lonlat) 4326 else assume_if_missing
  }

  x <- sf::st_transform(x, 4326)

  # GeoJSON usa lon/lat; esta comprobación detecta ficheros claramente fuera
  # de rango antes de publicarlos.
  bb <- sf::st_bbox(x)
  if (!is.finite(bb[["xmin"]]) || !is.finite(bb[["xmax"]]) ||
      bb[["xmin"]] < -180 || bb[["xmax"]] > 180 ||
      bb[["ymin"]] < -90 || bb[["ymax"]] > 90) {
    warning(
      "La geometría administrativa no parece estar en lon/lat EPSG:4326 tras transformar. BBOX=",
      paste(round(as.numeric(bb), 3), collapse = ", "),
      call. = FALSE
    )
  }

  x
}

normalise_nuts <- function(x, level_label) {
  if (nrow(x) == 0) return(x)

  # GISCO ha cambiado algunos nombres de columnas entre versiones/años.
  name_col <- dplyr::case_when(
    "NAME_LATN" %in% names(x) ~ "NAME_LATN",
    "NUTS_NAME" %in% names(x) ~ "NUTS_NAME",
    "name_latn" %in% names(x) ~ "name_latn",
    TRUE ~ NA_character_
  )

  if (is.na(name_col)) {
    x$admin_name <- x$NUTS_ID
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

download_admin_boundaries <- function() {
  if (!admin_enabled()) {
    message("ADMIN_ENABLE=false: se omiten límites administrativos.")
    return(write_empty_admin_outputs("ADMIN_ENABLE=false"))
  }
  if (!requireNamespace("sf", quietly = TRUE)) {
    warning("Falta el paquete 'sf'. Se omiten límites administrativos.", call. = FALSE)
    return(write_empty_admin_outputs("Falta paquete sf"))
  }
  if (!requireNamespace("giscoR", quietly = TRUE)) {
    warning("Falta el paquete 'giscoR'. Instala con install.packages('giscoR').", call. = FALSE)
    return(write_empty_admin_outputs("Falta paquete giscoR"))
  }

  fs::dir_create("data/raw/admin")
  fs::dir_create("data/processed")
  fs::dir_create("assets/admin")

  year <- admin_nuts_year()
  resolution <- admin_resolution()

  message("GISCO/NUTS: descargando CCAA NUTS2 España, año ", year, ", resolución ", resolution, ", EPSG:3035 → EPSG:4326")
  nuts2 <- tryCatch(
    giscoR::gisco_get_nuts(country = "ES", nuts_level = 2, year = year, resolution = resolution, epsg = 3035),
    error = function(e) e
  )
  if (inherits(nuts2, "error")) {
    warning("No se pudieron descargar CCAA NUTS2: ", conditionMessage(nuts2), call. = FALSE)
    nuts2 <- sf::st_sf(geometry = sf::st_sfc(crs = 4326))
  }

  message("GISCO/NUTS: descargando provincias NUTS3 España, año ", year, ", resolución ", resolution, ", EPSG:3035 → EPSG:4326")
  nuts3 <- tryCatch(
    giscoR::gisco_get_nuts(country = "ES", nuts_level = 3, year = year, resolution = resolution, epsg = 3035),
    error = function(e) e
  )
  if (inherits(nuts3, "error")) {
    warning("No se pudieron descargar provincias NUTS3: ", conditionMessage(nuts3), call. = FALSE)
    nuts3 <- sf::st_sf(geometry = sf::st_sfc(crs = 4326))
  }

  if (nrow(nuts2) == 0 && nrow(nuts3) == 0) {
    return(write_empty_admin_outputs("GISCO no devolvió límites"))
  }

  if (nrow(nuts2) > 0) {
    nuts2 <- normalise_nuts(nuts2, "ccaa") |>
      force_wgs84_lonlat() |>
      sf::st_make_valid()
    sf::st_write(nuts2, "data/processed/admin_nuts2_ccaa.geojson", delete_dsn = TRUE, quiet = TRUE)
    sf::st_write(nuts2, "assets/admin/admin_nuts2_ccaa.geojson", delete_dsn = TRUE, quiet = TRUE)
    readr::write_csv(sf::st_drop_geometry(nuts2) |> dplyr::select(admin_level, admin_id, admin_name), "data/processed/admin_nuts2_ccaa.csv")
  }

  if (nrow(nuts3) > 0) {
    nuts3 <- normalise_nuts(nuts3, "provincia") |>
      force_wgs84_lonlat() |>
      sf::st_make_valid()
    sf::st_write(nuts3, "data/processed/admin_nuts3_provincias.geojson", delete_dsn = TRUE, quiet = TRUE)
    sf::st_write(nuts3, "assets/admin/admin_nuts3_provincias.geojson", delete_dsn = TRUE, quiet = TRUE)
    readr::write_csv(sf::st_drop_geometry(nuts3) |> dplyr::select(admin_level, admin_id, admin_name), "data/processed/admin_nuts3_provincias.csv")
  }

  message("GISCO/NUTS: límites preparados")
  invisible(TRUE)
}

read_admin_layer <- function(path) {
  if (!file.exists(path) || file.info(path)$size == 0) return(NULL)
  if (!requireNamespace("sf", quietly = TRUE)) return(NULL)
  x <- tryCatch(sf::st_read(path, quiet = TRUE), error = function(e) NULL)
  if (is.null(x) || nrow(x) == 0) return(NULL)
  force_wgs84_lonlat(x)
}
