# visor-fuego

## v0.6.20: render siempre fresco y build verificable

Esta revisión corrige el problema por el que los datos de `assets/` podían estar actualizados mientras GitHub Pages seguía mostrando un `index.html` antiguo. La causa era `freeze: auto`: Quarto podía reutilizar la ejecución de `index.qmd` cuando el QMD no había cambiado, aunque sí hubieran cambiado los ficheros AEMET, FIRMS y EFFIS que consume.

### Cambios principales de v0.6.20

- **Ejecución forzada:** `_quarto.yml` usa `freeze: false`. En GitHub Actions se eliminan además `_freeze/` y `docs/` antes de `quarto render`.
- **Recursos completos:** Quarto publica `assets/**` entero, de modo que el HTML y todos los catálogos/estados proceden del mismo snapshot.
- **Selector AEMET vigente:** con `AEMET_HIDE_PAST_VALID_DATES=true` no se publican fechas válidas anteriores al día actual en Madrid. Si la última emisión es de ayer, el selector comienza por el mapa de esa emisión que sea válido para hoy.
- **Build identificable:** `scripts/12_build_site_manifest.R` genera `assets/site-build.json` con un `build_id` único y resumen temporal de AEMET, FIRMS y EFFIS.
- **Coherencia antes de publicar:** `scripts/11_check_published_assets.R` exige que `docs/assets/site-build.json` y el `build_id` embebido en `docs/index.html` coincidan con el snapshot actual.
- **Coherencia después de publicar:** tras `actions/deploy-pages`, el workflow consulta la web pública con cache-busting y verifica tanto el manifiesto como el HTML. Un deployment que continúe sirviendo un HTML viejo ya no puede terminar en verde.
- **Autocorrección en navegador:** el mapa consulta `assets/site-build.json`; si el HTML cargado pertenece a otro build, recarga la URL añadiendo `?build=<id>`.

Se mantienen las garantías de v0.6.19: `assets/` es la fuente canónica, AEMET exige simbología oficial (`ESCALA`/SLD/QML), una emisión AEMET de más de un día detiene el pipeline y FIRMS conserva temporalmente el último snapshot válido ante respuestas vacías.

## v0.6.19: snapshot web coherente y fuentes operativas robustas

Esta revisión prioriza que el visor publicado reproduzca un único snapshot operativo y que una incidencia temporal de una fuente externa no se convierta en información engañosa. El render web utiliza exclusivamente `assets/` para AEMET, FIRMS, resúmenes, alertas y EFFIS.

### Cambios principales de v0.6.19

- **Fuente única del render:** `index.qmd` deja de mezclar `data/processed/` y `assets/`; los productos publicados se leen exclusivamente desde `assets/`.
- **AEMET sin caché antigua:** la descarga clásica añade un parámetro de cache-busting y reintenta hasta tres veces si la emisión obtenida no es la del día.
- **Control de actualidad AEMET:** se publica `assets/aemet/status.json`; una emisión con más de un día de antigüedad detiene el pipeline.
- **Simbología AEMET estricta:** el workflow exige una fuente oficial de estilo. Se intenta `ESCALA` vía GDAL/terra, tabla de color del GeoTIFF y los estilos SLD/QML incluidos en el paquete. En producción ya no se acepta silenciosamente `IPIF fallback 1..6`.
- **FIRMS protegido frente a falsos ceros:** si la descarga actual queda vacía o falla, se conserva el último snapshot válido durante un máximo de 72 horas y se marca como `stale_preserved`.
- **Snapshot FIRMS canónico:** se publica también `assets/firms/firms_active_fires.csv` y `assets/firms/status.json`.
- **Validación reforzada:** el workflow comprueba que el render no vuelva a consumir productos operativos desde `data/processed/`, que AEMET no use una paleta fallback cuando se exige estilo oficial y que existan los estados AEMET/FIRMS.

AEMET documenta el IPIF actual como un raster GeoTIFF de 1 km con seis clases y expone la correspondencia nivel/color en el campo `ESCALA`, además de estilos SLD y QML. v0.6.19 usa esas fuentes como referencia de simbología.

## v0.6.18: ejecuciones programadas con respaldo

El workflow mantiene las actualizaciones principales a las **04:30** y **12:30** (Europe/Madrid) y añade ejecuciones de respaldo a las **04:50** y **12:50**. El respaldo consulta el historial de GitHub Actions antes de instalar dependencias: si ya existe una ejecución programada correcta en los últimos 45 minutos, termina sin ejecutar el pipeline; si la principal no se creó o falló, realiza la actualización completa. Las ejecuciones manuales siempre se ejecutan.

### Cambios principales de v0.6.18

- Horarios principales: 04:30 y 12:30, hora Madrid.
- Horarios de respaldo: 04:50 y 12:50, hora Madrid.
- Comprobación temprana mediante la API de GitHub Actions y `GITHUB_TOKEN`.
- El respaldo se activa si no hay una ejecución `schedule` correcta en los 45 minutos anteriores.
- Si la API de Actions no está disponible, el respaldo ejecuta el pipeline por seguridad.
- Las ejecuciones manuales no se filtran.
- Permiso `actions: read` añadido al token del workflow.

## v0.6.17: simbología AEMET IPIF oficial

Esta revisión corrige la representación de los GeoTIFF de peligro de incendios de AEMET. El producto IPIF actual utiliza seis clases discretas, codificadas de 1 a 6. El visor ya no deduce el color según qué clases aparezcan en cada mapa: conserva siempre la correspondencia oficial entre valor, nivel y color.

Visor Quarto/Leaflet para el seguimiento operativo del peligro de incendios en España mediante:

- **AEMET**: peligro meteorológico previsto para Península/Baleares y Canarias.
- **NASA FIRMS**: detecciones térmicas recientes y alertas agrupadas.
- **Copernicus/EFFIS**: áreas quemadas como capa contextual.
- **Eurostat/GISCO**: límites de comunidades autónomas y provincias.

### Cambios principales de v0.6.17

- Clases fijas: `1 Muy bajo`, `2 Bajo`, `3 Moderado`, `4 Alto`, `5 Muy alto`, `6 Extremo`.
- Lectura prioritaria del metadato `ESCALA` RGBA de AEMET.
- Lectura alternativa de la tabla de color del GeoTIFF cuando esté disponible.
- Paleta IPIF de respaldo solo si AEMET no expone el estilo; nunca se reenumeran las clases presentes.
- Campo `style_source` en `assets/aemet/layers.json` para auditar la procedencia del estilo.
- Los píxeles fuera de 1..6 se publican transparentes y generan un aviso.
- Se mantienen la separación entre fecha válida/emisión, el panel territorial, la navegación temporal y el despliegue directo de Pages.

> Al comparar con la web oficial de AEMET debe usarse la misma **fecha válida**. La base cartográfica y la transparencia pueden ser distintas, pero la clase IPIF de cada píxel debe coincidir.

Se mantienen las mejoras anteriores:

- Panel territorial interactivo para las 19 CCAA y las 59 provincias.
- Indicadores FIRMS para 6, 12, 24 y 48 horas, FRP y última detección.
- Superficie y perímetros EFFIS de los últimos 30 y 90 días.
- Estimación puntual del nivel AEMET para el territorio y día seleccionados.
- Navegación temporal AEMET con anterior, siguiente y reproducción automática.
- Indicadores de actualidad de AEMET, FIRMS y EFFIS.
- Ejecución diaria a las **04:30** y **12:30** con `timezone: Europe/Madrid`.
- Publicación robusta mediante `fetch`, `rebase` y hasta tres reintentos de `push`.
- Normalización explícita de tipos al combinar las fuentes NASA FIRMS.
- Los PNG de AEMET se publican como recursos Quarto dentro de `docs/assets/aemet/`.
- EFFIS se carga bajo demanda y no se incrusta en `docs/index.html`.

### Ejecución local

```bash
Rscript scripts/99_run_all.R
quarto render
Rscript scripts/11_check_published_assets.R
```

Para descargar FIRMS es necesario definir `FIRMS_MAP_KEY`. Para usar la base clara de CARTO hay que definir `CARTO_BASEMAP_KEY`. Las variables operativas pueden configurarse en `.Renviron`; el workflow crea este fichero durante cada ejecución.

### Clave CARTO en GitHub Actions

Crea un secret del repositorio llamado `CARTO_BASEMAP_KEY` en **Settings → Secrets and variables → Actions → New repository secret**. La clave se incorpora a la URL de teselas que consume el navegador, por lo que en un sitio estático no puede considerarse secreta frente al usuario final; debe solicitarse/restringirse para el dominio del visor. No se debe escribir manualmente en `index.qmd` ni en `.Renviron.example`.

### Publicación

Desde v0.6.13 GitHub Actions actualiza los datos, renderiza el sitio en `docs/`, valida los recursos y despliega directamente el artefacto mediante `actions/upload-pages-artifact` y `actions/deploy-pages`. En **Settings → Pages → Build and deployment**, la fuente debe ser **GitHub Actions**. Los commits automáticos mantienen `data/processed` y `assets`, pero no `docs/`.
