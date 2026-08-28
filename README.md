# visor-fuego

## v0.6.15: fechas y actualidad de las fuentes

Visor Quarto/Leaflet para el seguimiento operativo del peligro de incendios en España mediante:

- **AEMET**: peligro meteorológico previsto para Península/Baleares y Canarias.
- **NASA FIRMS**: detecciones térmicas recientes y alertas agrupadas.
- **Copernicus/EFFIS**: áreas quemadas como capa contextual.
- **Eurostat/GISCO**: límites de comunidades autónomas y provincias.

### Cambios principales de v0.6.15

- Distingue en la leyenda AEMET la **fecha válida** de la **fecha de emisión**.
- Añade al panel de actualidad la marca temporal de generación del propio visor.
- El estado AEMET se calcula sobre la capa seleccionada y muestra mensajes como `emisión de ayer · válido para hoy`.
- Una emisión de ayer se considera vigente cuando la capa seleccionada es válida para hoy, evitando marcar como atrasado un producto AEMET todavía operativo.
- Las fechas y horas exactas de Visor, FIRMS y EFFIS se muestran en horario de Madrid al pasar el cursor.
- Mantiene el despliegue independiente de Pages y el guardado Git *best-effort* introducidos en v0.6.14.

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

Desde v0.6.13 GitHub Actions actualiza los datos, renderiza el sitio en `docs/`, valida los recursos y despliega directamente el artefacto mediante `actions/upload-pages-artifact` y `actions/deploy-pages`. En **Settings → Pages → Build and deployment**, la fuente debe ser **GitHub Actions**. Los commits automáticos mantienen `data/processed` y `assets`, pero no `docs/`.
