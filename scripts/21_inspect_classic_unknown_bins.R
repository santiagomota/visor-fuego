source("R/utils.R", encoding = "UTF-8")

probe_path <- "data/raw/aemet_classic_probe/classic_download_probe_reclassified.csv"
if (!file.exists(probe_path)) probe_path <- "data/raw/aemet_classic_probe/classic_download_probe.csv"
if (!file.exists(probe_path)) stop("No existe classic_download_probe*.csv", call. = FALSE)

probe <- readr::read_csv(probe_path, show_col_types = FALSE)
file_col <- if ("local_file_norm" %in% names(probe)) "local_file_norm" else "local_file"
type_col <- if ("file_type_norm" %in% names(probe)) "file_type_norm" else "file_type"

inspect_one <- function(path, n = 512) {
  if (is.na(path) || !file.exists(path)) return(NULL)
  size <- file.info(path)$size
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, "raw", n = min(size, n))
  hex <- paste(sprintf("%02x", as.integer(raw[seq_len(min(length(raw), 96))])), collapse = " ")
  txt <- raw_preview_text(raw, n = min(length(raw), n))
  tar_magic <- if (length(raw) >= 262) tryCatch(rawToChar(raw[258:262], multiple = FALSE), error = function(e) "") else ""
  tibble::tibble(
    file = path,
    size_bytes = as.numeric(size),
    ext = tolower(tools::file_ext(path)),
    inferred_type = infer_file_type(path),
    first_hex = hex,
    tar_magic_258_262 = tar_magic,
    text_preview = txt
  )
}

unknowns <- probe |>
  dplyr::filter(!is.na(.data[[file_col]]), file.exists(.data[[file_col]])) |>
  dplyr::mutate(
    current_file = .data[[file_col]],
    inferred_type = vapply(current_file, infer_file_type, character(1))
  ) |>
  dplyr::filter(inferred_type %in% c("unknown", "gzip", "archive")) |>
  dplyr::distinct(current_file, .keep_all = TRUE) |>
  dplyr::slice_head(n = 25)

message("Inspeccionando binarios desconocidos: ", nrow(unknowns))

out <- purrr::map_dfr(unknowns$current_file, inspect_one)
out_path <- "data/raw/aemet_classic_probe/classic_unknown_bins_inspection.csv"
readr::write_csv(out, out_path)
message("Inspección guardada en: ", out_path)

print(out |> dplyr::select(file, size_bytes, ext, inferred_type, tar_magic_258_262, first_hex, text_preview), n = Inf, width = 160)

invisible(out)
