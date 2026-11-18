# ch9_control_friction.R -- what chapter 5's actual controller costs against the
# frictionless optimum the chapter 9 engine computes. Run from the repo root:
#   Rscript analysis/checks/ch9_control_friction.R
#
# THE QUESTION. The chapter 9 engine (and the Braiins fleet calculator's Price
# Adapt, which it was cross-checked against) both compute a STATELESS optimum:
# each interval is repriced from scratch, and the fleet may pause and resume
# with no friction at all. Chapter 5's controller is not stateless. It has three
# rules, and two of them deliberately give up value to protect hardware:
#
#   Rule 1  follow the level: recompute the optimal power from the last print
#   Rule 2  ignore the noise: hold the applied target 30 minutes, broken early
#           only when the ideal target diverges by more than a 10% deadband
#   Rule 3  survive the spikes: pause and resume are owned by an INTEGRAL
#           backstop, never by a single print
#
# The backstop constants are the book's own, from analysis/ch5-backtest/papo_sim.py:
#   K_TRIP        $10 per MW of accumulated excess above the best-efficiency
#                 breakeven, reset whenever the price dips back below it
#   RESTART_BAND  resume only when price <= breakeven x 0.90 ...
#   DWELL         ... held for 15 minutes
#   MIN_UP/DOWN   30 minutes minimum in each state
#   MAX_CYCLES    8 pause cycles per day
#
# Note the PAUSE CONDITION is already the same in both: the engine's "off" state
# is chosen exactly when no operating point pays, which is price above the
# breakeven at the best-efficiency point on the menu (ch9_curve jth_best: the
# S19j Pro's 1,200 W floor; 3,200 W on the S21 XP, above its 2,774 W floor).
# What differs is the friction around it.
# So this measures friction alone, not a different policy.
#
# Run at the full-headroom connection (74.10 MW) so neither fleet is constrained
# by the other and each can be simulated independently.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
source("analysis/checks/ch9_tuning.R")

K <- 41666.7; H <- 0.25
K_TRIP <- 10.0; RESTART_BAND <- 0.10
DWELL_N <- 1        # 15 minutes = 1 interval
MIN_UP_N <- 2; MIN_DOWN_N <- 2      # 30 minutes = 2 intervals
MAX_CYCLES_DAY <- 8
HOLD_N <- 2         # 30-minute hold
DEADBAND <- 0.10    # of stock power

FLEET <- data.frame(machine = c("S19j Pro", "S21 XP"), units = c(10000, 10000),
                    watts = c(3068, 3645), stringsAsFactors = FALSE)
CV <- list("S19j Pro" = ch9_curve("S19j Pro"), "S21 XP" = ch9_curve("S21 XP"))

# hashprice through the shared loader (analysis/checks/ch9_hashprice.R): the ten
# days missing from the spliced series filled, and the 2025 calendar asserted.
# Until 2026-09-25 this check ran on 34,752 intervals, three days short.
source("analysis/checks/ch9_hashprice.R")
hp <- ch9_hashprice()
z <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
z <- z[z$settlement_point == "LZ_WEST", ]; z <- z[order(z$interval_start), ]
z$date <- substr(z$interval_start, 1, 10)
z$year <- as.integer(substr(z$interval_start, 1, 4))
z$p_lag <- c(NA, head(z$price, -1))
z <- ch9_attach_hashprice(z, hp, !is.na(z$p_lag)); z$hp <- z$hp_real
s <- z[z$year == 2025, ]
ch9_check_calendar(s, 2025)

# the frictionless optimum: repriced every interval, pause and resume free
frictionless <- function(cv, units, stock_w) {
  best <- max.col(outer(s$hp_known, cv$h) / 96 - outer(s$p_lag, cv$p) / 1e6 * H,
                  ties.method = "first")
  on <- (s$hp_known * cv$h[best] / 96 - s$p_lag * cv$p[best] / 1e6 * H) > 0
  p <- ifelse(on, cv$p[best], 0); hh <- ifelse(on, cv$h[best], 0)
  list(profit = sum(hh * s$hp / 96 - p * s$price / 1e6 * H) * units,
       moves = sum(diff(p) != 0), stops = sum(diff(on) == -1),
       off_share = mean(!on))
}

# chapter 5's controller, as specified
ch5_controller <- function(cv, units, stock_w) {
  n <- nrow(s)
  be_floor <- s$hp_known * K / cv$jth_best       # breakeven at best efficiency on the menu (S21 XP: 3,200 W, above its 2,774 W floor)
  ideal_i <- max.col(outer(s$hp_known, cv$h) / 96 - outer(s$p_lag, cv$p) / 1e6 * H,
                     ties.method = "first")
  ideal_p <- cv$p[ideal_i]

  running <- TRUE; area <- 0; applied <- stock_w
  t_start <- 1L; t_stop <- -99L; last_change <- 1L
  cycles <- 0L; cur_day <- s$date[1]
  calm_since <- NA_integer_
  prof <- numeric(n); moves <- 0L; stops <- 0L; off <- logical(n)

  for (k in seq_len(n)) {
    if (s$date[k] != cur_day) { cur_day <- s$date[k]; cycles <- 0L }
    if (running) {
      # rule 3: integrate the excess above the floor breakeven
      if (s$p_lag[k] >= be_floor[k]) area <- area + (s$p_lag[k] - be_floor[k]) * H
      else area <- 0
      if (area >= K_TRIP && cycles < MAX_CYCLES_DAY && (k - t_start) >= MIN_UP_N) {
        running <- FALSE; stops <- stops + 1L; cycles <- cycles + 1L
        t_stop <- k; calm_since <- NA_integer_; area <- 0
      }
    } else {
      if (s$p_lag[k] <= be_floor[k] * (1 - RESTART_BAND)) {
        if (is.na(calm_since)) calm_since <- k
      } else calm_since <- NA_integer_
      if (!is.na(calm_since) && (k - calm_since) >= DWELL_N && (k - t_stop) >= MIN_DOWN_N) {
        running <- TRUE; t_start <- k; applied <- ideal_p[k]; last_change <- k
      }
    }
    if (!running) { off[k] <- TRUE; prof[k] <- 0; next }
    # rules 1 and 2: hold the applied target, break early on the deadband
    if ((k - last_change) >= HOLD_N ||
        abs(ideal_p[k] - applied) > DEADBAND * stock_w) {
      if (applied != ideal_p[k]) moves <- moves + 1L
      applied <- ideal_p[k]; last_change <- k
    }
    hh <- cv$h[which.min(abs(cv$p - applied))]
    prof[k] <- hh * s$hp[k] / 96 - applied * s$price[k] / 1e6 * H
  }
  list(profit = sum(prof) * units, moves = moves, stops = stops, off_share = mean(off))
}

cat(sprintf("2025 LZ_WEST, %d intervals, full-headroom connection so neither fleet constrains the other\n\n", nrow(s)))
cat(sprintf("%-10s %-16s %14s %11s %10s %11s\n",
            "machine", "controller", "profit", "target moves", "stops", "share off"))
tot <- c(0, 0)
for (m in seq_len(nrow(FLEET))) {
  cv <- CV[[FLEET$machine[m]]]
  a <- frictionless(cv, FLEET$units[m], FLEET$watts[m])
  b <- ch5_controller(cv, FLEET$units[m], FLEET$watts[m])
  tot <- tot + c(a$profit, b$profit)
  cat(sprintf("%-10s %-16s %14s %11s %10d %10.1f%%\n", FLEET$machine[m], "frictionless",
              format(round(a$profit), big.mark = ","),
              format(round(a$moves / 365, 1), nsmall = 1), a$stops, 100 * a$off_share))
  cat(sprintf("%-10s %-16s %14s %11s %10d %10.1f%%\n", "", "chapter 5 rules",
              format(round(b$profit), big.mark = ","),
              format(round(b$moves / 365, 1), nsmall = 1), b$stops, 100 * b$off_share))
  cat(sprintf("%-10s %-16s %13.2f%%\n", "", "friction cost", 100 * (b$profit / a$profit - 1)))
}
cat(sprintf("\nsite: frictionless $%s, chapter 5 rules $%s, friction costs %.2f%% (%s)\n",
            format(round(tot[1]), big.mark = ","), format(round(tot[2]), big.mark = ","),
            100 * (tot[2] / tot[1] - 1), format(round(tot[2] - tot[1]), big.mark = ",")))
cat("\nTarget moves per day are the actuation the deadband is there to bound;\n")
cat("chapter 5 reports about 26 a day for the S19j Pro and under 3 for the S21 XP\n")
cat("on its 5-minute feed, against 13 and 2 for a plain 30-minute hold\n")
cat("(analysis/ch5-backtest/output/trend_study/mixed_basis.csv, TEST-2025-26).\n")
cat("On this 15-minute feed the counts differ.\n")


# ---- does chapter 5's oracle-capture headline survive the curve correction? --
# When this check was written, chapter 5 printed the internal study's full-loop
# capture, 94.9% (S21 XP) and 95.3% (S19j Pro), from papo_sim.py's LINEAR
# efficiency model; from 2026-09-15 it printed 97.6% and 94.8% from the
# replication kit on the MEASURED 2026-Q2 telemetry curves. Since the 2026-09-25
# rebuild (ERCOT MIS 13061 settlement prices, modulation floor at the
# telemetry's best-efficiency points) it printed 98.2% and 96.2% of the oracle's
# GAIN over never pausing at stock power, out of sample; since 2026-09-26, with
# the S21 XP floored at Braiins OS's default minimum, 2,774 W, 98.1% and 96.2%
# (analysis/ch5-backtest/output/trend_study/mixed_basis.csv). This section is
# what established that a capture ratio survives a curve change. A ratio is
# much more robust to the curve than an absolute uplift, because the curve
# scales numerator and denominator together; this checks that rather than
# assuming it. NOTE the yardstick below is the share of the oracle's PROFIT on
# the 15-minute feed, not chapter 5's share of the GAIN on the 5-minute feed,
# so its levels are not comparable to chapter 5's.
cat("\n\n=== Chapter 5's oracle capture, on both curve sets ===\n")
lin <- function(p_min, p_def, p_max, j_best, j_def, step = 100) {
  b <- (j_def - j_best) / (p_def - p_min); a <- j_best - b * p_min
  grid <- unique(c(seq(p_min, p_max, by = step), p_max))
  list(p = grid, j = a + b * grid, h = grid / (a + b * grid),
       p_floor = p_min, p_max = p_max, jth_floor = a + b * p_min,
       jth_best = a + b * p_min, p_best = p_min)
}
CURVES <- list(
  telemetry = list("S19j Pro" = CV[["S19j Pro"]], "S21 XP" = CV[["S21 XP"]]),
  # the study's original linear fit (papo_sim.py PARAMETRIC_MINERS, floors
  # 1,630 / 2,760 W); papo_sim.py itself now runs the telemetry by default
  study_fit = list("S19j Pro" = lin(1630, 3068, 3420, 23.81, 28.53),
                   "S21 XP"   = lin(2760, 3645, 3990, 10.93, 12.82)))

oracle <- function(cv, units, stock_w) {
  best <- max.col(outer(s$hp, cv$h) / 96 - outer(s$price, cv$p) / 1e6 * H,
                  ties.method = "first")                    # decides on THIS interval
  on <- (s$hp * cv$h[best] / 96 - s$price * cv$p[best] / 1e6 * H) > 0
  sum(ifelse(on, cv$h[best], 0) * s$hp / 96 -
      ifelse(on, cv$p[best], 0) * s$price / 1e6 * H) * units
}

cat(sprintf("%-10s %-10s %14s %14s %10s\n", "curves", "machine", "full loop", "oracle", "capture"))
for (cs in names(CURVES)) {
  for (m in seq_len(nrow(FLEET))) {
    cv <- CURVES[[cs]][[FLEET$machine[m]]]
    full <- ch5_controller(cv, FLEET$units[m], FLEET$watts[m])$profit
    orc  <- oracle(cv, FLEET$units[m], FLEET$watts[m])
    cat(sprintf("%-10s %-10s %14s %14s %9.1f%%\n", if (m == 1) cs else "",
                FLEET$machine[m], format(round(full), big.mark = ","),
                format(round(orc), big.mark = ","), 100 * full / orc))
  }
}
cat("\nChapter 5 prints 96.2% (S19j Pro) and 98.1% (S21 XP) as a share of the\n")
cat("oracle GAIN over never pausing, on a 5-minute feed. This runs on the\n")
cat("15-minute feed and scores a share of TOTAL profit, so the levels\n")
cat("are not directly comparable. What matters is whether the CURVE changes the\n")
cat("capture ratio, and it barely does.\n")
