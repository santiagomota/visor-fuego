source("R/utils.R", encoding = "UTF-8")
source("R/effis.R", encoding = "UTF-8")

check_required_packages(c("dplyr", "fs", "glue", "httr2", "png", "purrr", "readr", "terra", "tibble", "tidyr"))

probe_effis_wms <- function() {
  if (!effis_enabled()) {
    message("EFFIS_ENABLE=false; no se prueba EFFIS.")
    return(invisible(NULL))
  }

  out_dir <- "data/raw/effis"
  fs::dir_create(out_dir)
  fs::dir_create("assets/effis")

  message("Probando EFFIS WMS")
  message("Bases: ", paste(effis_wms_bases(), collapse = ", "))
  
  avail_layers <- tryCatch(effis_available_layers(out_dir = out_dir, refresh = TRUE), error = function(e) tibble::tibble())
  if (nrow(avail_layers) > 0) {
    message("Capas candidatas según GetCapabilities:")
    print(
      avail_layers |>
        dplyr::filter(candidate %in% TRUE) |>
        dplyr::select(base_url, version, layer, title, candidate_score) |>
        dplyr::arrange(dplyr::desc(candidate_score), layer) |>
        utils::head(20),
      width = 180
    )
  } else {
    message("No se han podido extraer capas de GetCapabilities.")
  }
  message("Capas que se probarán: ", paste(effis_layer_config_base()$layer, collapse = ", "))
  message("Versiones: ", paste(effis_wms_versions(), collapse = ", "))
  message("Formatos: ", paste(effis_probe_formats(), collapse = ", "))

  # Descargar GetCapabilities de todas las bases/versiones y mostrar fechas TIME.
  caps <- purrr::map_dfr(effis_wms_bases(), function(base_url) {
    purrr::map_dfr(c("1.1.1", "1.3.0"), function(version) {
      cap <- effis_fetch_capabilities(base_url, version = version, out_dir = out_dir)
      dates <- character()
      layers <- effis_layer_config_base()
      if (isTRUE(cap$ok) && nrow(layers) > 0) {
        dates <- unique(unlist(lapply(layers$layer, function(layer) effis_extract_time_dates(cap$text, layer)), use.names = FALSE))
      }
      tibble::tibble(
        base_url = base_url,
        version = version,
        ok = isTRUE(cap$ok),
        status_code = cap$status,
        content_type = cap$content_type,
        file = cap$file,
        n_time_dates = length(dates),
        latest_time = if (length(dates) > 0) max(as.Date(dates), na.rm = TRUE) |> as.character() else NA_character_,
        message = cap$message
      )
    })
  })
  readr::write_csv(caps, file.path(out_dir, "effis_capabilities_probe.csv"))

  message("GetCapabilities:")
  print(caps |> dplyr::select(base_url, version, ok, status_code, content_type, n_time_dates, latest_time, file), width = 160)

  reqs <- effis_request_matrix(formats = effis_probe_formats())
  if (nrow(reqs) == 0) {
    message("No se han construido peticiones GetMap candidatas.")
    return(invisible(NULL))
  }

  max_req <- suppressWarnings(as.integer(Sys.getenv("EFFIS_PROBE_MAX_REQUESTS", unset = "120")))
  if (is.na(max_req) || max_req < 1) max_req <- 120L
  reqs <- reqs |> dplyr::slice_head(n = max_req)

  message("Peticiones GetMap candidatas: ", nrow(reqs))
  res <- purrr::map_dfr(seq_len(nrow(reqs)), function(i) {
    if (i %% 10 == 0) message("  ", i, "/", nrow(reqs))
    probe_effis_getmap_row(reqs[i, ], out_dir = out_dir)
  })

  out_csv <- file.path(out_dir, "effis_wms_probe.csv")
  readr::write_csv(res, out_csv)
  readr::write_csv(res, "assets/effis/effis_wms_probe.csv")

  message("Resumen guardado en: ", out_csv)
  print(res |> dplyr::count(status_code, base_url, version, format, file_type, has_pixels), n = Inf)

  best <- res |>
    dplyr::filter(status_code == 200, has_pixels %in% TRUE) |>
    dplyr::arrange(dplyr::desc(as.Date(date)), dplyr::desc(non_empty_pixels))

  if (nrow(best) > 0) {
    message("\nCandidatos EFFIS con contenido visible:")
    print(best |> dplyr::select(layer, date, base_url, version, format, bbox, wms_bbox, file_type, non_empty_pixels, file, url) |> utils::head(10), width = 180)
  } else {
    message("\nNo se detectaron píxeles visibles.")
    message("Revisa estas columnas para ver si son XML de error, fichero vacío o formato no reconocido:")
    print(res |> dplyr::select(status_code, base_url, version, format, bbox, wms_bbox, file_type, content_type, size_bytes, first_hex, message) |> utils::head(12), width = 180)
  }

  invisible(res)
}

probe_effis_wms()
