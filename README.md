# visor-fuego

Visor Quarto + Leaflet para publicar online un mapa estático de riesgo y situación de incendios.

La capa base del proyecto es **AEMET OpenData** para riesgo meteorológico previsto. Desde `v0.2.0` se añaden:

- **NASA FIRMS**: focos activos / anomalías térmicas recientes como puntos descargados en CSV/GeoJSON.
- **EFFIS/Copernicus EMS**: capa WMS europea de Fire Weather Index.

El proyecto renderiza un sitio estático en `docs/`, compatible con GitHub Pages.

## Estructura

```text
visor-fuego/
├── _quarto.yml
├── index.qmd
├── R/
│   ├── aemet.R
│   ├── effis.R
│   ├── firms.R
│   ├── prepare_layers.R
│   └── utils.R
├── scripts/
│   ├── 01_download_aemet_incendios.R
│   ├── 02_prepare_web_assets.R
│   ├── 03_diagnose_downloads.R
│   ├── 04_check_dashboard_inputs.R
│   ├── 05_download_firms_active_fires.R
│   └── 99_run_all.R
├── assets/
│   ├── aemet/
│   └── firms/
├── data/
│   ├── raw/aemet/
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
  "fs", "glue", "leaflet", "htmltools", "htmlwidgets", "terra", "png", "tidyr"
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
```

Si `EFFIS_DATE` no se define, se usa `Sys.Date()` durante el render.

## Ejecutar localmente

```bash
Rscript scripts/99_run_all.R
quarto render --execute
```

Después abre:

```bash
xdg-open docs/index.html
```

## Ejecutar por partes

```r
source("scripts/01_download_aemet_incendios.R", encoding = "UTF-8")
source("scripts/05_download_firms_active_fires.R", encoding = "UTF-8")
source("scripts/02_prepare_web_assets.R", encoding = "UTF-8")
```

## Publicar en GitHub Pages

1. Crea el repositorio en GitHub con nombre `visor-fuego`.
2. Sube este contenido.
3. En **Settings → Secrets and variables → Actions**, crea los secrets:
   - `AEMET_API_KEY`
   - `FIRMS_MAP_KEY` si quieres NASA FIRMS.
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

## Limitaciones

- Las imágenes AEMET se superponen con bounds aproximados si el recurso no viene georreferenciado.
- FIRMS detecta anomalías térmicas, no siempre incendios forestales confirmados.
- El bbox FIRMS por defecto cubre España y entorno; puede incluir detecciones próximas fuera de España.
- El WMS EFFIS depende de la disponibilidad del parámetro `TIME` para la fecha indicada.
- Este visor es informativo y no sustituye a avisos oficiales ni a servicios de emergencia.

## Licencia y atribución

Mantén visible la atribución incluida en el mapa:

```text
Fuentes: AEMET OpenData · NASA FIRMS · EFFIS/Copernicus EMS
```

EFFIS/Copernicus indica que sus datos son accesibles mediante WMS y que sus contenidos se reutilizan bajo CC BY 4.0 salvo indicación contraria. NASA FIRMS requiere una MAP_KEY gratuita para la API.

## Versión

`v0.2.0` añade NASA FIRMS y EFFIS/Copernicus al visor AEMET original.
