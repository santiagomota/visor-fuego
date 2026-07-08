#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")
source("R/firms.R", encoding = "UTF-8")

check_required_packages(c(
  "curl", "dplyr", "fs", "jsonlite", "purrr", "readr", "tibble"
))

download_firms_active_fires()
