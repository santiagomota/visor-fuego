# visor-fuego

## v0.6.8: navegación temporal y actualidad de datos

Visor Quarto/Leaflet para el seguimiento operativo del peligro de incendios en España mediante:

- **AEMET**: peligro meteorológico previsto para Península/Baleares y Canarias.
- **NASA FIRMS**: detecciones térmicas recientes y alertas agrupadas.
- **Copernicus/EFFIS**: áreas quemadas como capa contextual.
- **Eurostat/GISCO**: límites de comunidades autónomas y provincias.

### Cambios principales de v0.6.8

- Añade botones para avanzar y retroceder entre los días de una misma serie AEMET.
- Incorpora reproducción automática y pausa de los ocho horizontes temporales.
- Mantiene sincronizados el selector, la leyenda, la capa del mapa y el indicador de posición.
- Muestra el día de la semana y la fecha completa en español en el selector y la leyenda AEMET.
- Añade indicadores de actualidad independientes para AEMET, NASA FIRMS y EFFIS.
- Actualiza los tiempos relativos cada minuto y muestra la fecha exacta mediante ayuda contextual.
- Usa estados verde, ámbar, rojo y gris para distinguir datos recientes, con retraso, antiguos o no disponibles.
  - AEMET: verde si la emisión es de hoy, ámbar si es de ayer y rojo si es anterior.
  - FIRMS: verde hasta 6 horas, ámbar hasta 24 horas y rojo por encima de 24 horas.
  - EFFIS: verde hasta 24 horas, ámbar hasta 72 horas y rojo por encima de 72 horas.

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
