# visor-fuego

## v0.6.3: publicación AEMET y pipeline operativo consolidado

Visor Quarto/Leaflet para el seguimiento operativo del peligro de incendios en España mediante:

- **AEMET**: peligro meteorológico previsto para Península/Baleares y Canarias.
- **NASA FIRMS**: detecciones térmicas recientes y alertas agrupadas.
- **Copernicus/EFFIS**: áreas quemadas como capa contextual.
- **Eurostat/GISCO**: límites de comunidades autónomas y provincias.

### Cambios principales de v0.6.3

- Los PNG de AEMET se declaran como recursos Quarto y se copian a `docs/assets/aemet/` durante el render.
- El workflow utiliza `scripts/99_run_all.R` como único pipeline canónico.
- El resumen FIRMS se genera antes que las alertas y el histórico.
- La capa EFFIS se carga bajo demanda y no se incrusta en `docs/index.html`.
- EFFIS publica una sola copia del GeoJSON, filtrada y simplificada para uso web.
- Se valida que todos los recursos AEMET y EFFIS existan dentro de `docs/` antes de publicar.
- Se corrige la numeración del horizonte AEMET en la página Resumen.

### Ejecución local

```bash
Rscript scripts/99_run_all.R
quarto render --execute
Rscript scripts/11_check_published_assets.R
```

Para descargar FIRMS es necesario definir `FIRMS_MAP_KEY`. Las variables operativas pueden configurarse en `.Renviron`; el workflow crea este fichero durante cada ejecución.

### Publicación

GitHub Actions actualiza los datos, renderiza el sitio en `docs/`, valida los recursos publicados y realiza un commit únicamente cuando existen cambios.
