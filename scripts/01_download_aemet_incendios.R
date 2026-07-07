#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")
source("R/aemet.R", encoding = "UTF-8")

check_required_packages(c(
  "httr2", "jsonlite", "readr", "dplyr", "purrr", "stringr", "tibble",
  "fs", "glue", "tidyr"
))

api_key <- Sys.getenv("AEMET_API_KEY")
if (!nzchar(api_key)) {
  stop(
    "Falta AEMET_API_KEY. Define la variable de entorno o crea un .Renviron local.\n",
    "Ejemplo: AEMET_API_KEY=tu_clave",
    call. = FALSE
  )
}

fs::dir_create("data/raw/aemet")

areas <- strsplit(Sys.getenv("AEMET_AREAS", unset = "p,b,c"), ",")[[1]] |>
  trimws()

days <- strsplit(Sys.getenv("AEMET_FORECAST_DAYS", unset = "1,2,3,4,5,6,7"), ",")[[1]] |>
  trimws() |>
  as.integer()

products <- fire_endpoints(days = days, areas = areas)

manifest <- purrr::pmap_dfr(products, function(tipo, dia, area, endpoint) {
  tryCatch(
    download_one_fire_product(
      tipo = tipo,
      dia = dia,
      area = area,
      endpoint = endpoint,
      api_key = api_key
    ),
    error = function(e) {
      warning("Fallo en ", endpoint, ": ", conditionMessage(e))
      tibble::tibble(
        downloaded_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
        date = as.character(Sys.Date()),
        tipo = tipo,
        dia = dia,
        area = area,
        area_label = area_label(area),
        endpoint = endpoint,
        datos_url = NA_character_,
        metadatos_url = NA_character_,
        descripcion = conditionMessage(e),
        estado = NA_integer_,
        file = NA_character_,
        file_type = NA_character_
      )
    }
  )
})

readr::write_csv(manifest, "data/raw/aemet/manifest.csv")
message("Manifest guardado en data/raw/aemet/manifest.csv")
