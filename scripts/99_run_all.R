#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")

is_true <- function(name, default = FALSE) {
  value <- tolower(trimws(Sys.getenv(name, unset = if (isTRUE(default)) "true" else "false")))
  value %in% c("1", "true", "yes", "y", "si", "sí", "on")
}

run_script <- function(number, total, label, path, optional = FALSE) {
  message(sprintf("%d/%d %s", number, total, label))
  tryCatch(
    {
      source(path, local = new.env(parent = globalenv()), encoding = "UTF-8", chdir = FALSE)
      invisible(TRUE)
    },
    error = function(e) {
      if (isTRUE(optional)) {
        warning(label, ": ", conditionMessage(e), call. = FALSE)
        return(invisible(FALSE))
      }
      stop(label, ": ", conditionMessage(e), call. = FALSE)
    }
  )
}

admin_files <- c(
  "data/processed/admin_nuts2_ccaa.geojson",
  "data/processed/admin_nuts3_provincias.geojson"
)
update_admin <- is_true("UPDATE_ADMIN_BOUNDARIES", FALSE) || !all(file.exists(admin_files))
effis_optional <- is_true("EFFIS_BA_OPTIONAL", TRUE)

total <- 11L
run_script(1, total, "Descargando capas AEMET", "scripts/01_download_aemet_incendios.R")
run_script(2, total, "Preparando assets web AEMET", "scripts/02_prepare_web_assets.R")
run_script(3, total, "Descargando focos activos NASA FIRMS", "scripts/05_download_firms_active_fires.R")

if (update_admin) {
  run_script(4, total, "Descargando límites administrativos GISCO/NUTS", "scripts/06_download_admin_boundaries.R")
} else {
  message("4/11 Límites administrativos ya disponibles; se omite la descarga")
}

# EFFIS se actualiza antes del resumen territorial para que las superficies
# mostradas en el panel correspondan a la misma ejecución del workflow.
run_script(5, total, "Descargando EFFIS Burnt Areas", "scripts/29_download_effis_burnt_areas.R", optional = effis_optional)
run_script(6, total, "Preparando EFFIS Burnt Areas", "scripts/30_prepare_effis_burnt_areas_assets.R", optional = effis_optional)
run_script(7, total, "Construyendo resumen operativo y territorial", "scripts/07_build_operational_summary.R")
run_script(8, total, "Construyendo alertas operativas", "scripts/08_build_operational_alerts.R")
run_script(9, total, "Actualizando histórico del dashboard", "scripts/09_update_dashboard_history.R")
run_script(10, total, "Comprobando entradas del dashboard", "scripts/04_check_dashboard_inputs.R")
run_script(11, total, "Validando fechas AEMET", "scripts/24_check_aemet_valid_dates.R")

message("Pipeline v0.6.9 completado")
