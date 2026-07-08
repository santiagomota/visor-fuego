source("R/aemet_classic.R", encoding = "UTF-8")

max_tests_env <- Sys.getenv("AEMET_CLASSIC_PROBE_MAX", unset = "Inf")
max_tests <- suppressWarnings(as.numeric(max_tests_env))
if (is.na(max_tests)) max_tests <- Inf

probe_classic_download_endpoint(max_tests = max_tests)
