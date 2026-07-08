#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")
source("R/aemet_classic.R", encoding = "UTF-8")

check_required_packages(c("readr", "dplyr", "purrr", "stringr", "tibble", "fs"))

contents_csv <- Sys.getenv(
  "AEMET_CLASSIC_CONTENTS_CSV",
  unset = "data/raw/aemet_classic_probe/classic_archive_contents.csv"
)
preferred_label <- Sys.getenv("AEMET_CLASSIC_PREFERRED_LABEL", unset = "direct_1")

install_classic_probe_geotiffs(
  contents_csv = contents_csv,
  preferred_label = preferred_label,
  raw_dir = "data/raw/aemet"
)
