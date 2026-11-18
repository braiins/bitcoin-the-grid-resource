# ch3_typical_hour.R -- Chapter 3: what a "typical ERCOT hour" clears at.
# Run from the repo root:
#   Rscript analysis/checks/ch3_typical_hour.R
#
# Chapter 3 says a typical ERCOT hour clears between $20 and $40 per MWh. This
# script states what that means and checks it: the middle half of hours (25th
# to 75th percentile) of hourly real-time prices, all eight load zones pooled,
# in 2025, the book's anchor year.
#
# Input: analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz, ERCOT MIS report
# 13061 (15-minute real-time settlement point prices, eight load zones, Central
# prevailing time). An hourly price here is the mean of an hour's four
# 15-minute settlement point prices; the repeated fall-back hour is kept apart
# by the file's dst_repeated_flag, so every year has 8,760 or 8,784 hours.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
library(data.table)

# Read with base R, which decompresses .gz on its own: data.table::fread() would
# need the undeclared R.utils package for a gzipped file (reported 2026-09-26).
d <- as.data.table(read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz",
                            colClasses = c(interval_start = "character"), stringsAsFactors = FALSE))
d[, year := as.integer(substr(interval_start, 1, 4))]
d[, hour := substr(interval_start, 1, 13)]
hr <- d[, .(price = mean(price), n = .N), by = .(settlement_point, year, hour, dst_repeated_flag)]
stopifnot(all(hr$n == 4))

q <- function(v) as.list(c(stats::quantile(v, c(0.25, 0.50, 0.75), names = FALSE),
                           mean(v >= 20 & v <= 40)))
fmt <- function(tag, x, n) cat(sprintf("%-22s %6d  p25 $%6.2f  median $%6.2f  p75 $%6.2f  hours in $20-40: %4.1f%%\n",
                                       tag, n, x[[1]], x[[2]], x[[3]], 100 * x[[4]]))

cat("=== Hourly real-time prices, all eight load zones pooled ===\n")
for (y in sort(unique(hr$year))) {
  v <- hr[year == y, price]
  fmt(sprintf("%d%s", y, if (length(v) < 8 * 8760) " (partial)" else ""), q(v), length(v))
}
cat("\n=== 2025 by load zone ===\n")
for (z in sort(unique(hr$settlement_point))) {
  v <- hr[year == 2025 & settlement_point == z, price]
  fmt(z, q(v), length(v))
}
v <- hr[year == 2025, price]
x <- q(v)
cat(sprintf("\nChapter 3's claim, 2025 pooled: middle half of hours $%.2f to $%.2f -> %s\n",
            x[[1]], x[[3]], if (x[[1]] >= 19.5 && x[[3]] <= 40.5) "holds ($20 to $40)" else "DOES NOT HOLD"))
