# ch6_strike_events.R, Chapter 6: what the strike sweep's hindsight number is
# made of, and how much of it a rule that can only look back keeps. Run from
# the repo root:
#   Rscript analysis/checks/ch6_strike_events.R
#
# Same data and strikes as analysis/figures/fig_ch6_strike.R: LZ_WEST 15-minute
# settlement prices, calendar 2025 (analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz,
# ERCOT MIS 13061), 1 MW, strike = the machine's 2025 breakeven (S19j Pro
# $71.6, S21 XP $156.5; chapter 4). The figure's sweep pauses in exactly the
# intervals whose own price exceeds the strike, which nobody can know until
# the interval has settled: it is a ceiling. This script prints
#   1. the pauses that ceiling is made of: runs of consecutive intervals above
#      the strike, their lengths, the days they fall on, and how concentrated
#      the value is in the most expensive hours;
#   2. the same strike decided one settlement interval late (pause when the
#      PREVIOUS interval's price exceeded it), booked at each interval's own
#      price, so a late pause into a cheap interval books a loss;
#   3. that lagged rule with minimum runtimes, 30 and 60 minutes each way;
#   4. when in the year the value fell: 2025 by month, the June-September
#      share by year at the fixed $71.6 and at each day's own strike (each
#      day's hashprice through chapter 9's loader, the moving strike of
#      sell_vs_mine.R), and how much of the winter months' share ten days held.
#
# ORDER. The archive lists the repeated autumn hour with its N and Y rows
# interleaved (01:00 N, 01:00 Y, 01:15 N, ...). Anything that looks at the
# previous interval needs the real sequence, so rows are sorted by clock hour,
# then flag, then interval: the first pass through 01:00-01:45, then the second.
# The hindsight sums do not depend on order; the lagged ones move by about $1.
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))

z <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz",
              stringsAsFactors = FALSE)
z <- z[z$settlement_point == "LZ_WEST", ]
z <- z[order(substr(z$interval_start, 1, 13), z$dst_repeated_flag, z$interval_start), ]
z$year  <- as.integer(substr(z$interval_start, 1, 4))
z$month <- as.integer(substr(z$interval_start, 6, 7))
z$date  <- substr(z$interval_start, 1, 10)
z$hour  <- as.integer(substr(z$interval_start, 12, 13))
H <- 0.25

i25 <- which(z$year == 2025)
stopifnot(all(diff(i25) == 1), length(i25) == 35040)
y  <- z[i25, ]
p  <- y$price
pl <- z$price[i25 - 1]            # previous interval; the first is 2024-12-31 23:45
cat(sprintf("LZ_WEST 2025: %d intervals, mean $%.2f; first lagged price from %s\n",
            length(p), mean(p), z$interval_start[i25[1] - 1]))

be <- c(`S19j Pro` = 71.6, `S21 XP` = 156.5)

# runs of TRUE in a logical vector: start index and length
runs_of <- function(m) {
  r <- rle(m)
  ends <- cumsum(r$lengths)
  starts <- ends - r$lengths + 1
  data.frame(start = starts[r$values], len = r$lengths[r$values])
}

# the lagged rule with minimum runtimes: min_down intervals paused before a
# resume, min_up intervals running before the next pause
lagged <- function(V, min_down = 1, min_up = 1) {
  paused <- FALSE; age <- .Machine$integer.max; tot <- 0; n_pause <- 0
  for (k in seq_along(p)) {
    want <- pl[k] > V
    if (paused) {
      if (!want && age >= min_down) { paused <- FALSE; age <- 0 }
    } else {
      if (want && age >= min_up) { paused <- TRUE; age <- 0; n_pause <- n_pause + 1 }
    }
    age <- age + 1
    if (paused) tot <- tot + (p[k] - V) * H
  }
  c(gain = tot, pauses = n_pause)
}

for (nm in names(be)) {
  V <- be[[nm]]
  g <- pmax(p - V, 0) * H
  G <- sum(g)
  m <- p > V
  cat(sprintf("\n=== %s, strike $%.1f ===\n", nm, V))
  cat(sprintf("hindsight (the sweep): $%.0f/MW-yr, %d intervals above the strike (%.2f%%, %.2f h)\n",
              G, sum(m), 100 * mean(m), sum(m) * H))

  # 1. the pauses the ceiling is made of
  r <- runs_of(m)
  r$value <- vapply(seq_len(nrow(r)), function(j) sum(g[r$start[j]:(r$start[j] + r$len[j] - 1)]), 0)
  r$day <- y$date[r$start]
  cat(sprintf("runs above the strike: %d; median %.0f min; mean %.2f h; longest %.2f h\n",
              nrow(r), median(r$len) * 15, mean(r$len) * H, max(r$len) * H))
  for (k in 1:2) {
    s <- r$len <= k
    cat(sprintf("  of %d interval(s) or fewer: %d runs (%.1f%%), worth $%.0f (%.1f%% of the hindsight sum)\n",
                k, sum(s), 100 * mean(s), sum(r$value[s]), 100 * sum(r$value[s]) / G))
  }
  for (k in c(4, 16)) {
    s <- r$len >= k
    cat(sprintf("  of %g h or more: %d runs, worth %.1f%%\n", k * H, sum(s), 100 * sum(r$value[s]) / G))
  }
  per_day <- table(r$day)
  cat(sprintf("  days with a run: %d of 365; %.2f runs a day overall, %.2f on a day with one, at most %d\n",
              length(per_day), nrow(r) / 365, nrow(r) / length(per_day), max(per_day)))
  gs <- sort(g, decreasing = TRUE)
  for (hrs in c(200, 400))
    cat(sprintf("  the most expensive %d hours (%d intervals) hold %.1f%% of the sum\n",
                hrs, hrs * 4, 100 * sum(gs[seq_len(hrs * 4)]) / G))

  # 2 and 3. decided one interval late, with and without minimum runtimes
  lag1 <- lagged(V)
  cat(sprintf("decided one interval late: $%.0f/MW-yr (%.1f%% of hindsight) in %d pauses\n",
              lag1[["gain"]], 100 * lag1[["gain"]] / G, lag1[["pauses"]]))
  for (mr in c(2, 4)) {
    lm <- lagged(V, mr, mr)
    cat(sprintf("  with %d-minute minimums down and up: $%.0f (%.1f%% of the lagged, %.1f%% of hindsight) in %d pauses\n",
                mr * 15, lm[["gain"]], 100 * lm[["gain"]] / lag1[["gain"]],
                100 * lm[["gain"]] / G, lm[["pauses"]]))
  }
}

# 4. when in the year: S19j Pro, fixed strike first
V <- be[["S19j Pro"]]
g <- pmax(p - V, 0) * H
G <- sum(g)
mo <- tapply(g, y$month, sum)
cat(sprintf("\n=== when the S19j Pro's 2025 option fell, strike $%.1f ===\n", V))
cat("by month:", paste(sprintf("%s $%.0f", month.abb, mo), collapse = ", "), "\n")
jjas <- sum(mo[6:9]); dj <- sum(mo[c(12, 1)]); ndjf <- sum(mo[c(11, 12, 1, 2)])
cat(sprintf("June-September $%.0f = %.1f%%; December + January $%.0f = %.2f times June-September (December $%.0f, January $%.0f, each below it); January, February, November and December %.1f%%\n",
            jjas, 100 * jjas / G, dj, dj / jjas, mo[12], mo[1], 100 * ndjf / G))
w <- y$month %in% c(11, 12, 1, 2)
dd <- sort(tapply(g[w], y$date[w], sum), decreasing = TRUE)
cat(sprintf("ten days hold %.1f%% of those four months' gain, $%.0f = %.1f%% of the year's: %s\n",
            100 * sum(dd[1:10]) / sum(dd), sum(dd[1:10]), 100 * sum(dd[1:10]) / G,
            paste(names(dd)[1:10], collapse = ", ")))
gw <- g[w]; hw <- y$hour[w]
cat(sprintf("  over all four months, hours starting 05-09 hold %.0f%%, 17-21 hold %.0f%%\n",
            100 * sum(gw[hw >= 5 & hw <= 9]) / sum(gw), 100 * sum(gw[hw >= 17 & hw <= 21]) / sum(gw)))
top <- w & y$date %in% names(dd)[1:10]
cat(sprintf("  on the ten days alone, 05-09 hold %.0f%%, 17-21 hold %.0f%%\n",
            100 * sum(g[top & y$hour >= 5 & y$hour <= 9]) / sum(g[top]),
            100 * sum(g[top & y$hour >= 17 & y$hour <= 21]) / sum(g[top])))

# June-September share by year, fixed strike and each day's own strike
source("analysis/checks/ch9_hashprice.R")
hp <- ch9_hashprice(verbose = FALSE)
K <- 41666.7
cat("\nJune-September share of the S19j Pro's option, by year (LZ_WEST, 1 MW):\n")
for (yr in 2021:2025) {
  s <- z[z$year == yr, ]
  hpd <- hp$hp[match(s$date, hp$date)]
  stopifnot(!anyNA(hpd))
  gf <- pmax(s$price - V, 0) * H
  Vd <- hpd * K / 29.5
  go <- pmax(s$price - Vd, 0) * H
  sm <- s$month %in% 6:9
  cat(sprintf("  %d: fixed $%.1f strike %.1f%% of $%.0f; own-day strike (mean $%.0f) %.1f%% of $%.0f\n",
              yr, V, 100 * sum(gf[sm]) / sum(gf), sum(gf), mean(Vd),
              100 * sum(go[sm]) / sum(go), sum(go)))
}
