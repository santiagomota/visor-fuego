#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")
check_required_packages(c("readr", "dplyr", "fs", "jsonlite", "tibble"))

manifest_file <- "data/raw/aemet/manifest.csv"
layers_file <- "data/processed/layers.csv"

if (!file.exists(manifest_file)) {
  stop("No existe ", manifest_file, ". Ejecuta Rscript scripts/01_download_aemet_incendios.R", call. = FALSE)
}

manifest <- readr::read_csv(manifest_file, show_col_types = FALSE) |>
  normalise_manifest_types()

if (!"valid_date" %in% names(manifest)) {
  message("El manifest no tiene columna valid_date. Regenera con v0.6.3:")
  message("  Rscript scripts/01_download_aemet_incendios.R")
  message("  Rscript scripts/02_prepare_web_assets.R")
} else {
  message("Manifest AEMET: fechas de fichero, fecha válida y horizonte visible")
  message("
Nota v0.6.3: en la fuente clásica, down_YYYYMMDD_..._D00 se interpreta como Día 1, válido para YYYYMMDD. D01 es Día 2 y válido para YYYYMMDD + 1.")
  message("El valor recomendado de AEMET_CLASSIC_VALID_START_OFFSET_DAYS es 0.")
  manifest |>
    dplyr::filter(status == "downloaded", file_type == "raster") |>
    dplyr::mutate(
      issue_date = dplyr::coalesce(issue_date, date),
      valid_date = dplyr::coalesce(valid_date, date),
      forecast_day = dplyr::coalesce(forecast_day, dia)
    ) |>
    dplyr::count(area_label, issue_date, valid_date, forecast_day, name = "n") |>
    dplyr::arrange(area_label, valid_date, forecast_day) |>
    print(n = Inf)
}

if (file.exists(layers_file)) {
  layers <- readr::read_csv(layers_file, show_col_types = FALSE)
  message("\nPrimeras capas del catálogo Leaflet:")
  cols <- intersect(c("area_label", "valid_date", "date", "issue_date", "forecast_day", "dia", "url"), names(layers))
  layers |>
    dplyr::select(dplyr::all_of(cols)) |>
    head(10) |>
    print(n = Inf)
} else {
  message("\nNo existe ", layers_file, ". Ejecuta Rscript scripts/02_prepare_web_assets.R")
}


message("
Diagnóstico de posibles capas antiguas:")
if (file.exists(layers_file)) {
  layers <- readr::read_csv(layers_file, show_col_types = FALSE)
  if (all(c("area_label", "valid_date", "issue_date", "forecast_day", "source_file") %in% names(layers))) {
    layers |>
      dplyr::mutate(
        valid_date = as.character(valid_date),
        issue_date = as.character(issue_date)
      ) |>
      dplyr::count(area_label, issue_date, valid_date, forecast_day, name = "n") |>
      dplyr::arrange(area_label, valid_date, forecast_day) |>
      print(n = Inf)
  }

  if ("source_file" %in% names(layers)) {
    missing_sources <- layers |>
      dplyr::filter(!file.exists(source_file))
    if (nrow(missing_sources) > 0) {
      message("AVISO: hay capas con source_file inexistente: ", nrow(missing_sources))
      print(missing_sources |> dplyr::select(dplyr::any_of(c("valid_date", "area_label", "forecast_day", "source_file"))), n = Inf)
    }
  }
}
