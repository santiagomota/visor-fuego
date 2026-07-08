#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")

message("1/5 Descargando productos de AEMET")
source("scripts/01_download_aemet_incendios.R", encoding = "UTF-8")

message("2/5 Descargando focos activos NASA FIRMS")
source("scripts/05_download_firms_active_fires.R", encoding = "UTF-8")

message("3/5 Descargando límites administrativos GISCO/NUTS")
source("scripts/06_download_admin_boundaries.R", encoding = "UTF-8")

message("4/5 Preparando assets web AEMET")
source("scripts/02_prepare_web_assets.R", encoding = "UTF-8")

message("5/5 Construyendo resumen operativo")
source("scripts/07_build_operational_summary.R", encoding = "UTF-8")
