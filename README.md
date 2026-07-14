# visor-fuego

## v0.6.10: mapa panorámico

Visor Quarto/Leaflet para el seguimiento operativo del peligro de incendios en España mediante:

- **AEMET**: peligro meteorológico previsto para Península/Baleares y Canarias.
- **NASA FIRMS**: detecciones térmicas recientes y alertas agrupadas.
- **Copernicus/EFFIS**: áreas quemadas como capa contextual.
- **Eurostat/GISCO**: límites de comunidades autónomas y provincias.

### Cambios principales de v0.6.10

- Elimina el índice lateral únicamente en `index.qmd`, evitando que Quarto reserve una columna derecha vacía.
- Amplía el contenido de la página Mapa hasta los márgenes interiores de la pantalla en resoluciones de escritorio.
- Aumenta la altura del mapa de `84vh` a `88vh`.
- Compacta el título, el subtítulo y el encabezado del mapa para dedicar más superficie útil al visor.
- Traslada el diagnóstico desplegable **Fuente y actualización** debajo del mapa.
- Añade borde, sombra ligera y esquinas redondeadas para delimitar el área cartográfica en pantallas grandes.
- Mantiene un diseño adaptativo en portátiles, tabletas y móviles.
- Amplía la validación automática para comprobar el diseño panorámico y que el índice lateral no reaparezca.

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

Para descargar FIRMS es necesario definir `FIRMS_MAP_KEY`. Las variables operativas pueden configurarse en `.Renviron`; el workflow crea este fichero durante cada ejecución.

### Publicación

GitHub Actions actualiza los datos, renderiza el sitio en `docs/`, valida los recursos publicados y realiza un commit únicamente cuando existen cambios.
