source("R/utils.R", encoding = "UTF-8")

message("Diagnóstico de alineación AEMET")
message("--------------------------------")

layers_path <- "data/processed/layers.csv"
if (!file.exists(layers_path)) {
  stop("No existe ", layers_path, ". Ejecuta primero scripts/02_prepare_web_assets.R")
}

layers <- readr::read_csv(layers_path, show_col_types = FALSE)
if (nrow(layers) == 0) {
  stop("layers.csv está vacío")
}

print(layers |>
  dplyr::select(dplyr::any_of(c("layer_id", "date", "area_label", "tipo", "dia", "file_type", "source_file", "url", "bounds_json"))))

png_layers <- layers |>
  dplyr::filter(file_type == "image" | grepl("\\.png$", url, ignore.case = TRUE))

if (nrow(png_layers) == 0) {
  message("No hay capas PNG de AEMET.")
  quit(save = "no", status = 0)
}

message("\nConclusión:")
message("- Los productos AEMET descargados por OpenData son PNG.")
message("- Leaflet L.imageOverlay() solo coloca una imagen rectangular sobre unos bounds lat/lon.")
message("- Si el PNG oficial no encaja con mapa base/NUTS, no debe mostrarse como capa geográfica sin un geotransform/world file fiable o una calibración explícita.")
message("- En esta versión, las imágenes AEMET se muestran en aemet.html y el mapa principal conserva solo capas geográficas alineadas: FIRMS, EFFIS y NUTS.")
