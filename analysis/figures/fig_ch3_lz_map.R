# fig_ch3_lz_map.R, Chapter 3: ERCOT load zones map with generation nodes
# Output: book/images/ercot_lz_map.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch3_lz_map.R
#
# Layers and provenance (all print/repo-safe; verified 2026-08-22):
#   1. Texas state outline: U.S. Census Bureau cartographic boundary file
#      cb_2023_us_state_20m (public domain).
#      https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_state_20m.zip
#   2. Load-zone polygons: the four competitive load zones (LZ_HOUSTON,
#      LZ_NORTH, LZ_SOUTH, LZ_WEST) from the only public vector source, an
#      ArcGIS-hosted layer (ICF; unlicensed re-host, geometry evidently
#      traced from ERCOT's published load-zone map). ERCOT publishes NO
#      official vector geodata for load zones (they are electrical
#      constructs: sets of buses, per data product NP4-160-SG). Boundaries
#      are therefore APPROXIMATE and the caption must say so. The four NOIE
#      zones (LZ_AEN, LZ_CPS, LZ_LCRA, LZ_RAYBN) have no public polygons:
#      they are non-contiguous enclaves and are noted in the caption only.
#      https://services3.arcgis.com/fwwoCWVtaahwlvxO/ArcGIS/rest/services/ERCOT_Load_Zones/FeatureServer/7/query?where=1%3D1&outFields=NAME&outSR=4326&f=geojson
#   3. Node dots: generation-side nodes approximated by power-plant
#      locations from EIA-860M (June 2026), sheet "Operating", filtered to
#      Balancing Authority Code == "ERCO" (public domain; 988 plants,
#      ~180 GW nameplate). True node/bus coordinates are not published by
#      ERCOT (secured infrastructure information).
#      https://www.eia.gov/electricity/data/eia860m/xls/june_generator2026.xlsx
#
# Derived caches committed to the repo (rebuilt here if missing):
#   analysis/data/ercot_load_zones.geojson   (simplified, WGS84)
#   analysis/data/ercot_plants_erco_2026-06.csv
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages({
  library(sf)
  library(ggplot2)
})

dir.create("analysis/data", showWarnings = FALSE)
zones_path  <- "analysis/data/ercot_load_zones.geojson"
plants_path <- "analysis/data/ercot_plants_erco_2026-06.csv"

# ---- rebuild derived caches from raw sources if missing -------------------
if (!file.exists(zones_path)) {
  url <- paste0("https://services3.arcgis.com/fwwoCWVtaahwlvxO/ArcGIS/rest/",
                "services/ERCOT_Load_Zones/FeatureServer/7/query",
                "?where=1%3D1&outFields=NAME&outSR=4326&f=geojson")
  raw <- st_read(url, quiet = TRUE)
  # simplify in a metric CRS (Texas Centric Albers, EPSG:3083); 1.5 km
  # tolerance is invisible at 124 mm print width
  simp <- st_transform(raw, 3083) |> st_simplify(dTolerance = 1500) |>
    st_transform(4326)
  st_write(simp[, "NAME"], zones_path, quiet = TRUE)
}
if (!file.exists(plants_path)) {
  library(readxl)
  tmp <- tempfile(fileext = ".xlsx")
  download.file(paste0("https://www.eia.gov/electricity/data/eia860m/xls/",
                       "june_generator2026.xlsx"), tmp, quiet = TRUE)
  x <- read_excel(tmp, sheet = "Operating", skip = 2)
  erco <- x[!is.na(x[["Balancing Authority Code"]]) &
              x[["Balancing Authority Code"]] == "ERCO", ]
  agg <- aggregate(cbind(mw = erco[["Nameplate Capacity (MW)"]]),
                   by = list(plant_id = erco[["Plant ID"]],
                             plant = erco[["Plant Name"]],
                             lat = erco$Latitude, lon = erco$Longitude),
                   FUN = sum)
  write.csv(agg, plants_path, row.names = FALSE)
}

# ---- load layers ----------------------------------------------------------
crs_tx <- 3083  # Texas Centric Albers Equal Area
zones  <- st_read(zones_path, quiet = TRUE) |> st_transform(crs_tx)
plants <- read.csv(plants_path)
plants_sf <- st_as_sf(plants, coords = c("lon", "lat"), crs = 4326) |>
  st_transform(crs_tx)

# Texas outline from the Census 20m cartographic boundary file (cached)
tx_path <- "analysis/data/texas_outline.geojson"
if (!file.exists(tx_path)) {
  tmpz <- tempfile(fileext = ".zip"); tmpd <- tempfile()
  download.file(paste0("https://www2.census.gov/geo/tiger/GENZ2023/shp/",
                       "cb_2023_us_state_20m.zip"), tmpz, quiet = TRUE)
  unzip(tmpz, exdir = tmpd)
  st_read(file.path(tmpd, "cb_2023_us_state_20m.shp"), quiet = TRUE) |>
    subset(STUSPS == "TX") |> st_geometry() |> st_write(tx_path, quiet = TRUE)
}
texas <- st_read(tx_path, quiet = TRUE) |> st_transform(crs_tx)

# ---- styling --------------------------------------------------------------
ink <- "#3a3a3a"
# LZ_WEST slightly darker: it is the book's home zone
zone_fill <- c(Houston = "grey82", North = "grey93", South = "grey88",
               West = "grey76")
zones$fill <- zone_fill[zones$NAME]
zones$label <- paste0("LZ_", toupper(zones$NAME))

# manual label anchors (WGS84), adjusted so labels sit inside their zones
lab <- data.frame(
  label = c("LZ_NORTH", "LZ_WEST", "LZ_SOUTH", "LZ_HOUSTON"),
  lon = c(-96.9, -101.5, -98.6, -95.75),
  lat = c(33.5, 32.4, 27.9, 30.62)
)
lab_sf <- st_as_sf(lab, coords = c("lon", "lat"), crs = 4326) |>
  st_transform(crs_tx)
lab_xy <- cbind(lab, st_coordinates(lab_sf))

cities <- data.frame(
  name = c("Dallas", "Houston", "Austin", "San Antonio", "Midland"),
  lon = c(-96.80, -95.37, -97.74, -98.49, -102.08),
  lat = c(32.78, 29.76, 30.27, 29.42, 32.00),
  nudge = c(1, 1, -1, -1, -1)  # label above (1) or below (-1) the marker
)
cities_sf <- st_as_sf(cities, coords = c("lon", "lat"), crs = 4326) |>
  st_transform(crs_tx)
cities_xy <- cbind(cities, st_coordinates(cities_sf))

# "not ERCOT" annotations for the visible gaps (El Paso, upper Panhandle)
gaps <- data.frame(
  label = c("El Paso:\nWestern grid", "upper Panhandle:\nEastern grid"),
  lon = c(-105.4, -101.9), lat = c(31.0, 35.85)
)
gaps_sf <- st_as_sf(gaps, coords = c("lon", "lat"), crs = 4326) |>
  st_transform(crs_tx)
gaps_xy <- cbind(gaps, st_coordinates(gaps_sf))

p <- ggplot() +
  geom_sf(data = texas, fill = "white", color = NA) +
  geom_sf(data = zones, aes(fill = fill), color = "white", linewidth = 0.35,
          show.legend = FALSE) +
  scale_fill_identity() +
  geom_sf(data = texas, fill = NA, color = "grey55", linewidth = 0.3) +
  geom_sf(data = plants_sf, color = ink, size = 0.35, alpha = 0.45,
          shape = 16) +
  geom_point(data = cities_xy, aes(X, Y), shape = 23, size = 1.6,
             fill = "white", color = "grey15", stroke = 0.5) +
  geom_text(data = cities_xy, aes(X, Y + nudge * 26000, label = name),
            size = 2.1, color = "grey15",
            vjust = ifelse(cities_xy$nudge > 0, 0, 1)) +
  geom_text(data = lab_xy, aes(X, Y, label = label), size = 2.9,
            fontface = "bold", color = "grey25", family = "sans") +
  geom_text(data = gaps_xy, aes(X, Y, label = label), size = 2.0,
            fontface = "italic", color = "grey50", lineheight = 0.95) +
  theme_void(base_size = 9) +
  theme(
    plot.margin = margin(2, 2, 2, 2)
  )

ggsave("book/images/ercot_lz_map.png", p,
       width = 124, height = 112, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/ercot_lz_map.pdf", p,
       width = 124, height = 112, units = "mm", bg = "white")
cat("Wrote book/images/ercot_lz_map.png and .pdf\n")
