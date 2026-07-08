# visor-fuego

> v0.5.16: el selector de capas AEMET muestra primero Península y Baleares y después Canarias.

## Ajuste fino AEMET/Leaflet desde v0.5.15

Desde `v0.5.15`, los GeoTIFFs de AEMET se convierten por defecto a PNG en **EPSG:3857/Web Mercator** antes de publicarse como `L.imageOverlay()`. Esto reduce la discrepancia visual frente al mapa base de Leaflet, porque Leaflet renderiza internamente en Web Mercator.

Configuración recomendada:

```text
AEMET_PROVIDER=classic
AEMET_ALLOW_PNG_OVERLAY=false
AEMET_LEAFLET_PROJECTION=3857
AEMET_BOUNDS_NUDGE_LON=0
AEMET_BOUNDS_NUDGE_LAT=0
```

Regenera los assets AEMET:

```bash
Rscript scripts/02_prepare_web_assets.R
quarto render --execute
```

Para auditar CRS, bounds y dimensiones PNG:

```bash
Rscript scripts/23_diagnose_aemet_alignment.R
```

Si después de validar visualmente queda un desplazamiento sistemático muy pequeño, puedes aplicar un ajuste manual residual en grados con `AEMET_BOUNDS_NUDGE_LON` y `AEMET_BOUNDS_NUDGE_LAT`. Déjalos a `0` salvo que hayas medido el desplazamiento.


## AEMET: proveedor recomendado

Desde `v0.5.14`, el proveedor recomendado para AEMET es:

```text
AEMET_PROVIDER=classic
AEMET_ALLOW_PNG_OVERLAY=false
```

Este método usa el endpoint clásico de descarga SIG:

```text
https://www.aemet.es/es/api-eltiempo/incendios/download
```

El endpoint devuelve un paquete comprimido con GeoTIFFs georreferenciados:

```text
down_YYYYMMDD_peligro_c_D00.tif ... down_YYYYMMDD_peligro_c_D07.tif
down_YYYYMMDD_peligro_p_D00.tif ... down_YYYYMMDD_peligro_p_D07.tif
```

El visor ya no usa los PNG de AEMET como `imageOverlay`, porque no se alineaban con Leaflet.

Para instalar los GeoTIFFs desde el diagnóstico que ya hayas ejecutado:

```bash
Rscript scripts/22_install_classic_probe_geotiffs.R
Rscript scripts/02_prepare_web_assets.R
quarto render --execute
```

Para ejecutar el pipeline completo con descarga directa clásica:

```bash
Rscript scripts/99_run_all.R
quarto render --execute
```


Visor Quarto + Leaflet para publicar online un mapa estático de riesgo y situación de incendios.

La capa base del proyecto es **AEMET OpenData** para riesgo meteorológico previsto. Desde `v0.2.0` incorpora **NASA FIRMS** y **EFFIS/Copernicus EMS**. Desde `v0.3.0` añade una capa analítica con límites administrativos **Eurostat/GISCO NUTS** para resumir detecciones FIRMS por CCAA y provincia. Desde `v0.4.0` incorpora **alertas operativas automáticas** mediante clústeres de detecciones FIRMS recientes. Desde `v0.5.0` añade **histórico temporal** y una página de evolución de focos, FRP y alertas. Desde `v0.5.2` separa el mapa del resumen operativo y refuerza la transformación CRS de NUTS a EPSG:4326.

El proyecto renderiza un sitio estático en `docs/`, compatible con GitHub Pages.

## Qué incluye

- Riesgo previsto de incendios de AEMET como capa principal.
- Focos activos / anomalías térmicas recientes de NASA FIRMS.
- WMS EFFIS/Copernicus EMS de Fire Weather Index.
- Límites administrativos NUTS2/CCAA y NUTS3/provincias de GISCO.
- Resumen operativo:
  - focos totales;
  - focos en las últimas 6 h y 24 h;
  - FRP total;
  - CCAA y provincias con detecciones;
  - tabla de provincias con más focos;
  - clústeres/alertas operativas a partir de detecciones FIRMS;
  - resumen operativo separado en `summary.html`;
  - informe operativo estático en `report.html`;
  - histórico temporal y gráficos de evolución en `history.html`.

## Estructura

```text
visor-fuego/
├── _quarto.yml
├── index.qmd
├── summary.qmd
├── report.qmd
├── history.qmd
├── R/
│   ├── admin.R
│   ├── alerts.R
│   ├── aemet.R
│   ├── effis.R
│   ├── firms.R
│   ├── history.R
│   ├── prepare_layers.R
│   ├── summary.R
│   └── utils.R
├── scripts/
│   ├── 01_download_aemet_incendios.R
│   ├── 02_prepare_web_assets.R
│   ├── 03_diagnose_downloads.R
│   ├── 04_check_dashboard_inputs.R
│   ├── 05_download_firms_active_fires.R
│   ├── 06_download_admin_boundaries.R
│   ├── 07_build_operational_summary.R
│   ├── 08_build_operational_alerts.R
│   ├── 09_update_dashboard_history.R
│   └── 99_run_all.R
├── assets/
│   ├── admin/
│   ├── alerts/
│   ├── aemet/
│   ├── firms/
│   ├── history/
│   └── summary/
├── data/
│   ├── raw/aemet/
│   ├── raw/admin/
│   ├── raw/firms/
│   └── processed/
└── docs/
```

## Requisitos locales

En Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y libcurl4-openssl-dev libssl-dev libxml2-dev \
  libgdal-dev libproj-dev libgeos-dev libudunits2-dev
```

En R:

```r
install.packages(c(
  "curl", "httr2", "jsonlite", "readr", "dplyr", "purrr", "stringr", "tibble",
  "fs", "glue", "leaflet", "htmltools", "htmlwidgets", "terra", "png", "tidyr",
  "sf", "giscoR", "knitr", "ggplot2"
))
```

También necesitas [Quarto](https://quarto.org/).

## Variables de entorno

Crea un `.Renviron` local a partir de `.Renviron.example`:

```bash
cp .Renviron.example .Renviron
```

Contenido mínimo:

```text
AEMET_API_KEY=TU_API_KEY_AEMET
FIRMS_MAP_KEY=TU_MAP_KEY_FIRMS
```

`FIRMS_MAP_KEY` es opcional. Si no está definida, el visor se renderiza sin focos FIRMS.

Opciones útiles:

```text
AEMET_AREAS=p,c
AEMET_FORECAST_DAYS=1,2,3,4,5,6
AEMET_PRODUCTS=previsto

FIRMS_SOURCES=VIIRS_SNPP_NRT,VIIRS_NOAA20_NRT
FIRMS_DAYS=2
FIRMS_BBOX=-19,27,5,44.6

EFFIS_ENABLE=true
EFFIS_WMS_LAYERS=ecmwf007.fwi
EFFIS_WMS_LABELS=EFFIS - FWI
EFFIS_DATE=2026-07-08

ADMIN_ENABLE=true
ADMIN_NUTS_YEAR=2021
ADMIN_RESOLUTION=10

ALERT_CLUSTER_KM=12
ALERT_MAX_AGE_HOURS=48
HISTORY_MODE=daily_latest
HISTORY_KEEP_DAYS=90
```

Si `EFFIS_DATE` no se define, se usa `Sys.Date()` durante el render.

Si cambias esta versión sobre un repositorio ya renderizado, regenera los límites NUTS para forzar la salida correcta en EPSG:4326:

```bash
Rscript scripts/06_download_admin_boundaries.R
Rscript scripts/07_build_operational_summary.R
quarto render --execute
```


## Ejecutar localmente

```bash
Rscript scripts/99_run_all.R
quarto render --execute
```

Después abre:

```bash
xdg-open docs/index.html
xdg-open docs/summary.html
```

## Ejecutar por partes

```r
source("scripts/01_download_aemet_incendios.R", encoding = "UTF-8")
source("scripts/05_download_firms_active_fires.R", encoding = "UTF-8")
source("scripts/06_download_admin_boundaries.R", encoding = "UTF-8")
source("scripts/02_prepare_web_assets.R", encoding = "UTF-8")
source("scripts/07_build_operational_summary.R", encoding = "UTF-8")
source("scripts/08_build_operational_alerts.R", encoding = "UTF-8")
```

## Comprobación

```r
source("scripts/04_check_dashboard_inputs.R", encoding = "UTF-8")
```

Deberías ver ficheros en:

```text
data/processed/layers.json
data/processed/firms_active_fires.csv
data/processed/admin_nuts2_ccaa.geojson
data/processed/admin_nuts3_provincias.geojson
data/processed/firms_summary_ccaa.csv
data/processed/firms_summary_provincias.csv
data/processed/dashboard_summary.csv
data/processed/operational_alerts.csv
data/processed/operational_report.md
```

## Publicar en GitHub Pages

1. Crea el repositorio en GitHub con nombre `visor-fuego`.
2. Sube este contenido.
3. En **Settings → Secrets and variables → Actions**, crea los secrets:
   - `AEMET_API_KEY`
   - `FIRMS_MAP_KEY`, si quieres NASA FIRMS.
4. En **Settings → Pages**, selecciona:
   - Source: `Deploy from a branch`
   - Branch: `main`
   - Folder: `/docs`
5. Ejecuta manualmente el workflow `Update dashboard`, o espera a la actualización programada.

## Qué aporta cada fuente

| Fuente | Uso en el visor | Tipo |
|---|---|---|
| AEMET OpenData | Riesgo meteorológico previsto | PNG/GeoTIFF/GeoJSON preparado como capa AEMET |
| NASA FIRMS | Focos activos recientes / anomalías térmicas | CSV descargado y GeoJSON/markers |
| EFFIS/Copernicus EMS | Fire Weather Index europeo | WMS directo |
| Eurostat/GISCO | CCAA y provincias NUTS | GeoJSON y tablas resumen |
| Alertas FIRMS | Agrupación espacial de detecciones recientes | CSV/GeoJSON e informe Markdown |

## Limitaciones

- Las imágenes AEMET se superponen con bounds aproximados si el recurso no viene georreferenciado.
- FIRMS detecta anomalías térmicas, no siempre incendios forestales confirmados.
- El bbox FIRMS por defecto cubre España y entorno; puede incluir detecciones próximas fuera de España.
- El resumen por CCAA/provincia depende de límites NUTS y no sustituye delimitaciones administrativas oficiales de emergencias.
- El WMS EFFIS depende de la disponibilidad del parámetro `TIME` para la fecha indicada.
- Este visor es informativo y no sustituye a avisos oficiales ni a servicios de emergencia.
- Las alertas operativas son clústeres automáticos de anomalías térmicas FIRMS; requieren revisión humana.

## Licencia y atribución

Mantén visible la atribución incluida en el mapa:

```text
Fuentes: AEMET OpenData · NASA FIRMS · EFFIS/Copernicus EMS · Eurostat/GISCO
```

EFFIS/Copernicus indica que sus datos son accesibles mediante WMS y que sus contenidos se reutilizan bajo CC BY 4.0 salvo indicación contraria. NASA FIRMS requiere una MAP_KEY gratuita para la API. GISCO proporciona límites administrativos NUTS de Eurostat.

## Versión

`v0.4.0` añade alertas operativas automáticas, clústeres FIRMS y un informe estático `report.html` sobre la versión `v0.3.0`.
