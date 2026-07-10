# Corrige copernicus.qmd para que el render en GitHub Actions no falle
# por no tener definido el operador local %||%.

path <- "copernicus.qmd"

if (!file.exists(path)) {
  stop("No existe copernicus.qmd en el directorio actual", call. = FALSE)
}

x <- readLines(path, warn = FALSE, encoding = "UTF-8")

has_operator <- any(grepl("`%\\|\\|%`\\s*<-", x, perl = TRUE)) ||
  any(grepl("%\\|\\|%\\s*<-", x, perl = TRUE))

if (has_operator) {
  message("copernicus.qmd ya define %||%; no se modifica.")
  quit(status = 0)
}

chunk_idx <- grep("^```\\{r", x, perl = TRUE)
if (!length(chunk_idx)) {
  stop("No se encontró ningún chunk R en copernicus.qmd", call. = FALSE)
}

insert <- c(
  "",
  "# Operador null-coalescing local para que copernicus.qmd renderice de forma autónoma",
  "`%||%` <- function(x, y) {",
  "  if (is.null(x) || length(x) == 0 || all(is.na(x))) return(y)",
  "  if (length(x) == 1 && is.character(x) && !nzchar(x)) return(y)",
  "  x",
  "}",
  ""
)

x <- append(x, insert, after = chunk_idx[1])
writeLines(x, path, useBytes = TRUE)

message("Añadida definición local de %||% a copernicus.qmd")
