message("1/8 Descargando capas AEMET")
source("scripts/01_download_aemet_incendios.R", encoding = "UTF-8")

message("2/8 Descargando focos activos NASA FIRMS")
source("scripts/05_download_firms_active_fires.R", encoding = "UTF-8")

message("3/8 Descargando límites administrativos GISCO/NUTS")
source("scripts/06_download_admin_boundaries.R", encoding = "UTF-8")

message("4/8 Preparando assets web AEMET")
source("scripts/02_prepare_web_assets.R", encoding = "UTF-8")

message("5/8 Preparando assets EFFIS")
source("scripts/26_prepare_effis_assets.R", encoding = "UTF-8")

message("6/8 Construyendo resumen operativo")
source("scripts/07_build_operational_summary.R", encoding = "UTF-8")

message("7/8 Construyendo alertas operativas")
source("scripts/08_build_operational_alerts.R", encoding = "UTF-8")

message("8/8 Actualizando histórico del dashboard")
source("scripts/09_update_dashboard_history.R", encoding = "UTF-8")
