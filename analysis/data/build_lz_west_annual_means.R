# build_lz_west_annual_means.R: rebuild the LZ_WEST annual price aggregates
# used as cross-checks in chapters 4 and 6, entirely from ERCOT's own published
# market data. Run from the repo root:
#   Rscript analysis/data/build_lz_west_annual_means.R
#
# Writes:
#   analysis/data/lz_west_rt_annual_means.csv   (5-minute real-time)
#   analysis/data/lz_west_dam_annual_means.csv  (hourly day-ahead)
#
# Inputs, both fetched straight from ERCOT's Market Information System by
# analysis/data/fetch_ercot_rtm15_spp_history.py (reportTypeIds 13061 and
# 13060) and analysis/data/fetch_lz_west_ercot.py:
#   analysis/data/ercot_spp_rtm5_lzwest.csv.gz
#   analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz
#
# These two outputs were previously carried as opaque CSVs derived from
# third-party platform exports. They are now derived here so the repository
# produces them from ERCOT's own numbers and nothing sits in between.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))

summarise <- function(df, year_col, price_col, n_name) {
  years <- sort(unique(substr(df[[year_col]], 1, 4)))
  out <- do.call(rbind, lapply(years, function(y) {
    v <- df[[price_col]][substr(df[[year_col]], 1, 4) == y]
    data.frame(
      year   = as.integer(y),
      n      = length(v),
      mean   = round(mean(v), 2),
      median = round(stats::median(v), 2),
      min    = round(min(v), 2),
      max    = round(max(v), 2),
      pct_negative = round(100 * sum(v < 0) / length(v), 1)
    )
  }))
  names(out)[2] <- n_name
  out
}

rt <- read.csv(gzfile("analysis/data/ercot_spp_rtm5_lzwest.csv.gz"),
               stringsAsFactors = FALSE)
rt <- rt[rt$settlement_point == "LZ_WEST", ]
rt_out <- summarise(rt, "interval_start", "price", "n_intervals_5min")
write.csv(rt_out, "analysis/data/lz_west_rt_annual_means.csv", row.names = FALSE)

dam <- read.csv(gzfile("analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz"),
                stringsAsFactors = FALSE)
dam <- dam[dam$settlement_point == "LZ_WEST", ]
dam_out <- summarise(dam, "hour_start", "price", "n_hours")
write.csv(dam_out, "analysis/data/lz_west_dam_annual_means.csv", row.names = FALSE)

cat("real-time, 5-minute:\n"); print(rt_out, row.names = FALSE)
cat("\nday-ahead, hourly:\n"); print(dam_out, row.names = FALSE)
cat(sprintf("\n2025 real-time mean: $%.2f/MWh  (the book's $42.18 anchor is the\n",
            rt_out$mean[rt_out$year == 2025]))
cat("15-minute settlement mean, a different series; see chapter 4.)\n")
