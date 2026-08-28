# visor-fuego

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
quarto render --execute
Rscript scripts/11_check_published_assets.R
```

Para descargar FIRMS es necesario definir `FIRMS_MAP_KEY`. Para usar la base clara de CARTO hay que definir `CARTO_BASEMAP_KEY`. Las variables operativas pueden configurarse en `.Renviron`; el workflow crea este fichero durante cada ejecución.

### Clave CARTO en GitHub Actions

Crea un secret del repositorio llamado `CARTO_BASEMAP_KEY` en **Settings → Secrets and variables → Actions → New repository secret**. La clave se incorpora a la URL de teselas que consume el navegador, por lo que en un sitio estático no puede considerarse secreta frente al usuario final; debe solicitarse/restringirse para el dominio del visor. No se debe escribir manualmente en `index.qmd` ni en `.Renviron.example`.

### Publicación

Desde v0.6.13 GitHub Actions actualiza los datos, renderiza el sitio en `docs/`, valida los recursos y despliega directamente el artefacto mediante `actions/upload-pages-artifact` y `actions/deploy-pages`. En **Settings → Pages → Build and deployment**, la fuente debe ser **GitHub Actions**. Los commits automáticos mantienen `data/processed` y `assets`, pero no `docs/`.
