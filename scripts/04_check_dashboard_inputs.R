#!/usr/bin/env Rscript

paths <- c(
  "data/raw/aemet/manifest.csv",
  "data/processed/layers.csv",
  "data/processed/layers.json",
  "assets/aemet/layers.json",
  "docs/assets/aemet/layers.json"
)

cat("\nComprobación de entradas del dashboard\n")
cat("Directorio de trabajo:", getwd(), "\n\n")

for (p in paths) {
  exists <- file.exists(p)
  size <- if (exists) file.info(p)$size else NA_real_
  cat(sprintf("%-34s exists=%-5s size=%s\n", p, exists, ifelse(is.na(size), "NA", format(size, big.mark = ","))))
}

if (file.exists("data/processed/layers.csv")) {
  suppressPackageStartupMessages(library(readr))
  suppressPackageStartupMessages(library(dplyr))
  layers <- readr::read_csv("data/processed/layers.csv", show_col_types = FALSE)
  cat("\nCapas en data/processed/layers.csv:", nrow(layers), "\n")
  if (nrow(layers) > 0) {
    print(layers |> count(area_label, tipo, dia, layer_kind), n = Inf)
    missing_assets <- layers$url[!file.exists(layers$url)]
    if (length(missing_assets) > 0) {
      cat("\nAssets referenciados que no existen en el árbol fuente:\n")
      print(missing_assets)
    } else {
      cat("\nTodos los assets referenciados existen en el árbol fuente.\n")
    }
  }
}

if (dir.exists("_freeze")) {
  cat("\nAviso: existe _freeze/. Si ves HTML antiguo, ejecuta: quarto render --execute\n")
}
