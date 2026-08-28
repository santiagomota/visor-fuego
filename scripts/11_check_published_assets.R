#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")
check_required_packages(c("jsonlite", "fs"))

failures <- character()
warnings <- character()

fail <- function(message) failures <<- c(failures, message)
warn <- function(message) warnings <<- c(warnings, message)

required_pages <- c(
  "docs/index.html",
  "docs/summary.html",
  "docs/report.html",
  "docs/history.html",
  "docs/copernicus.html"
)

for (path in required_pages) {
  if (!file.exists(path) || file.info(path)$size <= 0) {
    fail(paste("Página ausente o vacía:", path))
  }
}

layers_path <- "assets/aemet/layers.json"
if (!file.exists(layers_path) || file.info(layers_path)$size <= 2) {
  fail(paste("Catálogo AEMET ausente o vacío:", layers_path))
} else {
  layers <- jsonlite::fromJSON(layers_path, simplifyVector = TRUE)
  if (!is.data.frame(layers) || nrow(layers) == 0) {
    fail("El catálogo AEMET no contiene capas")
  } else if (!"url" %in% names(layers)) {
    fail("El catálogo AEMET no contiene la columna url")
  } else {
    source_paths <- as.character(layers$url)
    published_paths <- file.path("docs", source_paths)
    missing_source <- source_paths[!file.exists(source_paths)]
    missing_published <- published_paths[!file.exists(published_paths)]

    if (length(missing_source) > 0) {
      fail(paste("Assets AEMET ausentes en el árbol fuente:", paste(missing_source, collapse = ", ")))
    }
    if (length(missing_published) > 0) {
      fail(paste("Assets AEMET ausentes en docs/:", paste(missing_published, collapse = ", ")))
    }

    expected_aemet_labels <- c("Muy bajo", "Bajo", "Moderado", "Alto", "Muy alto", "Extremo")
    if (!"legend_labels" %in% names(layers)) {
      fail("El catálogo AEMET no contiene legend_labels")
    } else {
      bad_legend <- vapply(seq_len(nrow(layers)), function(i) {
        ll <- layers$legend_labels
        labels <- if (is.matrix(ll) || is.data.frame(ll)) {
          as.character(ll[i, , drop = TRUE])
        } else if (is.list(ll)) {
          as.character(unlist(ll[[i]], use.names = FALSE))
        } else {
          as.character(ll[[i]])
        }
        !identical(unname(labels), expected_aemet_labels)
      }, logical(1))
      if (any(bad_legend)) {
        fail(paste(
          "Hay capas AEMET cuya leyenda no conserva las seis clases IPIF 1..6:",
          paste(as.character(layers$layer_id[bad_legend]), collapse = ", ")
        ))
      }
    }

    if (!"style_source" %in% names(layers)) {
      fail("El catálogo AEMET no informa style_source; no se puede auditar la simbología")
    } else {
      style_sources <- unique(as.character(layers$style_source))
      message("AEMET: fuentes de simbología: ", paste(style_sources, collapse = ", "))
      if (all(grepl("fallback", style_sources, ignore.case = TRUE))) {
        warn("Todas las capas AEMET usan la paleta de respaldo; revisar lectura de ESCALA/colortable")
      }
    }
  }
}

effis_summary_path <- "assets/effis_ba/summary.json"
if (file.exists(effis_summary_path) && file.info(effis_summary_path)$size > 2) {
  effis_summary <- jsonlite::fromJSON(effis_summary_path, simplifyVector = TRUE)
  n_features <- suppressWarnings(as.integer(effis_summary$n_features %||% 0L))
  if (!is.na(n_features) && n_features > 0) {
    effis_source <- "assets/effis_ba/effis_burnt_areas.geojson"
    effis_published <- file.path("docs", effis_source)
    if (!file.exists(effis_source) || file.info(effis_source)$size <= 30) {
      fail(paste("GeoJSON EFFIS fuente ausente o vacío:", effis_source))
    }
    if (!file.exists(effis_published) || file.info(effis_published)$size <= 30) {
      fail(paste("GeoJSON EFFIS publicado ausente o vacío:", effis_published))
    }
  }
}

territorial_paths <- c(
  "data/processed/territorial_summary.json",
  "assets/summary/territorial_summary.json"
)
for (path in territorial_paths) {
  if (!file.exists(path) || file.info(path)$size <= 20) {
    fail(paste("Resumen territorial ausente o vacío:", path))
  }
}

territorial <- NULL
if (file.exists("assets/summary/territorial_summary.json")) {
  territorial <- tryCatch(
    jsonlite::fromJSON("assets/summary/territorial_summary.json", simplifyVector = TRUE),
    error = function(e) {
      fail(paste("No se puede leer el resumen territorial:", conditionMessage(e)))
      NULL
    }
  )
}

if (!is.null(territorial)) {
  ccaa <- territorial$ccaa %||% data.frame()
  provincias <- territorial$provincias %||% data.frame()

  if (!is.data.frame(ccaa) || nrow(ccaa) != 19) {
    fail(paste("El resumen territorial debe contener 19 unidades NUTS2; contiene", nrow(ccaa)))
  }
  if (!is.data.frame(provincias) || nrow(provincias) != 59) {
    fail(paste("El resumen territorial debe contener 59 unidades NUTS3; contiene", nrow(provincias)))
  }

  required_fields <- c(
    "admin_level", "admin_id", "admin_name",
    "representative_lon", "representative_lat",
    "n_ultimas_6h", "n_ultimas_12h", "n_ultimas_24h", "n_ultimas_48h",
    "frp_media_mw", "frp_max_mw",
    "n_effis_30d", "effis_area_ha_30d",
    "n_effis_90d", "effis_area_ha_90d"
  )

  for (label in c("ccaa", "provincias")) {
    data <- territorial[[label]]
    missing_fields <- setdiff(required_fields, names(data))
    if (length(missing_fields) > 0) {
      fail(paste(
        "Faltan campos en el resumen territorial de", label, ":",
        paste(missing_fields, collapse = ", ")
      ))
    }
  }
}

if (file.exists("docs/index.html")) {
  index_html <- paste(readLines("docs/index.html", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  # Validar el comportamiento publicado mediante identificadores estables.
  # htmlwidgets serializa el JavaScript dentro de JSON y puede escapar '<' y '>'
  # como secuencias Unicode, por lo que no debemos exigir etiquetas HTML
  # literales como <strong>...</strong> en docs/index.html.
  required_fragments <- c(
    "Consulta territorial",
    "territory-panel",
    "n_ultimas_12h",
    "effis_area_ha_90d",
    "Centrar y ampliar",
    "data-freshness",
    "fire-legend-context",
    "formatMadridTimestamp",
    "validDateRelation",
    "aemetTitle"
  )

  missing_fragments <- required_fragments[!vapply(
    required_fragments,
    function(fragment) grepl(fragment, index_html, fixed = TRUE),
    logical(1)
  )]

  if (length(missing_fragments) > 0) {
    fail(paste(
      "El HTML principal no contiene la lógica esperada del panel y la actualidad:",
      paste(missing_fragments, collapse = ", ")
    ))
  }

  # Los textos visibles sí se verifican en la fuente QMD, donde no interviene
  # la serialización JSON de htmlwidgets.
  if (!file.exists("index.qmd")) {
    fail("No existe index.qmd para validar las etiquetas temporales de AEMET")
  } else {
    index_qmd <- paste(readLines("index.qmd", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    source_fragments <- c(
      "<strong>Válido:</strong>",
      "<strong>Emisión:</strong>",
      "Visor actualizado:",
      "emisión de ayer · válido para hoy"
    )
    missing_source_fragments <- source_fragments[!vapply(
      source_fragments,
      function(fragment) grepl(fragment, index_qmd, fixed = TRUE),
      logical(1)
    )]

    if (length(missing_source_fragments) > 0) {
      fail(paste(
        "index.qmd no contiene las etiquetas temporales esperadas:",
        paste(missing_source_fragments, collapse = ", ")
      ))
    }
  }

  if (grepl("__TERRITORIAL_DATA__", index_html, fixed = TRUE)) {
    fail("El token __TERRITORIAL_DATA__ no fue sustituido en docs/index.html")
  }


  carto_key <- trimws(Sys.getenv("CARTO_BASEMAP_KEY", unset = ""))
  if (nzchar(carto_key)) {
    if (!grepl("basemaps.cartocdn.com/light_all", index_html, fixed = TRUE)) {
      fail("CARTO_BASEMAP_KEY está definida pero el HTML no usa el basemap CARTO Positron")
    }
    if (!grepl("?key=", index_html, fixed = TRUE)) {
      fail("El basemap CARTO publicado no contiene el parámetro key")
    }
    if (grepl("CartoDB.Positron", index_html, fixed = TRUE)) {
      fail("El HTML sigue usando el proveedor CARTO anónimo antiguo")
    }
  } else {
    if (!grepl("tile.openstreetmap.org", index_html, fixed = TRUE) &&
        !grepl("OpenStreetMap.Mapnik", index_html, fixed = TRUE)) {
      fail("Sin CARTO_BASEMAP_KEY el HTML debe utilizar el fallback OpenStreetMap")
    }
    warn("CARTO_BASEMAP_KEY no está definida; se ha publicado el fallback OpenStreetMap")
  }

  # Quarto puede dejar el CSS personalizado embebido en el HTML o
  # compilarlo/minificarlo dentro de una hoja enlazada. La validación debe
  # aceptar ambos resultados y no depender de comentarios ni espacios.
  css_tags <- regmatches(
    index_html,
    gregexpr(
      "<link[^>]+href=[\"'][^\"']+\\.css(?:\\?[^\"']*)?[\"']",
      index_html,
      perl = TRUE,
      ignore.case = TRUE
    )
  )[[1]]

  css_hrefs <- if (length(css_tags) > 0 && !identical(css_tags, character(0))) {
    sub(".*href=[\"']([^\"']+)[\"'].*", "\\1", css_tags, perl = TRUE)
  } else {
    character()
  }

  css_hrefs <- sub("[?#].*$", "", css_hrefs)
  css_hrefs <- css_hrefs[!grepl("^(https?:)?//", css_hrefs, ignore.case = TRUE)]
  css_paths <- unique(file.path("docs", sub("^\\./", "", css_hrefs)))
  css_paths <- css_paths[file.exists(css_paths)]

  published_css <- if (length(css_paths) > 0) {
    paste(vapply(
      css_paths,
      function(path) paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
      character(1)
    ), collapse = "\n")
  } else {
    ""
  }

  layout_text <- paste(index_html, published_css, sep = "\n")
  layout_compact <- gsub("[[:space:]]+", "", layout_text)

  if (!grepl("page-layout-full", index_html, fixed = TRUE)) {
    fail("La página Mapa no se ha publicado con page-layout: full")
  }
  if (!grepl("height:88vh", layout_compact, fixed = TRUE)) {
    fail("El mapa publicado no conserva la altura panorámica de 88vh")
  }
  if (!grepl("body:has(section#mapa)", layout_compact, fixed = TRUE)) {
    fail("No se encuentra el selector CSS panorámico de la página Mapa")
  }
  if (!grepl(
    "grid-column:screen-start-inset/screen-end-inset",
    layout_compact,
    fixed = TRUE
  )) {
    fail("No se encuentra la regla CSS que amplía el mapa a todo el ancho útil")
  }

  if (grepl('id="TOC"', index_html, fixed = TRUE)) {
    fail("La página Mapa vuelve a contener un índice lateral y desperdicia ancho útil")
  }
}

index_size_mb <- if (file.exists("docs/index.html")) file.info("docs/index.html")$size / 1024^2 else NA_real_
if (!is.na(index_size_mb) && index_size_mb > 12) {
  fail(sprintf("docs/index.html pesa %.1f MB; EFFIS puede haberse incrustado por error", index_size_mb))
} else if (!is.na(index_size_mb) && index_size_mb > 8) {
  warn(sprintf("docs/index.html pesa %.1f MB", index_size_mb))
}

if (length(warnings) > 0) {
  for (message in warnings) cat("AVISO:", message, "\n")
}

if (length(failures) > 0) {
  cat("\nValidación fallida:\n")
  for (message in failures) cat("-", message, "\n")
  quit(status = 1)
}

cat("Sitio validado correctamente.\n")
cat("Páginas:", length(required_pages), "\n")
if (!is.null(territorial)) {
  cat("Territorios: CCAA=", nrow(territorial$ccaa), "; provincias=", nrow(territorial$provincias), "\n", sep = "")
}
if (!is.na(index_size_mb)) cat(sprintf("Tamaño docs/index.html: %.2f MB\n", index_size_mb))
