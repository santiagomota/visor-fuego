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
  required_fragments <- c(
    "Consulta territorial",
    "territory-panel",
    "n_ultimas_12h",
    "effis_area_ha_90d",
    "Centrar y ampliar"
  )

  missing_fragments <- required_fragments[!vapply(
    required_fragments,
    function(fragment) grepl(fragment, index_html, fixed = TRUE),
    logical(1)
  )]

  if (length(missing_fragments) > 0) {
    fail(paste(
      "El HTML principal no contiene elementos del panel territorial:",
      paste(missing_fragments, collapse = ", ")
    ))
  }

  if (grepl("__TERRITORIAL_DATA__", index_html, fixed = TRUE)) {
    fail("El token __TERRITORIAL_DATA__ no fue sustituido en docs/index.html")
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
