source("R/aemet_discovery.R", encoding = "UTF-8")

res <- probe_aemet_web_sources()

cat("\nArchivos generados:\n")
cat("- data/raw/aemet_web_probe/aemet_web_sources.csv\n")
cat("- data/raw/aemet_web_probe/aemet_web_candidates.csv\n")
cat("\nRevisa primero los candidatos geotiff_hint y wms_hint.\n")
