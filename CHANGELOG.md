# Changelog

## v0.6.21 - carga dinámica de datos operativos

- Desacopla AEMET de `index.html`: el navegador consulta `assets/aemet/layers.json` con `cache: no-store` y cache-busting en cada apertura.
- Filtra también en cliente las fechas AEMET anteriores al día actual en `Europe/Madrid`.
- Añade cache-busting a los PNG/GeoJSON AEMET cargados por Leaflet.
- Elimina la incrustación de los puntos FIRMS en el widget y los carga en vivo desde `assets/firms/firms_active_fires.geojson`.
- Recarga `assets/firms/status.json` para actualizar la última detección y distinguir un snapshot `stale_preserved`.
- Recarga `assets/summary/territorial_summary.json` para que el panel territorial no dependa de un HTML antiguo.
- Recarga `assets/site-build.json`, muestra el build actual y solicita una única recarga con `?build=<id>` si el HTML pertenece a una generación distinta.
- Mantiene los datos embebidos únicamente como fallback local/offline si una petición runtime falla.
- Añade un estado visible de carga dinámica en el panel del mapa.
- Solicita EFFIS bajo demanda con `cache: no-store` y cache-busting.

## v0.6.20 - render siempre fresco y build verificable

- Corrige la causa raíz del HTML obsoleto: elimina `freeze: auto` y fija `freeze: false` en `_quarto.yml`, porque los QMD pueden no cambiar aunque sí cambien AEMET/FIRMS/EFFIS.
- El workflow elimina `_freeze/` y `docs/` antes de cada render, evitando reutilizar una ejecución anterior de Quarto.
- Publica `assets/**` completo como recurso del sitio, en lugar de declarar solo subconjuntos de AEMET y EFFIS.
- Omite del catálogo web las capas AEMET cuya `valid_date` ya es anterior al día actual en `Europe/Madrid`; una emisión de ayer puede seguir siendo válida, pero el selector comienza siempre en hoy o en el siguiente día disponible.
- Añade `assets/site-build.json` con un `build_id` único, fecha de generación, snapshot AEMET, FIRMS y EFFIS.
- Inserta el mismo `build_id` dentro de `docs/index.html` y valida localmente que el HTML y el manifiesto pertenecen al mismo build.
- Añade una comprobación posterior al despliegue: GitHub Actions consulta el `site-build.json` y el `index.html` públicos con cache-busting y solo queda verde si ambos contienen el `build_id` recién generado.
- El navegador comprueba también el manifiesto publicado y, si detecta un HTML antiguo, recarga la página con el identificador del build actual.
- Mantiene la simbología AEMET oficial extraída de `ESCALA`, la protección FIRMS frente a falsos ceros y las ejecuciones de respaldo de v0.6.18.

## v0.6.19 - snapshot canónico, AEMET estricto y FIRMS resiliente

- Hace de `assets/` la fuente canónica del render web y elimina los fallbacks operativos a `data/processed/` en `index.qmd`.
- Añade cache-busting al paquete SIG clásico de AEMET y hasta tres intentos para obtener la emisión del día.
- Registra `assets/aemet/status.json` con fecha de emisión, antigüedad e intentos; aborta si la emisión tiene más de un día.
- Amplía la extracción de simbología AEMET: `ESCALA` vía `gdalinfo -json`, metadatos `terra`, tabla de color interna y ficheros SLD/QML del paquete.
- En GitHub Actions activa `AEMET_REQUIRE_OFFICIAL_STYLE=true`: no se publica una paleta aproximada si no se puede obtener la simbología oficial.
- Publica `assets/firms/firms_active_fires.csv` como snapshot canónico y `assets/firms/status.json` para auditar el estado de la descarga.
- Si FIRMS devuelve vacío o falla, conserva durante un máximo de 72 horas el último snapshot válido y lo marca `stale_preserved`; evita sustituir cientos de detecciones por un falso cero.
- Refuerza `scripts/11_check_published_assets.R` para validar actualidad AEMET, estado FIRMS, fuente oficial de estilo y ausencia de mezclas `data/processed`/`assets` en el render.

## v0.6.18 - respaldo de ejecuciones programadas

- Mantiene las ejecuciones principales a las 04:30 y 12:30 en `Europe/Madrid`.
- Añade ejecuciones de respaldo a las 04:50 y 12:50.
- El job `schedule-gate` consulta las ejecuciones recientes del mismo workflow antes de iniciar el pipeline pesado.
- Un respaldo se omite cuando existe una ejecución programada correcta en los últimos 45 minutos.
- Si la principal fue descartada o terminó con error, el respaldo ejecuta el pipeline completo.
- Las ejecuciones `workflow_dispatch` siempre continúan.
- Si la consulta a la API de GitHub falla, el respaldo se ejecuta por seguridad.
- Añade permiso `actions: read` para consultar el historial del workflow.

## v0.6.17 - simbología AEMET IPIF oficial y clases fijas

- Corrige la conversión de los GeoTIFF AEMET: las clases IPIF se interpretan siempre con su código fijo `1..6` (`Muy bajo` a `Extremo`).
- Elimina la asignación anterior de colores por posición entre los valores presentes, que podía desplazar las clases cuando un nivel no aparecía en un raster.
- Lee preferentemente la simbología oficial desde el metadato `ESCALA` del GeoTIFF y, como segunda opción, desde su tabla de color.
- Mantiene una paleta IPIF de respaldo únicamente si el fichero no expone la simbología, sin alterar nunca la correspondencia numérica entre clase y nivel.
- Los valores ajenos a `1..6` se tratan como transparentes en lugar de desplazar la leyenda.
- Añade `style_source` al catálogo AEMET para poder auditar de dónde procede la simbología de cada capa.
- La leyenda publica siempre las seis clases actuales del IPIF de AEMET.

## v0.6.16 - validación robusta de htmlwidgets

- Corrige un falso positivo en `scripts/11_check_published_assets.R`.
- La validación ya no exige etiquetas HTML literales dentro del JavaScript serializado por `htmlwidgets`.
- Comprueba la lógica publicada mediante identificadores JavaScript estables.
- Verifica por separado en `index.qmd` las etiquetas visibles **Válido**, **Emisión**, **Visor actualizado** y el estado **emisión de ayer · válido para hoy**.
- No cambia la funcionalidad ni la presentación introducida en v0.6.15.

## v0.6.15 - fechas y actualidad de las fuentes

- Añade una marca temporal explícita de generación del visor al panel `Actualidad de datos`.
- Separa en la leyenda AEMET `Válido` y `Emisión`, con día de la semana y fecha completa.
- Hace que el indicador AEMET use la capa seleccionada y distinga fecha de emisión de fecha válida.
- Trata `emisión de ayer · válido para hoy` como estado vigente en lugar de mostrar un aviso de datos atrasados.
- Al navegar a otros horizontes, muestra `válido para mañana` o la fecha válida concreta sin alterar la antigüedad real de la emisión.
- Muestra en los tooltips las fechas y horas exactas del visor, FIRMS y EFFIS en `Europe/Madrid`.
- Mejora el diagnóstico desplegable para mostrar por separado la validez máxima y la emisión AEMET.

## v0.6.14 - despliegue independiente del guardado Git

- Corrige el fallo `cannot rebase: You have unstaged changes` causado por el `docs/` regenerado por Quarto.
- Publica y despliega el artefacto de GitHub Pages inmediatamente después de validar el sitio, antes del commit automático de datos.
- Restaura `docs/` al estado del checkout antes de cualquier `rebase`, ya que el render ya ha quedado capturado en el artefacto de Pages.
- Convierte el guardado automático de `data/processed` y `assets` en una operación *best-effort*: un conflicto Git genera un aviso pero no bloquea una web ya desplegada.
- Mantiene hasta tres intentos de `fetch` + `rebase` + `push`, sin `force push`.
- Añade una comprobación explícita de que no queden cambios rastreados ajenos a los datos antes de hacer `rebase`.

## v0.6.13 - despliegue directo en GitHub Pages

- Corrige la publicación automática: el workflow despliega `docs/` directamente con `actions/upload-pages-artifact@v4` y `actions/deploy-pages@v4`.
- Añade los permisos `pages: write` e `id-token: write` y el entorno `github-pages`.
- Corrige el cron a `30 4,12 * * *` con `timezone: Europe/Madrid`, es decir, 04:30 y 12:30 hora de Madrid.
- Pasa `CARTO_BASEMAP_KEY` al render y detiene el workflow con un error claro si el secret no está configurado.
- Valida que `docs/index.html` contiene el dominio de CARTO tras el render.
- Deja de confirmar `docs/` en los commits automáticos para evitar guardar la URL de teselas con la API key en el historial Git; `data/processed` y `assets` continúan versionados.
- Actualiza `actions/checkout` a v6.

## v0.6.12 - API key de CARTO Basemaps

- Integra `CARTO_BASEMAP_KEY` en la base clara del mapa.
- Sustituye el proveedor anónimo `CartoDB.Positron` por la URL raster Positron con el parámetro `key`.
- Mantiene la atribución obligatoria a OpenStreetMap y CARTO.
- Añade fallback automático a OpenStreetMap cuando la clave no está configurada.
- Añade `CARTO_BASEMAP_KEY` a `.Renviron.example` y al workflow mediante un Repository Secret.
- Escribe las claves CARTO y FIRMS desde variables de entorno en el workflow para evitar expansión accidental en el heredoc.
- Amplía `scripts/11_check_published_assets.R` para detectar el proveedor CARTO anónimo y validar el fallback.

## v0.6.11 - validación CSS robusta

- Corrige el falso positivo de `scripts/11_check_published_assets.R` tras un render real de Quarto.
- Busca las reglas del diseño panorámico tanto en estilos embebidos como en las hojas CSS enlazadas.
- Tolera la compilación y minificación de CSS realizada por Quarto, sin depender de comentarios ni espacios literales.
- Comprueba de forma independiente `page-layout: full`, la altura `88vh`, el selector de la página Mapa y la regla de ancho completo.
- Mantiene la detección del índice lateral para evitar que vuelva a desperdiciarse ancho útil.
- No modifica el pipeline de datos, el mapa ni el horario del workflow.

## v0.6.10 - mapa panorámico

- Desactiva el índice de contenidos en `index.qmd` para recuperar la columna derecha reservada por Quarto.
- Extiende el contenido del mapa desde `screen-start-inset` hasta `screen-end-inset` en pantallas de escritorio.
- Aumenta la altura del widget Leaflet de `84vh` a `88vh` y eleva sus alturas mínimas adaptativas.
- Compacta el bloque de título y el encabezado de la sección Mapa.
- Mueve el bloque desplegable de fuentes y diagnóstico debajo del mapa para que el visor aparezca antes.
- Añade un acabado visual discreto al mapa mediante borde, sombra y esquinas redondeadas.
- Conserva el flujo normal en móvil y limita de forma adaptativa la altura del panel territorial.
- Añade comprobaciones de publicación para impedir que vuelva a aparecer el TOC lateral o se pierda el diseño panorámico.

## v0.6.9 - panel territorial interactivo

- Añade un panel lateral al pulsar sobre límites NUTS2 o NUTS3.
- Mantiene las comunidades autónomas visibles por defecto y conserva las provincias como capa opcional.
- Publica resúmenes FIRMS completos para 6, 12, 24 y 48 horas, con FRP total, media y máxima.
- Incorpora recuentos y superficie EFFIS de los últimos 30 y 90 días por territorio.
- Calcula puntos interiores representativos para las 19 CCAA y 59 provincias.
- Estima en el navegador el nivel AEMET del territorio seleccionado mediante muestreo del PNG georreferenciado y comparación con la leyenda oficial de colores.
- Actualiza el valor AEMET del panel cuando cambia la fecha, el área o el producto seleccionado.
- Añade selección visual, cierre del panel y botón para centrar y ampliar el territorio.
- Genera `territorial_summary.json` y sus versiones CSV en `data/processed` y `assets/summary`.
- Reordena `scripts/99_run_all.R` para actualizar EFFIS antes de construir el resumen territorial.

## v0.6.8 - navegación temporal y actualidad de datos

- Añade botones anterior y siguiente para recorrer los días AEMET dentro de la misma área, tipo de producto y emisión.
- Incorpora reproducción automática de la secuencia temporal, con pausa y repetición circular de los ocho horizontes.
- Sincroniza el selector, la leyenda, la posición temporal y los controles al cambiar de capa.
- Evita resultados asíncronos obsoletos al cambiar rápidamente entre capas GeoJSON.
- Añade un indicador visible de actualidad para AEMET, NASA FIRMS y EFFIS.
- Clasifica la actualidad mediante estados verde, ámbar, rojo y no disponible, calculados en el navegador y actualizados cada minuto.
- Muestra la fecha u hora exacta de cada fuente al situar el cursor sobre el indicador.
- Amplía los estilos adaptativos del panel para escritorio y dispositivos móviles.

## v0.6.7 - día de la semana en AEMET

- Añade el día de la semana y la fecha completa en español a las opciones del selector AEMET.
- Muestra en la leyenda activa la fecha válida, el horizonte, el área y el tipo de producto seleccionado.
- Interpreta las fechas `YYYY-MM-DD` en UTC para evitar desplazamientos de un día provocados por la zona horaria del navegador.
- Escapa los textos incorporados a la leyenda antes de generar HTML.
- Mantiene la actualización dinámica de la cabecera al cambiar de capa AEMET.
- Amplía el selector para acomodar las fechas completas sin perjudicar la visualización móvil.

## v0.6.6 - normalización robusta de NASA FIRMS

- Corrige el fallo de `purrr::map_dfr()` al combinar una respuesta FIRMS vacía, con `latitude` inferida como texto, y otra respuesta con detecciones numéricas.
- Lee inicialmente todas las columnas CSV de FIRMS como texto y aplica después un esquema canónico explícito.
- Convierte coordenadas, temperaturas, FRP, `scan` y `track` a tipos numéricos de forma controlada.
- Excluye del `bind_rows()` las respuestas sin detecciones y genera salidas vacías con cabeceras y tipos estables.
- Añade al log el número de detecciones válidas obtenido para cada sensor FIRMS.
- Actualiza los identificadores de versión del pipeline y los agentes HTTP a 0.6.6.

## v0.6.5 - horario de Madrid y control de concurrencia

- Programa el workflow a las 04:30 y 12:30 usando la zona IANA `Europe/Madrid`.
- Evita tener que cambiar manualmente el cron al comenzar o terminar el horario de verano.
- Corrige el rechazo `fetch first` cuando aparece un commit remoto durante la ejecución.
- Añade `fetch`, `rebase` seguro y hasta tres reintentos antes del `push`.
- Mantiene prohibido el `force push` para no sobrescribir cambios del usuario.

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
