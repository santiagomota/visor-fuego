source("R/aemet_discovery.R", encoding = "UTF-8")

manifest_path <- "data/raw/aemet/manifest.csv"
if (!file.exists(manifest_path)) {
  stop("No existe ", manifest_path, ". Ejecuta antes scripts/01_download_aemet_incendios.R", call. = FALSE)
}

manifest <- readr::read_csv(manifest_path, show_col_types = FALSE)
urls <- manifest |>
  dplyr::select(endpoint, tipo, dia, area, datos_url, metadatos_url) |>
  tidyr::pivot_longer(c(datos_url, metadatos_url), names_to = "url_kind", values_to = "url") |>
  dplyr::filter(!is.na(url), nzchar(url)) |>
  dplyr::distinct(url_kind, url, .keep_all = TRUE) |>
  dplyr::arrange(url_kind, endpoint, dia, area)

out_dir <- "data/raw/aemet_metadata_probe"
fs::dir_create(out_dir)

message("URLs AEMET a inspeccionar: ", nrow(urls))
rows <- vector("list", nrow(urls))
contexts <- list()

for (i in seq_len(nrow(urls))) {
  row <- urls[i, ]
  local_file <- file.path(out_dir, sprintf("%03d_%s.txt", i, row$url_kind))
  message(sprintf("[%03d/%03d] %s %s %s d%s", i, nrow(urls), row$url_kind, row$tipo, row$area, row$dia %||% NA))
  got <- tryCatch(
    fetch_text_raw(row$url, out_file = local_file, timeout = 90),
    error = function(e) list(error = conditionMessage(e), status_code = NA_integer_, content_type = NA_character_, size_bytes = NA_integer_, text = "")
  )
  rows[[i]] <- tibble::tibble(
    endpoint = row$endpoint,
    tipo = row$tipo,
    dia = suppressWarnings(as.integer(row$dia)),
    area = row$area,
    url_kind = row$url_kind,
    url = row$url,
    status_code = got$status_code %||% NA_integer_,
    content_type = got$content_type %||% NA_character_,
    size_bytes = got$size_bytes %||% NA_integer_,
    local_file = local_file,
    error = got$error %||% NA_character_
  )
  contexts[[i]] <- extract_term_contexts(got$text %||% "", paste0(row$url_kind, "_", i), row$url)
}

summary <- dplyr::bind_rows(rows)
ctx <- dplyr::bind_rows(contexts)

readr::write_csv(summary, file.path(out_dir, "aemet_metadata_probe_summary.csv"))
readr::write_csv(ctx, file.path(out_dir, "aemet_metadata_probe_contexts.csv"))

message("Resumen guardado en: ", file.path(out_dir, "aemet_metadata_probe_summary.csv"))
message("Contextos guardados en: ", file.path(out_dir, "aemet_metadata_probe_contexts.csv"))

print(summary |> dplyr::select(url_kind, tipo, dia, area, status_code, content_type, size_bytes, local_file), n = Inf)

if (nrow(ctx) > 0) {
  message("\nContextos relevantes:")
  print(
    ctx |>
      dplyr::filter(grepl("tif|geotiff|incend|ipif|mapasriesgo|descarga|download|coverage|raster|wms|wmts", term, ignore.case = TRUE)) |>
      dplyr::select(source_id, term, context) |>
      utils::head(80),
    n = 80,
    width = 160
  )
}
