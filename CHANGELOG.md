# Changelog

## v0.6.4 - corrección de publicación automática

- Corregido el paso `Commit si hay cambios` del workflow de GitHub Actions.
- Eliminado `data/raw/aemet` de `git add`: `data/raw/` contiene descargas temporales y está excluido por `.gitignore`.
- El workflow publica únicamente las salidas reproducibles de `data/processed`, `assets` y `docs`.
- El `push` se dirige explícitamente a la rama que ejecuta el workflow mediante `GITHUB_REF_NAME`.
- Validado que los ficheros ignorados dentro de `data/processed` que ya están versionados se actualizan correctamente con `git add -A`.
- Sustituido `.Renviron.example` por una configuración completa, sin duplicados y alineada con AEMET classic, FIRMS y EFFIS Burnt Areas.

## v0.6.3 - publicación AEMET y pipeline consolidado

- Declara `assets/aemet/**` y `assets/effis_ba/**` como recursos del proyecto Quarto.
- Corrige el fallo por el que las capas AEMET aparecían como rectángulos transparentes en GitHub Pages al no existir los PNG dentro de `docs/`.
- Añade `styles.css` a la configuración HTML global y elimina los estilos duplicados de `index.qmd`.
- Convierte `scripts/99_run_all.R` en el único pipeline canónico de actualización.
- Ejecuta el resumen operativo antes de alertas e histórico para mantener coherentes los recuentos FIRMS y los resúmenes territoriales.
- Elimina la tolerancia silenciosa para fallos en resumen, alertas, histórico y validaciones; EFFIS continúa siendo opcional de forma explícita.
- Añade control de concurrencia al workflow y publica también `assets/summary` mediante `git add -A` sobre los directorios de datos y salida.
- Añade `scripts/11_check_published_assets.R`, que valida páginas, PNG de AEMET, GeoJSON de EFFIS y tamaño del HTML principal.
- Corrige el desfase de un día en la tabla AEMET de `summary.qmd`.
- Cambia EFFIS Burnt Areas a carga bajo demanda desde JavaScript, evitando incrustar miles de polígonos en el HTML.
- Reduce EFFIS por defecto a 90 días, superficie mínima de 5 ha y simplificación geométrica de 100 m.
- Elimina la copia duplicada `data/processed/effis_burnt_areas.geojson`; la geometría publicable reside en `assets/effis_ba/`.
- Retira scripts de parche ya consolidados y la antigua página `aemet.qmd` no utilizada.

## v0.5.38 - páginas secundarias sincronizadas

- Actualiza las páginas `summary.qmd`, `report.qmd` y `history.qmd` para usar la lógica corregida de fechas AEMET.
- Añade `R/page_helpers.R` con utilidades compartidas para leer catálogos, normalizar fechas y filtrar la última emisión.
- El resumen y el informe ya no muestran capas AEMET antiguas salvo que sigan presentes en el catálogo como diagnóstico.
- La página de evolución tolera históricos incompletos y muestra tablas/gráficos solo cuando hay datos suficientes.
- EFFIS se informa como desactivado o sin capa actual si no hay `effis_layers.csv` publicable.
