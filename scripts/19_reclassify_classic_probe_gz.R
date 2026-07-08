source("R/utils.R", encoding = "UTF-8")
source("R/aemet_classic.R", encoding = "UTF-8")

probe_path <- "data/raw/aemet_classic_probe/classic_download_probe.csv"
if (!file.exists(probe_path)) {
  stop("No existe ", probe_path, ". Ejecuta primero scripts/18_probe_aemet_classic_download.R", call. = FALSE)
}

probe <- readr::read_csv(probe_path, show_col_types = FALSE)

if (!"local_file" %in% names(probe)) {
  stop("El probe no tiene columna local_file", call. = FALSE)
}

message("Reclasificando respuestas clásicas AEMET, incluyendo .gz y .tar...")

probe2 <- probe |>
  dplyr::rowwise() |>
  dplyr::mutate(
    local_file_norm = ifelse(!is.na(local_file) && file.exists(local_file), normalise_downloaded_extension(local_file), local_file),
    ext_norm = ifelse(!is.na(local_file_norm) && file.exists(local_file_norm), tolower(tools::file_ext(local_file_norm)), ext),
    file_type_norm = ifelse(!is.na(local_file_norm) && file.exists(local_file_norm), infer_file_type(local_file_norm), file_type),
    size_bytes_norm = ifelse(!is.na(local_file_norm) && file.exists(local_file_norm), as.numeric(file.info(local_file_norm)$size), size_bytes)
  ) |>
  dplyr::ungroup()

out_path <- "data/raw/aemet_classic_probe/classic_download_probe_reclassified.csv"
readr::write_csv(probe2, out_path)

message("Reclasificación guardada en: ", out_path)

print(
  probe2 |>
    dplyr::count(status_code, file_type_norm, ext_norm) |>
    dplyr::arrange(status_code, file_type_norm, ext_norm),
  n = Inf
)

good <- probe2 |>
  dplyr::filter(status_code >= 200, status_code < 300) |>
  dplyr::filter(file_type_norm %in% c("raster", "zip", "archive", "json")) |>
  dplyr::filter(size_bytes_norm > 1000)

if (nrow(good) > 0) {
  message("\nCandidatos útiles encontrados:")
  print(
    good |>
      dplyr::select(label, file_type_norm, ext_norm, size_bytes_norm, local_file_norm, url),
    n = Inf,
    width = 160
  )
} else {
  message("\nTodavía no hay candidatos raster/zip/json tras descomprimir .gz.")
}

invisible(probe2)
