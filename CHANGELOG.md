# Changelog

## v0.5.29

- EFFIS: deja de recomendar `ecmwf.fwi.danger_index` para el overlay estático porque puede generar rasters opacos pero visualmente vacíos.
- EFFIS: prioriza capas FWI renderizables como `ecmwf.fwi.fwi`, `ecmwf007.fwi` y `mf010.fwi`.
- EFFIS: la validación de descargas y PNGs ahora comprueba variación visual RGB/valor, no solo píxeles no transparentes.
- EFFIS: rechaza imágenes uniformes/vacías antes de publicarlas en `assets/effis`.

# Cambios

## v0.5.28

- Corrige los TIFFs WMS de EFFIS con canales RGB válidos pero banda alfa vacía.
- Si el alfa del TIFF es completamente 0, reconstruye la transparencia desde la máscara de datos válidos.
- Evita rechazar PNGs finales de EFFIS cuando el índice/categoría del raster es 0 pero contiene datos.

## v0.5.27

- Corrige la escritura de PNGs EFFIS conservando dimensiones de matrices/arrays tras el recorte de valores a `[0,1]`.
- Evita el error `image must be a matrix or an array of two or three dimensions` al convertir TIFFs WMS a PNG.


## v0.5.26

- Añade conversión EFFIS TIFF→PNG mediante GDAL (`sf::gdal_utils` o `gdal_translate`) antes del fallback manual con `terra`.
- Soluciona el caso en el que EFFIS devuelve `image/tiff` con píxeles válidos, pero `png::writePNG()` falla al reconstruir el PNG final.
- Normaliza y limita explícitamente los arrays RGBA antes de escribir PNG.
- Mantiene `image/png` como primera opción y `image/tiff` como alternativa operativa.

## v0.5.25

- Prioriza `image/png` para EFFIS estático y usa el PNG WMS directamente cuando ya contiene píxeles visibles.
- Mantiene `image/tiff` como alternativa, pero evita que un fallo de conversión TIFF bloquee la publicación.
- Registra errores de conversión en `data/raw/effis/effis_conversion_errors.csv`.
- Añade `wms_bbox` y `file_type` al catálogo final EFFIS para depuración.
- Recomienda `https://ies-ows.jrc.ec.europa.eu/effis` y `ecmwf.fwi.danger_index` como capa operativa.

## v0.5.24

- Corrige la construcción de URLs WMS de EFFIS para mantener BBOX con comas sin re-codificación.
- Alinea la petición GetMap con el ejemplo oficial de EFFIS (`SERVICE=wms`, BBOX decimal y URL manual).
- Detecta respuestas XML OGC como `xml` y extrae el mensaje de `ServiceException`.
- Añade `wms_bbox` en el diagnóstico para distinguir el BBOX configurado del BBOX realmente enviado.

# Changelog

## v0.5.22

- Refuerza el diagnóstico EFFIS: lee fechas disponibles desde GetCapabilities/TIME.
- Prueba automáticamente los endpoints actual e histórico de EFFIS.
- Prueba WMS 1.1.1 y 1.3.0, corrigiendo el orden BBOX de EPSG:4326 en WMS 1.3.0.
- Añade matrices de prueba para formatos PNG/TIFF, BBOX oficial EFFIS y BBOX del visor.
- El modo estático selecciona el primer GetMap con píxeles visibles y genera el overlay local desde esa respuesta.

## v0.5.21

- Cambia EFFIS a modo estático por defecto: descarga GetMap como `image/tiff`, convierte a PNG y lo publica en `assets/effis/`.
- Añade `scripts/26_prepare_effis_assets.R` al pipeline.
- Mejora `scripts/25_check_effis_wms.R` para probar `image/png` e `image/tiff`, registrar cabeceras, primeros bytes y píxeles válidos.
- Añade panel Leaflet específico para activar/desactivar EFFIS FWI y controlar su opacidad.
- Añade `assets/effis/**` a los recursos Quarto.

## v0.5.20 - EFFIS WMS robusto

- Corrige `scripts/25_check_effis_wms.R` para no usar `httr2::url_build(query=...)`, incompatible con algunas versiones de `httr2`.
- Corrige la integración EFFIS/Copernicus WMS en Leaflet.
- Envía parámetros WMS en mayúsculas, incluido `TIME`, tal como requiere el servicio.
- Usa `EPSG:4326` para las peticiones WMS de EFFIS, coherente con el ejemplo oficial.
- Crea un pane propio `effisPane` para que EFFIS quede visible por encima de AEMET cuando se active.
- Deja EFFIS desactivado por defecto en el control de capas para evitar que quede oculto bajo AEMET.
- Añade fechas fallback (`EFFIS_FALLBACK_DAYS`) y diagnóstico `scripts/25_check_effis_wms.R`.

## v0.5.18

- Corrige la convención temporal de los GeoTIFFs clásicos de AEMET: `D00` se interpreta como primer día previsto y, por defecto, válido para `YYYYMMDD + 1`.
- Añade la variable `AEMET_CLASSIC_VALID_START_OFFSET_DAYS=1` para ajustar la convención si AEMET cambiase el paquete.
- Cambia las etiquetas de horizonte a `Día 1`, `Día 2`, etc., en lugar de `D+0`, `D+1`.

## v0.5.17

- Corrige la interpretación temporal de los GeoTIFFs clásicos de AEMET: `down_YYYYMMDD_..._Dxx.tif` usa `YYYYMMDD` como fecha de emisión y `Dxx` como horizonte.
- El catálogo Leaflet usa ahora `valid_date = issue_date + D`, por lo que `D01` de un paquete emitido el 2026-07-07 se muestra como válido para 2026-07-08.
- El nombre de los GeoTIFFs instalados en `data/raw/aemet/` usa la fecha válida, no la fecha de emisión.
- El selector Leaflet mantiene primero Península/Baleares, pero dentro de cada zona prioriza la capa válida para la fecha de renderizado.
- Añade `scripts/24_check_aemet_valid_dates.R` para auditar `issue_date`, `valid_date` y las primeras capas del catálogo.

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

## v0.5.24

- EFFIS: cambia la configuración recomendada a `EFFIS_WMS_LAYERS=auto`.
- EFFIS: extrae nombres reales de capa desde `GetCapabilities` y evita seguir probando `ecmwf007.fwi` si el servidor lo devuelve como capa inválida.
- EFFIS: el diagnóstico `25_check_effis_wms.R` guarda `data/raw/effis/effis_available_layers.csv` y muestra las capas candidatas FWI/fire danger.
