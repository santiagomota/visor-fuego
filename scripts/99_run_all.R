#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")

message("1/2 Descargando productos de AEMET")
source("scripts/01_download_aemet_incendios.R", encoding = "UTF-8")

message("2/2 Preparando assets web")
source("scripts/02_prepare_web_assets.R", encoding = "UTF-8")
