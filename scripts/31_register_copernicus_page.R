#!/usr/bin/env Rscript
# Añade copernicus.qmd al navbar de Quarto de forma conservadora.

file <- "_quarto.yml"
if (!file.exists(file)) stop("No existe _quarto.yml", call. = FALSE)

x <- readLines(file, warn = FALSE, encoding = "UTF-8")
if (any(grepl("copernicus\\.qmd", x, ignore.case = TRUE))) {
  message("copernicus.qmd ya está registrado en _quarto.yml")
  quit(status = 0)
}

insert_line <- "      - href: copernicus.qmd"
insert_text <- c(insert_line, "        text: Copernicus")

# Intenta insertar después de report.qmd, summary.qmd o index.qmd.
patterns <- c("href: *report\\.qmd", "href: *summary\\.qmd", "href: *index\\.qmd")
idx <- integer()
for (pat in patterns) {
  idx <- grep(pat, x)
  if (length(idx) > 0) break
}

if (length(idx) == 0) {
  # Fallback: al final del fichero, con comentario claro.
  x <- c(x, "", "# Copernicus page pendiente de registrar manualmente:", "# - href: copernicus.qmd", "#   text: Copernicus")
  writeLines(x, file, useBytes = TRUE)
  warning("No se encontró navbar reconocible; se añadió comentario para registro manual")
  quit(status = 0)
}

pos <- idx[1]
x <- append(x, insert_text, after = pos + 1)
writeLines(x, file, useBytes = TRUE)
message("Registrado copernicus.qmd en _quarto.yml")
