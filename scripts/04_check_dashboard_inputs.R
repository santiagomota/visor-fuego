#!/usr/bin/env Rscript

paths <- c(
  "data/raw/aemet/manifest.csv",
  "data/processed/layers.csv",
  "data/processed/layers.json",
  "assets/aemet/layers.json",
  "data/processed/firms_active_fires.csv",
  "data/processed/firms_active_fires.geojson",
  "assets/firms/firms_active_fires.geojson"
)

cat("\nComprobación de entradas del dashboard\n")
cat("Directorio de trabajo:", getwd(), "\n\n")

for (p in paths) {
  exists <- file.exists(p)
  size <- if (exists) file.info(p)$size else NA_real_
  cat(sprintf("%-48s exists=%-5s size=%s\n", p, exists, ifelse(is.na(size), "NA", format(size, big.mark = ","))))
}

if (file.exists("data/processed/layers.csv")) {
  suppressPackageStartupMessages(library(readr))
  suppressPackageStartupMessages(library(dplyr))
  layers <- readr::read_csv("data/processed/layers.csv", show_col_types = FALSE)
  cat("\nCapas AEMET en data/processed/layers.csv:", nrow(layers), "\n")
  if (nrow(layers) > 0) {
    print(layers |> count(area_label, tipo, dia, layer_kind), n = Inf)
    missing_assets <- layers$url[!file.exists(layers$url)]
    if (length(missing_assets) > 0) {
      cat("\nAssets AEMET referenciados que no existen en el árbol fuente:\n")
      print(missing_assets)
    } else {
      cat("\nTodos los assets AEMET referenciados existen en el árbol fuente.\n")
    }
  }
}

if (file.exists("data/processed/firms_active_fires.csv")) {
  suppressPackageStartupMessages(library(readr))
  firms <- readr::read_csv("data/processed/firms_active_fires.csv", show_col_types = FALSE)
  cat("\nFocos NASA FIRMS:", nrow(firms), "\n")
  if (nrow(firms) > 0 && "source_dataset" %in% names(firms)) {
    print(table(firms$source_dataset, useNA = "ifany"))
  }
}

if (dir.exists("_freeze")) {
  cat("\nAviso: existe _freeze/. Si ves HTML antiguo, ejecuta: quarto render --execute\n")
}
