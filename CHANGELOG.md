# Changelog

Todos los cambios relevantes del proyecto se documentan en este fichero.

El proyecto utiliza versiones semánticas incrementales.

## [0.6.4] - 2026-07-10

### Corregido

- Corregido el paso `Commit si hay cambios` del workflow de GitHub Actions.
- Eliminado `data/raw/aemet` de `git add`, ya que `data/raw/` contiene descargas temporales y está excluido mediante `.gitignore`.
- El `push` se dirige explícitamente a la rama que ejecuta el workflow mediante `GITHUB_REF_NAME`.
- Validada la actualización de ficheros ya versionados dentro de directorios que contienen reglas de exclusión.

### Cambiado

- El workflow publica únicamente las salidas reproducibles de:
  - `data/processed/`
  - `assets/`
  - `docs/`
- Sustituido `.Renviron.example` por una configuración completa, sin duplicados y alineada con AEMET clásico, NASA FIRMS y EFFIS Burnt Areas.

## [0.6.3] - 2026-07-10

### Añadido

- Declarados `assets/aemet/**` y `assets/effis_ba/**` como recursos del proyecto Quarto.
- Añadido `scripts/11_check_published_assets.R`.
- Añadido control de concurrencia al workflow.
- Añadida validación de:
  - páginas HTML;
  - PNG de AEMET;
  - GeoJSON de EFFIS;
  - tamaño del HTML principal.

### Corregido

- Corregido el fallo por el que las capas AEMET aparecían como rectángulos transparentes en GitHub Pages al no existir los PNG dentro de `docs/`.
- Corregido el desfase de un día en la tabla AEMET de `summary.qmd`.
- Corregida la coherencia entre el resumen FIRMS, las alertas y el histórico.
- Eliminada la tolerancia silenciosa a fallos en los pasos críticos del pipeline.

### Cambiado

- `scripts/99_run_all.R` pasa a ser el único pipeline canónico de actualización.
- El resumen operativo se genera antes que las alertas y el histórico.
- `styles.css` se incorpora a la configuración HTML global.
- Eliminados estilos duplicados de `index.qmd`.
- La capa EFFIS Burnt Areas se carga bajo demanda desde JavaScript.
- EFFIS utiliza por defecto:
  - 90 días de ventana;
  - 5 hectáreas de superficie mínima;
  - 100 metros de simplificación geométrica.
- La geometría EFFIS publicable se mantiene únicamente en `assets/effis_ba/`.
- El workflow publica también `assets/summary`.

### Eliminado

- Eliminada la copia duplicada `data/processed/effis_burnt_areas.geojson`.
- Retirados scripts de parche ya consolidados.
- Retirada la antigua página `aemet.qmd` que ya no se utilizaba.

## [0.5.38] - 2026-07-09

### Añadido

- Añadido `R/page_helpers.R` con utilidades compartidas para:
  - leer catálogos;
  - normalizar fechas;
  - filtrar la última emisión disponible.

### Corregido

- Actualizadas `summary.qmd`, `report.qmd` y `history.qmd` para usar la lógica corregida de fechas AEMET.
- El resumen y el informe dejan de mostrar capas AEMET antiguas salvo que continúen presentes en el catálogo como diagnóstico.
- La página de evolución tolera históricos incompletos.
- Los gráficos y tablas históricas solo se muestran cuando existen datos suficientes.
- EFFIS se informa como desactivado o sin capa actual cuando no existe un `effis_layers.csv` publicable.

## [0.1.0] - 2026-07-07

### Añadido

- Primera versión funcional del visor.
- Sitio Quarto con mapa Leaflet.
- Integración inicial de previsiones de peligro de incendios de AEMET.
- Publicación mediante GitHub Pages.
- Estructura inicial de scripts de descarga, preparación de recursos y renderizado.

## Historial anterior y versiones intermedias

Entre `0.1.0` y `0.5.38` se desarrollaron de forma incremental:

- separación del mapa y el resumen operativo;
- ampliación del tamaño y diseño del visor;
- incorporación de límites administrativos;
- integración de NASA FIRMS;
- integración de Copernicus/EFFIS;
- generación de resúmenes y alertas;
- incorporación de histórico operativo;
- búsqueda y tratamiento de fuentes AEMET clásicas;
- correcciones de fechas, emisiones y horizontes;
- mejoras progresivas del workflow de GitHub Actions.

Las entradas detalladas de algunas versiones intermedias no estaban disponibles al reconstruir este fichero. No se han inventado números de versión ni fechas adicionales.
