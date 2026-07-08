# Changelog

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
