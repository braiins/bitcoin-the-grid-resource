# sell_vs_mine.R -- the owner-generator's choice: burn the megawatt-hour into
# hashes, or sell it? Run from the repo root:
#   Rscript analysis/checks/sell_vs_mine.R
#
# Decision rule: mine while the machine's implied value of a megawatt-hour (V,
# chapter 4's breakeven power price) exceeds the price the grid pays (P). Fuel
# cost sits on both sides and cancels; ASIC capital is sunk. Revenue per
# interval is therefore max(V, P), and the value of holding the option to sell
# is the excess sum(max(P - V, 0)) over the year.
#
# The same dollars are what a price-responsive BUYER saves by pausing above the
# strike, so the script reports the gain against two denominators:
#   * an owner-generator's revenue  (V x hours), and
#   * a spot buyer's profit         (V x hours - power cost),
# because the second is the base chapter 5 uses for its curtailment uplift.
#
# Data: analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz -- ERCOT's own
# 15-minute Real-Time Market settlement point prices (MIS report 13061), built
# by analysis/data/fetch_ercot_rtm15_spp_history.py. Credential-free.
# Machine values: chapter 4's 2025 breakevens, $71.6/MWh (S19j Pro) and
# $156.5/MWh (S21 XP), rounded to $72 and $157 in prose.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))

z <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
z$year <- as.integer(substr(z$interval_start, 1, 4))
H <- 0.25  # hours per settlement interval

# ---- integrity check against the cache the book previously used ------------
# FINDING (2026-09-04): analysis/data/ercot_spp_dam_rtm15_8zones.csv.gz stores
# Central time as a FIXED UTC-6 offset, so every timestamp inside daylight
# saving (roughly March to November, which includes every 4CP interval) is
# labelled ONE HOUR LATE. Both its dam and rtm15 rows are affected. Annual
# means barely move, but anything keyed to clock time is wrong by an hour.
# Verified below and by spot check: the true LZ_WEST price for the interval
# 2025-08-18 17:00-17:15 is $16.95; the old cache carries $16.95 at 18:00 and
# $20.20 at 17:00.
cat("=== Old cache vs ERCOT's own archive: the daylight-saving offset ===\n")
old <- read.csv("analysis/data/ercot_spp_dam_rtm15_8zones.csv.gz")
old <- old[old$market == "rtm15" & old$settlement_point == "LZ_WEST", ]
old$t <- as.POSIXct(old$interval_start, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
attr(old$t, "tzone") <- "America/Chicago"
old <- old[!duplicated(old$t), ]
old$isdst <- as.POSIXlt(old$t)$isdst
ref <- z[z$settlement_point == "LZ_WEST" & z$dst_repeated_flag != "Y", ]
ref$t <- as.POSIXct(ref$interval_start, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Chicago")
ref <- ref[!is.na(ref$t) & !duplicated(ref$t), ]
for (dst in c(0, 1)) {
  s <- old[old$isdst == dst, ]
  for (k in c(-4, 0)) {
    m <- merge(data.frame(t = s$t + k * 900, p = s$price),
               data.frame(t = ref$t, q = ref$price), by = "t")
    cat(sprintf("  %s, old labels shifted %+4d min: %6.2f%% identical (n=%d)\n",
                ifelse(dst == 1, "CDT summer", "CST winter"), k * 15,
                100 * mean(abs(m$p - m$q) < 1e-6), nrow(m)))
  }
}
cat(sprintf("\n2025 LZ_WEST mean: ERCOT archive $%.4f vs old cache $%.4f (the book anchor, $42.18, is the archive figure)\n",
            mean(z$price[z$settlement_point == "LZ_WEST" &
                         substr(z$interval_start, 1, 4) == "2025"]),
            mean(old$price[format(old$t, "%Y") == "2025"])))
cat("The gap is the nine intervals the old cache drops at the spring-forward, not a price error.\n\n")

w <- z[z$settlement_point == "LZ_WEST", ]
cat(sprintf("\nLZ_WEST 2025 mean from ERCOT's archive: $%.2f/MWh  (book anchor: $42.18)\n",
            mean(w$price[w$year == 2025])))

# ---- the sell option, on real-time data, year by year -----------------------
cat("\n=== The value of the option to sell, LZ_WEST, real-time 15-minute ===\n")
years <- sort(unique(w$year))
years <- years[sapply(years, function(y) sum(w$year == y) > 30000)]  # complete years only
cat(sprintf("%-6s %8s %8s %7s %7s %7s | %14s %9s %9s | %14s %9s %9s\n",
            "year", "mean", "max", ">$72h", ">$157h", ">$1k h",
            "gain S19jPro", "%revenue", "%profit", "gain S21XP", "%revenue", "%profit"))
for (y in years) {
  p <- w$price[w$year == y]
  cells <- c()
  for (V in c(71.6, 156.5)) {
    gain <- sum(pmax(p - V, 0)) * H
    rev  <- V * length(p) * H
    prof <- rev - sum(p) * H
    cells <- c(cells, gain, 100 * gain / rev, 100 * gain / prof)
  }
  cat(sprintf("%-6d %8.2f %8.0f %7.0f %7.0f %7.0f | %14s %8.1f%% %8.1f%% | %14s %8.1f%% %8.1f%%\n",
              y, mean(p), max(p), sum(p > 71.6) * H, sum(p > 156.5) * H, sum(p > 1000) * H,
              format(round(cells[1]), big.mark = ","), cells[2], cells[3],
              format(round(cells[4]), big.mark = ","), cells[5], cells[6]))
}
cat("\nNote: a negative %profit means a fleet running flat out on spot LOST money that year,\n")
cat("so the option was not an improvement on the business, it was the business.\n")

# ---- how concentrated is the gain? -----------------------------------------
cat("\n=== Concentration of the gain (share carried by the priciest hours) ===\n")
for (y in years) {
  p <- w$price[w$year == y]
  line <- sprintf("%d:", y)
  for (V in c(71.6, 156.5)) {
    o <- sort(pmax(p - V, 0), decreasing = TRUE)
    tot <- sum(o)
    line <- paste0(line, sprintf("  V=$%.0f top20h %3.0f%% top100h %3.0f%%",
                                 V, 100 * sum(o[1:80]) / tot, 100 * sum(o[1:400]) / tot))
  }
  cat(line, "\n")
}

# ---- day-ahead vs real-time, to show how much DAM understates ---------------
cat("\n=== Day-ahead understates the option (same year, same zone) ===\n")
# ERCOT's own day-ahead archive (MIS report 13060, fetch_ercot_rtm15_spp_history.py),
# every hour of the year, the repeated autumn hour included, as the real-time
# side counts every interval. No number this block prints is in the book.
dam <- read.csv("analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz")
dam <- dam[dam$settlement_point == "LZ_WEST", ]
dam$year <- as.integer(substr(dam$hour_start, 1, 4))
for (y in intersect(years, sort(unique(dam$year)))) {
  pd <- dam$price[dam$year == y]
  if (length(pd) < 8000) next
  pr <- w$price[w$year == y]
  for (V in c(71.6, 156.5)) {
    gd <- sum(pmax(pd - V, 0))            # hourly -> 1 h each
    gr <- sum(pmax(pr - V, 0)) * H
    cat(sprintf("  %d V=$%-6.1f day-ahead $%-10s real-time $%-10s  (real-time is %.2fx)\n",
                y, V, format(round(gd), big.mark = ","), format(round(gr), big.mark = ","), gr / gd))
  }
}

# ---- the honest multi-year version: the strike MOVES with hashprice ---------
# The tables above hold the machine value fixed at chapter 4's 2025 breakevens,
# which asks "what if today's machines had faced those years". The historical
# question uses each year's own hashprice: the spliced series in
# analysis/data/hashprice_daily_2021on.csv (see fetch_hashprice_history.py).
# On it the S19j Pro's strike runs about $438/MWh in 2021 down to $72 in 2025.
# Read through chapter 9's loader (analysis/checks/ch9_hashprice.R), which fills
# the ten days the spliced file lacks from hashprice_daily.csv. Until 2026-09-25
# this script dropped them, so "2025" ran on 8,688 hours, not 8,760.
source("analysis/checks/ch9_hashprice.R")
hp <- ch9_hashprice(verbose = FALSE)
w$date <- substr(w$interval_start, 1, 10)
w$hp <- hp$hp[match(w$date, hp$date)]
w2 <- w[!is.na(w$hp), ]
stopifnot(!anyNA(w$hp[w$date >= hp$date[1] & w$date <= tail(hp$date, 1)]))   # no interval inside the series goes unpriced
K <- 41666.7
cat("\n=== Same option, each year at its OWN hashprice (moving strike), LZ_WEST ===\n")
cat(sprintf("%-6s %8s | %10s %8s %12s | %10s %8s %12s\n", "year", "meanHP",
            "S19 strike", "sold h", "gain $/MW", "S21 strike", "sold h", "gain $/MW"))
for (y in years) {
  p <- w2[w2$year == y, ]
  out <- c()
  for (e in c(29.5, 13.5)) {
    V <- p$hp * K / e
    out <- c(out, mean(V), sum(p$price > V) * H, sum(pmax(p$price - V, 0)) * H)
  }
  cat(sprintf("%-6d %8.5f | %10.0f %8.0f %12s | %10.0f %8.0f %12s\n", y, mean(p$hp),
              out[1], out[2], format(round(out[3]), big.mark = ","),
              out[4], out[5], format(round(out[6]), big.mark = ",")))
}
cat("\nIn 2021 the strike stood near $440 and $960, so the option paid only in the\n")
cat("storm itself; it is still worth close to a million dollars a megawatt-year.\n")

# how much of 2021's moving-strike gain fell in the storm week (Feb 14-20, 2021)
p21 <- w2[w2$year == 2021, ]
V21 <- p21$hp * K / 29.5
g_all <- sum(pmax(p21$price - V21, 0)) * H
storm <- p21$date >= "2021-02-14" & p21$date <= "2021-02-20"
g_storm <- sum(pmax(p21$price[storm] - V21[storm], 0)) * H
cat(sprintf("\n2021 S19j Pro moving-strike gain: $%s, of which Feb 14-20 (Winter Storm Uri): $%s = %.0f%%\n",
            format(round(g_all), big.mark = ","), format(round(g_storm), big.mark = ","), 100 * g_storm / g_all))

# ---- the two denominators of chapter 6's "it looks small" sentence ----------
# The owner measures the sell option against the whole revenue of the machines;
# a spot buyer measures the same dollars against revenue less the power bill.
# Both for 1 MW of S19j Pro (29.5 J/TH) in 2025, at the moving strike and the
# realised LZ_WEST settlement prices.
p25 <- w2[w2$year == 2025, ]
V25 <- p25$hp * K / 29.5
rev25 <- sum(V25) * H
pow25 <- sum(p25$price) * H
cat(sprintf("\n2025 denominators, 1 MW S19j Pro: revenue $%s (mean strike $%.1f x %d h), power bill $%s, margin $%s, sell option $%s\n",
            format(round(rev25), big.mark = ","), mean(V25), round(nrow(p25) * H),
            format(round(pow25), big.mark = ","), format(round(rev25 - pow25), big.mark = ","),
            format(round(sum(pmax(p25$price - V25, 0)) * H), big.mark = ",")))

# ---- the 2021 denominator, and the negative-price hours ----------------------
# "About a quarter of what the machines earn all year": the 2021 sell option
# against 2021 mining revenue at the moving strike, both over the intervals the
# hashprice series covers. And the hours in which West Texas prices went negative
# in 2025, counted from the full settlement series (no hashprice merge needed).
rev21 <- sum(V21) * H
cat(sprintf("\n2021 denominators, 1 MW S19j Pro: revenue at the moving strike $%s over %d h; sell option $%s = %.0f%% of revenue\n",
            format(round(rev21), big.mark = ","), round(nrow(p21) * H),
            format(round(g_all), big.mark = ","), 100 * g_all / rev21))
neg25 <- sum(w$price[w$year == 2025] < 0)
cat(sprintf("2025 LZ_WEST negative-price intervals: %d = %.0f hours = %.1f%% of the year\n",
            neg25, neg25 * H, 100 * neg25 / sum(w$year == 2025)))
