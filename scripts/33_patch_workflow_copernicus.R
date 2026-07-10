#!/usr/bin/env Rscript
# Inserta Copernicus/EFFIS Burnt Areas en update-dashboard.yml como paso tolerante.

file <- ".github/workflows/update-dashboard.yml"
if (!file.exists(file)) stop("No existe .github/workflows/update-dashboard.yml", call. = FALSE)

x <- readLines(file, warn = FALSE, encoding = "UTF-8")
if (any(grepl("29_download_effis_burnt_areas", x, fixed = TRUE))) {
  message("El workflow ya contiene EFFIS Burnt Areas")
  quit(status = 0)
}

insert <- c(
  "          # Copernicus/EFFIS Burnt Areas: tolerante en v0.6.0-alpha.",
  "          Rscript scripts/29_download_effis_burnt_areas.R || echo 'Aviso: falló descarga EFFIS Burnt Areas'",
  "          Rscript scripts/30_prepare_effis_burnt_areas_assets.R || echo 'Aviso: falló preparación EFFIS Burnt Areas'"
)

# Inserta tras FIRMS si existe; si no, antes de render/fin del bloque run.
idx <- grep("05_download_firms_active_fires\\.R", x)
if (length(idx) == 0) idx <- grep("24_check_aemet_valid_dates\\.R", x)
if (length(idx) == 0) idx <- grep("quarto render", x)
if (length(idx) == 0) stop("No se encontró punto de inserción en el workflow", call. = FALSE)

x <- append(x, insert, after = idx[1])

# Asegura variables por defecto en .Renviron creado por workflow.
if (!any(grepl("EFFIS_BA_ENABLE", x, fixed = TRUE))) {
  env_idx <- grep("EFFIS_RENDER_MODE=", x)
  if (length(env_idx) == 0) env_idx <- grep("FIRMS_MAP_KEY=", x)
  ba_env <- c(
    "          EFFIS_BA_ENABLE=true",
    "          EFFIS_BA_BBOX=-19,27,5,44.6",
    "          EFFIS_BA_MAX_DAYS=365",
    "          EFFIS_BA_MIN_AREA_HA=0"
  )
  if (length(env_idx) > 0) x <- append(x, ba_env, after = env_idx[1])
}

# Asegura que assets/effis_ba entra en git add.
git_add_idx <- grep("git add .*assets", x)
if (length(git_add_idx) > 0 && !grepl("assets/effis_ba", x[git_add_idx[1]], fixed = TRUE)) {
  x[git_add_idx[1]] <- sub("assets/effis", "assets/effis_ba assets/effis", x[git_add_idx[1]], fixed = TRUE)
  if (identical(x[git_add_idx[1]], sub("assets/effis", "assets/effis_ba assets/effis", x[git_add_idx[1]], fixed = TRUE))) {
    x[git_add_idx[1]] <- sub("assets/aemet", "assets/aemet assets/effis_ba", x[git_add_idx[1]], fixed = TRUE)
  }
}

writeLines(x, file, useBytes = TRUE)
message("Workflow actualizado con EFFIS Burnt Areas")
