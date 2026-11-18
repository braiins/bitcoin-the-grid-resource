# ch1_network_energy.R -- Chapter 1: how much power the bitcoin network uses,
# across the range of its one unmeasured input. Run from the repo root:
#   Rscript analysis/checks/ch1_network_energy.R
#
# Power (W) = hashrate (TH/s) x fleet-average efficiency (J/TH). The hashrate
# is measured; the fleet average is not, and nobody publishes one for the
# machines in service. Chapter 1 therefore prints a RANGE, 18 to 26 J/TH at the
# machines, as its result, and works the equation through at the author's own
# estimate, 21.5 J/TH, which the text labels as the author's. The book used 26
# J/TH as its single figure until 2026-09-26 (DATA-017); it now sits at the top
# of the range. What stands beside the range (the listed fleets that publish a
# J/TH, the revenue check on the meter basis, Cambridge's CBECI) is printed by
# analysis/checks/ch1_fleet_efficiency.R.
#
# Inputs:
#   hashrate and bitcoin price: 7-day means to 2026-08-21, read from the
#       committed daily caches analysis/data/network_hashrate_daily.csv and
#       analysis/data/btc_price_daily.csv (Braiins Insights, stitched daily).
#       Until 2026-09-25 these were typed in from a live fetch of that day
#       (927.8 EH/s, $67,076) that was never committed, so the chapter's
#       $0.033 could not be reproduced from the repository. Reading the caches
#       gives $0.032, which also agrees with chapter 4's hand calculation.
#   The power table uses the printed 930 EH/s anchor, which both sources round to.
#   block subsidy 3.125 BTC x 144 blocks a day (protocol; block 840,000).
#   world generation 2025: 32,202 TWh (Energy Institute, Statistical Review
#       of World Energy 2026, EIStatReview2026).
#   PUE 1.10 (CBECI2026 methodology, Assumption 8, its best guess): the site
#       meter draws a tenth more than the machines (cooling, transformers).
#       Chapter 1's headline energy and its share of generation are stated at
#       the meter, because world generation, the IEA's data-centre total and
#       CBECI's own power figure are all grid-side quantities; the machine
#       figures are the worked example's (DATA-017 review, 2026-09-26).
#   breakeven efficiency at power price P ($/MWh), J/TH:
#       hashprice ($/TH/day) x 1e6 / (24 x P), i.e. hashprice x 41,667 / P,
#       the formula chapter 4 derives.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))

HASHRATE_EHS   <- 930       # printed anchor
SUBSIDY_BTC    <- 3.125 * 144
GEN_2025_TWH   <- 32202
EFF_AUTHOR     <- 21.5      # the author's estimate, the chapter's worked example
EFF_RANGE      <- c(18, 26)  # the chapter's headline range
PUE_BEST       <- 1.10      # CBECI2026 Assumption 8: meter / machines

# the anchors, read from the committed caches: 7 days to 2026-08-21
win <- function(df) df[as.Date(df$date) > as.Date("2026-08-14") & as.Date(df$date) <= as.Date("2026-08-21"), ]
h <- win(read.csv("analysis/data/network_hashrate_daily.csv", stringsAsFactors = FALSE))
b <- win(read.csv("analysis/data/btc_price_daily.csv", stringsAsFactors = FALSE))
stopifnot(nrow(h) == 7, nrow(b) == 7)
HASHRATE_EXACT <- mean(h$ehs)
BTC_USD        <- mean(b$usd)
cat(sprintf("Committed caches, 7 days to 2026-08-21: hashrate %.1f EH/s (printed anchor %g), bitcoin $%s\n\n",
            HASHRATE_EXACT, HASHRATE_EHS, format(round(BTC_USD), big.mark = ",")))

# power and energy across the efficiency range (17 and 30 are printed for context, outside it)
cat("=== Network power and energy at 930 EH/s, at the machines ===\n")
cat(sprintf("%8s %10s %12s %22s\n", "J/TH", "GW", "TWh/year", "share of 2025 gen."))
for (e in c(17, EFF_RANGE[1], EFF_AUTHOR, EFF_RANGE[2], 30)) {
  gw  <- HASHRATE_EHS * 1e6 * e / 1e9                       # TH/s x J/TH = W
  twh <- gw * 8760 / 1000
  cat(sprintf("%8g %10.2f %12.1f %21.2f%%%s\n", e, gw, twh, 100 * twh / GEN_2025_TWH,
              if (e == EFF_AUTHOR) "   <- the author's estimate" else if (e %in% EFF_RANGE) "   <- end of the range" else ""))
}
w_auth <- HASHRATE_EHS * 1e6 * EFF_AUTHOR
gw_r <- HASHRATE_EHS * EFF_RANGE / 1e3; twh_r <- gw_r * 8.76
cat(sprintf("\nAs printed: %s W = %.1f GW x 8,760 h = %.1f TWh/year, %.2f%% of %s TWh (the author's estimate)\n",
            format(w_auth, big.mark = ",", scientific = FALSE), w_auth / 1e9, w_auth / 1e9 * 8.76, 100 * w_auth / 1e9 * 8.76 / GEN_2025_TWH,
            format(GEN_2025_TWH, big.mark = ",")))
cat(sprintf("the range: %.1f to %.1f GW, %.1f to %.1f TWh/year, %.2f%% to %.2f%% of 2025 generation\n\n",
            gw_r[1], gw_r[2], twh_r[1], twh_r[2], 100 * twh_r[1] / GEN_2025_TWH, 100 * twh_r[2] / GEN_2025_TWH))

# the same at the grid meter: what the grid supplies, the basis of the headline and of the share of generation
cat(sprintf("=== The same at the grid meter (PUE %.2f, CBECI's best guess) ===\n", PUE_BEST))
cat(sprintf("%8s %10s %12s %22s\n", "J/TH", "GW", "TWh/year", "share of 2025 gen."))
for (e in c(EFF_RANGE[1], EFF_AUTHOR, EFF_RANGE[2])) {
  gw  <- HASHRATE_EHS * e * PUE_BEST / 1e3
  twh <- gw * 8.76
  cat(sprintf("%8g %10.2f %12.1f %21.2f%%%s\n", e, gw, twh, 100 * twh / GEN_2025_TWH,
              if (e == EFF_AUTHOR) "   <- the author's estimate" else "   <- end of the range"))
}
gw_m <- gw_r * PUE_BEST; twh_m <- gw_m * 8.76; twh_am <- w_auth / 1e9 * PUE_BEST * 8.76
cat(sprintf("at the meter: the range %.1f to %.1f GW, %.1f to %.1f TWh/year, %.2f%% to %.2f%% of 2025 generation; the author's estimate %.1f GW, %.1f TWh/year, %.2f%%\n\n",
            gw_m[1], gw_m[2], twh_m[1], twh_m[2], 100 * twh_m[1] / GEN_2025_TWH, 100 * twh_m[2] / GEN_2025_TWH,
            w_auth / 1e9 * PUE_BEST, twh_am, 100 * twh_am / GEN_2025_TWH))

# the profitability bound the chapter uses as a sanity check
hp <- SUBSIDY_BTC * BTC_USD / (HASHRATE_EXACT * 1e6)        # $/TH/day, subsidy only
cat("=== Profitability bound (block subsidy only, fees excluded) ===\n")
cat(sprintf("hashprice = %g BTC x $%s / %.1fM TH/s = $%.5f per TH-day\n",
            SUBSIDY_BTC, format(round(BTC_USD), big.mark = ","), HASHRATE_EXACT, hp))
for (P in c(40, 50, 60))
  cat(sprintf("  breakeven efficiency at $%d/MWh: %.1f J/TH\n", P, hp * 1e6 / (24 * P)))
for (e in c(EFF_RANGE[1], EFF_AUTHOR, EFF_RANGE[2]))
  cat(sprintf("  a %g J/TH average stays under the bound for a fleet paying up to $%.1f/MWh\n",
              e, hp * 1e6 / (24 * e)))
