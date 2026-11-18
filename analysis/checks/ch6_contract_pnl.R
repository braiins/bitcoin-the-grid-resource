# ch6_contract_pnl.R, Chapter 6: what a megawatt-year cost in 2025 by
# contract shape, LZ_WEST. Run from the repo root:
#   Rscript analysis/checks/ch6_contract_pnl.R
#
# All rows settle on ERCOT 15-minute real-time settlement prices except the
# day-ahead index row (hourly DAM prices). Block windows follow the ICE
# ERCOT futures definitions (hour-ending, Central prevailing time):
#   5x16  = HE 0700-2200, Mon-Fri, excluding NERC holidays
#   2x16  = HE 0700-2200, Sat/Sun and NERC holidays
#   7x8   = HE 0100-0600 and HE 2300-2400, all days
#   7x24  = all hours
# NERC holidays 2025: Jan 1, May 26, Jul 4, Sep 1, Nov 27, Dec 25 (none
# fall on a weekend in 2025, so no observation shifts apply).
# Fixed-price rows use the two prices disclosed in SEC filings:
#   $27.00/MWh  ~ Cipher Odessa PPA ("approximately 2.7 c/kWh")   % src: cipher10k2024
#   $43.95/MWh  = Riot Corsicana 25 MW fixed block                % src: riot10k2024
# The flexibility option (pause when price exceeds the machine's breakeven)
# is computed in analysis/figures/fig_ch6_strike.R and is the same number
# under every contract that lets the load act on it; this script only
# prices the always-on cost of each contract shape.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))

# NOTE (2026-09-04): repointed off ercot_spp_dam_rtm15_8zones.csv.gz, which
# stores Central time as a fixed UTC-6 offset and so labels daylight-saving
# hours an hour late. Block shapes are defined by hour-ending, so that shift
# misassigned summer hours between the peak and off-peak blocks. Both sources
# below carry Central prevailing time natively.
rt <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
rt <- rt[rt$settlement_point == "LZ_WEST" & substr(rt$interval_start, 1, 4) == "2025", ]
rt$t <- as.POSIXct(rt$interval_start, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Chicago")

da <- read.csv("analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz")
da <- da[da$settlement_point == "LZ_WEST" & substr(da$hour_start, 1, 4) == "2025", ]

nerc_holidays <- as.Date(c("2025-01-01", "2025-05-26", "2025-07-04",
                           "2025-09-01", "2025-11-27", "2025-12-25"))

he   <- as.integer(substr(rt$interval_start, 12, 13)) + 1   # hour-ending 1..24
day  <- as.Date(rt$t, tz = "America/Chicago")
wday <- format(rt$t, "%u")                          # 1=Mon .. 7=Sun
biz  <- wday %in% c("1", "2", "3", "4", "5") & !(day %in% nerc_holidays)
peak_he <- he >= 7 & he <= 22

win <- list(
  `7x24` = rep(TRUE, nrow(rt)),
  `5x16` = biz & peak_he,
  `2x16` = !biz & peak_he,
  `7x8`  = he <= 6 | he >= 23
)

cat("LZ_WEST calendar 2025, 15-min real-time settlement basis\n")
for (nm in names(win)) {
  v <- rt$price[win[[nm]]]
  cat(sprintf("  %-5s mean $%6.2f/MWh over %5.0f h/yr (n=%d intervals)\n",
              nm, mean(v), length(v) / 4, length(v)))
}

cat(sprintf("  DAM (hourly) mean $%.2f/MWh (n=%d hours)\n",
            mean(da$price), nrow(da)))

# always-on cost of a flat 1 MW load, per contract shape
hours_yr <- nrow(rt) / 4
rt_cost  <- sum(rt$price) * 0.25
cat(sprintf("\nAlways-on 1 MW flat load (%.0f h):\n", hours_yr))
cat(sprintf("  RT index:      $%8.0f/MW-yr\n", rt_cost))
cat(sprintf("  DAM index:     $%8.0f/MW-yr\n", mean(da$price) * hours_yr))
for (V in c(27.00, 43.95)) {
  cat(sprintf("  fixed $%.2f:  $%8.0f/MW-yr (vs RT index: %+.0f)\n",
              V, V * hours_yr, V * hours_yr - rt_cost))
}

# The day-ahead index's cost over the real-time index is a realized gap, not a
# quoted premium: the same two MIS archives (13060 day-ahead, 13061 real-time),
# LZ_WEST, every complete calendar year in them. Day-ahead mean vs real-time
# mean, flat 1 MW, each market's own intervals. 2021 is also shown without
# February, the month of Winter Storm Uri, to show where its sign comes from.
rt_all <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
rt_all <- rt_all[rt_all$settlement_point == "LZ_WEST", ]
da_all <- read.csv("analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz")
da_all <- da_all[da_all$settlement_point == "LZ_WEST", ]
rt_all$ym <- substr(rt_all$interval_start, 1, 7)
da_all$ym <- substr(da_all$hour_start, 1, 7)
gap_line <- function(lbl, r, d) {
  cat(sprintf("  %-12s RT $%7.2f  DAM $%7.2f  DAM - RT %+6.2f%%  (%d RT intervals, %d DAM hours)\n",
              lbl, mean(r), mean(d), 100 * (mean(d) / mean(r) - 1), length(r), length(d)))
}
cat("\nLZ_WEST day-ahead minus real-time, annual means (MIS 13060 vs 13061):\n")
for (y in 2021:2025) {
  gap_line(as.character(y), rt_all$price[substr(rt_all$ym, 1, 4) == y],
           da_all$price[substr(da_all$ym, 1, 4) == y])
}
gap_line("2021 ex Feb", rt_all$price[substr(rt_all$ym, 1, 4) == "2021" & rt_all$ym != "2021-02"],
         da_all$price[substr(da_all$ym, 1, 4) == "2021" & da_all$ym != "2021-02"])
gap_line("2021-02", rt_all$price[rt_all$ym == "2021-02"], da_all$price[da_all$ym == "2021-02"])

# sanity: the option value at the two disclosed fixed prices (sell-back
# whenever price > contract price; upper bound, ignores the mining margin
# forgone below breakeven) -- printed for reference, not quoted in the book
for (V in c(27.00, 43.95)) {
  cat(sprintf("  [ref] sell-back option at $%.2f strike: $%.0f/MW-yr\n",
              V, sum(pmax(rt$price - V, 0)) * 0.25))
}
