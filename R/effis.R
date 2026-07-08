source("R/utils.R", encoding = "UTF-8")

effis_enabled <- function() {
  tolower(Sys.getenv("EFFIS_ENABLE", unset = "true")) %in% c("true", "1", "yes", "si", "sí")
}

effis_date <- function() {
  Sys.getenv("EFFIS_DATE", unset = as.character(Sys.Date()))
}

effis_wms_base <- function() {
  Sys.getenv("EFFIS_WMS_BASE", unset = "https://maps.effis.emergency.copernicus.eu/effis")
}

effis_layer_config <- function() {
  layers <- strsplit(Sys.getenv("EFFIS_WMS_LAYERS", unset = "ecmwf007.fwi"), ",")[[1]] |> trimws()
  labels <- strsplit(Sys.getenv("EFFIS_WMS_LABELS", unset = "EFFIS - FWI"), ",")[[1]] |> trimws()

  if (length(labels) < length(layers)) {
    labels <- c(labels, paste("EFFIS", seq_along(layers))[(length(labels) + 1):length(layers)])
  }

  tibble::tibble(
    layer = layers[nzchar(layers)],
    label = labels[seq_along(layers)][nzchar(layers)],
    date = effis_date(),
    base_url = effis_wms_base()
  )
}

add_effis_wms_layers <- function(map) {
  if (!effis_enabled()) return(map)

  cfg <- effis_layer_config()
  if (nrow(cfg) == 0) return(map)

  for (i in seq_len(nrow(cfg))) {
    map <- leaflet::addWMSTiles(
      map,
      baseUrl = cfg$base_url[i],
      layers = cfg$layer[i],
      group = cfg$label[i],
      options = leaflet::WMSTileOptions(
        format = "image/png",
        transparent = TRUE,
        version = "1.1.1",
        time = cfg$date[i]
      ),
      attribution = "EFFIS/Copernicus EMS"
    )
  }

  map
}

effis_overlay_groups <- function() {
  if (!effis_enabled()) return(character())
  effis_layer_config()$label
}
