# visor-fuego

Visor Quarto + Leaflet para publicar online los mapas de riesgo meteorológico de incendios forestales de AEMET.

La fuente principal es **AEMET OpenData**, no el raspado HTML del visor web. El repositorio descarga los productos de incendios, prepara los ficheros para publicación estática y renderiza un sitio Quarto en `docs/`, listo para GitHub Pages.

## Estructura

```text
visor-fuego/
├── _quarto.yml
├── index.qmd
├── DESCRIPTION
├── README.md
├── R/
│   ├── aemet.R
│   ├── prepare_layers.R
│   └── utils.R
├── scripts/
│   ├── 01_download_aemet_incendios.R
│   ├── 02_prepare_web_assets.R
│   └── 99_run_all.R
├── docs/
│   └── assets/aemet/
├── data/
│   ├── raw/aemet/
│   └── processed/
└── .github/workflows/
    └── update-dashboard.yml
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
  "httr2", "jsonlite", "readr", "dplyr", "purrr", "stringr", "tibble",
  "fs", "glue", "leaflet", "htmltools", "htmlwidgets", "terra", "png", "tidyr"
))
```

También necesitas [Quarto](https://quarto.org/).

## API key de AEMET

Solicita una API key en AEMET OpenData y guárdala como variable de entorno:

```bash
export AEMET_API_KEY="TU_API_KEY"
```

O crea un fichero `.Renviron` local, no versionado:

```text
AEMET_API_KEY=TU_API_KEY
```

## Ejecutar localmente

```bash
Rscript scripts/99_run_all.R
quarto render
```

Después abre:

```bash
xdg-open docs/index.html
```

## Publicar en GitHub Pages

1. Crea el repositorio en GitHub con nombre `visor-fuego`.
2. Sube este contenido.
3. En **Settings → Secrets and variables → Actions**, crea el secret `AEMET_API_KEY`.
4. En **Settings → Pages**, selecciona:
   - Source: `Deploy from a branch`
   - Branch: `main`
   - Folder: `/docs`
5. Ejecuta manualmente el workflow `Update dashboard`, o espera a la actualización programada.

## Comandos iniciales sugeridos

```bash
cd visor-fuego
git init
git add .
git commit -m "Initial Quarto Leaflet AEMET fire risk viewer"
git branch -M main
git remote add origin git@github.com:TU_USUARIO/visor-fuego.git
git push -u origin main
```

## Nota sobre georreferenciación

AEMET OpenData expone endpoints de incendios para mapas de riesgo estimado y previsto. Si el recurso descargado es una imagen no georreferenciada, el visor la superpone con bounds aproximados por área (`p`, `b`, `c`). Si el recurso descargado es GeoTIFF, el script intenta convertirlo a PNG georreferenciado para `leaflet`.

Para análisis cuantitativo serio por municipio, celda o superficie conviene sustituir la imagen por una fuente raster/vectorial georreferenciada oficial cuando esté disponible.

## Licencia y atribución

La información de AEMET puede reutilizarse citando a AEMET como autora. Mantén visible la atribución incluida en el mapa.
