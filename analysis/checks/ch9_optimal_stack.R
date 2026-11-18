# ch9_optimal_stack.R -- Chapter 9: the flexibility stack for the reference
# site, year by year, as an operator could have planned it and as hindsight
# would have picked it, against two alternatives:
#   (a) the same grid-connected site never using its flexibility, and
#   (b) a behind-the-meter site buying power at a negotiated price with none
#       of the grid's flexibility revenue and none of the grid's charges.
# Run from the repo root:
#   Rscript analysis/checks/ch9_optimal_stack.R
# Writes analysis/data/ch9_optimal_stack.csv and ch9_btm_indifference.csv for
# the chapter 9 figures, and prints every number the chapter quotes.
#
# ONE MODEL FOR EVERY POLICY. Every policy here runs on the measured efficiency
# curves of analysis/checks/ch9_tuning.R (field telemetry), so "stock" means the
# stock point on the curve (28.57 J/TH for the S19j Pro, 12.76 for the S21 XP),
# not the nameplate 29.5 / 13.5 of chapter 4. The stack script
# (ch9_flexibility_stack.R) uses nameplate for its strike layer, which is why
# its strike figures sit 1 to 5 percent above the ones here (both book a wrong
# pause at its cost; the stack script clipped it at zero until 2026-09-27);
# the two agree on the tuned site to the dollar because both call the same
# function.
#
# THE CALENDAR. Hashprice comes through analysis/checks/ch9_hashprice.R, which
# fills the ten days missing from the spliced series and stops the run if a
# ledger year lacks a date or a quarter-hour. Until 2026-09-25 this script
# dropped those days silently and "2025" ran on 8,688 hours. The one exception
# is 2021-01-01: the loop decides on the previous day's hashprice and the series
# begins that day, so 2021 starts on January 2.
#
# THE GRID SITE. Real-time index at LZ_WEST, 67.13 MW connection. The mining
# decision compares the machine's value of the energy (previous day's hashprice)
# with the last published settlement price, chapter 5's convention; revenue and
# energy cost book at realised values. On top of energy the site pays the
# charges of chapter 6's ledger (Table 6.1). Three are keyed to the
# megawatt-hours it actually consumes: losses at ERCOT's factor and the
# ancillary and uplift allocations. The distribution line is billed as Oncor
# bills it (analysis/checks/oncor_distribution.R, shared with chapters 6 and 10
# and the calculator): per month, at the one site meter, on the month's highest
# quarter-hour of the site's draw with an 80 percent ratchet, plus the customer
# and metering charges, so a pause avoids it only where it lowers that month's
# peak, and it drives no pause and no power target. Every ledger year is billed
# as twelve whole months, as it is billed the whole transmission charge, though
# 2021 starts on January 2. Then Rider TCRF on the site's 4CP demand unless it
# dodges the four peaks. The 2025 ledger values are held for every year; the
# year-to-year comparison is about energy and flexibility, and the adders are
# 6 percent of the 2025 delivered price. Until 2026-10-03 the distribution line
# was booked at $0.50 per MWh consumed, which every pause appeared to save.
#
# THE LAYERS, in the order the chapter stacks them:
#   L0 never pause          stock power, always on           (chapters 4 and 6)
#   L1 strike               stock power, pause on the lagged rule   (chapter 6)
#   L2 tuning               joint exhaustive allocation over the curves under
#                           the 67.13 MW cap                          (chapter 5)
#   L3 4CP rule B           off on weekdays 4-6 p.m. June-September; TCRF
#                           saved for the official intervals that rule catches
#                                                                     (chapter 8)
#   L4 reserves instead     per fleet, standing ancillary revenue with the fleet
#                           held always on at stock; pre-RTC+B the reserve and
#                           the strike are exclusive for the same megawatt
#                                                                     (chapter 7)
# Where the window is played a seller withholds the window's hours from the
# award, and the ledger removes exactly what those hours paid at the day-ahead
# clearing price (analysis/data/ercot_dam_as_mcpc.csv.gz, ERCOT MIS 13091, hours
# ending 17 and 18 on June-September weekdays). Until 2026-09-25 it removed the window's share of
# the year's HOURS, about 2 percent, which understated the cut wherever the
# product paid most on summer afternoons (ECRS in 2023: 21 percent).
# The reserve path is booked conservatively: the fleet stays on the meter and
# buys every interval at the settlement price, including the storm hours of
# February 2021 in which a deployed Load Resource would have been off and paid.
# The 2021 reserve figure is therefore a floor on that count, and it rests on
# chapter 7's standing-revenue convention (every hour awarded at the day-ahead
# clearing price), which chapter 7 already qualifies.
#
# TWO ANNUAL CHOICES, AND WHO COULD HAVE MADE THEM. Inside a year every decision
# is lagged; nothing here sees an interval before it settles. Two choices are
# annual: which fleets hold reserve awards (and in which product), and whether
# to play the summer window. The ledger prints two answers to them, the way
# the loop is always printed beside its perfect-foresight twin:
#   HINDSIGHT  the best annual choice in hindsight: every allocation (neither
#              fleet, either, both), every product and the window on or off,
#              scored on the year's own outcomes, and the best taken. It needs
#              the year's prices before the year starts (in 2021, Uri). It is
#              the ceiling, not a strategy.
#   PLANNED    the choices an operator could have made with what was known at
#              the time. In January, commit to the reserve allocation and
#              product that won the PREVIOUS year's hindsight search; in the
#              first year, with no history, sell no reserves (the price-only
#              stack). On June 1, call the window with the rule of chapter 9's
#              step 5: the site's power-weighted strike on YESTERDAY's
#              hashprice, less LAST summer's window price, against the
#              transmission prize per window hour; in the first summer, with
#              no prior summer in the data, skip it. This is the headline,
#              the rule of record; the chapter prints the range of the rules
#              set in advance around it (the RULES SET IN ADVANCE line).
# The chapter's earlier reserve rule compared, fleet by fleet, standing revenue
# per MW with that fleet's strike-and-power-target gain per MW. Fed a year's own
# data it picked the year's best choice in only two years of five, because a
# fleet's power-target gain depends on the other fleet (they share the
# connection) and the per-MW view leaves out the window and the charges. The
# fixed rule scores whole-site allocations, so fed a year's own data it returns
# that year's best by construction; the planned site feeds it last year's.
# Alternatives are printed for the sensitivity: never selling reserves, the old
# per-fleet rule on last year's data, the planned reserve choice with the
# window taken in hindsight, and the planned site with the first summer's
# window played.
#
# THE BEHIND-THE-METER SITE. Same fleet, same 67.13 MW power budget, buys every
# megawatt-hour at one negotiated price P, pays no losses, ancillary, uplift,
# distribution or TCRF, sells no reserves, has no index to arbitrage, and may
# tune its machines against P like anyone else. It pays no distribution because
# it is chapter 6's islanded case: with no grid tie there is no utility meter to
# bill. A netted site that kept a grid tie would still pay the distribution line
# on its net monthly peak (chapter 6), which is the hybrid the chapter describes
# and does not model. The plant is treated as always
# available (a gas plant or a firmed contract); a wind-only island would run
# only when the wind blows. Two variants:
#   firm        the mine runs whenever it wants
#   interruptible the generator keeps the right to turn the mine off whenever
#               the zone price exceeds P, sells to the grid instead, and pays the
#               miner nothing for the interruption. Profit is then NOT monotone
#               in P (a cheap deal is interrupted most of the time), so the
#               script reports the run share and the highest P at which the
#               deal still matches the grid site, found on a price grid. The
#               zone price is a stand-in for the generator's node price, which
#               sits lower in West Texas, so the interruptions are overstated.
# The INDIFFERENCE PRICE P* is the P at which the behind-the-meter site earns
# exactly what the grid site earns, solved for three grid references (the
# planned site; the hindsight ceiling; never pause). The price range tested,
# BAND, runs from the wind captured price ($19, chapter 6) to the flat grid
# price with the peaks dodged ($45.35, chapter 6's ledger table). Chapter 6's
# own band tops out lower, at $39.90, because it prices a wind deal on the
# hours the wind blew; this fence is firm and flat, and a flat load's grid
# alternative is the $45. If P* lies below $19, no realistic behind-the-meter
# deal beats the grid site that year.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
source("analysis/checks/ch9_tuning.R")
source("analysis/checks/ch9_hashprice.R")

ZONE <- "LZ_WEST"; K <- 41666.7; H <- 0.25
FLEET <- data.frame(machine = c("S19j Pro", "S21 XP"), units = c(10000, 10000),
                    th = c(104, 270), watts = c(3068, 3645), jth = c(29.5, 13.5),
                    stringsAsFactors = FALSE)
FLEET$mw <- FLEET$units * FLEET$watts / 1e6
CAP_MW <- 67.13
TCRF   <- 41901                     # $/MW-yr of 4CP demand, chapter 8 (Oncor floor)
TLF <- 0.02155; ANC <- 0.39; UPLIFT <- 1.38   # chapter 6 ledger, 2025, per MWh consumed
source("analysis/checks/oncor_distribution.R")  # the distribution line, billed on each month's peak at the site meter
METERS <- 1                                      # one site meter, whatever the allocation of the fleets
BAND <- c(19, 45)                   # wind captured price to the flat grid price, peaks dodged (chapter 6: 45.35; its wind-hours top is 39.90)
CV <- list(ch9_curve("S19j Pro"), ch9_curve("S21 XP"))
PRODUCTS <- c(RRS = "rrs", ECRS = "ecrs", NonSpin = "nspin")
STORM <- c("2021-02-14", "2021-02-20")                       # Uri, as chapter 2 dates it

# ---- data (as in ch9_flexibility_stack.R) ------------------------------------
hp <- ch9_hashprice()
rt <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
rt <- rt[rt$settlement_point == ZONE, ]; rt <- rt[order(rt$interval_start), ]
rt$date <- substr(rt$interval_start, 1, 10); rt$year <- as.integer(substr(rt$date, 1, 4))
rt$month <- as.integer(substr(rt$date, 6, 7)); rt$hh <- as.integer(substr(rt$interval_start, 12, 13))
rt$wday <- format(as.Date(rt$date), "%u"); rt$key <- paste(rt$date, substr(rt$interval_start, 12, 16))
# CH9_LAG_Q (default 1): decide on the settlement price LAG_Q quarters back. The
# default is the book's ledger, which treats each price as readable the moment
# its quarter closes; ERCOT's API makes it readable a median 4.8 minutes later
# (analysis/checks/ch5_api_readability.py). CH9_LAG_Q=2 is the sensitivity run
# chapter 9 prints (a full quarter-hour late). Must be 1 or more. A run with it
# rewrites this script's CSVs in analysis/data: restore them with git checkout.
LAG_Q <- as.integer(Sys.getenv("CH9_LAG_Q", "1"))
stopifnot(LAG_Q >= 1)
rt$p_lag <- c(rep(NA, LAG_Q), head(rt$price, -LAG_Q))
rt <- ch9_attach_hashprice(rt, hp, !is.na(rt$p_lag))
source("analysis/checks/official_4cp.R")   # labels are interval ending; key = date + derived start
off <- read_official_4cp()
as <- read.csv("analysis/data/ercot_dam_as_mcpc.csv.gz", stringsAsFactors = FALSE)
as$year <- as.integer(substr(as$deliveryDate, 1, 4)); as$month <- as.integer(substr(as$deliveryDate, 6, 7))
as$wday <- format(as.Date(as$deliveryDate), "%u")
as$window <- as$month %in% 6:9 & as$wday %in% c("1", "2", "3", "4", "5") & as$hourEnding %in% c(17, 18)   # 4-6 p.m. Central
YEARS <- sort(unique(rt$year)); YEARS <- YEARS[sapply(YEARS, function(y) sum(rt$year == y) > 30000)]
for (y in YEARS) ch9_check_calendar(rt[rt$year == y, ], y, first = if (y == YEARS[1]) min(rt$date) else sprintf("%d-01-01", y))

# ---- helpers -------------------------------------------------------------------
# realised per-interval profit of one fleet at a fixed operating point
fleet_profit <- function(cv, k, units, hp_real, price) units * (hp_real * cv$h[k] / 96 - price * cv$p[k] / 1e6 * H)
adders_per_interval <- function(mw_on, price) mw_on * H * (price * TLF + ANC + UPLIFT)   # $ per interval, the energy-keyed lines
# the year's distribution bill for a site draw series (MW per interval, zero where the site is emptied);
# every call also records the lowest monthly peak and any month in which the ratchet binds
DIST_CHECK <- new.env(); DIST_CHECK$min_ncp <- Inf; DIST_CHECK$binds <- 0; DIST_CHECK$paths <- 0
dist_bill <- function(mw, month) {
  d <- od_year(mw, month, meters = METERS)
  DIST_CHECK$min_ncp <- min(DIST_CHECK$min_ncp, d$ncp); DIST_CHECK$binds <- DIST_CHECK$binds + d$binds; DIST_CHECK$paths <- DIST_CHECK$paths + 1
  d$bill
}
rule_B <- function(d) d$month %in% 6:9 & d$hh >= 16 & d$hh < 18 & d$wday %in% c("1", "2", "3", "4", "5")
rule_A <- function(d) d$month %in% 6:9 & d$hh >= 14 & d$hh < 18                                  # chapter 8's wider rule, console only
fmt <- function(x) format(round(x), big.mark = ",")
fmt_m <- function(x) sprintf("$%.2fM", x / 1e6)

# tuned site under the cap: per-interval profit and draw (MW) for both fleets
tuned_site <- function(s, price_dec, price_real, cap_mw = CAP_MW) {
  r <- ch9_tune_site(CV[[1]], CV[[2]], FLEET$units[1], FLEET$units[2], FLEET$watts[1], FLEET$watts[2],
                     s$hp_known, price_dec, s$hp_real, price_real, cap_mw)
  list(prof = r$r19$prof + r$r21$prof, prof19 = r$r19$prof, prof21 = r$r21$prof,
       mw = r$site_w / 1e6, mw19 = c(0, CV[[1]]$p)[r$bi] * FLEET$units[1] / 1e6,
       mw21 = c(0, CV[[2]]$p)[r$bj] * FLEET$units[2] / 1e6, r = r)
}
# one fleet tuned alone with the other fleet pinned at stock (the reserves case)
tuned_alone <- function(m, s, price_dec, price_real, cap_mw) {
  cv <- CV[[m]]; other <- 3 - m
  cap_p <- (cap_mw - FLEET$mw[other]) * 1e6 / FLEET$units[m]
  cap_p <- max(cv$p[cv$p <= cap_p])            # largest feasible grid point
  r <- ch9_tune(cv, s$hp_known, price_dec, s$hp_real, price_real, FLEET$watts[m], cap_p = cap_p)
  list(prof = r$tuned * FLEET$units[m], mw = ifelse(r$run, r$p_star, 0) * FLEET$units[m] / 1e6)
}
alloc_label <- function(alloc, product) {
  if (alloc == "flex") return("both fleets strike + tuning")
  if (alloc == "both") return(sprintf("both fleets on %s", product))
  sprintf("%s on %s, %s tuned", alloc, product, FLEET$machine[FLEET$machine != alloc])
}
choice_label <- function(ch) paste0(alloc_label(ch$alloc, ch$product), if (ch$fourcp) " + 4CP rule B" else "")

rows <- list(); ind <- list(); storm <- NULL
prev <- NULL; last_win <- NULL
old_allocs <- old_labels <- character(0)   # the old per-fleet rule's pick by year, console only (the CSV keeps its columns)
cat(sprintf("Reference site %.2f MW at %s, real-time index; adders held at the 2025 ledger; distribution on each month's peak at one meter ($%.6f per billing kW-month + $%.2f a month); TCRF $%s per MW-yr\n",
            CAP_MW, ZONE, OD_KW_MONTH, METERS * OD_FIXED_MONTH, format(TCRF, big.mark = ",")))
cat(sprintf("Ledger years %s; %d starts on %s, the first day with a previous day's hashprice\n\n",
            paste(YEARS, collapse = ", "), YEARS[1], min(rt$date)))
for (y in YEARS) {
  s <- rt[rt$year == y, ]; n <- nrow(s); o <- off[off$year == y, ]
  selB <- rule_B(s); caught <- sum(o$key %in% s$key[selB]); hours_B <- sum(selB) * H
  a <- as[as$year == y & as$deliveryDate >= min(s$date) & as$deliveryDate <= max(s$date), ]   # the ledger's own days (2021 starts on the 2nd)
  rate <- sapply(PRODUCTS, function(p) sum(a[[p]], na.rm = TRUE))                  # $ per MW-yr, awarded every hour
  rate_win <- sapply(PRODUCTS, function(p) sum(a[[p]][a$window], na.rm = TRUE))    # of which in the window's hours
  as_prod <- names(rate)[which.max(rate)]; as_rate <- max(rate)
  ks <- sapply(1:2, function(m) which.min(abs(CV[[m]]$p - FLEET$watts[m])))

  # L0 never pause, stock
  p0 <- fleet_profit(CV[[1]], ks[1], FLEET$units[1], s$hp_real, s$price) + fleet_profit(CV[[2]], ks[2], FLEET$units[2], s$hp_real, s$price)
  mw0 <- rep(CAP_MW, n)
  # L1 strike at stock, lagged decision per fleet
  on <- lapply(1:2, function(m) (s$hp_known * CV[[m]]$h[ks[m]] / 96 - s$p_lag * CV[[m]]$p[ks[m]] / 1e6 * H) > 0)
  p1 <- ifelse(on[[1]], fleet_profit(CV[[1]], ks[1], FLEET$units[1], s$hp_real, s$price), 0) +
        ifelse(on[[2]], fleet_profit(CV[[2]], ks[2], FLEET$units[2], s$hp_real, s$price), 0)
  mw1 <- on[[1]] * FLEET$mw[1] + on[[2]] * FLEET$mw[2]
  strike_per_mw <- sapply(1:2, function(m) {
    pr <- fleet_profit(CV[[m]], ks[m], FLEET$units[m], s$hp_real, s$price)
    sum(ifelse(on[[m]], pr, 0) - pr) / FLEET$mw[m] })          # $ per MW-yr, the stack script's either/or basis
  # L2 tuned, both fleets, lagged price
  t2 <- tuned_site(s, s$p_lag, s$price)
  flex_per_mw <- c(sum(t2$prof19 - fleet_profit(CV[[1]], ks[1], FLEET$units[1], s$hp_real, s$price)) / FLEET$mw[1],
                   sum(t2$prof21 - fleet_profit(CV[[2]], ks[2], FLEET$units[2], s$hp_real, s$price)) / FLEET$mw[2])  # strike + power target, $ per MW-yr
  # the mining side of every allocation: neither fleet on reserves (the price-only stack), one fleet
  # on reserves (always on at stock, no pausing) with the other tuned alone, or both on reserves
  paths <- list(flex = list(prof = t2$prof, mw = t2$mw, as_mw = 0))
  for (m in 1:2) {
    ta <- tuned_alone(3 - m, s, s$p_lag, s$price, CAP_MW)
    paths[[FLEET$machine[m]]] <- list(prof = fleet_profit(CV[[m]], ks[m], FLEET$units[m], s$hp_real, s$price) + ta$prof,
                                      mw = FLEET$mw[m] + ta$mw, as_mw = FLEET$mw[m])
  }
  paths[["both"]] <- list(prof = p0, mw = mw0, as_mw = CAP_MW)

  # grid charges, reserve revenue and the 4CP choice, for any allocation x product x window
  score <- function(alloc, product, fourcp, haircut = c("hours_paid", "share_of_year")) {
    haircut <- match.arg(haircut); cd <- paths[[alloc]]
    keep <- if (fourcp) !selB else rep(TRUE, n)
    mining <- sum(cd$prof[keep])
    adders <- sum(adders_per_interval(cd$mw[keep], s$price[keep]))
    dist <- dist_bill(ifelse(keep, cd$mw, 0), s$month)              # the window empties the site in its hours
    tcrf <- if (fourcp) CAP_MW * TCRF * (1 - caught / nrow(o)) else CAP_MW * TCRF
    asrev <- if (alloc == "flex") 0 else cd$as_mw * (rate[[product]] -
               if (!fourcp) 0 else if (haircut == "hours_paid") rate_win[[product]] else rate[[product]] * hours_B / (n * H))
    c(mining = mining, adders = adders, dist = dist, tcrf = tcrf, asrev = asrev, total = mining - adders - dist - tcrf + asrev)
  }
  choices <- list(list(alloc = "flex", product = NA_character_))
  for (al in c(FLEET$machine, "both")) for (pr in names(PRODUCTS)) if (rate[[pr]] > 0) choices[[length(choices) + 1]] <- list(alloc = al, product = pr)
  grid <- list()
  for (ch in choices) for (f in c(FALSE, TRUE))
    grid[[length(grid) + 1]] <- list(alloc = ch$alloc, product = ch$product, fourcp = f, sc = score(ch$alloc, ch$product, f))
  totals <- sapply(grid, function(g) g$sc[["total"]])
  hind <- grid[[which.max(totals)]]                               # the best annual choice in hindsight

  never <- c(mining = sum(p0), adders = sum(adders_per_interval(mw0, s$price)), dist = dist_bill(mw0, s$month), tcrf = CAP_MW * TCRF, asrev = 0)
  never["total"] <- never[["mining"]] - never[["adders"]] - never[["dist"]] - never[["tcrf"]]
  strike_only <- c(mining = sum(p1))
  tuned_only <- score("flex", NA, FALSE); tuned_4cp <- score("flex", NA, TRUE)
  mwh0 <- sum(mw0) * H

  cat(sprintf("==== %d ====  %s to %s, %s h; mean price $%.2f, strikes S19j Pro $%.0f / S21 XP $%.0f, best reserve %s $%s per MW-yr\n",
              y, min(s$date), max(s$date), fmt(n * H), mean(s$price), mean(s$hp_real) * K / 29.5, mean(s$hp_real) * K / 13.5, as_prod, fmt(as_rate)))
  cat(sprintf("  per MW-yr: strike alone S19j Pro $%s / S21 XP $%s; strike + power target $%s / $%s; best reserve $%s\n",
              fmt(strike_per_mw[1]), fmt(strike_per_mw[2]), fmt(flex_per_mw[1]), fmt(flex_per_mw[2]), fmt(as_rate)))
  cat(sprintf("  L0 never pause     mining $%14s  adders $%10s  distribution $%8s  TCRF $%10s  => grid profit $%14s\n",
              fmt(never["mining"]), fmt(never["adders"]), fmt(never["dist"]), fmt(never["tcrf"]), fmt(never["total"])))
  cat(sprintf("  L1 strike          mining $%14s  (+$%s over L0)\n", fmt(strike_only["mining"]), fmt(strike_only["mining"] - never["mining"])))
  cat(sprintf("  L2 + tuning        mining $%14s  (+$%s over L1)\n", fmt(tuned_only["mining"]), fmt(tuned_only["mining"] - strike_only["mining"])))
  cat(sprintf("  L3 + 4CP rule B    mining $%14s  TCRF $%10s  => %s$%s net over L2 (%d of %d peaks caught, %.0f h off)\n",
              fmt(tuned_4cp["mining"]), fmt(tuned_4cp["tcrf"]),
              if (tuned_4cp["total"] >= tuned_only["total"]) "+" else "-", fmt(abs(tuned_4cp["total"] - tuned_only["total"])), caught, nrow(o), hours_B))
  # chapter 8's wider rule A (every day 2-6 p.m., June-September) on the same tuned site, the same charges
  # and the same scoring as the L3 line; printed for chapter 9's comparison, never booked
  selA <- rule_A(s); caughtA <- sum(o$key %in% s$key[selA])
  totA <- sum(t2$prof[!selA]) - sum(adders_per_interval(t2$mw[!selA], s$price[!selA])) - dist_bill(ifelse(selA, 0, t2$mw), s$month) -
          CAP_MW * TCRF * (1 - caughtA / nrow(o))
  cat(sprintf("  L3 alt 4CP rule A  every day 2-6 p.m., %.0f h off, %d of %d peaks caught => %s$%s net over L2 (console only)\n",
              sum(selA) * H, caughtA, nrow(o), if (totA >= tuned_only["total"]) "+" else "-", fmt(abs(totA - tuned_only["total"]))))
  cat(sprintf("  WINDOW HOURS' SHARE OF STANDING REVENUE (%d h of the award withheld): %s; the window's share of the year's hours, the old haircut, %.1f%%\n",
              sum(a$window), paste(sprintf("%s %.1f%%", names(rate), 100 * ifelse(rate > 0, rate_win / rate, NA)), collapse = ", "), 100 * hours_B / (n * H)))
  for (al in c(FLEET$machine, "both")) {
    g <- score(al, as_prod, TRUE); g0 <- score(al, as_prod, FALSE); gold <- score(al, as_prod, TRUE, "share_of_year")
    cat(sprintf("  L4 %-42s reserves $%12s  => grid profit $%14s (4CP on) / $%14s (off); old haircut $%14s\n", alloc_label(al, as_prod),
                fmt(g["asrev"]), fmt(g["total"]), fmt(g0["total"]), fmt(gold["total"])))
  }

  # the old per-fleet rule, fed this year's own numbers: sell a fleet if the best standing revenue per MW
  # beat that fleet's strike-and-power-target gain per MW
  old_pick <- function(rate_best, fpm) { sell <- rate_best > fpm; if (all(sell)) "both" else if (sell[1]) FLEET$machine[1] else if (sell[2]) FLEET$machine[2] else "flex" }
  own_old <- old_pick(as_rate, flex_per_mw)
  own_old_sc <- score(own_old, as_prod, hind$fourcp)
  cat(sprintf("  CHOICE RULES FED THIS YEAR'S OWN DATA: the old per-fleet rule picks %s ($%s, %s the best); the whole-site rule picks %s ($%s, the best by construction)\n",
              alloc_label(own_old, as_prod), fmt(own_old_sc["total"]),
              if (abs(own_old_sc["total"] - hind$sc[["total"]]) < 1) "equal to" else sprintf("$%s below", fmt(hind$sc[["total"]] - own_old_sc["total"])),
              choice_label(hind), fmt(hind$sc[["total"]])))

  # ---- the summer-window rule as a site could apply it on June 1 ----------------------------
  # the site's power-weighted strike on YESTERDAY's hashprice against LAST summer's window price,
  # margin per MWh against the prize per window hour. The window's hours this summer are known from
  # the calendar; the prize is held at the Oncor floor.
  jth_site <- CAP_MW * 1e6 / sum(FLEET$units * FLEET$th)          # total watts over total TH/s = 17.95 J/TH
  june1 <- sprintf("%d-06-01", y)
  hp_june <- hp$hp_known[hp$date == june1]
  V_rule <- hp_june * K / jth_site                                  # known on the decision date
  V_hind <- mean(s$hp_real) * K / jth_site                          # the year's mean, known only in December
  win_now <- mean(s$price[selB])
  thr <- TCRF / hours_B
  window_paid <- tuned_4cp[["total"]] > tuned_only[["total"]]
  if (!is.null(last_win)) {
    m_rule <- V_rule - last_win; m_hind <- V_hind - last_win
    win_call <- m_rule < thr
    flip <- 100 * (m_rule * hours_B / TCRF - 1)                    # change in the prize that would flip the call
    cat(sprintf("  WINDOW RULE, June 1: site strike $%.0f on yesterday's hashprice $%.4f (%.2f J/TH); last summer's window price $%.2f -> margin $%.0f vs $%.0f per window hour: %s (%s); with the year's mean hashprice, known only in hindsight, strike $%.0f and margin $%.0f: %s; this summer's window price $%.2f; the window %s $%s net\n",
                V_rule, hp_june, jth_site, last_win, m_rule, thr, if (win_call) "play" else "skip",
                if (m_rule <= 0) "no prize flips it, the margin is negative" else sprintf("the call flips if the prize were %.1f%% %s", abs(flip), if (flip > 0) "higher" else "lower"),
                V_hind, m_hind, if (m_hind < thr) "play" else "skip", win_now,
                if (window_paid) "paid" else "lost", fmt(abs(tuned_4cp[["total"]] - tuned_only[["total"]]))))
  } else {
    win_call <- FALSE
    cat(sprintf("  WINDOW RULE, June 1: site strike $%.0f on yesterday's hashprice $%.4f (%.2f J/TH); no prior summer in the data, so the planned site skips; the window pays only if its hours average above $%.0f (strike less $%.0f per window hour); this summer's window price $%.2f; with the year's mean hashprice, known only in hindsight, strike $%.0f; the window %s $%s net\n",
                V_rule, hp_june, jth_site, V_rule - thr, thr, win_now, V_hind,
                if (window_paid) "paid" else "lost", fmt(abs(tuned_4cp[["total"]] - tuned_only[["total"]]))))
  }
  last_win <- win_now

  # ---- the planned site: reserves as last year's hindsight search chose, window by the June rule ----
  plan_res <- if (is.null(prev)) list(alloc = "flex", product = NA_character_) else prev$hind[c("alloc", "product")]
  plan <- list(alloc = plan_res$alloc, product = plan_res$product, fourcp = win_call)
  plan$sc <- score(plan$alloc, plan$product, plan$fourcp)
  # alternatives, for the sensitivity
  alt_noreserves <- score("flex", NA, win_call)                                    # never sell reserves
  alt_old <- if (is.null(prev)) alt_noreserves else {                               # the old per-fleet rule on last year's numbers
    al <- old_pick(prev$as_rate, prev$flex_per_mw); if (al == "flex") score("flex", NA, win_call) else score(al, prev$as_prod, win_call) }
  alt_old_label <- if (is.null(prev)) "no prior year" else alloc_label(old_pick(prev$as_rate, prev$flex_per_mw), prev$as_prod)
  old_labels <- c(old_labels, alt_old_label)
  old_allocs <- c(old_allocs, if (is.null(prev)) "flex" else old_pick(prev$as_rate, prev$flex_per_mw))
  alt_hindwin <- max(score(plan$alloc, plan$product, FALSE)[["total"]], score(plan$alloc, plan$product, TRUE)[["total"]])   # planned reserves, window in hindsight
  alt_win21 <- score(plan$alloc, plan$product, if (is.null(prev)) TRUE else win_call)[["total"]]                             # first summer played
  cat(sprintf("  PLANNED (decided before the year; reserves = last year's best in hindsight%s; window = the June rule): %s => grid profit $%s; flexibility $%s over never pausing (%.1f%%), $%.2f per MWh of the site's %s MWh; %s the hindsight ceiling\n",
              if (is.null(prev)) ", none in the first year" else sprintf(" (%s)", choice_label(prev$hind)), choice_label(plan), fmt(plan$sc[["total"]]),
              fmt(plan$sc[["total"]] - never[["total"]]), 100 * (plan$sc[["total"]] / never[["total"]] - 1), (plan$sc[["total"]] - never[["total"]]) / mwh0, fmt(mwh0),
              if (abs(plan$sc[["total"]] - hind$sc[["total"]]) < 1) "equal to" else sprintf("$%s below", fmt(hind$sc[["total"]] - plan$sc[["total"]]))))
  cat(sprintf("  HINDSIGHT CEILING (the best annual choice in hindsight): %s => grid profit $%s; flexibility $%s over never pausing (%.1f%%), $%.2f per MWh\n",
              choice_label(hind), fmt(hind$sc[["total"]]), fmt(hind$sc[["total"]] - never[["total"]]),
              100 * (hind$sc[["total"]] / never[["total"]] - 1), (hind$sc[["total"]] - never[["total"]]) / mwh0))
  cat(sprintf("  ALTERNATIVE PLANS (flexibility over never pausing): never sell reserves $%s (%.1f%%); old per-fleet rule on last year's data, %s, $%s (%.1f%%); planned reserves with the window in hindsight $%s; planned with the first summer's window played $%s\n",
              fmt(alt_noreserves[["total"]] - never[["total"]]), 100 * (alt_noreserves[["total"]] / never[["total"]] - 1),
              alt_old_label, fmt(alt_old[["total"]] - never[["total"]]), 100 * (alt_old[["total"]] / never[["total"]] - 1),
              fmt(alt_hindwin - never[["total"]]), fmt(alt_win21 - never[["total"]])))
  # ---- the firmware's development fee, which the ledger does not take out (chapter 9, Layer Two) ----
  # Braiins OS takes its fee as a share of every hash a machine computes, so it is priced here on mining
  # revenue before energy (hashprice x terahash), not on the power target's gain. A path's revenue is its
  # profit plus the energy it bought at the settlement price; the direct sums below hold it to the curves.
  gross_rev <- function(ch) { cd <- paths[[ch$alloc]]; keep <- if (ch$fourcp) !selB else rep(TRUE, n)
                              sum(cd$prof[keep] + cd$mw[keep] * s$price[keep] * H) }
  rev_never <- sum(sapply(1:2, function(m) FLEET$units[m] * sum(s$hp_real * CV[[m]]$h[ks[m]] / 96)))
  rev_plan <- gross_rev(plan)
  if (plan$alloc == "flex") {                                   # the tuned path, summed from the curve points it chose
    keep <- if (plan$fourcp) !selB else rep(TRUE, n)
    rev_direct <- sum((s$hp_real * (c(0, CV[[1]]$h)[t2$r$bi] * FLEET$units[1] + c(0, CV[[2]]$h)[t2$r$bj] * FLEET$units[2]) / 96)[keep])
    stopifnot(abs(rev_plan - rev_direct) < 1)
  }
  FEE <- 0.025                                                   # Braiins OS licence sec. 5.4 default; the website's 2.5% dev fee
  cat(sprintf("  FIRMWARE FEE (not in the ledger): mining revenue before energy, never pausing $%s, planned site $%s (%.3f of it); at %.1f%% the fee is $%s and $%s ($%s and $%s per MW-yr); the power target's increment $%s\n",
              fmt(rev_never), fmt(rev_plan), rev_plan / rev_never, 100 * FEE, fmt(FEE * rev_never), fmt(FEE * rev_plan),
              fmt(FEE * rev_never / CAP_MW), fmt(FEE * rev_plan / CAP_MW), fmt(tuned_only[["mining"]] - strike_only[["mining"]])))

  if (y == 2025) {
    aug <- o$date[substr(o$date, 6, 7) == "08"][1]
    d0 <- as.Date(aug); wk_start <- d0 - (as.integer(format(d0, "%u")) - 1); wk <- as.character(seq(wk_start, wk_start + 6, by = 1))
    sel <- s$date %in% wk
    fourcp_plan <- plan$fourcp                                     # the planned site's own window decision
    mw19_w <- if (fourcp_plan) ifelse(selB, 0, t2$mw19) else t2$mw19
    mw21_w <- if (fourcp_plan) ifelse(selB, 0, t2$mw21) else t2$mw21
    wkdf <- data.frame(interval_start = s$interval_start[sel], price = s$price[sel],
                       strike19 = s$hp_real[sel] * K / 29.5, strike21 = s$hp_real[sel] * K / 13.5,
                       mw19 = mw19_w[sel], mw21 = mw21_w[sel], mw19_stock = FLEET$mw[1], mw21_stock = FLEET$mw[2],
                       window = selB[sel], official_4cp = s$key[sel] %in% o$key)
    write.csv(wkdf, "analysis/data/ch9_dispatch_week_2025.csv", row.names = FALSE)
    oa <- o[substr(o$date, 6, 7) == "08", ][1, ]
    cat(sprintf("  dispatch week exported: %s to %s (official August interval %s %s-%s, ERCOT label %s, at $%.2f), %d intervals, window %.0f%% of the week; site mean %.1f MW; S21 XP at its ceiling %.0f%% of the week; S19j Pro below stock but on %.0f%%, off %.0f%% (of which the window %.0f%%)\n",
                wk[1], wk[7], oa$date, oa$interval_start_cpt, oa$interval_ending_cpt, oa$interval_ending_cpt,
                s$price[sel][wkdf$official_4cp][1], sum(sel), 100 * mean(selB[sel]),
                mean((mw19_w + mw21_w)[sel]), 100 * mean(mw21_w[sel] >= 39.8),
                100 * mean(mw19_w[sel] < FLEET$mw[1] & mw19_w[sel] > 0), 100 * mean(mw19_w[sel] == 0), 100 * mean(selB[sel])))
  }

  # the sum that is not the stack: strike + tuning + the whole transmission prize, against the joint result
  naive <- (strike_only[["mining"]] - never[["mining"]]) + (tuned_only[["mining"]] - strike_only[["mining"]]) + CAP_MW * TCRF
  joint <- tuned_4cp[["total"]] - never[["total"]]
  cat(sprintf("  SUM VS STACK (strike + tuning + 4CP on the index): naive sum $%s, joint $%s, interference $%s (%.0f%% overstatement)\n",
              fmt(naive), fmt(joint), fmt(joint - naive), 100 * (naive / joint - 1)))

  # ---- behind the meter: tuned against a constant price P, same cap ----------
  # one tuned run per price serves both variants, cached so the three targets share the work
  btm_cache <- new.env()
  btm_eval <- function(P) {
    key <- sprintf("%.12g", P)
    if (is.null(btm_cache[[key]])) { t <- tuned_site(s, rep(P, n), rep(P, n)); btm_cache[[key]] <- c(firm = sum(t$prof), int = sum(t$prof[s$price <= P])) }
    btm_cache[[key]]
  }
  btm_profit <- function(P, interruptible = FALSE) unname(btm_eval(P)[if (interruptible) "int" else "firm"])
  solve_P <- function(target, lo = -600, hi = 1500) {       # firm supply: monotone in P
    if (btm_profit(lo) < target) return(NA_real_)
    for (it in 1:24) { mid <- (lo + hi) / 2; if (btm_profit(mid) > target) lo <- mid else hi <- mid }
    (lo + hi) / 2
  }
  Pg <- seq(0, 400, by = 2.5)
  ceiling_P <- function(target) {                             # interruptible: highest P on a grid that still matches
    prof <- sapply(Pg, btm_profit, interruptible = TRUE)
    ok <- which(prof >= target); if (!length(ok)) return(c(NA_real_, max(prof), Pg[which.max(prof)]))
    hiP <- Pg[max(ok)]; lo <- hiP; hi <- min(hiP + 2.5, 400)
    for (it in 1:12) { mid <- (lo + hi) / 2; if (btm_profit(mid, TRUE) >= target) lo <- mid else hi <- mid }
    c((lo + hi) / 2, max(prof), Pg[which.max(prof)])
  }
  refs <- c(planned = plan$sc[["total"]], hindsight = hind$sc[["total"]], never = never[["total"]])
  P_firm <- sapply(refs, solve_P)
  P_int <- lapply(refs, ceiling_P)
  pstr <- function(p) if (is.na(p)) "no price" else sprintf("$%.2f", p)
  cat(sprintf("  BEHIND THE METER, firm supply: indifference price %s vs the planned grid site, %s vs the hindsight ceiling, %s vs the never-pausing one; band $%d-$%d\n",
              pstr(P_firm[["planned"]]), pstr(P_firm[["hindsight"]]), pstr(P_firm[["never"]]), BAND[1], BAND[2]))
  cat(sprintf("                    interruptible at P: best case $%s at P = $%.0f; matches the planned grid site up to P = %s, the hindsight ceiling up to P = %s, the never-pausing one up to P = %s\n",
              fmt(P_int$planned[2]), P_int$planned[3], pstr(P_int$planned[1]), pstr(P_int$hindsight[1]), pstr(P_int$never[1])))
  for (P in c(BAND[1], 30, BAND[2])) cat(sprintf("                    at P = $%2d: firm BTM profit $%s (%+.1f%% vs planned grid, %+.1f%% vs hindsight, %+.1f%% vs never pause); interruptible runs %.0f%% of intervals, profit $%s\n", P,
        fmt(btm_profit(P)), 100 * (btm_profit(P) / refs[["planned"]] - 1), 100 * (btm_profit(P) / refs[["hindsight"]] - 1), 100 * (btm_profit(P) / never[["total"]] - 1),
        100 * mean(s$price <= P), fmt(btm_profit(P, TRUE))))
  # the two columns: what the fence saves per MWh against what flexibility earns per MWh
  charges_mwh <- function(ch) (ch$sc[["adders"]] + ch$sc[["dist"]] + ch$sc[["tcrf"]]) / (sum(paths[[ch$alloc]]$mw[if (ch$fourcp) !selB else TRUE]) * H)
  cat(sprintf("  PER MWh: grid site pays $%.2f of charges on top of energy as planned, $%.2f at the hindsight ceiling, $%.2f never pausing; flexibility earns $%.2f per MWh consumed at stock as planned, $%.2f at the ceiling; mean energy price $%.2f\n",
              charges_mwh(plan), charges_mwh(hind), (never[["adders"]] + never[["dist"]] + never[["tcrf"]]) / mwh0,
              (plan$sc[["total"]] - never[["total"]]) / mwh0, (hind$sc[["total"]] - never[["total"]]) / mwh0, mean(s$price)))
  cat(sprintf("  DISTRIBUTION (Oncor, the site meter's highest quarter-hour each month): never pausing $%s (%.2f MW every month), planned $%s, hindsight ceiling $%s; per MWh consumed $%.3f never pausing, $%.3f as planned\n",
              fmt(never[["dist"]]), CAP_MW, fmt(plan$sc[["dist"]]), fmt(hind$sc[["dist"]]), never[["dist"]] / mwh0,
              plan$sc[["dist"]] / (sum(paths[[plan$alloc]]$mw[if (plan$fourcp) !selB else TRUE]) * H)))
  # what sets the gap between those bills: the months' peaks, and the two draws the never-pausing site is
  # booked on (its charges on the 67.13 MW connection at nameplate, its energy at the curves' stock points)
  peaks <- function(ch) range(od_ncp(ifelse(if (ch$fourcp) !selB else rep(TRUE, n), paths[[ch$alloc]]$mw, 0), s$month))
  top <- which.max(t2$mw); w_stock <- sapply(1:2, function(m) CV[[m]]$p[ks[m]])
  cat(sprintf("  DISTRIBUTION PEAKS: monthly peaks %.2f to %.2f MW as planned, %.2f to %.2f MW at the hindsight ceiling; the tuned site's highest quarter-hour %.2f MW (S19j Pro %s W + S21 XP %s W a pair); never pausing is billed on the %.2f MW connection at nameplate (%s + %s W a pair), the draw its other charges are booked on, while its energy is priced at the curves' stock points, %.2f MW (%s + %s W)\n",
              peaks(plan)[1], peaks(plan)[2], peaks(hind)[1], peaks(hind)[2], t2$mw[top],
              fmt(t2$mw19[top] * 1e6 / FLEET$units[1]), fmt(t2$mw21[top] * 1e6 / FLEET$units[2]),
              CAP_MW, fmt(FLEET$watts[1]), fmt(FLEET$watts[2]),
              sum(w_stock * FLEET$units) / 1e6, fmt(w_stock[1]), fmt(w_stock[2])))

  # ---- the storm week: how much of each year's flexibility fell in February 14-20, 2021 ----------
  in_storm <- s$date >= STORM[1] & s$date <= STORM[2]
  # The distribution line is billed on February's highest quarter-hour, which no path set in the storm
  # week (asserted below), so the storm week neither earned nor cost any of it and it stays out of the sum.
  storm_value <- function(ch) {                              # per-interval value over never pausing, summed over the storm
    cd <- paths[[ch$alloc]]; keep <- if (ch$fourcp) !selB else rep(TRUE, n)
    feb <- s$month == 2; draw <- ifelse(keep, cd$mw, 0)
    stopifnot(max(draw[feb & !in_storm]) >= max(draw[feb]))
    v <- ifelse(keep, cd$prof - adders_per_interval(cd$mw, s$price), 0) - (p0 - adders_per_interval(mw0, s$price))
    as_storm <- if (ch$alloc == "flex") 0 else cd$as_mw * sum(a[[PRODUCTS[[ch$product]]]][a$deliveryDate >= STORM[1] & a$deliveryDate <= STORM[2]], na.rm = TRUE)
    sum(v[in_storm]) + as_storm
  }
  if (any(in_storm)) {
    storm <- c(planned = storm_value(plan), hindsight = storm_value(hind),
               planned_flex = plan$sc[["total"]] - never[["total"]], hindsight_flex = hind$sc[["total"]] - never[["total"]])
    stormA <- a$deliveryDate >= STORM[1] & a$deliveryDate <= STORM[2]
    cat(sprintf("  2021 RESERVES: $%s of the $%s RRS standing revenue per MW-yr fell in Feb 14-20 (%.0f%%); the site's RRS total assumes every hour awarded at the day-ahead clearing price (chapter 7's standing-revenue convention)\n",
                fmt(sum(a$rrs[stormA], na.rm = TRUE)), fmt(rate[["RRS"]]), 100 * sum(a$rrs[stormA], na.rm = TRUE) / rate[["RRS"]]))
    cat(sprintf("  2021 STORM WEEK (Feb 14-20): planned site $%s of its $%s flexibility (%.0f%%); hindsight ceiling $%s of $%s (%.0f%%)\n",
                fmt(storm["planned"]), fmt(storm["planned_flex"]), 100 * storm["planned"] / storm["planned_flex"],
                fmt(storm["hindsight"]), fmt(storm["hindsight_flex"]), 100 * storm["hindsight"] / storm["hindsight_flex"]))
  }
  cat("\n")

  rows[[length(rows) + 1]] <- data.frame(year = y, first_day = min(s$date), hours = n * H, mean_price = mean(s$price),
    strike19 = mean(s$hp_real) * K / 29.5, strike21 = mean(s$hp_real) * K / 13.5,
    mwh = mwh0, never_mining = never[["mining"]], never_adders = never[["adders"]], never_dist = never[["dist"]], never_tcrf = never[["tcrf"]], never_total = never[["total"]],
    strike_gain = strike_only[["mining"]] - never[["mining"]], tuning_gain = tuned_only[["mining"]] - strike_only[["mining"]],
    fourcp_net = tuned_4cp[["total"]] - tuned_only[["total"]], fourcp_caught = caught, fourcp_hours = hours_B,
    as_product = as_prod, as_rate = as_rate, as_window_share = rate_win[[as_prod]] / as_rate,
    window_rule_play = win_call, window_hindsight_play = window_paid,
    plan_alloc = plan$alloc, plan_product = plan$product, plan_label = alloc_label(plan$alloc, plan$product), plan_fourcp = plan$fourcp,
    plan_mining = plan$sc[["mining"]], plan_adders = plan$sc[["adders"]], plan_dist = plan$sc[["dist"]], plan_tcrf = plan$sc[["tcrf"]], plan_asrev = plan$sc[["asrev"]],
    plan_total = plan$sc[["total"]], plan_flex = plan$sc[["total"]] - never[["total"]],
    hind_alloc = hind$alloc, hind_product = hind$product, hind_label = alloc_label(hind$alloc, hind$product), hind_fourcp = hind$fourcp,
    hind_mining = hind$sc[["mining"]], hind_adders = hind$sc[["adders"]], hind_dist = hind$sc[["dist"]], hind_tcrf = hind$sc[["tcrf"]], hind_asrev = hind$sc[["asrev"]],
    hind_total = hind$sc[["total"]], hind_flex = hind$sc[["total"]] - never[["total"]],
    priceonly_best_total = max(tuned_only[["total"]], tuned_4cp[["total"]]), alt_noreserves_total = alt_noreserves[["total"]],
    alt_oldrule_total = alt_old[["total"]], alt_hindwindow_total = alt_hindwin, alt_firstwindow_total = alt_win21,
    alt_firstreserves_total = if (is.null(prev)) hind$sc[["total"]] else plan$sc[["total"]],
    naive_sum = naive, joint_index = joint,
    charges_per_mwh_plan = charges_mwh(plan), charges_per_mwh_hind = charges_mwh(hind),
    charges_per_mwh_never = (never[["adders"]] + never[["dist"]] + never[["tcrf"]]) / mwh0, stringsAsFactors = FALSE)
  ind[[length(ind) + 1]] <- data.frame(year = y, reference = rep(names(refs), 2), variant = rep(c("firm", "interruptible"), each = 3),
    p_star = c(P_firm, sapply(P_int, `[`, 1)), band_lo = BAND[1], band_hi = BAND[2],
    btm_at_19 = btm_profit(19), btm_at_30 = btm_profit(30), btm_at_45 = btm_profit(45))
  prev <- list(hind = hind, as_rate = as_rate, as_prod = as_prod, flex_per_mw = flex_per_mw)
}
res <- do.call(rbind, rows); indf <- do.call(rbind, ind)
write.csv(res, "analysis/data/ch9_optimal_stack.csv", row.names = FALSE)
write.csv(indf, "analysis/data/ch9_btm_indifference.csv", row.names = FALSE)

cat("=== Five years (USD millions) ===\n")
tot <- function(x) sum(x) / 1e6
cat(sprintf("  flexibility over never pausing, 2021-2025: planned $%.2fM; hindsight ceiling $%.2fM (the planned site earned %.0f%% of the ceiling)\n",
            tot(res$plan_flex), tot(res$hind_flex), 100 * sum(res$plan_flex) / sum(res$hind_flex)))
cat(sprintf("  alternatives: never sell reserves $%.2fM; old per-fleet rule on last year's data $%.2fM; planned reserves, window in hindsight $%.2fM; planned with the first summer's window played $%.2fM\n",
            tot(res$alt_noreserves_total - res$never_total), tot(res$alt_oldrule_total - res$never_total),
            tot(res$alt_hindwindow_total - res$never_total), tot(res$alt_firstwindow_total - res$never_total)))
# The one default the headline leans on is the first year's: with no history it
# sells no reserves. Had a prior year's ledger pointed it at the first year's
# hindsight choice, that year would equal the ceiling, and every later year is
# unchanged, because each January follows the previous year's hindsight winner.
cat(sprintf("  first-year default: had the first year followed its own hindsight choice (%s), the planned five years would be $%.2fM, not $%.2fM\n",
            res$hind_label[1], tot(res$alt_firstreserves_total - res$never_total), tot(res$plan_flex)))
cat(sprintf("  where the planned reserve choice differs from never selling reserves: %s\n",
            paste(sprintf("%d %s %s", res$year, res$plan_label, sprintf("%+.2fM", (res$plan_total - res$alt_noreserves_total) / 1e6))[res$plan_alloc != "flex"], collapse = "; ")))
cat(sprintf("  where the old per-fleet rule's reserve choice differs from never selling reserves: %s\n",
            paste(sprintf("%d %s %+.2fM", res$year, old_labels, (res$alt_oldrule_total - res$alt_noreserves_total) / 1e6)[old_allocs != "flex"], collapse = "; ")))
# The rules an operator could have set in advance (the planned site, never
# selling reserves, the old per-fleet rule on last year's data), graded the way
# chapter 5 grades the loop: capture is a rule's gain over never pausing as a
# share of the ceiling's, the hindsight ceiling standing in for the oracle one
# level up. The reserve commitments are every year a rule set in advance sold
# reserves, each scored against never selling them in the same year.
ns_flex <- res$alt_noreserves_total - res$never_total
later <- res$year != res$year[1]
cap <- function(flex, i) 100 * sum(flex[i]) / sum(res$hind_flex[i])
cat(sprintf("  CAPTURE (flexibility over never pausing as a share of the hindsight ceiling's): planned %d %.1f%%, %d-%d %.1f%%, five years %.1f%%; never sell reserves %d %.1f%%, %d-%d %.1f%%, five years %.1f%%\n",
            res$year[1], cap(res$plan_flex, !later), min(res$year[later]), max(res$year), cap(res$plan_flex, later), cap(res$plan_flex, TRUE),
            res$year[1], cap(ns_flex, !later), min(res$year[later]), max(res$year), cap(ns_flex, later), cap(ns_flex, TRUE)))
adv <- c(tot(res$alt_oldrule_total - res$never_total), tot(res$plan_flex), tot(ns_flex))
sells <- c((res$plan_total - res$alt_noreserves_total)[res$plan_alloc != "flex"],
           (res$alt_oldrule_total - res$alt_noreserves_total)[old_allocs != "flex"])
cat(sprintf("  RULES SET IN ADVANCE: five-year flexibility $%.2fM to $%.2fM (old per-fleet rule $%.2fM, planned $%.2fM, never sell reserves $%.2fM) against the hindsight ceiling's $%.2fM; they committed to reserves %d times (planned %d, old per-fleet rule %d) and never selling reserves did better in %d of them, by $%.2fM to $%.2fM\n",
            min(adv), max(adv), adv[1], adv[2], adv[3], tot(res$hind_flex), length(sells), sum(res$plan_alloc != "flex"), sum(old_allocs != "flex"),
            sum(sells < 0), min(-sells) / 1e6, max(-sells) / 1e6))
if (!is.null(storm))
  cat(sprintf("  STORM SHARE: Feb 14-20, 2021 earned $%.2fM of the planned five-year $%.2fM (%.0f%%), and $%.2fM of the hindsight five-year $%.2fM (%.0f%%)\n",
              storm["planned"] / 1e6, tot(res$plan_flex), 100 * storm["planned"] / sum(res$plan_flex),
              storm["hindsight"] / 1e6, tot(res$hind_flex), 100 * storm["hindsight"] / sum(res$hind_flex)))
cat(sprintf("  DISTRIBUTION CHECK: %d site draw series billed; lowest monthly peak of any of them %.2f MW, against the ratchet's 80%% of the %.2f MW connection, %.2f MW; the ratchet binds in %d months%s\n",
            DIST_CHECK$paths, DIST_CHECK$min_ncp, CAP_MW, OD_RATCHET * CAP_MW, DIST_CHECK$binds,
            if (DIST_CHECK$min_ncp >= OD_RATCHET * CAP_MW) ", and no history before a year's first month could make it bind" else "; a year's first month bills no history"))
cat("\n=== Summary table (for the chapter) ===\n")
fp <- function(ref) round(indf$p_star[indf$reference == ref & indf$variant == "firm"], 2)
print(data.frame(year = res$year, never = round(res$never_total / 1e6, 2),
                 planned = round(res$plan_total / 1e6, 2), plan_flex = round(res$plan_flex / 1e6, 2),
                 plan_pct = round(100 * res$plan_flex / res$never_total, 1), plan_per_mwh = round(res$plan_flex / res$mwh, 2),
                 hindsight = round(res$hind_total / 1e6, 2), hind_flex = round(res$hind_flex / 1e6, 2),
                 hind_pct = round(100 * res$hind_flex / res$never_total, 1), hind_per_mwh = round(res$hind_flex / res$mwh, 2)), row.names = FALSE)
print(data.frame(year = res$year, planned = paste0(res$plan_label, ifelse(res$plan_fourcp, " + window", "")),
                 hindsight = paste0(res$hind_label, ifelse(res$hind_fourcp, " + window", "")),
                 P_star_planned = fp("planned"), P_star_hindsight = fp("hindsight"), P_star_never = fp("never")), row.names = FALSE)
cat("\nwrote analysis/data/ch9_optimal_stack.csv and analysis/data/ch9_btm_indifference.csv\n")
