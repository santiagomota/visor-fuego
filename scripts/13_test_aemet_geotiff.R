source("R/aemet.R", encoding = "UTF-8")
source("R/prepare_layers.R", encoding = "UTF-8")

key <- Sys.getenv("AEMET_API_KEY")
if (!nzchar(key)) stop("Falta AEMET_API_KEY", call. = FALSE)

area <- Sys.getenv("AEMET_TEST_AREA", unset = "p")
dia <- as.integer(Sys.getenv("AEMET_TEST_DAY", unset = "1"))
endpoint <- sprintf("/api/incendios/mapasriesgo/previsto/dia/%s/area/%s", dia, area)

row <- download_one_fire_product(
  tipo = "previsto",
  dia = dia,
  area = area,
  endpoint = endpoint,
  api_key = key,
  date = Sys.Date()
)

print(row)

if (!is.na(row$file) && file.exists(row$file)) {
  cat("\nFichero:", row$file, "\n")
  cat("Tipo:", infer_file_type(row$file), "\n")
  cat("Tamaño:", file.info(row$file)$size, "bytes\n")

  con <- file(row$file, "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, what = "raw", n = 16)
  cat("Primeros bytes:", paste(sprintf("%02x", as.integer(raw)), collapse = " "), "\n")

  if (infer_file_type(row$file) == "raster" && requireNamespace("terra", quietly = TRUE)) {
    r <- terra::rast(row$file)
    cat("CRS:", terra::crs(r), "\n")
    cat("Extensión:", paste(as.vector(terra::ext(r)), collapse = ", "), "\n")
    cat("Dimensión:", paste(dim(r), collapse = " x "), "\n")
  }
}
