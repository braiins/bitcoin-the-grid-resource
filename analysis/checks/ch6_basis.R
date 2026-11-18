# ch6_basis.R, Chapter 6: how big basis is for a West Texas mine. Run from the
# repo root:
#   Rscript analysis/checks/ch6_basis.R
#
# Basis is the gap between the hub a futures block settles at and the load
# zone price the mine pays. Both sides here are ERCOT 15-minute real-time
# settlement point prices from MIS report 13061: the load zone from
# analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz, the hubs from
# analysis/data/ercot_rtm15_spp_hubs_2021on.csv.gz (the same report's HB_NORTH
# and HB_WEST rows, fetch_ercot_rtm15_spp_history.py --hubs, pinned to end
# where the load-zone file ends, 2026-08-29). They join interval for interval
# on (interval_start, dst_repeated_flag).
#
# Printed for LZ_WEST against each hub, and against LZ_NORTH for reference:
#   * the all-hours annual mean of zone minus hub, 2021 to 2026-08-29;
#   * the same inside the 5x16 window a peak block covers, and what that gap
#     comes to over a year for 1 MW held through the window (the mismatch a
#     1 MW 5x16 block bought at the hub leaves a West mine holding);
#   * for 2025, the mean absolute interval gap and its 5th/95th percentiles.
# The 5x16 window is chapter 6's (ch6_contract_pnl.R): hours ending 07-22,
# Monday to Friday, excluding NERC holidays (ICE's definition). NERC holidays:
# New Year's, Memorial, Independence, Labor, Thanksgiving and Christmas Days,
# a Sunday holiday observed the Monday after, a Saturday one not moved.
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))

lz  <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz", stringsAsFactors = FALSE)
hub <- read.csv("analysis/data/ercot_rtm15_spp_hubs_2021on.csv.gz", stringsAsFactors = FALSE)
key <- c("interval_start", "dst_repeated_flag")
side <- function(d, pt, nm) { d <- d[d$settlement_point == pt, c(key, "price")]; names(d)[3] <- nm; d }
w <- Reduce(function(a, b) merge(a, b, by = key),
            list(side(lz, "LZ_WEST", "west"), side(lz, "LZ_NORTH", "lz_north"),
                 side(hub, "HB_NORTH", "hb_north"), side(hub, "HB_WEST", "hb_west")))
stopifnot(nrow(w) == sum(lz$settlement_point == "LZ_WEST"),     # every zone interval has both hubs
          nrow(w) == sum(hub$settlement_point == "HB_NORTH"))
cat(sprintf("joined %d intervals, %s to %s\n", nrow(w), min(w$interval_start), max(w$interval_start)))

nerc_holidays <- function(y) {
  obs <- function(d) if (format(d, "%u") == "7") d + 1 else d
  last_mon_may <- max(Filter(function(d) format(d, "%u") == "1", as.Date(sprintf("%d-05-%02d", y, 25:31))))
  first_mon_sep <- min(Filter(function(d) format(d, "%u") == "1", as.Date(sprintf("%d-09-%02d", y, 1:7))))
  fourth_thu_nov <- Filter(function(d) format(d, "%u") == "4", as.Date(sprintf("%d-11-%02d", y, 22:28)))
  as.Date(c(obs(as.Date(sprintf("%d-01-01", y))), last_mon_may, obs(as.Date(sprintf("%d-07-04", y))),
            first_mon_sep, fourth_thu_nov, obs(as.Date(sprintf("%d-12-25", y)))))
}
# the same six days ch6_contract_pnl.R lists by hand for 2025
stopifnot(identical(nerc_holidays(2025), as.Date(c("2025-01-01", "2025-05-26", "2025-07-04",
                                                  "2025-09-01", "2025-11-27", "2025-12-25"))))
hol <- do.call(c, lapply(2021:2026, nerc_holidays))

w$year <- as.integer(substr(w$interval_start, 1, 4))
day <- as.Date(substr(w$interval_start, 1, 10))
he  <- as.integer(substr(w$interval_start, 12, 13)) + 1           # hour-ending 1..24
w$pk <- format(day, "%u") %in% as.character(1:5) & !(day %in% hol) & he >= 7 & he <= 22

pairs <- c(`LZ_WEST - HB_NORTH` = "hb_north", `LZ_WEST - HB_WEST` = "hb_west",
           `LZ_WEST - LZ_NORTH` = "lz_north")
for (nm in names(pairs)) {
  d <- w$west - w[[pairs[[nm]]]]
  cat(sprintf("\n%s, $/MWh (15-minute real-time settlement prices, MIS 13061)\n", nm))
  cat(sprintf("  %-12s %9s %9s %16s %8s\n", "year", "all hours", "5x16", "1 MW 5x16, $/yr", "5x16 h"))
  for (y in sort(unique(w$year))) {
    s <- w$year == y
    lbl <- if (y == 2026) "2026 to 8-29" else as.character(y)
    cat(sprintf("  %-12s %+9.2f %+9.2f %16s %8.0f\n", lbl, mean(d[s]), mean(d[s & w$pk]),
                format(round(sum(d[s & w$pk]) * 0.25), big.mark = ","), sum(s & w$pk) * 0.25))
  }
  s25 <- w$year == 2025
  q <- quantile(d[s25], c(0.05, 0.95))
  cat(sprintf("  2025: mean absolute gap $%.2f; 5th percentile %+.2f, 95th %+.2f\n",
              mean(abs(d[s25])), q[[1]], q[[2]]))
}
