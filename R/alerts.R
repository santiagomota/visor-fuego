source("R/utils.R", encoding = "UTF-8")
source("R/summary.R", encoding = "UTF-8")

alert_cluster_km <- function() {
  x <- suppressWarnings(as.numeric(Sys.getenv("ALERT_CLUSTER_KM", unset = "12")))
  if (is.na(x) || x <= 0) x <- 12
  x
}

alert_max_age_hours <- function() {
  x <- suppressWarnings(as.numeric(Sys.getenv("ALERT_MAX_AGE_HOURS", unset = "48")))
  if (is.na(x) || x <= 0) x <- 48
  x
}

haversine_km <- function(lon1, lat1, lon2, lat2) {
  r <- 6371.0088
  to_rad <- pi / 180
  lon1 <- lon1 * to_rad; lat1 <- lat1 * to_rad
  lon2 <- lon2 * to_rad; lat2 <- lat2 * to_rad
  dlon <- lon2 - lon1
  dlat <- lat2 - lat1
  a <- sin(dlat / 2)^2 + cos(lat1) * cos(lat2) * sin(dlon / 2)^2
  2 * r * atan2(sqrt(a), sqrt(pmax(0, 1 - a)))
}

connected_components <- function(adj) {
  n <- nrow(adj)
  comp <- integer(n)
  cid <- 0L
  for (i in seq_len(n)) {
    if (comp[i] != 0L) next
    cid <- cid + 1L
    stack <- i
    comp[i] <- cid
    while (length(stack) > 0) {
      v <- stack[length(stack)]
      stack <- stack[-length(stack)]
      neigh <- which(adj[v, ] & comp == 0L)
      if (length(neigh) > 0) {
        comp[neigh] <- cid
        stack <- c(stack, neigh)
      }
    }
  }
  comp
}

cluster_firms_points <- function(fires, radius_km = alert_cluster_km(), max_age_hours = alert_max_age_hours()) {
  if (nrow(fires) == 0) return(tibble::tibble())
  fires <- fires |>
    dplyr::mutate(
      longitude = suppressWarnings(as.numeric(longitude)),
      latitude = suppressWarnings(as.numeric(latitude)),
      age_hours = suppressWarnings(as.numeric(age_hours)),
      frp = suppressWarnings(as.numeric(frp)),
      acq_datetime_utc = as.character(acq_datetime_utc)
    ) |>
    dplyr::filter(!is.na(longitude), !is.na(latitude)) |>
    dplyr::filter(is.na(age_hours) | age_hours <= max_age_hours)

  if (nrow(fires) == 0) return(tibble::tibble())

  n <- nrow(fires)
  adj <- matrix(FALSE, nrow = n, ncol = n)
  diag(adj) <- TRUE

  for (i in seq_len(n)) {
    if (i == n) next
    d <- haversine_km(
      fires$longitude[i], fires$latitude[i],
      fires$longitude[(i + 1):n], fires$latitude[(i + 1):n]
    )
    hit <- which(d <= radius_km) + i
    if (length(hit) > 0) {
      adj[i, hit] <- TRUE
      adj[hit, i] <- TRUE
    }
  }

  fires$cluster_num <- connected_components(adj)
  stamp <- format(Sys.Date(), "%Y%m%d")

  fires |>
    dplyr::group_by(cluster_num) |>
    dplyr::summarise(
      longitude = mean(longitude, na.rm = TRUE),
      latitude = mean(latitude, na.rm = TRUE),
      n_focos = dplyr::n(),
      n_ultimas_6h = sum(!is.na(age_hours) & age_hours <= 6),
      n_ultimas_24h = sum(!is.na(age_hours) & age_hours <= 24),
      frp_total_mw = round(sum(frp, na.rm = TRUE), 1),
      frp_max_mw = round(suppressWarnings(max(frp, na.rm = TRUE)), 1),
      edad_min_h = round(suppressWarnings(min(age_hours, na.rm = TRUE)), 1),
      ultima_deteccion_utc = suppressWarnings(max(acq_datetime_utc, na.rm = TRUE)),
      sensores = paste(sort(unique(stats::na.omit(source_dataset))), collapse = ", "),
      satellites = paste(sort(unique(stats::na.omit(satellite))), collapse = ", "),
      instruments = paste(sort(unique(stats::na.omit(instrument))), collapse = ", "),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      frp_max_mw = dplyr::if_else(is.infinite(frp_max_mw), NA_real_, frp_max_mw),
      edad_min_h = dplyr::if_else(is.infinite(edad_min_h), NA_real_, edad_min_h),
      alerta_operativa = dplyr::case_when(
        n_ultimas_6h >= 2 | frp_total_mw >= 150 ~ "alta",
        n_ultimas_6h >= 1 | n_ultimas_24h >= 2 | frp_total_mw >= 50 ~ "media",
        n_ultimas_24h >= 1 ~ "seguimiento",
        TRUE ~ "informativa"
      ),
      score = round(
        n_ultimas_6h * 5 + n_ultimas_24h * 2 + n_focos + log1p(pmax(0, frp_total_mw)) * 2,
        1
      )
    ) |>
    dplyr::arrange(
      factor(alerta_operativa, levels = c("alta", "media", "seguimiento", "informativa")),
      dplyr::desc(score),
      dplyr::desc(frp_total_mw)
    ) |>
    dplyr::mutate(
      cluster_id = sprintf("ALERT-%s-%03d", stamp, dplyr::row_number()),
      popup_label = paste0(
        "<strong>", cluster_id, "</strong><br>",
        "Nivel: ", alerta_operativa, "<br>",
        "Focos: ", n_focos, "<br>",
        "Últimas 6 h: ", n_ultimas_6h, "<br>",
        "FRP total: ", frp_total_mw, " MW<br>",
        "Última detección UTC: ", ultima_deteccion_utc
      )
    ) |>
    dplyr::select(
      cluster_id, alerta_operativa, score, longitude, latitude,
      n_focos, n_ultimas_6h, n_ultimas_24h,
      frp_total_mw, frp_max_mw, edad_min_h, ultima_deteccion_utc,
      sensores, satellites, instruments, popup_label
    )
}

alerts_to_geojson <- function(alerts) {
  if (nrow(alerts) == 0) {
    return(list(type = "FeatureCollection", features = list()))
  }
  props_cols <- setdiff(names(alerts), c("longitude", "latitude"))
  features <- purrr::map(seq_len(nrow(alerts)), function(i) {
    props <- as.list(alerts[i, props_cols, drop = FALSE])
    props <- lapply(props, function(v) {
      if (length(v) == 0 || is.na(v)) NULL else unname(v)
    })
    list(
      type = "Feature",
      geometry = list(type = "Point", coordinates = c(alerts$longitude[i], alerts$latitude[i])),
      properties = props
    )
  })
  list(type = "FeatureCollection", features = features)
}

write_operational_report <- function(alerts, fires) {
  fs::dir_create("data/processed")
  fs::dir_create("assets/alerts")

  generated <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  n_high <- if (nrow(alerts) > 0) sum(alerts$alerta_operativa == "alta", na.rm = TRUE) else 0L
  n_medium <- if (nrow(alerts) > 0) sum(alerts$alerta_operativa == "media", na.rm = TRUE) else 0L

  lines <- c(
    "# Informe operativo automático",
    "",
    paste0("Generado UTC: `", generated, "`"),
    "",
    "## Resumen",
    "",
    paste0("- Focos FIRMS procesados: **", nrow(fires), "**."),
    paste0("- Clústeres/alertas generadas: **", nrow(alerts), "**."),
    paste0("- Alertas altas: **", n_high, "**."),
    paste0("- Alertas medias: **", n_medium, "**."),
    "",
    "## Criterio de clasificación",
    "",
    "- **Alta**: varios focos muy recientes o FRP total elevado.",
    "- **Media**: al menos un foco muy reciente, varios focos en 24 h o FRP relevante.",
    "- **Seguimiento**: detecciones recientes sin concentración clara.",
    "",
    "Este informe es informativo y no sustituye a fuentes oficiales ni a servicios de emergencia."
  )

  if (nrow(alerts) > 0) {
    top <- alerts |>
      dplyr::select(cluster_id, alerta_operativa, score, n_focos, n_ultimas_6h, n_ultimas_24h, frp_total_mw, ultima_deteccion_utc, latitude, longitude) |>
      head(10)
    rows <- apply(top, 1, function(r) {
      paste0(
        "| ", paste(r, collapse = " | "), " |"
      )
    })
    lines <- c(
      lines,
      "",
      "## Principales alertas",
      "",
      "| ID | Nivel | Score | Focos | ≤6 h | ≤24 h | FRP MW | Última UTC | Lat | Lon |",
      "|---|---:|---:|---:|---:|---:|---:|---|---:|---:|",
      rows
    )
  }

  writeLines(lines, "data/processed/operational_report.md", useBytes = TRUE)
  writeLines(lines, "assets/alerts/operational_report.md", useBytes = TRUE)
  invisible(lines)
}

make_operational_alerts <- function() {
  fs::dir_create("data/processed")
  fs::dir_create("assets/alerts")

  fires <- read_firms_processed()
  alerts <- cluster_firms_points(fires)

  readr::write_csv(alerts, "data/processed/operational_alerts.csv")
  readr::write_csv(alerts, "assets/alerts/operational_alerts.csv")

  geo <- alerts_to_geojson(alerts)
  jsonlite::write_json(geo, "data/processed/operational_alerts.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")
  jsonlite::write_json(geo, "assets/alerts/operational_alerts.geojson", auto_unbox = TRUE, pretty = TRUE, null = "null")

  summary <- tibble::tibble(
    generated_at_utc = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    n_alertas = nrow(alerts),
    n_alertas_altas = sum(alerts$alerta_operativa == "alta", na.rm = TRUE),
    n_alertas_medias = sum(alerts$alerta_operativa == "media", na.rm = TRUE),
    cluster_km = alert_cluster_km(),
    max_age_hours = alert_max_age_hours()
  )
  readr::write_csv(summary, "data/processed/operational_alerts_summary.csv")
  readr::write_csv(summary, "assets/alerts/operational_alerts_summary.csv")

  write_operational_report(alerts, fires)
  message("Alertas operativas: ", nrow(alerts), " clústeres generados")
  invisible(alerts)
}
