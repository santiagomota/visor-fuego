source("R/aemet_discovery.R", encoding = "UTF-8")

ctx_path <- "data/raw/aemet_web_probe/aemet_web_term_contexts.csv"
if (!file.exists(ctx_path)) {
  message("No existe ", ctx_path, ". Ejecutando scripts/14_probe_aemet_web_sources.R primero...")
  probe_aemet_web_sources()
}

ctx <- readr::read_csv(ctx_path, show_col_types = FALSE)

interesting <- ctx |>
  dplyr::filter(grepl("tif|geotiff|incend|ipif|mapasriesgo|descarga|download|coverage|raster|wms|wmts", term, ignore.case = TRUE)) |>
  dplyr::arrange(source_id, position)

out_path <- "data/raw/aemet_web_probe/aemet_interesting_contexts.csv"
readr::write_csv(interesting, out_path)

message("Contextos interesantes guardados en: ", out_path)
print(
  interesting |>
    dplyr::select(source_id, term, context) |>
    utils::head(80),
  n = 80,
  width = 160
)
