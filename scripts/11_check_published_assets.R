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

# Manifiesto único de build: permite detectar un render congelado aunque los
# assets se hayan actualizado correctamente.
site_build_source_path <- "assets/site-build.json"
site_build_published_path <- "docs/assets/site-build.json"
site_build <- NULL

if (!file.exists(site_build_source_path) || file.info(site_build_source_path)$size <= 2) {
  fail(paste("Manifiesto de build ausente:", site_build_source_path))
} else {
  site_build <- tryCatch(
    jsonlite::fromJSON(site_build_source_path, simplifyVector = TRUE),
    error = function(e) {
      fail(paste("No se puede leer", site_build_source_path, ":", conditionMessage(e)))
      NULL
    }
  )
}

if (!file.exists(site_build_published_path) || file.info(site_build_published_path)$size <= 2) {
  fail(paste("Manifiesto de build no publicado por Quarto:", site_build_published_path))
} else if (!is.null(site_build)) {
  site_build_published <- tryCatch(
    jsonlite::fromJSON(site_build_published_path, simplifyVector = TRUE),
    error = function(e) {
      fail(paste("No se puede leer", site_build_published_path, ":", conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(site_build_published)) {
    source_id <- as.character(site_build$build_id %||% "")
    published_id <- as.character(site_build_published$build_id %||% "")
    if (!nzchar(source_id)) fail("assets/site-build.json no contiene build_id")
    if (!identical(source_id, published_id)) {
      fail(paste("El manifiesto publicado no corresponde al build actual:", published_id, "!=", source_id))
    }
  }
}

if (!is.null(site_build)) {
  today_madrid <- format(Sys.time(), tz = "Europe/Madrid", format = "%Y-%m-%d")
  build_date <- as.character(site_build$generated_date_madrid %||% "")
  require_today <- tolower(trimws(Sys.getenv("SITE_BUILD_REQUIRE_TODAY", unset = "true"))) %in%
    c("1", "true", "yes", "y", "si", "sí", "on")
  if (require_today && nzchar(build_date) && !identical(build_date, today_madrid)) {
    fail(paste("El build fue generado el", build_date, "pero hoy en Madrid es", today_madrid))
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
      fallback_layers <- grepl("fallback", as.character(layers$style_source), ignore.case = TRUE)
      require_official <- tolower(trimws(Sys.getenv("AEMET_REQUIRE_OFFICIAL_STYLE", unset = "false"))) %in%
        c("1", "true", "yes", "y", "si", "sí", "on")
      if (any(fallback_layers)) {
        msg <- paste(
          "Hay capas AEMET con simbología de respaldo:",
          paste(as.character(layers$layer_id[fallback_layers]), collapse = ", ")
        )
        if (require_official) fail(msg) else warn(msg)
      }
    }
  }
}

aemet_status_path <- "assets/aemet/status.json"
if (!file.exists(aemet_status_path) || file.info(aemet_status_path)$size <= 2) {
  fail(paste("Estado de descarga AEMET ausente:", aemet_status_path))
} else {
  aemet_status <- tryCatch(
    jsonlite::fromJSON(aemet_status_path, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (is.null(aemet_status)) {
    fail("No se puede leer assets/aemet/status.json")
  } else {
    issue_age <- suppressWarnings(as.integer(aemet_status$issue_age_days %||% NA_integer_))
    message(
      "AEMET: emisión ", aemet_status$issue_date %||% "s/d",
      " · estado ", aemet_status$freshness %||% "s/d",
      " · intentos ", aemet_status$attempts %||% "s/d"
    )
    if (!is.na(issue_age) && issue_age > 1L) {
      fail(paste("La emisión AEMET tiene", issue_age, "días de antigüedad; máximo operativo: 1"))
    }
  }
}

# En el sitio operativo no se publican fechas AEMET ya pasadas. Esto evita que
# una emisión de ayer empiece el selector por D00 cuando ese día ya terminó.
if (exists("layers") && is.data.frame(layers) && nrow(layers) > 0 && "valid_date" %in% names(layers)) {
  hide_past <- tolower(trimws(Sys.getenv("AEMET_HIDE_PAST_VALID_DATES", unset = "true"))) %in%
    c("1", "true", "yes", "y", "si", "sí", "on")
  if (hide_past) {
    today_madrid_date <- as.Date(format(Sys.time(), tz = "Europe/Madrid", format = "%Y-%m-%d"))
    valid_dates <- suppressWarnings(as.Date(layers$valid_date))
    past_layers <- !is.na(valid_dates) & valid_dates < today_madrid_date
    if (any(past_layers)) {
      fail(paste(
        "El catálogo AEMET contiene fechas válidas pasadas:",
        paste(unique(as.character(valid_dates[past_layers])), collapse = ", ")
      ))
    }
  }
}

firms_csv_path <- "assets/firms/firms_active_fires.csv"
if (!file.exists(firms_csv_path) || file.info(firms_csv_path)$size <= 0) {
  fail(paste("Snapshot FIRMS canónico ausente:", firms_csv_path))
}
firms_status_path <- "assets/firms/status.json"
if (!file.exists(firms_status_path) || file.info(firms_status_path)$size <= 2) {
  fail(paste("Estado FIRMS ausente:", firms_status_path))
} else {
  firms_status <- tryCatch(jsonlite::fromJSON(firms_status_path, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(firms_status)) {
    fail("No se puede leer assets/firms/status.json")
  } else {
    message(
      "FIRMS: estado ", firms_status$download_status %||% "s/d",
      " · detecciones ", firms_status$n_detections %||% "s/d",
      " · última observación ", firms_status$last_observation_utc %||% "s/d"
    )
    if (identical(as.character(firms_status$download_status %||% ""), "stale_preserved")) {
      warn("FIRMS ha conservado el último snapshot válido porque la descarga actual no fue utilizable")
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

# Ninguna página publicada debe mezclar productos operativos intermedios con
# el snapshot canónico de assets/. Los límites estáticos también se sirven desde
# assets/admin en la página principal.
render_sources <- c("index.qmd", "summary.qmd", "report.qmd", "history.qmd", "copernicus.qmd", "R/page_helpers.R")
for (source_file in render_sources) {
  if (!file.exists(source_file)) next
  source_txt <- paste(readLines(source_file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  # Se permiten menciones explicativas de data/processed, pero no rutas de lectura
  # entre comillas que puedan ser consumidas por el render.
  if (grepl('["\']data/processed/', source_txt, perl = TRUE)) {
    fail(paste("El render sigue leyendo data/processed en", source_file, "; debe usar assets/ como snapshot canónico"))
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
    "aemetTitle",
    "verifyPublishedBuild",
    "loadRuntimeData",
    "fetchJsonNoStore",
    "applyRuntimeAemetLayers",
    "applyRuntimeFirmsGeoJson",
    "runtime-source-status",
    "assets/aemet/layers.json",
    "assets/firms/firms_active_fires.geojson",
    "assets/firms/status.json",
    "assets/alerts/operational_alerts.geojson",
    "assets/summary/territorial_summary.json",
    "assets/site-build.json"
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
      "emisión de ayer · válido para hoy",
      "assets/aemet/layers.json",
      "assets/firms/firms_active_fires.geojson",
      "assets/firms/status.json",
      "assets/alerts/operational_alerts.geojson",
      "assets/summary/territorial_summary.json",
      "assets/site-build.json",
      "fetchJsonNoStore",
      "cache: 'no-store'",
      "loadRuntimeData",
      "applyRuntimeFirmsGeoJson",
      "__SITE_BUILD__"
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

    forbidden_operational_sources <- c(
      "data/processed/layers.json",
      "data/processed/firms_active_fires.csv",
      "data/processed/dashboard_summary.csv",
      "data/processed/firms_summary_ccaa.csv",
      "data/processed/firms_summary_provincias.csv",
      "data/processed/territorial_summary.json",
      "data/processed/operational_alerts.csv",
      "data/processed/operational_alerts_summary.csv",
      "data/processed/effis_burnt_areas_summary.csv"
    )
    leaked_sources <- forbidden_operational_sources[vapply(
      forbidden_operational_sources,
      function(fragment) grepl(fragment, index_qmd, fixed = TRUE),
      logical(1)
    )]
    if (length(leaked_sources) > 0) {
      fail(paste(
        "index.qmd vuelve a mezclar data/processed con el snapshot canónico assets/:",
        paste(leaked_sources, collapse = ", ")
      ))
    }

    if (grepl("addCircleMarkers\\(\\s*data\\s*=\\s*firms_data", index_qmd, perl = TRUE)) {
      fail("index.qmd vuelve a incrustar FIRMS en el HTML; debe cargarlos en vivo desde assets/firms/firms_active_fires.geojson")
    }

    if (grepl("addCircleMarkers\\(\\s*data\\s*=\\s*alerts_data", index_qmd, perl = TRUE)) {
      fail("index.qmd vuelve a incrustar alertas FIRMS en el HTML; deben cargarse en vivo desde assets/alerts/operational_alerts.geojson")
    }
  }

  if (grepl("__TERRITORIAL_DATA__", index_html, fixed = TRUE)) {
    fail("El token __TERRITORIAL_DATA__ no fue sustituido en docs/index.html")
  }
  if (grepl("__SITE_BUILD__", index_html, fixed = TRUE)) {
    fail("El token __SITE_BUILD__ no fue sustituido en docs/index.html")
  }
  if (!is.null(site_build)) {
    expected_build_id <- as.character(site_build$build_id %||% "")
    if (nzchar(expected_build_id) && !grepl(expected_build_id, index_html, fixed = TRUE)) {
      fail(paste(
        "docs/index.html no contiene el build_id actual", expected_build_id,
        "; el render puede haberse reutilizado desde _freeze"
      ))
    }
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
if (!is.null(site_build)) cat("Build:", as.character(site_build$build_id %||% "s/d"), "\n")
cat("Páginas:", length(required_pages), "\n")
if (!is.null(territorial)) {
  cat("Territorios: CCAA=", nrow(territorial$ccaa), "; provincias=", nrow(territorial$provincias), "\n", sep = "")
}
if (!is.na(index_size_mb)) cat(sprintf("Tamaño docs/index.html: %.2f MB\n", index_size_mb))
