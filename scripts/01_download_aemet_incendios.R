#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")
source("R/aemet.R", encoding = "UTF-8")

check_required_packages(c(
  "curl", "jsonlite", "readr", "dplyr", "purrr", "stringr", "tibble",
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

previous_manifest <- if (file.exists("data/raw/aemet/manifest.csv")) {
  tryCatch(readr::read_csv("data/raw/aemet/manifest.csv", show_col_types = FALSE), error = function(e) tibble::tibble())
} else {
  tibble::tibble()
}

areas <- strsplit(Sys.getenv("AEMET_AREAS", unset = "p,b,c"), ",")[[1]] |>
  trimws()

days <- strsplit(Sys.getenv("AEMET_FORECAST_DAYS", unset = "1,2,3,4,5,6,7"), ",")[[1]] |>
  trimws() |>
  as.integer()

products_env <- Sys.getenv("AEMET_PRODUCTS", unset = "estimado,previsto")
products <- strsplit(products_env, ",")[[1]] |> trimws()

products_tbl <- fire_endpoints(days = days, areas = areas, products = products)

manifest <- purrr::pmap_dfr(products_tbl, function(tipo, dia, area, endpoint) {
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
      manifest_row(
        tipo = tipo,
        dia = dia,
        area = area,
        endpoint = endpoint,
        status = "error",
        descripcion = conditionMessage(e)
      )
    }
  )
})

manifest <- use_previous_downloads_after_errors(manifest, previous_manifest)

readr::write_csv(manifest, "data/raw/aemet/manifest.csv")
message("Manifest guardado en data/raw/aemet/manifest.csv")

summary <- manifest |>
  dplyr::count(status) |>
  dplyr::mutate(txt = paste0(status, "=", n)) |>
  dplyr::pull(txt) |>
  paste(collapse = "; ")
message("Resumen: ", summary)
