#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")
source("R/prepare_layers.R", encoding = "UTF-8")

check_required_packages(c(
  "jsonlite", "readr", "dplyr", "purrr", "stringr", "tibble",
  "fs", "terra", "png"
))

layers <- prepare_layers_for_web("data/raw/aemet/manifest.csv")

if (nrow(layers) == 0) {
  message("No se generaron capas web. El dashboard se renderizará con mapa base y aviso.")
} else {
  message("Capas web preparadas: ", nrow(layers))
}
