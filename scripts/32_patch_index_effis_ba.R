#!/usr/bin/env Rscript
# Añade una capa opcional de EFFIS Burnt Areas al mapa Leaflet sin tocar bloques R internos.

file <- "index.qmd"
if (!file.exists(file)) stop("No existe index.qmd", call. = FALSE)

x <- readLines(file, warn = FALSE, encoding = "UTF-8")
if (any(grepl("BEGIN EFFIS_BA_LAYER", x, fixed = TRUE))) {
  message("El bloque EFFIS Burnt Areas ya existe en index.qmd")
  quit(status = 0)
}

block <- c(
  "",
  "<!-- BEGIN EFFIS_BA_LAYER -->",
  "```{=html}",
  "<script>",
  "(function() {",
  "  const url = 'assets/effis_ba/effis_burnt_areas.geojson';",
  "  function findLeafletMap() {",
  "    if (window.HTMLWidgets && HTMLWidgets.find) {",
  "      const widgets = HTMLWidgets.find('.leaflet');",
  "      for (const w of widgets) {",
  "        if (w && typeof w.getMap === 'function') return w.getMap();",
  "        if (w && w.instance && w.instance instanceof L.Map) return w.instance;",
  "        if (w && w.map && w.map instanceof L.Map) return w.map;",
  "      }",
  "    }",
  "    for (const k in window) {",
  "      try { if (window[k] instanceof L.Map) return window[k]; } catch(e) {}",
  "    }",
  "    return null;",
  "  }",
  "  function addEffisBurntAreas(map) {",
  "    if (!map || !window.L || map.__effisBurntAreasAdded) return;",
  "    map.__effisBurntAreasAdded = true;",
  "    if (!map.getPane('effisBaPane')) {",
  "      map.createPane('effisBaPane');",
  "      map.getPane('effisBaPane').style.zIndex = 430;",
  "    }",
  "    fetch(url, { cache: 'no-store' })",
  "      .then(r => r.ok ? r.json() : null)",
  "      .then(gj => {",
  "        if (!gj || !gj.features || gj.features.length === 0) return;",
  "        const layer = L.geoJSON(gj, {",
  "          pane: 'effisBaPane',",
  "          style: function() {",
  "            return { color: '#7f2704', weight: 1.2, opacity: 0.85, fillColor: '#d94801', fillOpacity: 0.22 };",
  "          },",
  "          onEachFeature: function(feature, lyr) {",
  "            const p = feature.properties || {};",
  "            const label = p.effis_label || p.effis_id || 'Área quemada EFFIS';",
  "            const date = p.effis_date || '';",
  "            const area = p.effis_area_ha ? Number(p.effis_area_ha).toLocaleString('es-ES', {maximumFractionDigits: 1}) + ' ha' : '';",
  "            lyr.bindPopup('<strong>Copernicus/EFFIS</strong><br>' + label + '<br>' + date + '<br>' + area);",
  "          }",
  "        });",
  "        L.control.layers(null, { 'Copernicus/EFFIS · áreas quemadas': layer }, { collapsed: true }).addTo(map);",
  "      })",
  "      .catch(() => {});",
  "  }",
  "  function waitForMap(tries) {",
  "    const map = findLeafletMap();",
  "    if (map) addEffisBurntAreas(map);",
  "    else if (tries > 0) setTimeout(() => waitForMap(tries - 1), 400);",
  "  }",
  "  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => waitForMap(20));",
  "  else waitForMap(20);",
  "})();",
  "</script>",
  "```",
  "<!-- END EFFIS_BA_LAYER -->"
)

writeLines(c(x, block), file, useBytes = TRUE)
message("Añadido bloque EFFIS Burnt Areas a index.qmd")
