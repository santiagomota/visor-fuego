#!/usr/bin/env Rscript

source("R/utils.R", encoding = "UTF-8")

check_required_packages(c("readr", "dplyr", "fs", "tibble"))

manifest_file <- "data/raw/aemet/manifest.csv"
if (!file.exists(manifest_file)) {
  stop("No existe ", manifest_file, call. = FALSE)
}

manifest <- readr::read_csv(manifest_file, show_col_types = FALSE)
files <- manifest |>
  dplyr::filter(status == "downloaded", !is.na(file), file.exists(file)) |>
  dplyr::mutate(
    file_norm = vapply(file, normalise_downloaded_extension, character(1)),
    type_now = vapply(file_norm, infer_file_type, character(1)),
    size_bytes = fs::file_size(file_norm)
  )

if (nrow(files) == 0) {
  message("No hay ficheros descargados para diagnosticar.")
  quit(save = "no")
}

print(files |> dplyr::select(status, tipo, area_label, dia, file_norm, type_now, size_bytes), n = Inf)

message("\nPrevisualización de ficheros no reconocidos como image/raster/zip/geojson:\n")

bad <- files |> dplyr::filter(!type_now %in% c("image", "raster", "zip", "json"))

if (nrow(bad) == 0) {
  message("Todos los ficheros tienen un tipo potencialmente procesable.")
} else {
  for (i in seq_len(nrow(bad))) {
    f <- bad$file_norm[i]
    con <- file(f, "rb")
    raw <- readBin(con, what = "raw", n = min(fs::file_size(f), 2048))
    close(con)
    txt <- tryCatch(rawToChar(raw), error = function(e) "")
    txt <- suppressWarnings(iconv(txt, from = "latin1", to = "UTF-8", sub = "byte"))
    cat("\n---\n", f, "\n", sep = "")
    cat("Tipo detectado: ", infer_file_type(f), "\n", sep = "")
    cat("Primeros bytes: ", paste(format(raw[seq_len(min(32, length(raw)))]), collapse = " "), "\n", sep = "")
    cat("Texto inicial:\n", substr(txt, 1, 1000), "\n", sep = "")
  }
}
