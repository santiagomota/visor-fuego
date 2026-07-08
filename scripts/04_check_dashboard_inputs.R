#!/usr/bin/env Rscript

paths <- c(
  "data/raw/aemet/manifest.csv",
  "data/processed/layers.csv",
  "data/processed/layers.json",
  "assets/aemet/layers.json",
  "data/processed/firms_active_fires.csv",
  "data/processed/firms_active_fires.geojson",
  "assets/firms/firms_active_fires.geojson",
  "data/processed/admin_nuts2_ccaa.geojson",
  "data/processed/admin_nuts3_provincias.geojson",
  "assets/admin/admin_nuts2_ccaa.geojson",
  "assets/admin/admin_nuts3_provincias.geojson",
  "data/processed/firms_summary_ccaa.csv",
  "data/processed/firms_summary_provincias.csv",
  "data/processed/dashboard_summary.csv",
  "assets/summary/dashboard_summary.json",
  "data/processed/operational_alerts.csv",
  "data/processed/operational_alerts.geojson",
  "assets/alerts/operational_alerts.geojson",
  "data/processed/operational_report.md",
  "assets/alerts/operational_report.md"
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


if (file.exists("data/processed/dashboard_summary.csv")) {
  suppressPackageStartupMessages(library(readr))
  overview <- readr::read_csv("data/processed/dashboard_summary.csv", show_col_types = FALSE)
  cat("\nResumen operativo:\n")
  print(overview)
}

if (file.exists("data/processed/firms_summary_provincias.csv")) {
  suppressPackageStartupMessages(library(readr))
  prov <- readr::read_csv("data/processed/firms_summary_provincias.csv", show_col_types = FALSE)
  cat("\nProvincias con focos FIRMS:", nrow(prov), "\n")
  if (nrow(prov) > 0) {
    print(head(prov[, intersect(c("admin_name", "n_focos", "n_ultimas_6h", "n_ultimas_24h", "frp_total_mw", "alerta_operativa"), names(prov))], 10))
  }
}


if (file.exists("data/processed/operational_alerts.csv")) {
  suppressPackageStartupMessages(library(readr))
  alerts <- readr::read_csv("data/processed/operational_alerts.csv", show_col_types = FALSE)
  cat("\nAlertas operativas:", nrow(alerts), "\n")
  if (nrow(alerts) > 0) {
    cols <- intersect(c("cluster_id", "alerta_operativa", "score", "n_focos", "n_ultimas_6h", "n_ultimas_24h", "frp_total_mw", "ultima_deteccion_utc"), names(alerts))
    print(head(alerts[, cols], 10))
  }
}

if (file.exists("data/processed/dashboard_history.csv")) {
  suppressPackageStartupMessages(library(readr))
  hist <- readr::read_csv("data/processed/dashboard_history.csv", show_col_types = FALSE)
  cat("\nHistórico del dashboard:", nrow(hist), "registros\n")
  if (nrow(hist) > 0) {
    cols <- intersect(c("snapshot_date", "n_firms", "n_firms_24h", "frp_total_mw", "n_alertas", "n_alertas_altas", "top_provincia"), names(hist))
    print(tail(hist[, cols], 10))
  }
} else {
  cat("\nHistórico del dashboard: no existe data/processed/dashboard_history.csv\n")
}

if (file.exists("data/processed/admin_nuts2_ccaa.geojson") && requireNamespace("sf", quietly = TRUE)) {
  x <- tryCatch(sf::st_read("data/processed/admin_nuts2_ccaa.geojson", quiet = TRUE), error = function(e) NULL)
  if (!is.null(x) && nrow(x) > 0) {
    bb <- sf::st_bbox(sf::st_transform(x, 4326))
    cat("\nBBOX NUTS2 EPSG:4326:", paste(round(as.numeric(bb), 4), collapse = ", "), "\n")
  }
}

cat("\nPáginas Quarto esperadas: index.qmd, summary.qmd, report.qmd, history.qmd\n")
