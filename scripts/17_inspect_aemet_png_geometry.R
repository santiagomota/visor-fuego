if (!requireNamespace("png", quietly = TRUE)) {
  stop("Falta el paquete R 'png'. Instala con install.packages('png').", call. = FALSE)
}
source("R/utils.R", encoding = "UTF-8")

manifest_path <- "data/raw/aemet/manifest.csv"
if (!file.exists(manifest_path)) {
  stop("No existe ", manifest_path, call. = FALSE)
}
manifest <- readr::read_csv(manifest_path, show_col_types = FALSE)
files <- manifest |>
  dplyr::filter(!is.na(file), file.exists(file), file_type == "image") |>
  dplyr::pull(file) |>
  unique()

if (length(files) == 0) {
  message("No hay PNG/JPEG AEMET en el manifest.")
  quit(save = "no")
}

inspect_png <- function(path) {
  img <- png::readPNG(path)
  h <- dim(img)[1]
  w <- dim(img)[2]
  ch <- dim(img)[3] %||% 1L

  if (length(dim(img)) == 2) {
    mask <- !is.na(img) & img < 0.99
  } else if (ch >= 4) {
    mask <- img[, , 4] > 0.01
  } else {
    # Aproximación: píxeles no blancos. Útil si AEMET entrega PNG sin alfa.
    rgb <- img[, , seq_len(min(3, ch)), drop = FALSE]
    mask <- apply(rgb, c(1, 2), function(v) any(v < 0.98))
  }

  if (!any(mask)) {
    bbox_px <- c(xmin = NA_integer_, xmax = NA_integer_, ymin = NA_integer_, ymax = NA_integer_)
  } else {
    yy <- which(rowSums(mask) > 0)
    xx <- which(colSums(mask) > 0)
    bbox_px <- c(xmin = min(xx), xmax = max(xx), ymin = min(yy), ymax = max(yy))
  }

  tibble::tibble(
    file = path,
    width = w,
    height = h,
    channels = ch,
    aspect = w / h,
    content_xmin_px = bbox_px[["xmin"]],
    content_xmax_px = bbox_px[["xmax"]],
    content_ymin_px = bbox_px[["ymin"]],
    content_ymax_px = bbox_px[["ymax"]],
    content_width_px = bbox_px[["xmax"]] - bbox_px[["xmin"]] + 1L,
    content_height_px = bbox_px[["ymax"]] - bbox_px[["ymin"]] + 1L,
    content_aspect = content_width_px / content_height_px
  )
}

out <- purrr::map_dfr(files, inspect_png)
out_path <- "data/raw/aemet/aemet_png_geometry.csv"
readr::write_csv(out, out_path)
message("Diagnóstico PNG guardado en: ", out_path)
print(out, n = Inf, width = 140)
