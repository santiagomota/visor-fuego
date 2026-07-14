# visor-fuego

## v0.6.7: fecha y día de la semana en AEMET

Visor Quarto/Leaflet para el seguimiento operativo del peligro de incendios en España mediante:

- **AEMET**: peligro meteorológico previsto para Península/Baleares y Canarias.
- **NASA FIRMS**: detecciones térmicas recientes y alertas agrupadas.
- **Copernicus/EFFIS**: áreas quemadas como capa contextual.
- **Eurostat/GISCO**: límites de comunidades autónomas y provincias.

### Cambios principales de v0.6.7

- Añade el día de la semana y la fecha completa al selector de capas AEMET.
- Añade una cabecera dinámica a la leyenda con la fecha válida, el horizonte, el área y el tipo de producto.
- Formatea las fechas en español usando UTC para impedir desplazamientos por la zona horaria del navegador.
- Conserva la normalización robusta de las respuestas NASA FIRMS introducida en v0.6.6.

Se mantienen las mejoras anteriores:

- Ejecución diaria a las **04:30** y **12:30** con `timezone: Europe/Madrid`.
- Cambio automático entre horario peninsular de invierno y de verano.
- Publicación robusta mediante `fetch`, `rebase` y hasta tres reintentos de `push`.
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
