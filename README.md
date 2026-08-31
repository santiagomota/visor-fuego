# visor-fuego

> **v0.6.24:** mantiene 04:30 y 12:30 como horas objetivo y añade tres respaldos por franja. Los respaldos consultan el `site-build.json` realmente publicado y solo ejecutan el pipeline si Pages sigue sin actualizar.


## v0.6.24: programación redundante basada en el build publicado

GitHub Actions puede retrasar o descartar eventos `schedule`. Esta versión mantiene las actualizaciones objetivo de las **04:30** y **12:30** (Europe/Madrid), pero añade respaldos a las **04:47, 05:13 y 05:41**, y a las **12:47, 13:13 y 13:41**.

### Cambios principales de v0.6.24

- Las ejecuciones principales siguen siendo 04:30 y 12:30.
- Se añaden tres oportunidades de respaldo por franja para reducir la probabilidad de perder una actualización si GitHub descarta un evento programado.
- Los respaldos ya no confían en una ejecución `success` del historial de Actions: consultan `assets/site-build.json` de GitHub Pages con `no-cache`.
- Si Pages contiene un build generado después del objetivo de la franja, el respaldo termina en pocos segundos sin instalar R/Quarto.
- Si Pages no está actualizado, si el manifiesto no puede leerse o si la ejecución principal no llegó a crearse, el respaldo ejecuta el pipeline completo.
- Se conserva `concurrency` con `cancel-in-progress: false`: si una principal retrasada termina antes de un respaldo en cola, el respaldo comprobará Pages y se omitirá.


## v0.6.23: AEMET runtime obligatorio y sin fallback obsoleto

Esta versión corrige el despliegue incompleto detectado el 30 de agosto de 2026: `assets/aemet/layers.json` estaba actualizado, pero el `index.qmd` publicado en `main` seguía usando un catálogo embebido anterior.

### Cambios principales de v0.6.23

- AEMET se carga en tiempo de ejecución desde `assets/aemet/layers.json` con `cache: no-store`.
- Si el catálogo AEMET runtime falla, el visor muestra AEMET como no disponible; nunca recurre a un catálogo embebido antiguo.
- El bloque «Fuente y actualización» deja de imprimir fechas y recuentos operativos congelados en el HTML.
- El workflow valida antes del pipeline que `index.qmd` contiene `loadRuntimeData()` y el `fetch` AEMET dinámico.
- Tras renderizar, se exige que `docs/index.html` contenga la arquitectura runtime.


## v0.6.21: datos operativos cargados en vivo desde `assets/`

Esta revisión desacopla los datos del `index.html`. El mapa puede haber quedado en caché, pero al abrirse vuelve a consultar con `cache: no-store` los catálogos y estados operativos publicados en `assets/`. Así una copia antigua del HTML no puede volver a iniciar AEMET en una fecha pasada ni mantener focos FIRMS de un snapshot anterior.

### Cambios principales de v0.6.21

- **AEMET en tiempo de ejecución:** el selector se construye desde `assets/aemet/layers.json` mediante `fetch(..., {cache: "no-store"})`, con un parámetro de cache-busting. Las fechas válidas anteriores a hoy en Madrid se excluyen también en el navegador.
- **PNG AEMET sin caché antigua:** cada `imageOverlay` usa una URL con identificador de runtime/build, por lo que una imagen regenerada para el mismo día no reutiliza una copia anterior del navegador.
- **FIRMS en vivo:** los puntos del mapa ya no se incrustan en el HTML. Se cargan desde `assets/firms/firms_active_fires.geojson`; su estado se toma de `assets/firms/status.json`.
- **Panel territorial en vivo:** `assets/summary/territorial_summary.json` se recarga al abrir el visor y actualiza la consulta territorial.
- **Build en vivo:** `assets/site-build.json` actualiza la marca temporal y el identificador del build. Si el HTML pertenece a otro build, se solicita una única recarga con `?build=<id>`.
- **Fallback local:** los JSON embebidos por Quarto se conservan solo como respaldo para ejecución local/offline si una petición runtime falla.
- **Diagnóstico visible:** el panel indica si los datos operativos se cargaron en vivo o si alguna fuente tuvo que utilizar el respaldo embebido.
- **EFFIS cache-busting:** la capa bajo demanda también se solicita sin reutilizar una respuesta antigua.

Se mantienen `freeze: false`, la eliminación de `_freeze/` en Actions, la verificación post-deployment, la simbología oficial IPIF extraída de AEMET y la protección FIRMS frente a falsos ceros.

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


## v0.6.29: preflight único y coherente

- Mantiene el snapshot runtime inmutable por `build_id` de v0.6.28.
- Elimina la validación runtime duplicada que seguía buscando la llamada antigua directa a `assets/aemet/layers.json`.
- Evita `grep` diagnósticos capaces de abortar el workflow bajo `set -euo pipefail`.
- Alinea `browser-cache.html`, `sw.js`, validación local y validación remota en la misma versión 0.6.29.
