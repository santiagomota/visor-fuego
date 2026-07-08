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

  message("GISCO/NUTS: descargando CCAA NUTS2 España, año ", year, ", resolución ", resolution)
  nuts2 <- tryCatch(
    giscoR::gisco_get_nuts(country = "ES", nuts_level = 2, year = year, resolution = resolution, epsg = 4326),
    error = function(e) e
  )
  if (inherits(nuts2, "error")) {
    warning("No se pudieron descargar CCAA NUTS2: ", conditionMessage(nuts2), call. = FALSE)
    nuts2 <- sf::st_sf(geometry = sf::st_sfc(crs = 4326))
  }

  message("GISCO/NUTS: descargando provincias NUTS3 España, año ", year, ", resolución ", resolution)
  nuts3 <- tryCatch(
    giscoR::gisco_get_nuts(country = "ES", nuts_level = 3, year = year, resolution = resolution, epsg = 4326),
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
      sf::st_make_valid()
    sf::st_write(nuts2, "data/processed/admin_nuts2_ccaa.geojson", delete_dsn = TRUE, quiet = TRUE)
    sf::st_write(nuts2, "assets/admin/admin_nuts2_ccaa.geojson", delete_dsn = TRUE, quiet = TRUE)
    readr::write_csv(sf::st_drop_geometry(nuts2) |> dplyr::select(admin_level, admin_id, admin_name), "data/processed/admin_nuts2_ccaa.csv")
  }

  if (nrow(nuts3) > 0) {
    nuts3 <- normalise_nuts(nuts3, "provincia") |>
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
  x
}
