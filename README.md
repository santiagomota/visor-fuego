# visor-fuego

## v0.6.9: panel territorial interactivo

Visor Quarto/Leaflet para el seguimiento operativo del peligro de incendios en España mediante:

- **AEMET**: peligro meteorológico previsto para Península/Baleares y Canarias.
- **NASA FIRMS**: detecciones térmicas recientes y alertas agrupadas.
- **Copernicus/EFFIS**: áreas quemadas como capa contextual.
- **Eurostat/GISCO**: límites de comunidades autónomas y provincias.

### Cambios principales de v0.6.9

- Añade un panel territorial al pulsar sobre una comunidad autónoma o provincia.
- Mantiene las CCAA visibles por defecto con un contorno discreto; las provincias se activan desde el control de capas.
- Muestra detecciones FIRMS en las últimas 6, 12, 24 y 48 horas.
- Incluye FRP máxima y media, última detección y prioridad FIRMS del territorio.
- Resume los perímetros y la superficie quemada EFFIS de los últimos 30 y 90 días.
- Estima el nivel AEMET para la fecha seleccionada mediante un punto representativo interior de cada territorio.
- Actualiza automáticamente el nivel territorial AEMET al navegar entre días o reproducir la secuencia.
- Permite centrar y ampliar el mapa sobre el territorio seleccionado.
- Publica resúmenes completos para las 19 unidades NUTS2 y las 59 unidades NUTS3, incluidas las que no tienen actividad reciente.
- Reordena el pipeline para preparar EFFIS antes del resumen territorial, garantizando que todos los indicadores procedan de la misma ejecución.

La estimación territorial AEMET es orientativa: se obtiene del color del raster en un punto interior representativo y no equivale al máximo ni al promedio de toda la superficie del territorio.

Se mantienen las mejoras anteriores:

- Ejecución diaria a las **04:30** y **12:30** con `timezone: Europe/Madrid`.
- Cambio automático entre horario peninsular de invierno y de verano.
- Publicación robusta mediante `fetch`, `rebase` y hasta tres reintentos de `push`.
- Normalización explícita de tipos al combinar las fuentes NASA FIRMS.
- `data/raw/` permanece ignorado y solo se publican `data/processed`, `assets` y `docs`.
- Los PNG de AEMET se declaran como recursos Quarto y se copian a `docs/assets/aemet/` durante el render.
- El workflow utiliza `scripts/99_run_all.R` como único pipeline canónico.
- El resumen FIRMS se genera antes que las alertas y el histórico.
- La capa EFFIS se carga bajo demanda y no se incrusta en `docs/index.html`.
- Se valida que todos los recursos AEMET y EFFIS existan dentro de `docs/` antes de publicar.

### Ejecución local

```bash
Rscript scripts/99_run_all.R
quarto render --execute
Rscript scripts/11_check_published_assets.R
```

Para descargar FIRMS es necesario definir `FIRMS_MAP_KEY`. Las variables operativas pueden configurarse en `.Renviron`; el workflow crea este fichero durante cada ejecución.

### Publicación

GitHub Actions actualiza los datos, renderiza el sitio en `docs/`, valida los recursos publicados y realiza un commit únicamente cuando existen cambios.
