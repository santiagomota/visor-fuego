# visor-fuego

## v0.5.38: Resumen, Informe y Evolución

Las páginas secundarias del visor quedan sincronizadas con la lógica operativa actual:

- AEMET clásico se interpreta sin desplazamiento adicional: `D00` es `Día 1` y corresponde a la fecha del fichero.
- Si existen varias emisiones en el catálogo, las páginas resumen la última emisión disponible.
- El informe muestra una comprobación explícita de emisiones presentes para detectar arrastre de capas antiguas.
- La evolución lee `dashboard_history.csv` si existe y evita fallar cuando el histórico todavía está incompleto.
- EFFIS queda documentado como desactivado o sin capa actual cuando no hay overlay publicable.

