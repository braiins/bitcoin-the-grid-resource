# ch9_calculator_export.R -- pre-aggregate the chapter 9 model into the JSON
# payload the companion calculator embeds, and write it into the page. Run from
# the repo root, then hold the page to the ledger:
#   Rscript analysis/checks/ch9_calculator_export.R
#   node analysis/calculator/check_calculator.mjs
#
# Output: analysis/data/ch9_calculator_data.json, and the same payload as the
# `const DATA = ...;` line of analysis/calculator/ch9_calculator.html, which this
# script rewrites so the embed is never a hand step.
#
# The calculator is a single self-contained HTML page, so it cannot ship the
# 15-minute prices since 2021 for its four zones. Instead every combination the
# reader can select is precomputed here and the page does only arithmetic on
# the summary rows.
#
# ONE ENGINE. The page runs on the basis of chapter 9's ledger,
# analysis/checks/ch9_optimal_stack.R, through the same functions:
#   - stock is the measured curve's stock point on the 100 W grid (3,100 W at
#     28.57 J/TH for the S19j Pro, 3,600 W at 12.76 for the S21 XP), and the
#     energy the charges are keyed to is the fleet's 3,068 / 3,645 W draw, as
#     the ledger books it;
#   - a pause the lagged rule got wrong is booked at what it cost, not clipped
#     at zero, so the strike line is the ledger's strike_gain;
#   - the power target is ch9_tune_site, the joint exhaustive allocation under
#     the connection, and its row is the increment over a site that already
#     pauses at stock (tuning_gain);
#   - the charges are chapter 6's ledger (Table 6.1), held for every year:
#     losses, ancillary and uplift on every megawatt-hour consumed; the
#     distribution line as Oncor bills it, per month at the one site meter on
#     the month's highest quarter-hour with an 80 percent ratchet, plus the
#     customer and metering charges (analysis/checks/oncor_distribution.R, the
#     definition the ledger uses), so a pause avoids it only where it lowers a
#     month's peak; and Rider TCRF on the stock draw at every official 4CP
#     interval the summer window does not catch. Until 2026-10-03 the page
#     booked distribution at $0.50 per MWh consumed;
#   - a fleet that holds a reserve award stays on the meter at stock power and
#     withholds the window's hours, which the ledger removes at what they paid.
# check_calculator.mjs runs the page's own script and requires, to the dollar,
# the ledger's never-pausing site, strike, power target, window, planned and
# hindsight sites for all five years, and chapter 9's connection figures.
# Until 2026-09-27 the page added a nameplate, clipped strike (29.5 / 13.5
# J/TH, then ch9_flexibility_stack.R's basis; that script books wrong pauses
# at their cost too since the same day) to a curve-basis power target, left
# out every charge but TCRF, kept the strike and the power target on megawatts
# sold as reserves, and priced 4CP from LZ_WEST alone in every zone. The
# nameplate strike survives only in the monthly block, which reproduces the
# chapter's Figure 9.1 and Table 9.1 (ch9_flexibility_stack.R).
#
# ANY MIX OF THE TWO MACHINES. The strike, the never-pausing site and a fleet
# held on a reserve award are per machine, so they scale exactly with each
# fleet's count. The joint power-target run is not: under one connection the
# S19j Pro makes room for the S21 XP, so its value depends on the mix. It is
# homogeneous, though: scaling both counts and the connection by k leaves every
# interval's allocation unchanged and multiplies every dollar by k. So the run
# is solved here for a 20,000-unit site at every S21 XP share of units from 0
# to 100 percent in steps of 5, and the page scales it to the fleet's size and
# interpolates between the two neighbouring shares. At a grid share (the
# reference site's one-to-one mix among them) the page is exact.
#
# THE DISTRIBUTION LINE ON ANY MIX. Each row carries, per path, dkw: the
# year's billing megawatts summed over its twelve months (MW-months), and per
# window rule the same with the rule's hours emptied (dkw_<path>_A, _B; not a
# part to subtract, because a monthly peak does not subtract). The page bills
# (DSC + DCRF) x 1,000 x dkw plus twelve months of the customer and metering
# charges, once for the site. Where the site is two paths, one per fleet, the
# page adds their dkw, and the sum of two fleets' monthly peaks is the site's
# monthly peak only when both peak in the same quarter-hour. They do on every
# path the page combines: a fleet held on a reserve award draws its stock power
# in every interval; at stock power the S19j Pro runs only when the S21 XP,
# with the higher strike, also runs; and the joint power-target run is one
# site series. The ratchet would break the sum in a month it binds; the run
# prints how many of the exported series it binds in (none, when written).
# Each year is billed on its own months, so a year's first month carries no
# ratchet history. A month's peak can never exceed the series' connection (a
# fleet's stock draw for a per-fleet stock path, the fleet's grid ceiling under
# the connection for one tuned alone, the site's connection for the joint run),
# so a series whose every monthly peak reaches 80 percent of its connection
# cannot be ratcheted by any earlier year either. The run prints the lowest
# monthly peak of any series as a share of its connection, and stops before
# writing anything if any series falls below that line or the ratchet binds
# anywhere, because the page's "a ratchet that no path here triggers" rests on
# both.
#
# Payload shape:
#   meta     constants (TCRF, the charges, the distribution tariff, K), the
#            reference fleet, the curves, the contracts, the years, the mix grid
#   stock[]  one row per (year, zone, contract, machine), for 10,000 units at
#            the curve's stock point: never-pausing profit, the strike's gain,
#            the perfect-foresight gain, paused hours, and per path (n never
#            pausing, s pausing on the strike) the energy consumed in MWh and
#            its price-weighted sum, over the year and in each window rule's
#            hours, with the margin those hours earned, and the summed monthly
#            billing megawatts for the distribution line (dkw)
#   tuned[]  one row per (year, zone, price basis, S21 XP share, connection):
#            the joint power-target run for 20,000 units, per machine its gain
#            over never pausing and over pausing at stock, and for the site the
#            same energy and window sums as stock[]
#   alone[]  one row per (year, zone, price basis, machine, connection): that
#            fleet tuned alone, per 10,000 units, while the other fleet holds a
#            reserve award at stock (ch9_optimal_stack.R tuned_alone)
#   fourcp[] one row per (year, rule): window hours, official intervals caught
#   as[]     one row per year: standing revenue per MW-year per product, the
#            part paid in each window rule's hours, the share paid in Uri's week
#   monthly[] one row per (year, month, zone, machine): mean price, and at
#            nameplate the mean strike and the share of intervals paused
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))

K    <- 41666.7
H    <- 0.25
TCRF <- 41901
TLF <- 0.02155; ANC <- 0.39; UPLIFT <- 1.38   # chapter 6 ledger, per MWh consumed, as ch9_optimal_stack.R holds them
source("analysis/checks/oncor_distribution.R") # the distribution line, billed on each month's peak at one site meter, as the ledger bills it
ZONES <- c("LZ_WEST", "LZ_NORTH", "LZ_HOUSTON", "LZ_SOUTH")
STORM <- c("2021-02-14", "2021-02-20")                       # Uri, as chapter 2 dates it
MIX_N <- 20000; MIX_STEPS <- 20                              # S21 XP share of units 0, 5, ..., 100 percent

FLEET <- data.frame(
  machine = c("S19j Pro", "S21 XP"),
  units   = c(10000, 10000),
  th      = c(104, 270),
  watts   = c(3068, 3645),
  jth     = c(29.5, 13.5),
  stringsAsFactors = FALSE
)
FLEET$mw <- FLEET$units * FLEET$watts / 1e6

# ---- the curves -------------------------------------------------------------
# Shared with the chapter's own scripts so the two cannot drift. See the header
# of analysis/checks/ch9_tuning.R for the curves, the ceilings and the floor.
source("analysis/checks/ch9_tuning.R")
CURVE <- list("S19j Pro" = ch9_curve("S19j Pro"), "S21 XP" = ch9_curve("S21 XP"))
KS <- sapply(1:2, function(m) which.min(abs(CURVE[[m]]$p - FLEET$watts[m])))   # the curve's stock point
# Two connection sizes the reader can compare, for any fleet: its stock draw,
# and full tilt, every machine at its ceiling (74.10 MW for the reference
# fleet: 10,000 x 3,420 + 10,000 x 3,990). At full tilt every allocation fits,
# so the full-tilt run is the unconstrained one, and the share of intervals in
# which the stock connection holds a fleet below its full-tilt choice is the
# share in which that connection binds. Whether a connection makes the site a
# Large Load is the page's test, at the meter (machines plus cooling and
# losses), not this script's.
cap_mw <- function(u19, u21, which) {
  w <- if (which == "stock") FLEET$watts else sapply(CURVE, function(cv) cv$p_max)
  (u19 * w[1] + u21 * w[2]) / 1e6
}
stopifnot(abs(cap_mw(1e4, 1e4, "stock") - 67.13) < 1e-9, abs(cap_mw(1e4, 1e4, "fulltilt") - 74.10) < 1e-9)

# hashprice through the chapter's shared loader (analysis/checks/ch9_hashprice.R):
# the ten days missing from the spliced series filled, the calendar asserted
source("analysis/checks/ch9_hashprice.R")
hp <- ch9_hashprice()

all_rt <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
all_da <- read.csv("analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz")
source("analysis/checks/official_4cp.R")   # labels are interval ending; key = date + derived start
off <- read_official_4cp()
asm <- read.csv("analysis/data/ercot_dam_as_mcpc.csv.gz", stringsAsFactors = FALSE)
asm$year <- as.integer(substr(asm$deliveryDate, 1, 4)); asm$month <- as.integer(substr(asm$deliveryDate, 6, 7))
asm$wday <- format(as.Date(asm$deliveryDate), "%u")
# the window rules' hours in the ancillary file, as ch9_optimal_stack.R defines rule B
# (hours ending 17 and 18, June-September weekdays) and chapter 8 rule A (hours ending 15 to 18, every day)
asm$winA <- asm$month %in% 6:9 & asm$hourEnding %in% 15:18
asm$winB <- asm$month %in% 6:9 & asm$wday %in% c("1", "2", "3", "4", "5") & asm$hourEnding %in% c(17, 18)
PRODUCTS <- c("rrs", "ecrs", "nspin")

CONTRACTS <- list(
  list(id = "rt_index",        label = "Real-time index",          fixed = NA),
  list(id = "dam_index",       label = "Day-ahead index",          fixed = NA),
  list(id = "fixed_takeorpay", label = "Fixed $27 take-or-pay",    fixed = 27.00),
  list(id = "fixed_sellback",  label = "Fixed $27 + sell-back",    fixed = 27.00),
  list(id = "ppa_sellback",    label = "Fixed $43.95 + sell-back", fixed = 43.95)
)
# The contract algebra. Every contract but take-or-pay lets the site pause, and
# under the sell-back ones a paused megawatt-hour is sold back at the market
# price, so pausing gains the spread between that price and the machine's
# value: exactly what it gains on the index. A sell-back contract is therefore
# the index plus a fixed swap on the stock volume, and every layer is worth the
# same dollars on it (chapter 9, Section 9.2); only the never-pausing baseline
# moves. Take-or-pay pays for its volume whether it is burned or not: pausing
# earns nothing, so the page prices no strike and no power target on it, and a
# window hour paused forfeits the whole revenue. The day-ahead index settles at
# the day-ahead price and knows it a day ahead, so its decision price and its
# settlement price are the same series (as in ch9_flexibility_stack.R). Only
# two price bases therefore exist for the power-target run: real time
# (decided on the lagged price, settled at the price) and day ahead.
basis_of <- function(id) if (id == "dam_index") "dam" else "rt"

prep <- function(zone) {
  z <- all_rt[all_rt$settlement_point == zone, ]
  z <- z[order(z$interval_start), ]
  z$date  <- substr(z$interval_start, 1, 10)
  z$year  <- as.integer(substr(z$interval_start, 1, 4))
  z$month <- as.integer(substr(z$interval_start, 6, 7))
  z$hh    <- as.integer(substr(z$interval_start, 12, 13))
  z$wday  <- format(as.Date(z$date), "%u")
  z$key   <- paste(z$date, substr(z$interval_start, 12, 16))
  z$p_lag <- c(NA, head(z$price, -1))
  d <- all_da[all_da$settlement_point == zone, ]
  d$date <- substr(d$hour_start, 1, 10); d$hh <- as.integer(substr(d$hour_start, 12, 13))
  z$dam <- d$price[match(paste(z$date, z$hh), paste(d$date, d$hh))]
  ch9_attach_hashprice(z, hp, !is.na(z$p_lag) & !is.na(z$dam))
}

# energy consumed (MWh) and its price-weighted sum, over the year and in each
# rule's hours, for a path drawing mw[t] megawatts; the margin the path earned
# in each rule's hours; and the summed monthly billing megawatts, over the year
# and with each rule's hours emptied. The page turns these into the ledger's
# charges: losses at TLF x the price-weighted sum (the contract's own price
# times the energy on a fixed contract), ancillary and uplift at $/MWh times
# the energy, and distribution on the billing megawatts.
# `conn` is the most the series can draw (its connection), for the history check.
DIST_CHECK <- new.env(); DIST_CHECK$series <- 0; DIST_CHECK$binds <- 0
DIST_CHECK$min_share <- Inf; DIST_CHECK$below <- 0
dkw_sum <- function(mw, month, conn) {
  d <- od_year(mw, month)
  DIST_CHECK$series <- DIST_CHECK$series + 1; DIST_CHECK$binds <- DIST_CHECK$binds + (d$binds > 0)
  share <- min(d$ncp) / conn
  DIST_CHECK$min_share <- min(DIST_CHECK$min_share, share); DIST_CHECK$below <- DIST_CHECK$below + (share < OD_RATCHET - 1e-9)
  sum(d$billing)
}
energy_cols <- function(prefix, mw, price, rules, margin, month, conn) {
  out <- list()
  out[[paste0("mwh_", prefix)]] <- sum(mw) * H
  out[[paste0("pw_", prefix)]]  <- sum(mw * price) * H
  out[[paste0("dkw_", prefix)]] <- dkw_sum(mw, month, conn)
  for (rn in names(rules)) {
    sel <- rules[[rn]]
    out[[paste0("win_", prefix, "_", rn)]] <- sum(margin[sel])
    out[[paste0("mwh_", prefix, "_", rn)]] <- sum(mw[sel]) * H
    out[[paste0("pw_", prefix, "_", rn)]]  <- sum(mw[sel] * price[sel]) * H
    out[[paste0("dkw_", prefix, "_", rn)]] <- dkw_sum(ifelse(sel, 0, mw), month, conn)   # the site emptied in the rule's hours
  }
  out
}

stock_rows <- list(); tuned_rows <- list(); alone_rows <- list()
monthly_rows <- list(); fourcp_rows <- list(); as_rows <- list()
YEARS <- NULL; LEDGER_DAYS <- list()
for (zone in ZONES) {
  z <- prep(zone)
  ys <- sort(unique(z$year)); ys <- ys[sapply(ys, function(y) sum(z$year == y) > 30000)]
  for (y in ys) ch9_check_calendar(z[z$year == y, ], y, first = if (y == ys[1]) min(z$date) else sprintf("%d-01-01", y))
  if (is.null(YEARS)) YEARS <- ys
  stopifnot(identical(ys, YEARS))
  for (y in ys) {
    s <- z[z$year == y, ]; n <- nrow(s)
    rules <- list(
      A = s$month %in% 6:9 & s$hh >= 14 & s$hh < 18,
      B = s$month %in% 6:9 & s$hh >= 16 & s$hh < 18 & s$wday %in% c("1", "2", "3", "4", "5"))
    o <- off[off$year == y, ]
    days <- range(s$date)
    if (is.null(LEDGER_DAYS[[as.character(y)]])) LEDGER_DAYS[[as.character(y)]] <- days
    stopifnot(identical(LEDGER_DAYS[[as.character(y)]], days))

    # the summer window: which official intervals each rule catches (system-wide, so the same in every zone)
    for (rn in names(rules)) {
      fr <- data.frame(year = y, rule = rn, hours = round(sum(rules[[rn]]) * H),
                       caught = sum(o$key %in% s$key[rules[[rn]]]), of = nrow(o), stringsAsFactors = FALSE)
      prior <- Filter(function(r) r$year == y && r$rule == rn, fourcp_rows)
      if (length(prior)) stopifnot(prior[[1]]$caught == fr$caught, prior[[1]]$hours == fr$hours)
      else fourcp_rows[[length(fourcp_rows) + 1]] <- fr
    }

    price_of <- list(rt = list(P = s$price, Pd = s$p_lag), dam = list(P = s$dam, Pd = s$dam))

    # ---- per machine, per contract, at the curve's stock point ----------------
    for (m in 1:2) {
      cv <- CURVE[[m]]; ks <- KS[m]; u <- FLEET$units[m]; mw <- FLEET$mw[m]
      rev <- s$hp_real * cv$h[ks] / 96                           # $ per unit per interval
      for (cn in CONTRACTS) {
        pb <- price_of[[basis_of(cn$id)]]
        Pc <- if (is.na(cn$fixed)) pb$P else rep(cn$fixed, n)
        pr_c <- rev - Pc * cv$p[ks] / 1e6 * H                      # what the contract books, running
        pr_m <- rev - pb$P * cv$p[ks] / 1e6 * H                    # running against the market price
        on <- (s$hp_known * cv$h[ks] / 96 - pb$Pd * cv$p[ks] / 1e6 * H) > 0
        ok <- cn$id != "fixed_takeorpay"
        pr_win <- if (ok) pr_m else rev                            # a window hour paused under take-or-pay forfeits the revenue
        row <- list(year = y, zone = zone, contract = cn$id, machine = FLEET$machine[m],
                    always = u * sum(pr_c),
                    strike = if (ok) -u * sum(pr_m[!on]) else 0,
                    foresight = if (ok) u * sum(pmax(-pr_m, 0)) else 0,
                    paused_h = if (ok) sum(!on) * H else 0)
        row <- c(row, energy_cols("n", rep(mw, n), pb$P, rules, u * pr_win, s$month, mw),
                 energy_cols("s", mw * on, pb$P, rules, u * ifelse(on, pr_m, 0), s$month, mw))
        stock_rows[[length(stock_rows) + 1]] <- as.data.frame(row, stringsAsFactors = FALSE)
      }
      for (mo in 1:12) {
        k <- s$month == mo
        if (!any(k)) next
        V  <- s$hp_real  * K / FLEET$jth[m]
        Vd <- s$hp_known * K / FLEET$jth[m]
        monthly_rows[[length(monthly_rows) + 1]] <- data.frame(
          year = y, month = mo, zone = zone, machine = FLEET$machine[m],
          mean_price = round(mean(s$price[k]), 2),
          mean_strike = round(mean(V[k]), 1),
          paused_share = round(mean((s$p_lag > Vd)[k]), 4),
          stringsAsFactors = FALSE)
      }
    }

    # ---- the joint power-target run, per price basis, mix and connection ------
    for (b in names(price_of)) {
      pb <- price_of[[b]]
      for (k in 0:MIX_STEPS) {
        u19 <- MIX_N * (MIX_STEPS - k) / MIX_STEPS; u21 <- MIX_N * k / MIX_STEPS
        # half a watt of margin, so that rounding a connection to megawatts never
        # excludes the allocation that fills it exactly; every allocation draws a
        # whole number of watts, so the margin changes nothing else
        runs <- lapply(c(stock = "stock", fulltilt = "fulltilt"), function(cp)
          ch9_tune_site(CURVE[[1]], CURVE[[2]], u19, u21, FLEET$watts[1], FLEET$watts[2],
                        s$hp_known, pb$Pd, s$hp_real, pb$P, cap_mw(u19, u21, cp) + 0.5e-6))
        p19 <- c(0, CURVE[[1]]$p); p21 <- c(0, CURVE[[2]]$p)
        # the stock connection binds where it holds either fleet below the point it takes at full tilt
        bound <- mean(p19[runs$stock$bi] < p19[runs$fulltilt$bi] | p21[runs$stock$bj] < p21[runs$fulltilt$bj])
        for (cp in names(runs)) {
          r <- runs[[cp]]
          row <- list(year = y, zone = zone, basis = b, k = k, cap = cp,
                      gain19 = r$gain19, gain21 = r$gain21, incr19 = r$incr19, incr21 = r$incr21,
                      mean_w19 = r$r19$mean_w, mean_w21 = r$r21$mean_w,
                      oc19 = r$r19$oc_share, th19 = r$r19$th_share, oc21 = r$r21$oc_share, th21 = r$r21$th_share,
                      cap_bound = if (cp == "stock") bound else 0, site_mw = r$mean_site_mw)
          row <- c(row, energy_cols("t", r$site_w / 1e6, pb$P, rules, r$r19$prof + r$r21$prof, s$month, cap_mw(u19, u21, cp)))
          tuned_rows[[length(tuned_rows) + 1]] <- as.data.frame(row, stringsAsFactors = FALSE)
        }
        # the reference site: the strike rows above must be exactly what the joint run's two baselines differ by
        if (k == MIX_STEPS / 2) for (cn in CONTRACTS) if (basis_of(cn$id) == b && cn$id != "fixed_takeorpay") {
          st <- Filter(function(r) r$year == y && r$zone == zone && r$contract == cn$id, tail(stock_rows, 2 * length(CONTRACTS)))
          stopifnot(length(st) == 2,
                    abs(st[[1]]$strike - (runs$stock$gain19 - runs$stock$incr19)) < 0.01,
                    abs(st[[2]]$strike - (runs$stock$gain21 - runs$stock$incr21)) < 0.01)
        }
      }
      # ---- one fleet tuned alone while the other holds a reserve award at stock ----
      # The held fleet takes its stock draw out of the connection, so the tuned
      # fleet's share is its own stock draw at the stock connection and at least
      # its ceiling at full tilt, whatever the mix: the row is per machine.
      for (m in 1:2) {
        cv <- CURVE[[m]]; other <- 3 - m; ks <- KS[m]
        for (cp in c("stock", "fulltilt")) {
          cap_p <- (cap_mw(FLEET$units[1], FLEET$units[2], cp) - FLEET$mw[other]) * 1e6 / FLEET$units[m]
          cap_p <- max(cv$p[cv$p <= cap_p + 1e-6])                 # largest feasible grid point, as tuned_alone takes it
          r <- ch9_tune(cv, s$hp_known, pb$Pd, s$hp_real, pb$P, FLEET$watts[m], cap_p = cap_p)
          prof <- r$tuned * FLEET$units[m]
          never <- FLEET$units[m] * (s$hp_real * cv$h[ks] / 96 - pb$P * cv$p[ks] / 1e6 * H)
          row <- list(year = y, zone = zone, basis = b, machine = FLEET$machine[m], cap = cp,
                      gain = sum(prof - never), cap_w = cap_p)
          row <- c(row, energy_cols("a", ifelse(r$run, r$p_star, 0) * FLEET$units[m] / 1e6, pb$P, rules, prof, s$month,
                                    cap_p * FLEET$units[m] / 1e6))
          alone_rows[[length(alone_rows) + 1]] <- as.data.frame(row, stringsAsFactors = FALSE)
        }
      }
    }
  }
}

# ---- standing revenue, on the ledger's own days (2021 starts on January 2) ----
for (y in YEARS) {
  d <- LEDGER_DAYS[[as.character(y)]]
  a <- asm[asm$year == y & asm$deliveryDate >= d[1] & asm$deliveryDate <= d[2], ]
  if (!nrow(a)) next
  storm <- a$deliveryDate >= STORM[1] & a$deliveryDate <= STORM[2]
  row <- list(year = y)
  for (p in PRODUCTS) {
    tot <- sum(a[[p]], na.rm = TRUE)
    row[[p]] <- tot
    row[[paste0(p, "_A")]] <- sum(a[[p]][a$winA], na.rm = TRUE)
    row[[paste0(p, "_B")]] <- sum(a[[p]][a$winB], na.rm = TRUE)
    row[[paste0(p, "_storm")]] <- if (tot > 0) sum(a[[p]][storm], na.rm = TRUE) / tot else 0
  }
  as_rows[[length(as_rows) + 1]] <- as.data.frame(row, stringsAsFactors = FALSE)
}

stock <- do.call(rbind, stock_rows); tuned <- do.call(rbind, tuned_rows); alone <- do.call(rbind, alone_rows)
monthly <- do.call(rbind, monthly_rows); fourcp <- do.call(rbind, fourcp_rows); as_tab <- do.call(rbind, as_rows)

# ---- hand-rolled JSON so the repo needs no extra package -------------------
# Dollars keep their cents and energy three decimals, so the page's sums of
# rows land on the ledger's dollar; shares keep four.
DIGITS <- function(col) if (grepl("^(mwh|dkw|site_mw|mean_w|jth)", col)) 3 else if (grepl("^(oc|th|cap_bound)|_storm$", col)) 4 else 2
j_num <- function(x, d = 6) ifelse(is.na(x), "null", formatC(round(x, d), format = "f", drop0trailing = TRUE, digits = d))
j_str <- function(x) paste0('"', gsub('"', '\\\\"', x), '"')
j_rows <- function(df) {
  cols <- names(df)
  enc <- lapply(cols, function(cl) if (is.numeric(df[[cl]])) j_num(df[[cl]], DIGITS(cl)) else j_str(as.character(df[[cl]])))
  body <- vapply(seq_len(nrow(df)), function(i)
    paste0("{", paste(sprintf('"%s":%s', cols, vapply(enc, `[`, "", i)), collapse = ","), "}"), "")
  paste0("[", paste(body, collapse = ","), "]")
}

curves <- do.call(rbind, lapply(1:2, function(m) {
  cv <- CURVE[[m]]
  data.frame(machine = FLEET$machine[m], p_floor = cv$p_floor, p_max = cv$p_max,
             stock = FLEET$watts[m], p_stock = cv$p[KS[m]],
             jth_floor = round(cv$jth_floor, 3), jth_best = round(cv$jth_best, 3),
             jth_stock = round(cv$j[KS[m]], 3), stringsAsFactors = FALSE)
}))
meta <- sprintf(paste0('{"generated":"%s","zone_default":"LZ_WEST","tcrf":%d,"K":%s,',
                       '"charges":{"tlf":%s,"anc":%s,"uplift":%s},',
                       '"dist":{"dsc":%s,"dcrf":%s,"customer":%s,"metering":%s,"ratchet":%s,"months":12,"meters":1},',
                       '"mix":{"units":%d,"steps":%d},"fleet":%s,"years":[%s],"contracts":%s,"curves":%s}'),
  format(Sys.Date()), TCRF, j_num(K), j_num(TLF), j_num(ANC), j_num(UPLIFT),
  j_num(OD_DSC), j_num(OD_DCRF), j_num(OD_CUSTOMER), j_num(OD_METERING), j_num(OD_RATCHET),
  MIX_N, MIX_STEPS,
  j_rows(FLEET[, c("machine", "units", "th", "watts", "jth", "mw")]),
  paste(YEARS, collapse = ","),
  paste0("[", paste(sapply(CONTRACTS, function(c)
    sprintf('{"id":%s,"label":%s,"fixed":%s}', j_str(c$id), j_str(c$label),
            if (is.na(c$fixed)) "null" else j_num(c$fixed))), collapse = ","), "]"),
  j_rows(curves))

out <- sprintf('{"meta":%s,"stock":%s,"tuned":%s,"alone":%s,"fourcp":%s,"as":%s,"monthly":%s}',
               meta, j_rows(stock), j_rows(tuned), j_rows(alone), j_rows(fourcp), j_rows(as_tab), j_rows(monthly))
# the page's "a ratchet that no path here triggers": checked before anything is written
if (DIST_CHECK$binds > 0 || DIST_CHECK$below > 0)
  stop(sprintf("the distribution ratchet binds in %d series and %d series have a month below %.0f%% of their connection (lowest %.1f%%): revisit the page's ratchet sentence",
               DIST_CHECK$binds, DIST_CHECK$below, 100 * OD_RATCHET, 100 * DIST_CHECK$min_share))
writeLines(out, "analysis/data/ch9_calculator_data.json")

# ---- write the payload into the page -----------------------------------------
PAGE <- "analysis/calculator/ch9_calculator.html"
html <- readLines(PAGE, encoding = "UTF-8", warn = FALSE)
at <- grep("^const DATA = ", html)
stopifnot(length(at) == 1)
html[at] <- paste0("const DATA = ", out, ";")
con <- file(PAGE, open = "w", encoding = "UTF-8"); writeLines(html, con); close(con)

cat(sprintf("Wrote analysis/data/ch9_calculator_data.json: %.1f KB, and inlined it in %s\n",
            file.size("analysis/data/ch9_calculator_data.json") / 1024, PAGE))
cat(sprintf("  stock rows %d, tuned rows %d (S21 XP share of units 0 to 100%% in %d steps), alone rows %d, monthly rows %d, 4CP rows %d, AS rows %d\n",
            nrow(stock), nrow(tuned), MIX_STEPS, nrow(alone), nrow(monthly), nrow(fourcp), nrow(as_tab)))
cat(sprintf("  zones %s; years %s\n", paste(ZONES, collapse = " "), paste(YEARS, collapse = " ")))
cat(sprintf("  distribution: %d draw series billed by month; the ratchet binds in %d of them; lowest monthly peak of any series %.1f%% of its connection, %d series below the ratchet's %.0f%% line, so no earlier year's history could make it bind\n",
            DIST_CHECK$series, DIST_CHECK$binds, 100 * DIST_CHECK$min_share, DIST_CHECK$below, 100 * OD_RATCHET))
ref <- tuned[tuned$zone == "LZ_WEST" & tuned$basis == "rt" & tuned$k == MIX_STEPS / 2 & tuned$year == max(YEARS), ]
cat(sprintf("  reference site %d, LZ_WEST real time: power-target gain over never pausing $%s at %.2f MW, $%s at %.2f MW (ch9_flexibility_stack.R Layer 4); stock connection binds in %.1f%% of intervals\n",
            max(YEARS), format(round(sum(ref[ref$cap == "stock", c("gain19", "gain21")])), big.mark = ","), cap_mw(1e4, 1e4, "stock"),
            format(round(sum(ref[ref$cap == "fulltilt", c("gain19", "gain21")])), big.mark = ","), cap_mw(1e4, 1e4, "fulltilt"),
            100 * ref$cap_bound[ref$cap == "stock"]))
