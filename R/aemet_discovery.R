source("R/utils.R", encoding = "UTF-8")

html_unescape_basic <- function(x) {
  if (length(x) == 0 || is.na(x)) return(x)
  x <- gsub("&amp;", "&", x, fixed = TRUE)
  x <- gsub("&quot;", "\"", x, fixed = TRUE)
  x <- gsub("&#39;", "'", x, fixed = TRUE)
  x <- gsub("&apos;", "'", x, fixed = TRUE)
  x <- gsub("&lt;", "<", x, fixed = TRUE)
  x <- gsub("&gt;", ">", x, fixed = TRUE)
  x
}

fetch_text_raw <- function(url, out_file = NULL, timeout = 60) {
  if (!requireNamespace("curl", quietly = TRUE)) {
    stop("Falta el paquete R 'curl'. Instala con install.packages('curl').", call. = FALSE)
  }

  h <- curl::new_handle()
  curl::handle_setopt(
    h,
    useragent = "visor-fuego-aemet-discovery/0.5.9",
    timeout = timeout,
    connecttimeout = 20,
    followlocation = TRUE,
    ssl_verifypeer = TRUE
  )
  curl::handle_setheaders(
    h,
    `Accept` = "text/html,application/xhtml+xml,application/xml,application/javascript,text/javascript,application/json,text/plain,*/*;q=0.8"
  )

  resp <- curl::curl_fetch_memory(url, handle = h)
  if (!is.null(out_file)) {
    fs::dir_create(dirname(out_file))
    writeBin(resp$content, out_file)
  }

  txt0 <- tryCatch(rawToChar(resp$content, multiple = FALSE), error = function(e) "")
  candidates <- c(
    suppressWarnings(iconv(txt0, from = "UTF-8", to = "UTF-8", sub = "byte")),
    suppressWarnings(iconv(txt0, from = "latin1", to = "UTF-8", sub = "byte")),
    suppressWarnings(iconv(txt0, from = "CP1252", to = "UTF-8", sub = "byte"))
  )
  candidates <- candidates[!is.na(candidates) & nzchar(candidates)]
  txt <- if (length(candidates) > 0) candidates[[1]] else ""

  list(
    url = url,
    status_code = resp$status_code,
    content_type = paste(resp$type %||% NA_character_, collapse = ";"),
    size_bytes = length(resp$content),
    text = txt
  )
}

resolve_url <- function(base_url, link) {
  if (is.na(link) || !nzchar(link)) return(NA_character_)
  link <- trimws(link)
  link <- gsub("\\\\/", "/", link)
  link <- html_unescape_basic(link)

  if (grepl("^https?://", link, ignore.case = TRUE)) return(link)
  if (startsWith(link, "//")) return(paste0("https:", link))

  base_no_query <- strsplit(base_url, "[?#]")[[1]][1]
  m <- regexec("^(https?://[^/]+)(/.*)?$", base_no_query, ignore.case = TRUE)
  parts <- regmatches(base_no_query, m)[[1]]
  origin <- parts[2]
  base_path <- parts[3] %||% "/"

  if (startsWith(link, "/")) return(paste0(origin, link))

  base_dir <- sub("/[^/]*$", "/", base_path)
  paste0(origin, base_dir, link)
}

extract_attr_links <- function(txt) {
  patterns <- c(
    "(?:src|href)\\s*=\\s*\\\"([^\\\"]+)\\\"",
    "(?:src|href)\\s*=\\s*'([^']+)'"
  )
  out <- unlist(lapply(patterns, function(p) {
    m <- gregexpr(p, txt, perl = TRUE, ignore.case = TRUE)
    hits <- regmatches(txt, m)[[1]]
    if (length(hits) == 1 && identical(hits, character(0))) return(character())
    sub(p, "\\1", x = hits, perl = TRUE, ignore.case = TRUE)
  }), use.names = FALSE)
  unique(out[nzchar(out)])
}

extract_quoted_strings <- function(txt) {
  m <- gregexpr("[\\\'][^\\\']{3,400}[\\\']|[\\\"][^\\\"]{3,400}[\\\"]", txt, perl = TRUE)
  x <- regmatches(txt, m)[[1]]
  if (length(x) == 1 && identical(x, character(0))) return(character())
  x <- substr(x, 2, nchar(x) - 1)
  x <- gsub("\\\\/", "/", x)
  unique(x[nzchar(x)])
}

is_plausible_urlish <- function(x) {
  if (is.na(x) || !nzchar(x)) return(FALSE)
  x <- html_unescape_basic(trimws(x))

  # Evitamos expresiones regulares complejas con caracteres URL, porque R/TRE
  # puede fallar con signos como *, +, [, ], etc. Aquí solo descartamos textos
  # que claramente son fragmentos de código y aceptamos candidatos razonables.
  if (nchar(x) > 500) return(FALSE)
  if (grepl("\\s", x, perl = TRUE)) return(FALSE)
  if (grepl("[{}<>`\"]", x, perl = TRUE)) return(FALSE)
  if (grepl("\\b(function|return|prototype|var |const |let |if\\(|for\\(|while\\()", x, ignore.case = TRUE, perl = TRUE)) return(FALSE)
  if (grepl("!==|===|=>|&&|\\|\\|", x, perl = TRUE)) return(FALSE)

  if (grepl("^(https?://|//|/|\\./|\\.\\./)", x, ignore.case = TRUE, perl = TRUE)) return(TRUE)
  if (grepl("\\.(js|css|json|geojson|tif|tiff|png|jpg|jpeg|xml|kml|gml)(\\?|#|$)", x, ignore.case = TRUE, perl = TRUE)) return(TRUE)

  # Candidatos relativos tipo js/app.js, api/foo, datos/bar, etc.
  has_slash <- grepl("/", x, fixed = TRUE)
  has_relevant_word <- grepl("api|datos|download|descarga|incend|riesgo|peligro|ipif|alcif|mapasriesgo|layer|raster|coverage|wms|wmts|tile|tiles", x, ignore.case = TRUE, perl = TRUE)
  has_safe_chars <- !grepl("[^A-Za-z0-9._~:/?#\\[\\]@!$&'()*+,;=%-]", x, perl = TRUE)

  has_slash && has_relevant_word && has_safe_chars
}

classify_candidate <- function(x) {
  xl <- tolower(x)
  dplyr::case_when(
    grepl("\\.(tif|tiff)(\\?|$)", xl) | grepl("geotiff|image/tiff|image/geotiff|application/geotiff", xl) ~ "geotiff_hint",
    grepl("service=wms|getcapabilities.*wms|/wms(\\?|/|$)|geoserver|mapserver", xl) ~ "wms_hint",
    grepl("wmts|tilematrix|/tiles?/|\\{z\\}|\\{x\\}|\\{y\\}|/z/|xyz", xl) ~ "tiles_hint",
    grepl("\\.(geojson|json)(\\?|$)", xl) | grepl("featurecollection", xl) ~ "json_hint",
    grepl("/api/|api/|graphql|download|descarga|datos|layers|layer|raster|coverage|ipif|alcif|incendio|incendios|riesgo|peligro", xl) ~ "api_or_product_hint",
    TRUE ~ "other"
  )
}

extract_candidate_urls <- function(txt, base_url, source_id) {
  raw_candidates <- c(extract_attr_links(txt), extract_quoted_strings(txt))
  raw_candidates <- unique(raw_candidates[nzchar(raw_candidates)])
  raw_candidates <- raw_candidates[!grepl("^(data:|mailto:|tel:|javascript:|#)", raw_candidates, ignore.case = TRUE)]
  raw_candidates <- raw_candidates[vapply(raw_candidates, is_plausible_urlish, logical(1))]

  keep <- grepl(
    "tif|tiff|geotiff|wms|wmts|geoserver|mapserver|tile|tiles|api|download|descarga|datos|layers|layer|raster|coverage|ipif|alcif|incendio|incendios|riesgo|peligro|\\.js|\\.css|\\.json",
    raw_candidates,
    ignore.case = TRUE
  )
  raw_candidates <- raw_candidates[keep]

  if (length(raw_candidates) == 0) return(tibble::tibble())

  tibble::tibble(
    source_id = source_id,
    source_url = base_url,
    raw_candidate = raw_candidates,
    resolved_url = vapply(raw_candidates, function(x) {
      tryCatch(resolve_url(base_url, x), error = function(e) NA_character_)
    }, character(1)),
    candidate_type = vapply(raw_candidates, classify_candidate, character(1))
  ) |>
    dplyr::filter(!is.na(resolved_url), nzchar(resolved_url)) |>
    dplyr::filter(!grepl("/js/leaflet/leaflet", resolved_url, ignore.case = TRUE) | candidate_type %in% c("geotiff_hint", "json_hint")) |>
    dplyr::distinct(resolved_url, raw_candidate, .keep_all = TRUE)
}

extract_term_contexts <- function(txt, source_id, source_url, terms = c("geotiff", "tif", "tiff", "incend", "ipif", "peligro", "riesgo", "mapasriesgo", "descarga", "download", "wms", "wmts", "coverage", "raster", "alcif"), context_chars = 160) {
  if (is.na(txt) || !nzchar(txt)) return(tibble::tibble())
  rows <- list()
  k <- 1L
  for (term in terms) {
    m <- gregexpr(term, txt, ignore.case = TRUE, perl = TRUE)[[1]]
    if (length(m) == 1 && m[1] == -1) next
    for (pos in head(m, 40)) {
      start <- max(1, pos - context_chars)
      end <- min(nchar(txt), pos + nchar(term) + context_chars)
      rows[[k]] <- tibble::tibble(
        source_id = source_id,
        source_url = source_url,
        term = term,
        position = pos,
        context = gsub("\\s+", " ", substr(txt, start, end))
      )
      k <- k + 1L
    }
  }
  if (length(rows) == 0) tibble::tibble() else dplyr::bind_rows(rows)
}

probe_aemet_web_sources <- function(out_dir = "data/raw/aemet_web_probe") {
  fs::dir_create(out_dir)
  pages_dir <- file.path(out_dir, "pages")
  fs::dir_create(pages_dir)

  seed_pages <- tibble::tibble(
    source_id = c("aemet_classic", "aemet_help", "alcif_home", "alcif_auth"),
    url = c(
      "https://www.aemet.es/es/eltiempo/prediccion/incendios",
      "https://www.aemet.es/es/eltiempo/prediccion/incendios/ayuda",
      "https://incendios.aemet.es/",
      "https://incendios.aemet.es/auth/"
    )
  )

  message("Inspeccionando páginas AEMET...")
  fetched_pages <- purrr::pmap(seed_pages, function(source_id, url) {
    out_file <- file.path(pages_dir, paste0(source_id, ".html"))
    res <- tryCatch(fetch_text_raw(url, out_file = out_file), error = function(e) list(error = conditionMessage(e), url = url, text = "", status_code = NA_integer_, content_type = NA_character_, size_bytes = NA_integer_))
    tibble::tibble(
      source_id = source_id,
      url = url,
      status_code = res$status_code %||% NA_integer_,
      content_type = res$content_type %||% NA_character_,
      size_bytes = res$size_bytes %||% NA_integer_,
      local_file = out_file,
      text = res$text %||% "",
      error = res$error %||% NA_character_
    )
  }) |> dplyr::bind_rows()

  page_candidates <- purrr::pmap_dfr(
    fetched_pages,
    function(source_id, url, status_code, content_type, size_bytes, local_file, text, error) {
      extract_candidate_urls(text, url, source_id)
    }
  )

  asset_urls <- page_candidates |>
    dplyr::filter(grepl("\\.(js|css|json)(\\?|$)", resolved_url, ignore.case = TRUE)) |>
    dplyr::pull(resolved_url) |>
    unique()

  assets_dir <- file.path(out_dir, "assets")
  fs::dir_create(assets_dir)

  message("Assets candidatos JS/CSS/JSON: ", length(asset_urls))
  fetched_assets <- purrr::map_dfr(seq_along(asset_urls), function(i) {
    url <- asset_urls[[i]]
    ext <- tolower(tools::file_ext(strsplit(url, "[?#]")[[1]][1]))
    if (!nzchar(ext)) ext <- "txt"
    local_file <- file.path(assets_dir, sprintf("asset_%03d.%s", i, ext))
    res <- tryCatch(fetch_text_raw(url, out_file = local_file, timeout = 90), error = function(e) list(error = conditionMessage(e), url = url, text = "", status_code = NA_integer_, content_type = NA_character_, size_bytes = NA_integer_))
    tibble::tibble(
      source_id = paste0("asset_", i),
      url = url,
      status_code = res$status_code %||% NA_integer_,
      content_type = res$content_type %||% NA_character_,
      size_bytes = res$size_bytes %||% NA_integer_,
      local_file = local_file,
      text = res$text %||% "",
      error = res$error %||% NA_character_
    )
  })

  asset_candidates <- purrr::pmap_dfr(
    fetched_assets,
    function(source_id, url, status_code, content_type, size_bytes, local_file, text, error) {
      extract_candidate_urls(text, url, source_id)
    }
  )

  fetched_all <- dplyr::bind_rows(fetched_pages, fetched_assets)
  term_contexts <- purrr::pmap_dfr(
    fetched_all,
    function(source_id, url, status_code, content_type, size_bytes, local_file, text, error) {
      extract_term_contexts(text, source_id, url)
    }
  )

  sources <- fetched_all |>
    dplyr::select(source_id, url, status_code, content_type, size_bytes, local_file, error)

  candidates <- dplyr::bind_rows(page_candidates, asset_candidates) |>
    dplyr::mutate(
      priority = dplyr::case_when(
        candidate_type == "geotiff_hint" ~ 1L,
        candidate_type == "wms_hint" ~ 2L,
        candidate_type == "tiles_hint" ~ 3L,
        candidate_type == "json_hint" ~ 4L,
        candidate_type == "api_or_product_hint" ~ 5L,
        TRUE ~ 9L
      )
    ) |>
    dplyr::arrange(priority, candidate_type, resolved_url) |>
    dplyr::distinct(resolved_url, .keep_all = TRUE)

  readr::write_csv(sources, file.path(out_dir, "aemet_web_sources.csv"))
  readr::write_csv(candidates, file.path(out_dir, "aemet_web_candidates.csv"))
  readr::write_csv(term_contexts, file.path(out_dir, "aemet_web_term_contexts.csv"))

  message("Fuentes inspeccionadas: ", nrow(sources))
  message("Candidatos encontrados: ", nrow(candidates))
  message("Contextos con términos relevantes: ", nrow(term_contexts))
  message("Candidatos GeoTIFF/WMS/tiles depurados:")
  print(
    candidates |>
      dplyr::filter(candidate_type %in% c("geotiff_hint", "wms_hint", "tiles_hint")) |>
      dplyr::select(candidate_type, resolved_url) |>
      utils::head(50),
    n = 50
  )

  invisible(list(sources = sources, candidates = candidates, contexts = term_contexts))
}
