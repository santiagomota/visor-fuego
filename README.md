# visor-fuego

## v0.6.12: autenticación CARTO Basemaps

Visor Quarto/Leaflet para el seguimiento operativo del peligro de incendios en España mediante:

- **AEMET**: peligro meteorológico previsto para Península/Baleares y Canarias.
- **NASA FIRMS**: detecciones térmicas recientes y alertas agrupadas.
- **Copernicus/EFFIS**: áreas quemadas como capa contextual.
- **Eurostat/GISCO**: límites de comunidades autónomas y provincias.

### Cambios principales de v0.6.12

- Añade soporte para la nueva API key obligatoria de CARTO Basemaps.
- Lee la clave desde `CARTO_BASEMAP_KEY` en `.Renviron` y desde el secret homónimo en GitHub Actions.
- Sustituye `providers$CartoDB.Positron` por una URL explícita Positron con `?key=...`.
- Mantiene las atribuciones obligatorias de OpenStreetMap y CARTO.
- Si no existe clave, usa OpenStreetMap como base clara de respaldo y evita el aviso de CARTO.
- El workflow escribe las claves desde variables de entorno para no interpretarlas dentro del heredoc.
- La validación comprueba que un render con clave no vuelva a utilizar el proveedor CARTO anónimo.

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
quarto render --execute
Rscript scripts/11_check_published_assets.R
```

Para descargar FIRMS es necesario definir `FIRMS_MAP_KEY`. Para usar la base clara de CARTO hay que definir `CARTO_BASEMAP_KEY`. Las variables operativas pueden configurarse en `.Renviron`; el workflow crea este fichero durante cada ejecución.

### Clave CARTO en GitHub Actions

Crea un secret del repositorio llamado `CARTO_BASEMAP_KEY` en **Settings → Secrets and variables → Actions → New repository secret**. La clave se incorpora a la URL de teselas que consume el navegador, por lo que en un sitio estático no puede considerarse secreta frente al usuario final; debe solicitarse/restringirse para el dominio del visor. No se debe escribir manualmente en `index.qmd` ni en `.Renviron.example`.

### Publicación

GitHub Actions actualiza los datos, renderiza el sitio en `docs/`, valida los recursos publicados y realiza un commit únicamente cuando existen cambios.
