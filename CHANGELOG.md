# Changelog

## v0.5.4 - 2026-07-08

### Cambiado

- Se retira la superposición geográfica directa de los PNG de AEMET sobre Leaflet, porque no alinean de forma fiable como `L.imageOverlay()` rectangular.
- Se añade la página `AEMET` para consultar las imágenes oficiales descargadas sin inducir error de alineación.
- El mapa principal queda reservado a capas geográficas alineadas: NASA FIRMS, alertas, EFFIS WMS y límites GISCO/NUTS.
- Se añade `scripts/12_diagnose_aemet_alignment.R` para documentar el diagnóstico.

## v0.5.3 - 2026-07-08

### Corregido

- Reescribe la descarga de límites administrativos NUTS para usar directamente GeoJSON GISCO en EPSG:4326.
- Evita el flujo anterior EPSG:3035 → EPSG:4326, que podía producir desajustes visuales en Leaflet según la combinación de GISCO/giscoR/sf.
- Añade validación de bbox para España, Canarias, Ceuta y Melilla antes de publicar los límites.
- Añade `scripts/10_diagnose_admin_boundaries.R` para revisar CRS, bbox y ejemplos de entidades.

## v0.5.2 - 2026-07-08

Ajustes de presentación y corrección de CRS para límites administrativos.

### Cambiado

- El mapa principal pasa a ocupar más altura de pantalla (`84vh`) y deja de compartir página con el resumen operativo.
- El resumen operativo se mueve a una página independiente `summary.qmd` / `summary.html`.
- La navegación añade una pestaña **Resumen**.

### Corregido

- Las geometrías NUTS se descargan en EPSG:3035 y se transforman explícitamente a EPSG:4326 antes de publicarse como GeoJSON.
- La lectura de límites administrativos fuerza EPSG:4326 antes de dibujar en Leaflet y antes de hacer cruces espaciales con FIRMS.
- Se añade una comprobación de bbox para detectar geometrías administrativas fuera de rango lon/lat.

## v0.5.1 - 2026-07-08

Corrección de robustez del histórico temporal.

### Corregido

- Normalización estricta de tipos en `dashboard_history.csv`.
- Evita errores de `bind_rows()` cuando el histórico está vacío o contiene columnas `NA` interpretadas como `logical`.
- Normalización básica de tipos en históricos administrativos por CCAA y provincia.


## v0.5.0 - 2026-07-08

Añade histórico temporal del dashboard y página de evolución operativa.

### Incluye

- Nuevo módulo `R/history.R`.
- Script `scripts/09_update_dashboard_history.R`.
- Nueva página `history.qmd` / `history.html`.
- Histórico agregado en `data/processed/dashboard_history.csv` y `assets/history/dashboard_history.csv`.
- Histórico territorial de CCAA y provincias.
- Gráficos de evolución de focos FIRMS, focos recientes, FRP total y alertas.
- Variables `HISTORY_MODE` y `HISTORY_KEEP_DAYS`.
- Workflow actualizado para publicar assets históricos.

## v0.4.0 - 2026-07-08

Añade una capa operativa de alertas automáticas basada en clústeres de detecciones NASA FIRMS recientes.

### Incluye

- Nuevo módulo `R/alerts.R`.
- Script `scripts/08_build_operational_alerts.R`.
- Agrupación espacial configurable con `ALERT_CLUSTER_KM`.
- Filtro de antigüedad configurable con `ALERT_MAX_AGE_HOURS`.
- CSV y GeoJSON de alertas operativas.
- Capa Leaflet `Alertas operativas FIRMS`.
- Tabla de alertas en el dashboard principal.
- Página `report.qmd` / `report.html` con informe operativo estático.

## v0.3.0 - 2026-07-08

### Añadido

- Descarga de límites administrativos Eurostat/GISCO NUTS2 y NUTS3 para España.
- Nuevos scripts:
  - `scripts/06_download_admin_boundaries.R`.
  - `scripts/07_build_operational_summary.R`.
- Nuevos módulos R:
  - `R/admin.R`.
  - `R/summary.R`.
- Resumen operativo con focos FIRMS totales, últimas 6 h, últimas 24 h, FRP total y territorios afectados.
- Tablas resumen:
  - `data/processed/firms_summary_ccaa.csv`.
  - `data/processed/firms_summary_provincias.csv`.
  - `data/processed/dashboard_summary.csv`.
- Capas Leaflet opcionales de CCAA y provincias.
- Recursos publicados en `assets/admin/` y `assets/summary/`.

### Cambiado

- `scripts/99_run_all.R` pasa a cinco fases: AEMET, FIRMS, límites administrativos, assets AEMET y resumen operativo.
- El dashboard añade tarjetas de resumen y tabla de provincias con detecciones recientes.
- Workflow de GitHub Actions actualizado con `sf`, `giscoR`, `knitr` y nuevos assets.

## v0.2.0 - 2026-07-08

### Añadido

- Capa NASA FIRMS de focos activos recientes mediante la API Area CSV.
- Exportación FIRMS a `data/processed/firms_active_fires.csv` y GeoJSON.
- Capa WMS EFFIS/Copernicus EMS para Fire Weather Index (`ecmwf007.fwi`).
- Variables de entorno `FIRMS_MAP_KEY`, `FIRMS_SOURCES`, `FIRMS_DAYS`, `FIRMS_BBOX`, `EFFIS_ENABLE`, `EFFIS_WMS_LAYERS` y `EFFIS_DATE`.
- Workflow de GitHub Actions actualizado para descargar AEMET + FIRMS y renderizar con EFFIS.

### Cambiado

- El dashboard pasa de “AEMET only” a visor combinado: AEMET + NASA FIRMS + EFFIS.
- `scripts/99_run_all.R` ejecuta ahora tres fases: AEMET, FIRMS y preparación web.

## v0.1.0

Primera versión funcional del visor AEMET de riesgo meteorológico de incendios forestales.
