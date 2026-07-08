# Changelog

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
