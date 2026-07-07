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

# AEMET puede devolver 404 para algunas combinaciones según el producto disponible
# en ese momento. El script las registra como status = "missing" y sigue.
areas <- parse_csv_env("AEMET_AREAS", "p,b,c")
days <- parse_csv_env("AEMET_FORECAST_DAYS", "1,2,3,4,5,6,7") |>
  as.integer()
products_requested <- parse_csv_env("AEMET_PRODUCTS", "previsto,estimado")

products <- fire_endpoints(
  days = days,
  areas = areas,
  products = products_requested
)

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
      message("  - error: ", conditionMessage(e))
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
        http_status = NA_integer_,
        status = "error",
        file = NA_character_,
        file_type = NA_character_
      )
    }
  )
})

readr::write_csv(manifest, "data/raw/aemet/manifest.csv")

summary <- manifest |>
  dplyr::count(status, name = "n") |>
  dplyr::mutate(txt = paste0(status, "=", n)) |>
  dplyr::pull(txt) |>
  paste(collapse = "; ")

message("Manifest guardado en data/raw/aemet/manifest.csv")
message("Resumen: ", summary)
