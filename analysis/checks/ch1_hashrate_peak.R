# ch1_hashrate_peak.R -- Chapters 1 and 4, glossary: when network hashrate
# peaked, and how much of it 2026 gave back. Run from the repo root:
#   Rscript analysis/checks/ch1_hashrate_peak.R
#
# Series: analysis/data/network_hashrate_daily.csv (Braiins Insights
# hashrate-and-difficulty-history, stitched to daily by
# analysis/figures/fig_ch4_hashprice_cycle.R), the same cache chapter 1's
# 930 EH/s comes from and the series chapter 4's middle panel plots.
#
# One estimator: the 7-day mean (the 7 days ending on the date named), the
# estimator of chapter 1's 930 EH/s. Peak and give-back are both read on it,
# so the comparison never mixes a single day with a weekly mean. Daily
# values are printed beside it for reference only: a daily hashrate is an
# estimate from one day's blocks, and wherever the API frame this cache is
# stitched from is coarser than a day, a linearly interpolated one.
# The ch1 figure's snapshot (analysis/data/braiins_hashrate_difficulty_all.json,
# one point about every 62 days) is printed last only to show that it agrees
# on the period; it is a plotting series, not the estimator.
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))
suppressMessages(library(jsonlite))

hr <- read.csv("analysis/data/network_hashrate_daily.csv", stringsAsFactors = FALSE)
hr$date <- as.Date(hr$date)
stopifnot(!anyNA(hr$ehs), all(diff(hr$date) == 1))
hr$m7 <- as.numeric(stats::filter(hr$ehs, rep(1 / 7, 7), sides = 1))

at <- function(d) hr[hr$date == as.Date(d), ]
top <- function(df, col) df[which.max(df[[col]]), ]

cat(sprintf("Daily cache %s to %s (%d days)\n", min(hr$date), max(hr$date), nrow(hr)))
cat(sprintf("  start: %.1f EH/s on %s; 7-day mean %.1f in the first week, to %s\n",
            hr$ehs[1], hr$date[1], hr$m7[7], hr$date[7]))

# 7-day means: the estimator
pk  <- top(hr, "m7")
h26 <- top(hr[hr$date >= as.Date("2026-01-01"), ], "m7")
anc <- at("2026-08-21")
end <- tail(hr, 1)
cat("\n7-day means (the estimator)\n")
cat(sprintf("  peak:      %.1f EH/s, week to %s\n", pk$m7, pk$date))
cat(sprintf("  2026 high: %.1f EH/s, week to %s, below the peak\n", h26$m7, h26$date))
cat(sprintf("  ch1 anchor: %.1f EH/s, week to %s: %.1f%% given back\n",
            anc$m7, anc$date, 100 * (1 - anc$m7 / pk$m7)))
cat(sprintf("  last week:  %.1f EH/s, week to %s (the ch4 panel's end): %.1f%% given back\n",
            end$m7, end$date, 100 * (1 - end$m7 / pk$m7)))

# daily values, for reference
dpk <- top(hr, "ehs")
d26 <- top(hr[hr$date >= as.Date("2026-01-01"), ], "ehs")
cat("\nDaily values (reference only)\n")
cat(sprintf("  daily max: %.1f EH/s on %s\n", dpk$ehs, dpk$date))
cat(sprintf("  2026 daily high: %.1f EH/s on %s\n", d26$ehs, d26$date))
cat(sprintf("  daily to daily: %.1f%% given back to %.1f on %s, %.1f%% to %.1f on %s\n",
            100 * (1 - anc$ehs / dpk$ehs), anc$ehs, anc$date,
            100 * (1 - end$ehs / dpk$ehs), end$ehs, end$date))

snap <- fromJSON("analysis/data/braiins_hashrate_difficulty_all.json")$hashrate$global
s <- which.max(snap$y)
cat(sprintf("\nch1 figure snapshot (%d points): highest sampled point %.1f EH/s on %s\n",
            nrow(snap), snap$y[s], substr(snap$x[s], 1, 10)))
