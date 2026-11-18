# ch9_flexibility_stack.R -- Chapter 9: what the whole flexibility stack is
# worth to one reference site, contract by contract, on historical data only.
# Run from the repo root:
#   Rscript analysis/checks/ch9_flexibility_stack.R
#
# THE REFERENCE FLEET (fixed for the chapter)
#   10,000 Antminer S19j Pro : 104 TH/s, 3,068 W, 29.5 J/TH -> 30.68 MW, 1.04 EH/s
#   10,000 Antminer S21 XP   : 270 TH/s, 3,645 W, 13.5 J/TH -> 36.45 MW, 2.70 EH/s
#   combined 67.13 MW, 3.74 EH/s. That sits just under the 75 MW "Large Load"
#   threshold of ERCOT Protocols Section 2, so Senate Bill 6's minimum billing
#   demand does not reach this site and 4CP avoidance still works.
#
# THE STRIKE MOVES. Chapter 4's identity is
#     revenue per MWh consumed = hashprice x 41,666.7 / efficiency (J/TH)
# so the breakeven power price follows hashprice, which moves daily. Chapter 4's
# $71.6 and $156.5 are the 2025 values, NOT constants: on the spliced series the
# S19j Pro's strike runs $438 (2021), $172, $104, $90, $72 (2025), $48 (2026 ytd).
# Holding it fixed across years answers a different and much rosier question.
#
# NO LOOK-AHEAD. Two decisions could cheat, and both are lagged here:
#   * price     -- a 15-minute settlement price does not exist while its own
#                  interval runs, so the controller decides interval t on the
#                  price of t-1. This is chapter 5's stated convention ("the
#                  controller sees each print one full interval late").
#   * hashprice -- a day's network revenue and hashrate are not known until the
#                  day closes, so the strike for day d uses hashprice from d-1.
# Revenue is still BOOKED at the realised hashprice of the day it was earned,
# and cost at the realised settlement price. Only the decision is lagged.
# The perfect-foresight variant is computed alongside, and the gap between them
# is reported: that gap is the honest price of not seeing the future.
#
# THE CONTRACT ALGEBRA, per interval, per machine. V = strike ($/MWh),
# P = settlement price, E = energy the machine would consume (MWh), F = the
# contract's fixed price:
#   index (real-time or day-ahead)  mine: (V-P)E   pause: 0
#                                   -> pausing AVOIDS a cost
#   fixed with sell-back rights     mine: (V-F)E   sell:  (P-F)E
#                                   -> pausing EARNS the spread; same switch point
#   fixed, take-or-pay, no resale   mine: (V-F)E   pause: -F*E
#                                   -> never worth pausing FOR PRICE, but the site
#                                      can still physically pause for 4CP; it just
#                                      forfeits the full V rather than V-P.
# Where flexibility is permitted at all, the switch point is identical and the
# dollars earned are identical. What the contract changes is the baseline you
# earn them on, and whether you are allowed to earn them.
#
# Data (all historical, credential-free, committed):
#   analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz   ERCOT MIS 13061
#   analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz     ERCOT MIS 13060
#   analysis/data/hashprice_daily_2021on.csv                spliced, see the
#     header of analysis/data/fetch_hashprice_history.py
#   analysis/data/ercot_official_4cp_2018_2025.csv          ERCOT filings, read
#     through analysis/checks/official_4cp.R (labels are interval ending)
#   analysis/data/ercot_dam_as_mcpc.csv.gz                  ERCOT MIS 13091
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))

K    <- 41666.7   # (3.6e9 J/MWh) / (86,400 s/day); chapter 4's constant
H    <- 0.25      # hours per settlement interval
TCRF <- 41901     # $/MW-yr of 4CP demand, Oncor Rider TCRF floor (chapter 8)
ZONE <- "LZ_WEST"

FLEET <- data.frame(
  machine = c("S19j Pro", "S21 XP"),
  units   = c(10000, 10000),
  th      = c(104, 270),
  watts   = c(3068, 3645),
  jth     = c(29.5, 13.5),
  stringsAsFactors = FALSE
)
FLEET$mw <- FLEET$units * FLEET$watts / 1e6

# ---- data ------------------------------------------------------------------
# Hashprice through the shared loader: the spliced series with its ten missing
# days filled and the calendar asserted (see analysis/checks/ch9_hashprice.R;
# until 2026-09-25 this script dropped those days without saying so).
source("analysis/checks/ch9_hashprice.R")
hp <- ch9_hashprice()                                    # hp = booked, hp_known = yesterday's, the decidable one

rt <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
rt <- rt[rt$settlement_point == ZONE, ]
rt <- rt[order(rt$interval_start), ]
rt$date  <- substr(rt$interval_start, 1, 10)
rt$year  <- as.integer(substr(rt$interval_start, 1, 4))
rt$month <- as.integer(substr(rt$interval_start, 6, 7))
rt$hh    <- as.integer(substr(rt$interval_start, 12, 13))
rt$wday  <- format(as.Date(rt$date), "%u")
rt$key   <- paste(rt$date, substr(rt$interval_start, 12, 16))
# CH9_LAG_Q (default 1): decide on the settlement price LAG_Q quarters back. The
# default is the book's ledger, which treats each price as readable the moment
# its quarter closes; ERCOT's API makes it readable a median 4.8 minutes later
# (analysis/checks/ch5_api_readability.py). CH9_LAG_Q=2 is the sensitivity run
# chapter 9 prints (a full quarter-hour late). Must be 1 or more.
LAG_Q <- as.integer(Sys.getenv("CH9_LAG_Q", "1"))
stopifnot(LAG_Q >= 1)
rt$p_lag <- c(rep(NA, LAG_Q), head(rt$price, -LAG_Q))   # last published print
rt <- ch9_attach_hashprice(rt, hp, !is.na(rt$p_lag))    # hp_real books revenue, hp_known decides

da <- read.csv("analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz")
da <- da[da$settlement_point == ZONE, ]
da$date <- substr(da$hour_start, 1, 10)
da$hh   <- as.integer(substr(da$hour_start, 12, 13))
rt$dam  <- da$price[match(paste(rt$date, rt$hh), paste(da$date, da$hh))]

# official 4CP intervals: ERCOT labels each by its END; analysis/checks/official_4cp.R
# derives the start, and key = date + start matches rt$key (interval start)
source("analysis/checks/official_4cp.R")
off <- read_official_4cp()

YEARS <- sort(unique(rt$year))
YEARS <- YEARS[sapply(YEARS, function(y) sum(rt$year == y) > 30000)]  # complete years only
for (y in YEARS) ch9_check_calendar(rt[rt$year == y, ], y, first = if (y == YEARS[1]) min(rt$date) else sprintf("%d-01-01", y))
stopifnot(!any(is.na(rt$dam[rt$year %in% YEARS])))
cat(sprintf("ledger years %s, every quarter-hour of each; %d starts on %s, the first day with a previous day's hashprice\n\n",
            paste(YEARS, collapse = ", "), YEARS[1], min(rt$date)))

# ---- the engine ------------------------------------------------------------
# Returns annual profit for one machine, one year, one contract, under three
# policies: always-on, the honest lagged controller, and perfect foresight.
run <- function(s, mw, jth, contract, fixed = NA) {
  E  <- mw * H
  V  <- s$hp_real  * K / jth              # realised value of the energy
  Vd <- s$hp_known * K / jth              # what the controller could know
  # A day-ahead-indexed site BUYS at the day-ahead price and knows it a day
  # ahead, so that price is both what settles and what it decides on. Chapter 6
  # prices the same contract the same way (ch6_contract_pnl.R: "All rows settle
  # on ERCOT 15-minute real-time settlement prices except the day-ahead index
  # row"). Until 2026-09-20 this row settled at the real-time price and only
  # decided on the day-ahead one, which made it a comparison of signals rather
  # than of contracts and left its never-pausing baseline identical to the
  # real-time row's, hiding the day-ahead index's cost over real time (chapter
  # 6: 2.1% below in 2021, then 2.4, 8.8, 3.4 and 1.3% above).
  P  <- if (contract == "dam_index") s$dam else s$price   # what settles
  Pd <- if (contract == "dam_index") s$dam else s$p_lag   # what the controller sees

  mine_always <- if (contract == "rt_index" || contract == "dam_index") {
    sum((V - P) * E)
  } else sum((V - fixed) * E)

  pause_ok <- contract != "fixed_takeorpay"
  # A late pause into an interval the strike did not clear books its loss:
  # signed (P - V), as ch6_strike_events.R and the ledger book it. Until
  # 2026-09-27 this was pmax(P - V, 0), which clipped those losses at zero.
  gain_lag <- if (pause_ok) sum((P - V)[Pd > Vd]) * E else 0
  gain_fc  <- if (pause_ok) sum(pmax(P - V, 0)) * E else 0
  list(always = mine_always,
       lagged = mine_always + gain_lag,
       foresight = mine_always + gain_fc,
       paused_h = if (pause_ok) sum(Pd > Vd) * H else 0,
       capture = if (gain_fc > 0) gain_lag / gain_fc else NA_real_)
}

CONTRACTS <- list(
  list(id = "rt_index",        label = "Real-time index",          fixed = NA),
  list(id = "dam_index",       label = "Day-ahead index",          fixed = NA),
  list(id = "fixed_takeorpay", label = "Fixed $27 take-or-pay",    fixed = 27.00),
  list(id = "fixed_sellback",  label = "Fixed $27 + sell-back",    fixed = 27.00),
  list(id = "ppa_sellback",    label = "Fixed $43.95 + sell-back", fixed = 43.95)
)

cat("=== The reference fleet ===\n")
print(FLEET[, c("machine", "units", "th", "watts", "jth", "mw")], row.names = FALSE)
cat(sprintf("combined %.2f MW, %.2f EH/s -- under the 75 MW Large Load threshold\n\n",
            sum(FLEET$mw), sum(FLEET$units * FLEET$th) / 1e6))

cat("=== The strike moves with hashprice ===\n")
for (y in YEARS) {
  s <- rt[rt$year == y, ]
  cat(sprintf("  %d: hashprice $%.5f -> strike S19j Pro $%4.0f, S21 XP $%4.0f | mean price $%6.2f\n",
              y, mean(s$hp_real), mean(s$hp_real) * K / 29.5, mean(s$hp_real) * K / 13.5,
              mean(s$price)))
}

cat("\n=== Layer 1, the strike: annual profit ($ millions), honest lagged controller ===\n")
for (m in seq_len(nrow(FLEET))) {
  cat(sprintf("\n--- %s (%.2f MW, %.1f J/TH) ---\n", FLEET$machine[m], FLEET$mw[m], FLEET$jth[m]))
  cat(sprintf("%-24s %6s %9s %9s %8s %9s %9s\n",
              "contract", "year", "always", "flex", "uplift", "paused h", "capture"))
  for (cn in CONTRACTS) {
    for (y in YEARS) {
      s <- rt[rt$year == y, ]
      r <- run(s, FLEET$mw[m], FLEET$jth[m], cn$id, cn$fixed)
      cat(sprintf("%-24s %6d %9.2f %9.2f %7.1f%% %9.0f %8s\n",
                  if (y == YEARS[1]) cn$label else "", y,
                  r$always / 1e6, r$lagged / 1e6,
                  100 * (r$lagged - r$always) / abs(r$always), r$paused_h,
                  if (is.na(r$capture)) "-" else sprintf("%.0f%%", 100 * r$capture)))
    }
  }
}

cat("\n\n=== The price of not seeing the future (real-time index) ===\n")
cat("'capture' above is the honest lagged controller's share of the perfect-foresight gain.\n")
cat(sprintf("%-6s %26s %26s\n", "year", "S19j Pro lagged / foresight", "S21 XP lagged / foresight"))
for (y in YEARS) {
  s <- rt[rt$year == y, ]
  a <- run(s, FLEET$mw[1], FLEET$jth[1], "rt_index")
  b <- run(s, FLEET$mw[2], FLEET$jth[2], "rt_index")
  cat(sprintf("%-6d %11s / %-11s %11s / %-11s\n", y,
              format(round(a$lagged - a$always), big.mark = ","),
              format(round(a$foresight - a$always), big.mark = ","),
              format(round(b$lagged - b$always), big.mark = ","),
              format(round(b$foresight - b$always), big.mark = ",")))
}

# Why the real-time index beats the day-ahead one, year by year. The total gap
# per MW-yr splits exactly into the never-pausing baseline (the day-ahead
# premium or discount on every megawatt-hour) and the pause option (what each
# site's lagged strike earned over its own baseline). The premium is not fixed:
# it is each year's realised day-ahead mean over the real-time mean.
cat("\n\n=== Real-time index less day-ahead index, per MW-yr: baseline (the premium) + option = total ===\n")
cat(sprintf("%-6s %9s | %-34s | %-34s | %s\n", "year", "DAM - RT", "S19j Pro baseline + option = total",
            "S21 XP baseline + option = total", "carried by"))
for (y in YEARS) {
  s <- rt[rt$year == y, ]
  prem <- 100 * (mean(s$dam) / mean(s$price) - 1)
  parts <- lapply(seq_len(nrow(FLEET)), function(m) {
    r <- run(s, FLEET$mw[m], FLEET$jth[m], "rt_index"); d <- run(s, FLEET$mw[m], FLEET$jth[m], "dam_index")
    c(base = r$always - d$always, opt = (r$lagged - r$always) - (d$lagged - d$always), tot = r$lagged - d$lagged) / FLEET$mw[m]
  })
  carried <- sapply(parts, function(p) if (abs(p["base"]) >= abs(p["opt"])) "premium" else "option")
  cat(sprintf("%-6d %+8.2f%% | %9s %+9s = %9s | %9s %+9s = %9s | %s / %s\n", y, prem,
              format(round(parts[[1]]["base"]), big.mark = ","), format(round(parts[[1]]["opt"]), big.mark = ","), format(round(parts[[1]]["tot"]), big.mark = ","),
              format(round(parts[[2]]["base"]), big.mark = ","), format(round(parts[[2]]["opt"]), big.mark = ","), format(round(parts[[2]]["tot"]), big.mark = ","),
              carried[1], carried[2]))
}


# ---- Layer 2: ancillary services, and the pre-RTC+B conflict ----------------
# A megawatt sold as a reserve must be ON the meter for every hour of the award
# (chapter 7, "committed to consume"), so pre-RTC+B that megawatt cannot also
# take the strike. The comparison is therefore a straight either/or, per MW:
# standing ancillary revenue against the strike gain the same MW would earn.
as <- read.csv("analysis/data/ercot_dam_as_mcpc.csv.gz")
as$year <- as.integer(substr(as$deliveryDate, 1, 4))
cat("\n\n=== Layer 2, ancillary services: standing revenue vs the strike, per MW-year ===\n")
cat("Pre-RTC+B these are mutually exclusive for the same megawatt.\n\n")
cat(sprintf("%-6s %9s %9s %9s | %12s %12s | %s\n",
            "year", "RRS", "ECRS", "NonSpin", "strike S19j", "strike S21", "better use of a MW"))
for (y in YEARS) {
  a <- as[as$year == y, ]
  if (!nrow(a)) next
  best <- c(RRS = sum(a$rrs, na.rm = TRUE), ECRS = sum(a$ecrs, na.rm = TRUE),
            NonSpin = sum(a$nspin, na.rm = TRUE))
  s <- rt[rt$year == y, ]
  g <- sapply(seq_len(nrow(FLEET)), function(m) {
    V  <- s$hp_real * K / FLEET$jth[m]; Vd <- s$hp_known * K / FLEET$jth[m]
    sum((s$price - V)[s$p_lag > Vd]) * H              # signed, as Layer 1
  })
  win <- if (max(best) > max(g)) sprintf("sell %s", names(best)[which.max(best)]) else "keep the strike"
  cat(sprintf("%-6d %9s %9s %9s | %12s %12s | %s\n", y,
              format(round(best["RRS"]), big.mark = ","),
              format(round(best["ECRS"]), big.mark = ","),
              format(round(best["NonSpin"]), big.mark = ","),
              format(round(g[1]), big.mark = ","), format(round(g[2]), big.mark = ","), win))
}

# ---- Layer 3: 4CP avoidance ------------------------------------------------
# Rules scored on information available at the time; the official interval list
# is used only to SCORE them after the fact, never to make the decision.
#   A  every day 2-6 p.m., June-September
#   B  weekdays 4-6 p.m., June-September
# The site's 4CP demand is the mean of its demand across the four official
# intervals, so covering three of four leaves a quarter of the bill standing.
rules <- list(
  A = function(d) d$month %in% 6:9 & d$hh >= 14 & d$hh < 18,
  B = function(d) d$month %in% 6:9 & d$hh >= 16 & d$hh < 18 & d$wday %in% c("1","2","3","4","5")
)
cat(sprintf("\n\n=== Layer 3, 4CP: full exposure for %.2f MW is $%s a year ===\n",
            sum(FLEET$mw), format(round(sum(FLEET$mw) * TCRF), big.mark = ",")))
cat(sprintf("%-6s %-5s %8s %7s %13s %13s %13s\n",
            "year", "rule", "hours", "caught", "TCRF saved", "margin lost", "net"))
fourcp <- list()
for (y in YEARS) {
  s <- rt[rt$year == y, ]; o <- off[off$year == y, ]
  if (!nrow(o)) next
  covered <- sapply(seq_len(nrow(FLEET)), function(m) {
    V <- s$hp_real * K / FLEET$jth[m]; Vd <- s$hp_known * K / FLEET$jth[m]
    sum(s$key %in% o$key & s$p_lag > Vd)
  })
  for (rn in names(rules)) {
    sel <- rules[[rn]](s)
    caught <- sum(o$key %in% s$key[sel])
    saved  <- sum(FLEET$mw) * TCRF * caught / nrow(o)
    lost <- 0
    for (m in seq_len(nrow(FLEET))) {
      V <- s$hp_real * K / FLEET$jth[m]; Vd <- s$hp_known * K / FLEET$jth[m]
      # only intervals the strike would not already have paused cost anything
      extra <- sel & !(s$p_lag > Vd)
      lost <- lost + sum(pmax(V[extra] - s$price[extra], 0)) * FLEET$mw[m] * H
    }
    cat(sprintf("%-6d %-5s %8.0f %4d/%-2d %13s %13s %13s\n", y, rn, sum(sel) * H,
                caught, nrow(o), format(round(saved), big.mark = ","),
                format(round(lost), big.mark = ","),
                format(round(saved - lost), big.mark = ",")))
    fourcp[[paste(y, rn)]] <- c(saved = saved, lost = lost, net = saved - lost)
  }
  cat(sprintf("       [the strike alone covered %d of %d official intervals for the S19j Pro, %d of %d for the S21 XP]\n",
              covered[1], nrow(o), covered[2], nrow(o)))
}

# ---- The stack: is it additive? --------------------------------------------
cat("\n\n=== The stack on a real-time index, 4CP rule B: sums vs reality ===\n")
cat(sprintf("%-6s %13s %13s %13s %13s %13s\n",
            "year", "strike", "4CP gross", "naive sum", "true joint", "interference"))
for (y in YEARS) {
  s <- rt[rt$year == y, ]
  f <- fourcp[[paste(y, "B")]]
  if (is.null(f)) next
  strike_val <- sum(sapply(seq_len(nrow(FLEET)), function(m) {
    V <- s$hp_real * K / FLEET$jth[m]; Vd <- s$hp_known * K / FLEET$jth[m]
    sum((s$price - V)[s$p_lag > Vd]) * FLEET$mw[m] * H   # signed, as Layer 1
  }))
  naive <- strike_val + f["saved"]
  joint <- strike_val + f["net"]
  cat(sprintf("%-6d %13s %13s %13s %13s %13s\n", y,
              format(round(strike_val), big.mark = ","),
              format(round(f["saved"]), big.mark = ","),
              format(round(naive), big.mark = ","),
              format(round(joint), big.mark = ","),
              format(round(joint - naive), big.mark = ",")))
}
cat("\nThe interference is the mining margin spent covering intervals the price\n")
cat("signal never flagged. Chapter 8 showed the energy price no longer marks the\n")
cat("peak; this is what that costs the reference fleet.\n")


# ---- Layer 4: tuning along the efficiency curve -----------------------------
# The controller picks the profit-optimal point on the machine's MEASURED curve
# (Braiins fleet telemetry, 2026-Q2, the 104 TH/s and 270 TH/s variants). See
# analysis/checks/ch9_tuning.R for the curves and the ceilings.
source("analysis/checks/ch9_tuning.R")
CURVE <- list("S19j Pro" = ch9_curve("S19j Pro"), "S21 XP" = ch9_curve("S21 XP"))

cat("\n\n=== Layer 4, tuning: the throttle and the overclock ===\n")
for (n in names(CURVE)) {
  cv <- CURVE[[n]]
  st <- FLEET$watts[FLEET$machine == n]
  k <- which.min(abs(cv$p - st)); top <- length(cv$p)
  marg <- (cv$p[top] - cv$p[k]) / (cv$h[top] - cv$h[k])
  cat(sprintf("  %-9s floor %d W = %.2f J/TH | best %.2f J/TH at %d W | stock %d W = %.1f TH/s | ceiling %d W = %.1f TH/s\n",
              n, cv$p_floor, cv$jth_floor, cv$jth_best, cv$p_best, st, cv$h[k], cv$p_max, cv$h[top]))
  cat(sprintf("            overclocking to the ceiling costs %.1f J/TH at the margin, so it pays under $%.0f/MWh at 2025 hashprice\n",
              marg, mean(rt$hp_real[rt$year == 2025]) * K / marg))
}
CAPS <- c(stock = sum(FLEET$mw), largeload = 75,
          uncapped = sum(FLEET$units * sapply(FLEET$machine, function(n) max(ch9_curve(n)$p))) / 1e6)
cat(sprintf("\nAt full tilt this fleet would draw %.0f MW against a stock %.2f MW, so the\n",
            CAPS[["uncapped"]], CAPS[["stock"]]))
cat("interconnection binds. A cap reads as a surcharge on electricity: both fleets\n")
cat("dispatch against an effective price raised until the site fits its connection.\n")
cat("A connection of 75 MW or more also makes the site a Large Load, and SB 6's\n")
cat("minimum billing demand then ends 4CP avoidance.\n\n")
cat(sprintf("%-6s %14s %16s %16s %16s\n", "year", "connection",
            "S19j Pro tuning", "S21 XP tuning", "site total"))
for (y in YEARS) {
  s <- rt[rt$year == y, ]
  for (cn in names(CAPS)) {
    st <- ch9_tune_site(CURVE[["S19j Pro"]], CURVE[["S21 XP"]],
                        FLEET$units[1], FLEET$units[2], FLEET$watts[1], FLEET$watts[2],
                        s$hp_known, s$p_lag, s$hp_real, s$price, CAPS[[cn]])
    cat(sprintf("%-6s %11.1f MW %16s %16s %16s\n",
                if (cn == names(CAPS)[1]) y else "", CAPS[[cn]],
                format(round(st$gain19), big.mark = ","),
                format(round(st$gain21), big.mark = ","),
                format(round(st$gain19 + st$gain21), big.mark = ",")))
  }
}
cat("\nThe efficient machine pins at its ceiling and overclocks; the old one is\n")
cat("throttled to make room for it whenever the connection binds. Under a tight\n")
cat("connection tuning is mostly a reallocation between fleets, not a windfall.\n")

# ---- the larger connection, net of the grid charges it changes ---------------
# The table above is before grid charges. A larger connection draws more
# megawatt-hours, which carry chapter 6's energy-keyed charges (losses, ancillary,
# uplift, as ch9_optimal_stack.R books them), and sets a higher monthly peak, which
# the distribution line bills (analysis/checks/oncor_distribution.R, one site meter).
# Transmission (Rider TCRF) is left out: the planned site plays the summer window
# in 2025 and pays none on either connection. The never-pausing baseline is the
# same on both connections, so its charges cancel in the difference.
source("analysis/checks/oncor_distribution.R")
CH6_TLF <- 0.02155; CH6_ANC <- 0.39; CH6_UPLIFT <- 1.38   # chapter 6 ledger, as ch9_optimal_stack.R holds them
s <- rt[rt$year == 2025, ]
cn_net <- list()
for (cn in c("stock", "uncapped")) {
  st <- ch9_tune_site(CURVE[["S19j Pro"]], CURVE[["S21 XP"]],
                      FLEET$units[1], FLEET$units[2], FLEET$watts[1], FLEET$watts[2],
                      s$hp_known, s$p_lag, s$hp_real, s$price, CAPS[[cn]])
  mw <- st$site_w / 1e6
  cn_net[[cn]] <- c(gain = st$gain19 + st$gain21,
                    energy_keyed = sum(mw * 0.25 * (s$price * CH6_TLF + CH6_ANC + CH6_UPLIFT)),
                    distribution = od_year(mw, s$month)$bill)
}
cat("\nCONNECTION NET 2025 (gain vs never pausing, less the grid charges the connection changes):\n")
for (cn in names(cn_net)) {
  v <- cn_net[[cn]]
  cat(sprintf("  %5.2f MW: gain $%s, energy-keyed charges $%s, distribution $%s, gain less those $%s\n",
              CAPS[[cn]], format(round(v[["gain"]]), big.mark = ","),
              format(round(v[["energy_keyed"]]), big.mark = ","),
              format(round(v[["distribution"]]), big.mark = ","),
              format(round(v[["gain"]] - v[["energy_keyed"]] - v[["distribution"]]), big.mark = ",")))
}
dv <- cn_net[["uncapped"]] - cn_net[["stock"]]
cat(sprintf("  %.2f vs %.2f MW: gain +$%s, energy-keyed charges +$%s, distribution +$%s, net +$%s\n",
            CAPS[["uncapped"]], CAPS[["stock"]],
            format(round(dv[["gain"]]), big.mark = ","),
            format(round(dv[["energy_keyed"]]), big.mark = ","),
            format(round(dv[["distribution"]]), big.mark = ","),
            format(round(dv[["gain"]] - dv[["energy_keyed"]] - dv[["distribution"]]), big.mark = ",")))
