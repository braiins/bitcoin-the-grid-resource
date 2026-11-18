# Chapter 8 generation-based demand proxy, from ERCOT's Fuel Mix Report.
# Sum interval MWh across fuels, multiply by four for MW. WSL adjustments are
# included in Other in 2019-2021, then reported separately (negative) from 2022.
# Net DC-tie imports are omitted; do not subtract storage charging a second time.
# This settlement reconstruction is not a live demand feed; INITIAL months at
# the edge retain that status in the cache. No Native Load gap-fill is used.
# All consumers get complete months and an exact UTC calendar grid, including
# 92 / 96 / 100 intervals on each Central operating day.
load_demand <- function(verbose = TRUE) {
  tz <- "America/Chicago"
  z <- read.csv("analysis/data/ercot_fuel_mix_15min_2019on.csv.gz", stringsAsFactors = FALSE)
  fuels <- c("Biomass", "Coal", "Gas", "Gas-CC", "Hydro", "Nuclear", "Other", "Solar", "WSL", "Wind")
  # read.csv normalizes Gas-CC to Gas.CC.
  demand <- 4 * rowSums(z[, make.names(fuels)])
  stopifnot(all(is.finite(demand)), all(z$dst_repeated_flag %in% c("N", "Y")))
  key <- paste(z$interval_start, z$dst_repeated_flag)
  stopifnot(!anyDuplicated(key))
  first <- min(substr(z$interval_start, 1, 10))
  last <- max(substr(z$interval_start, 1, 10))
  stopifnot(first == "2019-01-01", format(as.Date(last) + 1, "%d") == "01")
  t0 <- as.POSIXct(first, tz = tz)
  t1 <- as.POSIXct(as.character(as.Date(last) + 1), tz = tz)
  t <- seq(t0, t1 - 900, by = 900)
  loc <- format(t, "%Y-%m-%dT%H:%M:%S", tz = tz)
  flag <- ifelse(duplicated(loc), "Y", "N")
  i <- match(paste(loc, flag), key)
  stopifnot(length(i) == nrow(z), !anyNA(i))
  day <- substr(loc, 1, 10)
  days <- sort(unique(day))
  expected <- as.numeric(difftime(as.POSIXct(as.character(as.Date(days) + 1), tz = tz),
                                as.POSIXct(days, tz = tz), units = "hours")) * 4
  stopifnot(all(table(day) == expected), all(expected %in% c(92, 96, 100)))
  if (verbose) {
    cat(sprintf("Complete ERCOT fuel-mix proxy: %s to %s, %d intervals; no gap-fill.\n", first, last, length(t)))
    print(table(year = substr(day, 1, 4), settlement = z$settlement_type[i]))
    cat("MW = 4 x summed fuel MWh, including WSL (inside Other before 2022); DC-tie flows omitted.\n\n")
  }
  zz <- format(t, "%z", tz = tz)
  # Workbook ending labels use the operating-day clock, including 24:00.
  naive_end <- as.POSIXct(loc, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC") + 900
  te <- format(naive_end, "%H:%M", tz = "UTC"); te[te == "00:00"] <- "24:00"
  data.frame(deliveryStart = paste0(loc, substr(zz, 1, 3), ":", substr(zz, 4, 5)),
             deliveryDate = day, timeEnding = te, demand = demand[i], filled = FALSE,
             stringsAsFactors = FALSE)
}
