#!/usr/bin/env Rscript

path <- "index.qmd"
if (!file.exists(path)) stop("No existe index.qmd en el directorio actual", call. = FALSE)

x <- readLines(path, warn = FALSE, encoding = "UTF-8")
txt <- paste(x, collapse = "\n")

original <- txt

# 1) Crear un pane específico para AEMET en el JS de onRender.
#    No tocamos FIRMS: al dejar FIRMS en el pane por defecto de Leaflet,
#    y AEMET en un pane inferior, los puntos quedan visibles por encima.
pane_code <- paste0(
  "const map = this;\n",
  "  if (map.createPane && !map.getPane('aemetPane')) {\n",
  "    map.createPane('aemetPane');\n",
  "    map.getPane('aemetPane').style.zIndex = 350;\n",
  "    map.getPane('aemetPane').style.pointerEvents = 'none';\n",
  "  }"
)

if (!grepl("aemetPane", txt, fixed = TRUE)) {
  txt2 <- sub("const map = this;", pane_code, txt, fixed = TRUE)
  if (identical(txt2, txt)) {
    stop("No se encontró 'const map = this;' para crear el pane AEMET", call. = FALSE)
  }
  txt <- txt2
}

# 2) Poner raster AEMET en el pane inferior.
# Formato habitual en index.qmd:
# L.imageOverlay(layer.url, layer.bounds, { opacity: currentOpacity, interactive: false })
txt <- gsub(
  "L\\.imageOverlay\\(layer\\.url, layer\\.bounds, \\{\\s*opacity: currentOpacity,\\s*interactive: false\\s*\\}\\)",
  "L.imageOverlay(layer.url, layer.bounds, { opacity: currentOpacity, interactive: false, pane: 'aemetPane' })",
  txt,
  perl = TRUE
)

# 3) Si AEMET se publica alguna vez como GeoJSON, también en el pane inferior.
# Sustituye solo la primera opción del bloque L.geoJSON(data, { ... }).
txt <- gsub(
  "L\\.geoJSON\\(data, \\{\\s*style:",
  "L.geoJSON(data, { pane: 'aemetPane', style:",
  txt,
  perl = TRUE
)

# 4) Evitar duplicados si el script se ejecuta varias veces.
txt <- gsub("pane: 'aemetPane', pane: 'aemetPane',", "pane: 'aemetPane',", txt, fixed = TRUE)
txt <- gsub("interactive: false, pane: 'aemetPane', pane: 'aemetPane'", "interactive: false, pane: 'aemetPane'", txt, fixed = TRUE)

if (identical(txt, original)) {
  message("No se aplicaron cambios: index.qmd ya parecía parcheado o no contiene los patrones esperados.")
} else {
  writeLines(strsplit(txt, "\n", fixed = TRUE)[[1]], path, useBytes = TRUE)
  message("index.qmd actualizado: AEMET se renderiza en aemetPane zIndex=350.")
}

# Comprobación mínima
patched <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
checks <- c("aemetPane", "pane: 'aemetPane'", "L.imageOverlay")
missing <- checks[!vapply(checks, grepl, logical(1), x = patched, fixed = TRUE)]
if (length(missing) > 0) {
  stop("Parche incompleto. Faltan patrones: ", paste(missing, collapse = ", "), call. = FALSE)
}

message("Comprobación OK. Ejecuta: quarto render --execute")
