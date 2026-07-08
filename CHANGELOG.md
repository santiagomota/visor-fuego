# Changelog

## v0.5.16

- Ordena las capas AEMET del selector Leaflet para mostrar primero Península y Baleares, después Baleares si existe como producto independiente, y finalmente Canarias.
- Refuerza el mismo orden tanto al preparar `layers.csv`/`layers.json` como al leer catálogos existentes desde `index.qmd`.

## v0.5.15 - 2026-07-08

### Fixed

- Ajusta la generación del overlay AEMET para Leaflet: por defecto reproyecta los GeoTIFFs a EPSG:3857/Web Mercator antes de exportarlos a PNG.
- Calcula los `LatLngBounds` de Leaflet a partir de la extensión Web Mercator transformada de vuelta a EPSG:4326.
- Añade `AEMET_LEAFLET_PROJECTION`, `AEMET_BOUNDS_NUDGE_LON` y `AEMET_BOUNDS_NUDGE_LAT` para controlar el ajuste del overlay.
- Añade `scripts/23_diagnose_aemet_alignment.R` para auditar CRS, bounds y dimensiones de los PNG generados.


## v0.5.14 - 2026-07-08

### Fixed

- Integra la descarga SIG clásica de AEMET (`/es/api-eltiempo/incendios/download`) como proveedor principal.
- Extrae el paquete `.tar.gz` de AEMET y publica los GeoTIFFs `down_YYYYMMDD_peligro_[p|c]_D00..D07.tif`.
- Evita usar PNG de AEMET como `imageOverlay` salvo que `AEMET_ALLOW_PNG_OVERLAY=true`.
- Añade `scripts/22_install_classic_probe_geotiffs.R` para instalar GeoTIFFs desde el diagnóstico clásico ya ejecutado.

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
