#!/usr/bin/env Rscript

# Patch index.qmd to load Copernicus/EFFIS Burnt Areas GeoJSON on the existing Leaflet map.
# It is intentionally independent from the exact FIRMS/AEMET code layout.

index_file <- "index.qmd"
if (!file.exists(index_file)) {
  stop("No se encontró index.qmd en el directorio actual.", call. = FALSE)
}

x <- readLines(index_file, warn = FALSE, encoding = "UTF-8")
text <- paste(x, collapse = "\n")

marker <- "EFFIS Burnt Areas GeoJSON loader"
if (grepl(marker, text, fixed = TRUE)) {
  message("index.qmd ya contiene el cargador EFFIS Burnt Areas; no se modifica.")
  quit(status = 0)
}

# Allow explicit override if the map object is not called `m`.
map_var <- Sys.getenv("LEAFLET_MAP_OBJECT", unset = "")

if (!nzchar(map_var)) {
  # Detect a variable assigned from leaflet(...), leaflet::leaflet(...)
  assign_pat <- "^\\s*([A-Za-z.][A-Za-z0-9_.]*)\\s*<-\\s*(leaflet::)?leaflet\\s*\\("
  hits <- grep(assign_pat, x, perl = TRUE)
  if (length(hits) > 0) {
    map_var <- sub(assign_pat, "\\1", x[hits[1]], perl = TRUE)
  }
}

if (!nzchar(map_var)) {
  # Fallback to common names if they are printed as final widget.
  common <- c("m", "map", "mapa", "leaflet_map", "visor_map")
  for (cand in common) {
    if (any(grepl(paste0("^\\s*", cand, "\\s*$"), x, perl = TRUE))) {
      map_var <- cand
      break
    }
  }
}

if (!nzchar(map_var)) {
  stop(paste(
    "No se pudo detectar el objeto Leaflet en index.qmd.",
    "Puedes reintentar indicando el nombre del objeto, por ejemplo:",
    "LEAFLET_MAP_OBJECT=m Rscript scripts/34_patch_index_effis_ba_onrender.R",
    sep = "\n"
  ), call. = FALSE)
}

# Find the last standalone print of the map object; insert immediately before it.
print_pat <- paste0("^\\s*", gsub("\\.", "\\\\.", map_var), "\\s*$")
print_hits <- grep(print_pat, x, perl = TRUE)

if (length(print_hits) == 0) {
  stop(paste0(
    "Se detectó el objeto Leaflet '", map_var, "', pero no se encontró una línea final que lo imprima.\n",
    "Añade manualmente el bloque generado antes de la salida del mapa o ejecuta con LEAFLET_MAP_OBJECT=<nombre>."
  ), call. = FALSE)
}

insert_at <- tail(print_hits, 1)

js <- paste0(
  "function(el, x) {\n",
  "  // EFFIS Burnt Areas GeoJSON loader\n",
  "  var map = this;\n",
  "  if (!map || typeof L === 'undefined') return;\n",
  "  var url = 'assets/effis_ba/effis_burnt_areas.geojson';\n",
  "  if (map.__effisBaLoaderInstalled) return;\n",
  "  map.__effisBaLoaderInstalled = true;\n",
  "  if (!map.getPane('effisBaPane')) {\n",
  "    map.createPane('effisBaPane');\n",
  "    map.getPane('effisBaPane').style.zIndex = 420;\n",
  "  }\n",
  "  function popupHtml(props) {\n",
  "    props = props || {};\n",
  "    var keys = ['firedate','FIREDATE','date','Date','area_ha','AREA_HA','area','AREA','country','COUNTRY','name','Name'];\n",
  "    var rows = [];\n",
  "    keys.forEach(function(k) {\n",
  "      if (props[k] !== undefined && props[k] !== null && String(props[k]).length > 0) {\n",
  "        rows.push('<tr><th style=\\\"text-align:left;padding-right:6px\\\">' + k + '</th><td>' + props[k] + '</td></tr>');\n",
  "      }\n",
  "    });\n",
  "    return rows.length ? '<b>EFFIS Burnt Areas</b><table>' + rows.join('') + '</table>' : '<b>EFFIS Burnt Areas</b>';\n",
  "  }\n",
  "  fetch(url, {cache: 'no-store'})\n",
  "    .then(function(response) {\n",
  "      if (!response.ok) throw new Error('No se pudo cargar ' + url + ': HTTP ' + response.status);\n",
  "      return response.json();\n",
  "    })\n",
  "    .then(function(data) {\n",
  "      if (!data || !data.features || data.features.length === 0) {\n",
  "        console.warn('EFFIS Burnt Areas: GeoJSON vacío o sin features');\n",
  "        return;\n",
  "      }\n",
  "      var layer = L.geoJSON(data, {\n",
  "        pane: 'effisBaPane',\n",
  "        style: function(feature) {\n",
  "          return {color: '#7c2d12', weight: 1, opacity: 0.85, fillColor: '#fb923c', fillOpacity: 0.25};\n",
  "        },\n",
  "        onEachFeature: function(feature, lyr) {\n",
  "          lyr.bindPopup(popupHtml(feature.properties));\n",
  "        }\n",
  "      });\n",
  "      layer.addTo(map);\n",
  "      L.control.layers(null, {'EFFIS Burnt Areas': layer}, {collapsed: true, position: 'topright'}).addTo(map);\n",
  "      console.log('EFFIS Burnt Areas cargadas:', data.features.length);\n",
  "    })\n",
  "    .catch(function(err) {\n",
  "      console.warn('EFFIS Burnt Areas no disponible:', err);\n",
  "    });\n",
  "}"
)

snippet <- c(
  "",
  "# EFFIS Burnt Areas GeoJSON loader ------------------------------------------------",
  "if (file.exists(\"assets/effis_ba/effis_burnt_areas.geojson\")) {",
  paste0("  ", map_var, " <- htmlwidgets::onRender("),
  paste0("    ", map_var, ","),
  "    ",
  paste0("    ", deparse(js, width.cutoff = 500), collapse = "\n"),
  "  )",
  "}",
  ""
)

# The deparse() result may be multi-line; flatten carefully.
snippet <- unlist(strsplit(snippet, "\n", fixed = TRUE), use.names = FALSE)

x2 <- append(x, snippet, after = insert_at - 1)
writeLines(x2, index_file, useBytes = TRUE)

message("index.qmd actualizado: se insertó EFFIS Burnt Areas antes de imprimir el objeto Leaflet '", map_var, "'.")
message("Comprueba con: grep -n \"EFFIS Burnt Areas GeoJSON loader\\|effis_ba\\|effisBaPane\" index.qmd")
