#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")

message("1/6 Descargando productos de AEMET")
source("scripts/01_download_aemet_incendios.R", encoding = "UTF-8")

message("2/6 Descargando focos activos NASA FIRMS")
source("scripts/05_download_firms_active_fires.R", encoding = "UTF-8")

message("3/6 Descargando límites administrativos GISCO/NUTS")
source("scripts/06_download_admin_boundaries.R", encoding = "UTF-8")

message("4/6 Preparando assets web AEMET")
source("scripts/02_prepare_web_assets.R", encoding = "UTF-8")

message("5/6 Construyendo resumen operativo")
source("scripts/07_build_operational_summary.R", encoding = "UTF-8")

message("6/6 Construyendo alertas operativas")
source("scripts/08_build_operational_alerts.R", encoding = "UTF-8")
