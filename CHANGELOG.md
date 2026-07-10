# Changelog

## v0.5.38 - páginas secundarias sincronizadas

- Actualiza las páginas `summary.qmd`, `report.qmd` y `history.qmd` para usar la lógica corregida de fechas AEMET.
- Añade `R/page_helpers.R` con utilidades compartidas para leer catálogos, normalizar fechas y filtrar la última emisión.
- El resumen y el informe ya no muestran capas AEMET antiguas salvo que sigan presentes en el catálogo como diagnóstico.
- La página de evolución tolera históricos incompletos y muestra tablas/gráficos solo cuando hay datos suficientes.
- EFFIS se informa como desactivado o sin capa actual si no hay `effis_layers.csv` publicable.
