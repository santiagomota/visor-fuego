source("R/utils.R", encoding = "UTF-8")
source("R/effis.R", encoding = "UTF-8")
check_required_packages(c("dplyr", "fs", "httr2", "jsonlite", "png", "purrr", "readr", "terra", "tibble", "tidyr"))
prepare_effis_static_assets()
