source("R/utils.R", encoding = "UTF-8")
source("R/aemet_classic.R", encoding = "UTF-8")

probe_path <- "data/raw/aemet_classic_probe/classic_download_probe_reclassified.csv"
if (!file.exists(probe_path)) {
  probe_path <- "data/raw/aemet_classic_probe/classic_download_probe.csv"
}
if (!file.exists(probe_path)) {
  stop("No existe classic_download_probe*.csv. Ejecuta primero scripts/18_probe_aemet_classic_download.R", call. = FALSE)
}

probe <- readr::read_csv(probe_path, show_col_types = FALSE)

file_col <- if ("local_file_norm" %in% names(probe)) "local_file_norm" else "local_file"
type_col <- if ("file_type_norm" %in% names(probe)) "file_type_norm" else "file_type"
size_col <- if ("size_bytes_norm" %in% names(probe)) "size_bytes_norm" else "size_bytes"

candidate_rows <- probe |>
  dplyr::filter(status_code >= 200, status_code < 300) |>
  dplyr::filter(!is.na(.data[[file_col]]), file.exists(.data[[file_col]])) |>
  dplyr::mutate(
    current_file = .data[[file_col]],
    current_type = vapply(current_file, infer_file_type, character(1)),
    current_ext = tolower(tools::file_ext(current_file)),
    current_size = as.numeric(file.info(current_file)$size)
  ) |>
  dplyr::filter(current_type %in% c("archive", "zip", "gzip") | current_ext %in% c("tar", "zip", "gz"))

message("Archivos clásicos candidatos a extraer: ", nrow(candidate_rows))

contents <- purrr::map_dfr(seq_len(nrow(candidate_rows)), function(i) {
  row <- candidate_rows[i, ]
  in_file <- row$current_file[[1]]
  out_dir <- file.path("data/raw/aemet_classic_probe/extracted", safe_slug(row$label[[1]] %||% paste0("candidate_", i)))
  message(sprintf("[%03d/%03d] %s", i, nrow(candidate_rows), in_file))

  extracted <- extract_aemet_archive(in_file, out_dir = out_dir)

  if (length(extracted) == 0) {
    return(tibble::tibble(
      label = row$label[[1]],
      url = row$url[[1]],
      archive_file = in_file,
      extracted_file = NA_character_,
      ext = NA_character_,
      file_type = NA_character_,
      size_bytes = NA_real_,
      is_geospatial = FALSE
    ))
  }

  tibble::tibble(
    label = row$label[[1]],
    url = row$url[[1]],
    archive_file = in_file,
    extracted_file = as.character(extracted),
    ext = tolower(tools::file_ext(extracted)),
    file_type = vapply(extracted, infer_file_type, character(1)),
    size_bytes = as.numeric(file.info(extracted)$size)
  ) |>
    dplyr::mutate(
      is_geospatial = file_type %in% c("raster", "json", "xml") |
        ext %in% c("tif", "tiff", "asc", "grd", "nc", "geojson", "json", "kml", "gml", "gpkg", "shp")
    )
})

out_path <- "data/raw/aemet_classic_probe/classic_archive_contents.csv"
readr::write_csv(contents, out_path)
message("Contenido de archivos clásicos guardado en: ", out_path)

print(
  contents |>
    dplyr::count(file_type, ext, is_geospatial) |>
    dplyr::arrange(dplyr::desc(is_geospatial), file_type, ext),
  n = Inf
)

geo <- contents |>
  dplyr::filter(is_geospatial, !is.na(extracted_file), file.exists(extracted_file)) |>
  dplyr::arrange(dplyr::desc(size_bytes))

if (nrow(geo) > 0) {
  message("\nCandidatos geoespaciales encontrados dentro de archivos AEMET clásicos:")
  print(
    geo |>
      dplyr::select(label, file_type, ext, size_bytes, extracted_file, url),
    n = Inf,
    width = 160
  )
} else {
  message("\nNo se han encontrado todavía ficheros geoespaciales dentro de los .gz/.tar/.zip.")
  message("Siguiente diagnóstico recomendado: inspeccionar primeros bytes y strings de los .bin generados.")
}

invisible(contents)
