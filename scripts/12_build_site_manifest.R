#!/usr/bin/env Rscript

source("R/site_build.R", encoding = "UTF-8")
check_required_packages(c("jsonlite", "fs"))
write_site_build_manifest("assets/site-build.json")
