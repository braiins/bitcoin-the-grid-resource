# ch5_oracle_check.R: reproduces the oracle-plausibility numbers printed in
# chapter 5, section "The Report Card: Chasing the Oracle".
# Run from the repo root:  Rscript analysis/checks/ch5_oracle_check.R
#
# Chapter 5's Figure 5.5 comes from the replication kit
# (analysis/ch5-backtest/mixed_basis_study.py): out of sample the full loop
# captures 98.1% (S21 XP) and 96.2% (S19j Pro) of the oracle's GAIN over
# running at stock power without pausing, 95.1% and 92.8% in the 2024 tuning
# year. This check is independent of that simulator, computed entirely from
# repo data: a pause-only S19j Pro at stock settings on the 2025 LZ_WEST
# real-time 5-minute prices.
#   oracle    = perfect foresight: skip exactly the loss-making intervals
#   always-on = never pause
#   1-lag     = persistence: run iff the PREVIOUS interval was profitable
# It reports both yardsticks: the share of the oracle's PROFIT, and the share
# of the oracle's GAIN over always-on. Chapter 5 prints only the share of
# intervals below breakeven from it. Its ratios are NOT Figure 5.5's: this
# oracle only pauses, at stock power, and decides and bills on the same
# five-minute print, so its gain is a smaller, pause-only one. Figure 5.5's
# oracle also moves the power target and bills the 15-minute settlement
# price; against it, pausing alone at stock power captures 22% (S21 XP) and
# 65% (S19j Pro) of the gain out of sample
# (analysis/ch5-backtest/baselines_study.py). What this check does show is
# why a lagged rule lands near a pause-only oracle: only ~14% of intervals sit
# above breakeven, and misclassification happens only at the breakeven
# boundary, where the per-interval margin is ~zero by definition.
#
# Data: analysis/data/ercot_spp_rtm5_lzwest.csv.gz, ERCOT real-time 5-minute
# settlement point prices, LZ_WEST, filtered to calendar 2025 (UTC stamps).
# Fetched straight from ERCOT's Market Information System; no third-party
# platform sits between this script and the market facts.
# Machine: S19j Pro stock (104 TH/s, 3,068 W; bitmain2021s19jpro).
# Hashprice: 2025 mean, $0.050785/TH/day (analysis/data/hashprice_daily.csv),
# truncated to $0.0507 as chapter 4's source comments do (see ch5_stakes.py).
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))

prices <- read.csv(gzfile("analysis/data/ercot_spp_rtm5_lzwest.csv.gz"),
                   stringsAsFactors = FALSE)
prices <- prices[substr(prices$interval_start, 1, 4) == "2025", ]
prices <- prices[order(prices$interval_start), ]
s <- prices$price
HP <- 0.0507; TH <- 104; W <- 3068

rev_5min <- HP * TH / 288                    # $ per 5-minute interval
cost_5min <- (W / 1e6) * (5 / 60) * s        # $ per interval at each price
margin <- rev_5min - cost_5min

oracle   <- sum(pmax(margin, 0))
always   <- sum(margin)
one_lag  <- sum(margin[-1][margin[-length(margin)] > 0])
be <- HP * 3.6e9 / ((W / TH) * 86400)

cat(sprintf("n intervals:          %d\n", length(s)))
cat(sprintf("stock breakeven:      $%.1f/MWh\n", be))
cat(sprintf("intervals above BE:   %.1f%%  (below: %.1f%%)\n",
            100 * mean(s > be), 100 * mean(s <= be)))
cat(sprintf("oracle profit:        $%.0f/machine-year\n", oracle))
cat(sprintf("always-on:            %.1f%% of oracle\n", 100 * always / oracle))
cat(sprintf("1-interval-lag rule:  %.1f%% of oracle\n", 100 * one_lag / oracle))
cat(sprintf("gain over always-on:  1-lag rule captures %.1f%% of the oracle's gain\n",
            100 * (one_lag - always) / (oracle - always)))
