#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")

message("1/3 Descargando productos de AEMET")
source("scripts/01_download_aemet_incendios.R", encoding = "UTF-8")

message("2/3 Descargando focos activos NASA FIRMS")
source("scripts/05_download_firms_active_fires.R", encoding = "UTF-8")

message("3/3 Preparando assets web AEMET")
source("scripts/02_prepare_web_assets.R", encoding = "UTF-8")
