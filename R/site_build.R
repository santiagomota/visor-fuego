source("R/utils.R", encoding = "UTF-8")

read_json_if_exists <- function(path, default = list()) {
  if (!file.exists(path) || file.info(path)$size <= 2) return(default)
  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = TRUE),
    error = function(e) default
  )
}

current_madrid_date <- function() {
  as.Date(format(Sys.time(), tz = "Europe/Madrid", format = "%Y-%m-%d"))
}

site_build_payload <- function() {
  layers <- read_json_if_exists("assets/aemet/layers.json", data.frame())
  aemet_status <- read_json_if_exists("assets/aemet/status.json", list())
  firms_status <- read_json_if_exists("assets/firms/status.json", list())
  effis_status <- read_json_if_exists("assets/effis_ba/summary.json", list())

  valid_dates <- if (is.data.frame(layers) && "valid_date" %in% names(layers)) {
    suppressWarnings(as.Date(layers$valid_date))
  } else {
    as.Date(character())
  }
  valid_dates <- valid_dates[!is.na(valid_dates)]

  now_utc <- format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
  sha <- trimws(Sys.getenv("GITHUB_SHA", unset = "local"))
  run_id <- trimws(Sys.getenv("GITHUB_RUN_ID", unset = "local"))
  run_attempt <- trimws(Sys.getenv("GITHUB_RUN_ATTEMPT", unset = "1"))
  sha_short <- if (nzchar(sha) && sha != "local") substr(sha, 1, 8) else "local"
  stamp <- format(Sys.time(), tz = "UTC", format = "%Y%m%dT%H%M%SZ")
  build_id <- paste(stamp, sha_short, run_id, run_attempt, sep = "-")

  list(
    build_id = build_id,
    generated_at_utc = now_utc,
    generated_date_madrid = as.character(current_madrid_date()),
    git_sha = sha,
    github_run_id = run_id,
    github_run_attempt = run_attempt,
    aemet = list(
      issue_date = as.character(aemet_status$issue_date %||% NA_character_),
      valid_min = if (length(valid_dates)) as.character(min(valid_dates)) else NA_character_,
      valid_max = if (length(valid_dates)) as.character(max(valid_dates)) else NA_character_,
      n_layers = if (is.data.frame(layers)) nrow(layers) else 0L,
      style_sources = if (is.data.frame(layers) && "style_source" %in% names(layers)) {
        sort(unique(as.character(layers$style_source)))
      } else character()
    ),
    firms = list(
      n_detections = suppressWarnings(as.integer(firms_status$n_detections %||% NA_integer_)),
      last_observation_utc = as.character(firms_status$last_observation_utc %||% NA_character_),
      download_status = as.character(firms_status$download_status %||% NA_character_)
    ),
    effis = list(
      generated_at = as.character(effis_status$generated_at %||% NA_character_),
      n_features = suppressWarnings(as.integer(effis_status$n_features %||% NA_integer_))
    )
  )
}

write_site_build_manifest <- function(path = "assets/site-build.json") {
  payload <- site_build_payload()
  fs::dir_create(dirname(path))
  jsonlite::write_json(
    payload,
    path,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null"
  )
  message("Build del sitio: ", payload$build_id)
  message(
    "AEMET válido ", payload$aemet$valid_min %||% "s/d", " .. ", payload$aemet$valid_max %||% "s/d",
    " · emisión ", payload$aemet$issue_date %||% "s/d",
    " · FIRMS ", payload$firms$n_detections %||% "s/d"
  )
  invisible(payload)
}
