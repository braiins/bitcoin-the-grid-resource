# ch9_tuning.R -- the tuning layer: choose the profit-optimal operating point on
# a machine's measured efficiency curve. Sourced by ch9_flexibility_stack.R and
# ch9_calculator_export.R so the chapter and the calculator share one definition.
#
# THE CURVES are the Braiins fleet telemetry the fleet calculator ships, quarter
# 2026-Q2 (the committed file's label and the book's), for exactly the two
# variants this book uses:
#   Antminer S19J Pro (104 TH/s): 20 points, 800 to 4,400 W, stock 3,068 W
#   Antminer S21 XP  (270 TH/s): 15 points, 2,000 to 4,600 W, stock 3,645 W
# committed as analysis/data/miner_efficiency_telemetry_2026q2.csv.
#
# THE OPERATING ENVELOPE is taken from the fleet calculator's own rule, checked
# against its code on 2026-09-04: the ceiling is floor(PSU rating x 0.95), capped
# at the highest power the telemetry covers, and the floor is the power at which
# J/TH is minimised (chapter 5's best-efficiency point). THIS ENGINE'S FLOOR
# DIFFERS since 2026-09-26: the author's choice is to model what Braiins OS
# allows by default, so the floor is Braiins OS's default minimum power target,
# or the best-efficiency point where that is higher (ch9_floor below, the one
# place this engine sets it), as in chapter 5's kit. The PSU rating is looked up from the
# model NAME, not from the catalogue: any S19 is 3,600 W and any S21 is 4,200 W.
# Checked against Bitmain's help centre on 2026-09-26 (article bodies read
# through support.bitmain.com/api/v2/help_center/en-us/articles/<id>.json).
# The 3,600 W S19 figure matches Bitmain's APW12 spec (900001205726: up to
# 240 A at 15 V), the PSU family its compatibility table gives the S19j Pro
# (15909673875993). The 4,200 W S21 figure matches neither the S21 XP's PSU,
# APW171215a/c or PW380a/b/c (47856379027737), whose APW171215a spec gives
# 267 A rated, at most about 4,005 W at 15 V (32499285460505), nor the 4,000 W
# 'Adapted AC output power requirement' on the S21 XP page (bitmain2024s21xp,
# updated 2026-09-23), which reads as a requirement on the supply feeding the
# machine, not as a PSU rating. So the S19j Pro ceiling sits 5% under its PSU,
# but the S21 XP ceiling only about 0.4% under, not 5%. Chapter 5 prints the
# two ceilings without a PSU rationale for that reason.
#   Antminer S19J Pro (104 TH/s): 1,200 W floor, 3,420 W ceiling, 3,068 stock
#   Antminer S21 XP  (270 TH/s): 2,774 W floor, 3,990 W ceiling, 3,645 stock
# (the S21 XP's floor was its 2,200 W best-efficiency point until 2026-09-26)
# I earlier read the catalogue's psu_limit field (4,400 and 4,600 W) as the
# ceiling. It is not: it is the extent of the telemetry, and the optimiser never
# uses it. Those numbers were wrong and are withdrawn.
#
# ONE DELIBERATE DIFFERENCE, from chapter 5's kit, not from the fleet
# calculator: this engine interpolates J/TH linearly between measured points on
# a 100 W grid and sets hashrate to power / J (ch9_curve below), exactly as the
# calculator does, so hashrate bends between measured points. The chapter 5 kit
# (analysis/ch5-backtest/telemetry_miner.py) interpolates HASHRATE linearly and
# scans at 10 W, so its profit is piecewise linear in power and its loop only
# ever applies the corner points of the curve (chapter 5 prints four on the S21
# XP and eight on the S19j Pro). This engine may pick any grid point, and under
# the shared connection it does; analysis/checks/ch9_vs_papo.R compares it with
# the calculator. An earlier version of this comment said this engine optimised
# over the measured points themselves; ch9_curve has not done so since the
# ceiling fix below.
#
# Points BELOW the modulation floor are dropped. Below a curve's
# best-efficiency power they are strictly dominated: they deliver less
# hashrate AND worse joules per terahash. On the S19j Pro that removes 800 and
# 1,000 W. On the S21 XP the floor is Braiins OS's default minimum, 2,774 W,
# above its 2,200 W best point, so it removes 2,000 to 2,600 W: 2,000 W is
# 1.0% worse than 2,200 W (ch5_vfloor.py), and 2,200 to 2,600 W are points
# Braiins OS does not run by default.

# Braiins OS's default minimum power target (W) per model: Braiins Academy,
# Technical Resources, table "Default Power Limits" (Min Power), read
# 2026-09-26, bib entry braiinsacademytechres, as analysis/checks/ch5_vfloor.py
# part 3 transcribes it. Chapter 5's kit holds the same two values in
# analysis/ch5-backtest/telemetry_miner.py BOS_DEFAULT_MIN_W; part 3 reads this
# line with a regex, so keep it on one line, and asserts both copies against
# its transcription and this engine's floor against the kit's.
CH9_BOS_MIN_W <- c("S19j Pro" = 944, "S21 XP" = 2774)

# The modulation floor: the default minimum, or the best-efficiency point where
# that is higher, because running below the best point is dominated. The S19j
# Pro's default, 944 W, sits below its 1,200 W best point; the S21 XP's,
# 2,774 W, above its 2,200 W one.
ch9_floor <- function(model, t) {
  max(CH9_BOS_MIN_W[[model]], t$power_w[which.min(t$avg_jth)])
}

# PSU rating by model name, mirroring the fleet calculator's getPsuLimit().
ch9_psu <- function(model) {
  lower <- tolower(model)
  if (any(sapply(c("hydro", "hyd.", "hyd ", "immersion", "imm.", "imm "),
                 function(m) grepl(m, lower, fixed = TRUE)))) return(6500)
  if (grepl("s21", lower) || grepl("t21", lower)) return(4200)
  if (grepl("s19", lower) || grepl("t19", lower)) return(3600)
  4200
}

# The operating menu: J/TH linearly interpolated between the measured points on
# a 100 W grid, from the modulation floor to the ceiling, then hashrate
# H(p) = p / J(p). A floor off the grid (the S21 XP's 2,774 W) is its own first
# point, and the grid resumes at the next multiple of 100 W (2,800 W), so the
# measured points and the 3,600 W grid point nearest stock stay on it.
# This mirrors the fleet calculator's interpJth/precomputeProfitGrid exactly.
# Optimising over the raw measured points alone is NOT equivalent: it strands
# the ceiling at the nearest measured point below it (3,800 W instead of 3,990
# for the S21 XP), and since the efficient machine sits at its ceiling almost
# always, that one step was worth about $2M a year on this fleet.
ch9_curve <- function(model, step = 100,
                      path = "analysis/data/miner_efficiency_telemetry_2026q2.csv") {
  t <- read.csv(path)
  t <- t[t$model == model, ]
  t <- t[order(t$power_w), ]
  p_floor <- ch9_floor(model, t)
  p_max <- min(floor(ch9_psu(model) * 0.95), max(t$power_w))
  grid <- unique(c(p_floor, seq(ceiling(p_floor / step) * step, p_max, by = step), p_max))
  j <- approx(t$power_w, t$avg_jth, xout = grid, rule = 2)$y
  # jth_floor is the J/TH AT the floor; jth_best the best J/TH on the menu, and
  # p_best where it sits (the pause threshold's breakeven). They coincide on
  # the S19j Pro (1,200 W); on the S21 XP the best is 3,200 W, not the floor.
  list(model = model, p = grid, j = j, h = grid / j,
       p_floor = p_floor, p_max = p_max, jth_floor = j[1],
       jth_best = min(j), p_best = grid[which.min(j)])
}

# Profit of every operating point, for every interval, then take the best.
#   hp_dec / price_dec  what the controller can know (previous day's hashprice,
#                       last published price)
#   hp_real / price_real what actually settles
# Returns the tuned profit stream, the chosen power, and the same quantities for
# a binary controller pinned at stock power, so the difference is pure tuning.
ch9_tune <- function(cv, hp_dec, price_dec, hp_real, price_real, stock_w, cap_p = NULL) {
  H <- 0.25
  # decision: revenue per interval is hp * TH/s / 96; cost is $/MWh * MW * 0.25
  rev_dec  <- outer(hp_dec, cv$h) / 96
  cost_dec <- outer(price_dec, cv$p) / 1e6 * H
  pick <- max.col(rev_dec - cost_dec, ties.method = "first")
  run  <- (rev_dec - cost_dec)[cbind(seq_along(pick), pick)] > 0

  p_star <- cv$p[pick]
  if (!is.null(cap_p)) {                      # site connection cap applied upstream
    p_star <- pmin(p_star, cap_p)
    keep <- match(p_star, cv$p)
    pick <- ifelse(is.na(keep), pick, keep)
    p_star <- cv$p[pick]
    run <- run & (cap_p >= cv$p[1])
  }
  h_star <- cv$h[pick]
  prof_tuned <- ifelse(run, hp_real * h_star / 96 - price_real * p_star / 1e6 * H, 0)

  k <- which.min(abs(cv$p - stock_w))
  run_b <- (hp_dec * cv$h[k] / 96 - price_dec * cv$p[k] / 1e6 * H) > 0
  prof_stock <- ifelse(run_b, hp_real * cv$h[k] / 96 - price_real * cv$p[k] / 1e6 * H, 0)

  list(tuned = prof_tuned, stock = prof_stock, p_star = p_star, pick = pick, run = run,
       gain = sum(prof_tuned - prof_stock),
       mean_w = mean(ifelse(run, p_star, 0)),
       oc_share = mean(run & p_star > stock_w),
       th_share = mean(run & p_star < stock_w),
       run_share = mean(run), stock_run_share = mean(run_b))
}

# ---- the site connection cap ------------------------------------------------
# Overclocking is limited by the interconnection, not by the machines. At full
# tilt, at the ceilings ch9_curve returns, the reference fleet would draw
# 10,000 x 3,420 + 10,000 x 3,990 = 74.10 MW against a stock draw of 67.13 MW
# (chapter 9 prints both). The 90 MW this comment once gave used the telemetry's
# extent, 4,400 and 4,600 W, withdrawn above. A site contracted for 67 MW cannot
# do that, and a site that raised its contract past 75 MW would become a "Large Load"
# under ERCOT Protocols Section 2 and inherit Senate Bill 6's minimum billing
# demand, which ends 4CP avoidance entirely. Overclocking can therefore cost a
# site the peak-avoidance game: a real interaction between two layers.
#
# ALLOCATING A BINDING CONNECTION. Maximising site profit subject to a power cap
# is a Lagrangian problem, and its solution has a clean reading: the cap behaves
# exactly like a surcharge on electricity. Each fleet is dispatched against an
# effective price lambda >= the market price, and lambda is raised until the
# site fits its connection. Both fleets then sit at the same marginal cost per
# watt, which is the efficient allocation. Giving one fleet its unconstrained
# optimum and squeezing the other is NOT optimal: it starves the S19j Pro at
# power levels where its curve is steep and its marginal value is high.
# Site-level tuning. Both fleets share one interconnection, so the allocation is
# a joint choice, not two independent ones.
#
# EXHAUSTIVE, NOT A SHADOW PRICE. An earlier version raised a uniform shadow
# price until the site fitted its connection. That is the right Lagrangian in
# theory, but on a coarse grid of multipliers it walks BOTH fleets down together
# and lands on allocations that leave the connection under-used: it reported a
# mean draw of 60.9 MW against a 67.13 MW cap, and produced the impossible
# result that lagged information beat full information. With the 100 W grids of
# ch9_curve, 24 operating points for the S19j Pro (1,200 to 3,420 W) and 14 for
# the S21 XP (2,774 to 3,990 W), plus "off" for each fleet, there are only 375
# combinations, so this evaluates every one and takes the best feasible. That is
# exact on the grid. (500 with the S21 XP's earlier 2,200 W floor.)
ch9_tune_site <- function(cv19, cv21, units19, units21, stock19, stock21,
                          hp_dec, price_dec, hp_real, price_real, cap_mw) {
  cap_w <- cap_mw * 1e6
  H <- 0.25
  n <- length(price_dec)
  p19 <- c(0, cv19$p); h19 <- c(0, cv19$h)      # index 1 = fleet off
  p21 <- c(0, cv21$p); h21 <- c(0, cv21$h)

  best_dec <- rep(-Inf, n); bi <- rep(1L, n); bj <- rep(1L, n)
  for (i in seq_along(p19)) {
    rev19  <- hp_dec * h19[i] / 96
    cost19 <- price_dec * p19[i] / 1e6 * H
    prof19 <- (rev19 - cost19) * units19
    for (j in seq_along(p21)) {
      if (p19[i] * units19 + p21[j] * units21 > cap_w) next
      prof <- prof19 + (hp_dec * h21[j] / 96 - price_dec * p21[j] / 1e6 * H) * units21
      take <- prof > best_dec
      if (any(take)) { best_dec[take] <- prof[take]; bi[take] <- i; bj[take] <- j }
    }
  }

  settle <- function(pv, hv, k, units, stock_w, cv) {
    ks <- which.min(abs(cv$p - stock_w)) + 1L    # +1 for the "off" slot
    prof   <- (hp_real * hv[k]  / 96 - price_real * pv[k]  / 1e6 * H) * units
    prof_b <- (hp_real * hv[ks] / 96 - price_real * pv[ks] / 1e6 * H) * units
    # Two baselines, because they answer different questions and must not be
    # added together:
    #   gain      vs stock power that NEVER pauses -- comparable with the fleet
    #             calculator's Price Adapt uplift, and it already contains the
    #             value of pausing
    #   gain_incr vs stock power that DOES pause on price -- the value tuning
    #             adds on top of a plain on/off strike controller, which is the
    #             only version that can sit beside a separate strike row without
    #             counting the same dollars twice
    on_b <- (hp_dec * hv[ks] / 96 - price_dec * pv[ks] / 1e6 * H) > 0
    prof_bp <- ifelse(on_b, prof_b, 0)
    list(gain = sum(prof - prof_b), gain_incr = sum(prof - prof_bp),
         prof = prof, prof_stock = prof_b, prof_stock_pausing = prof_bp,   # per-interval streams, for ch9_optimal_stack.R
         mean_w = mean(pv[k]),
         oc_share = mean(pv[k] > stock_w),
         th_share = mean(pv[k] < stock_w & pv[k] > 0),
         off_share = mean(pv[k] == 0))
  }
  r19 <- settle(p19, h19, bi, units19, stock19, cv19)
  r21 <- settle(p21, h21, bj, units21, stock21, cv21)
  list(gain19 = r19$gain, gain21 = r21$gain,
       incr19 = r19$gain_incr, incr21 = r21$gain_incr, r19 = r19, r21 = r21,
       bi = bi, bj = bj, site_w = p19[bi] * units19 + p21[bj] * units21,
       cap_bound_share = mean(p19[bi] * units19 + p21[bj] * units21 > cap_w * 0.999),
       mean_site_mw = mean(p19[bi] * units19 + p21[bj] * units21) / 1e6)
}
