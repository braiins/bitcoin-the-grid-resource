# ch10_hashprice_sensitivity.R -- Chapter 10: what happens to the flexibility
# stack of chapter 9's reference site as hashprice falls. Run from the repo root:
#   Rscript analysis/checks/ch10_hashprice_sensitivity.R
#
# THE QUESTION. The strike is hashprice x 41,666.7 / J/TH (chapter 4), so every
# halving, and every fall in hashprice between halvings, moves every machine's
# strike down toward the power price. The S19j Pro already lives there in 2025:
# its strike of $72 sits inside the LZ_WEST price band and it paused 14 percent
# of the year on chapter 9's strike-only rule, while the S21 XP, at $157, paused
# under 2 percent. NOTE ON BASES: the "off" shares printed here are the engine's,
# which underclocks before it pauses and counts only quarter-hours at zero draw,
# so they sit below the strike-only pause shares of chapter 9's Figure 9.1.
# This script reruns chapter 9's 2025 ledger with hashprice scaled to 100, 75,
# 50, 35 and 25 percent of its actual path and reports what the site's
# flexibility was then worth: in dollars, as a share of the never-pausing
# site's margin after power and grid charges, as a share of mining revenue,
# and in hours paused. It then runs
# the actual first months of 2026, the first year under RTC+B, on the same
# basis (no summer-window layer: the year's official 4CP intervals are not yet
# published, and the data end in late August).
#
# Everything else is chapter 9's engine, unchanged: analysis/checks/
# ch9_optimal_stack.R conventions (lagged decisions, measured curves, 67.13 MW
# cap, 2025 ledger charges, TCRF at the Oncor floor, summer window = weekdays
# 4-6 p.m. June-September, reserves left aside because they lose in 2025).
# The distribution line is billed as Oncor bills it, on the site meter's highest
# quarter-hour each month (analysis/checks/oncor_distribution.R, shared with
# chapters 6 and 9), so a pause or an underclock avoids it only where it lowers
# a month's peak; the partial 2026 bills its last month pro rata by days, as it
# bills TCRF pro rata by hours. Until 2026-10-03 this script booked it at $0.50
# per MWh consumed, which every pause appeared to save.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
source("analysis/checks/ch9_tuning.R")
ZONE <- "LZ_WEST"; K <- 41666.7; H <- 0.25
FLEET <- data.frame(machine = c("S19j Pro", "S21 XP"), units = c(10000, 10000), th = c(104, 270),
                    watts = c(3068, 3645), jth = c(29.5, 13.5), stringsAsFactors = FALSE)
FLEET$mw <- FLEET$units * FLEET$watts / 1e6
CAP_MW <- 67.13; TCRF <- 41901; TLF <- 0.02155; ANC <- 0.39; UPLIFT <- 1.38   # per MWh consumed, chapter 6 ledger, 2025
source("analysis/checks/oncor_distribution.R")   # the distribution line, billed on each month's peak at one site meter
CV <- list(ch9_curve("S19j Pro"), ch9_curve("S21 XP"))
# hashprice through chapter 9's shared loader (analysis/checks/ch9_hashprice.R):
# the ten days missing from the spliced series filled and the calendar
# asserted. Until 2026-09-25 this script dropped them, so the 2025 row ran on
# 8,688 hours and the 2026 row on 234 days.
source("analysis/checks/ch9_hashprice.R")
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

fleet_profit <- function(cv, k, units, hp_real, price) units * (hp_real * cv$h[k] / 96 - price * cv$p[k] / 1e6 * H)
adders <- function(mw_on, price) mw_on * H * (price * TLF + ANC + UPLIFT)   # $ per interval, the energy-keyed lines
DIST_CHECK <- new.env(); DIST_CHECK$min_ncp <- Inf; DIST_CHECK$binds <- 0
dist_bill <- function(mw, s, share) {              # the year's distribution bill for a site draw series (MW per interval)
  d <- od_year(mw, s$month, meters = 1, share = share)
  DIST_CHECK$min_ncp <- min(DIST_CHECK$min_ncp, d$ncp); DIST_CHECK$binds <- DIST_CHECK$binds + d$binds
  d$bill
}
rule_B <- function(d) d$month %in% 6:9 & d$hh >= 16 & d$hh < 18 & d$wday %in% c("1", "2", "3", "4", "5")
ks <- sapply(1:2, function(m) which.min(abs(CV[[m]]$p - FLEET$watts[m])))

evaluate <- function(s, o, f, label) {
  s$hp_real <- s$hp_real * f; s$hp_known <- s$hp_known * f
  n <- nrow(s); hours <- n * H
  p0 <- fleet_profit(CV[[1]], ks[1], FLEET$units[1], s$hp_real, s$price) + fleet_profit(CV[[2]], ks[2], FLEET$units[2], s$hp_real, s$price)
  rev0 <- sum(s$hp_real * (CV[[1]]$h[ks[1]] * FLEET$units[1] + CV[[2]]$h[ks[2]] * FLEET$units[2]) / 96)
  tcrf_full <- CAP_MW * TCRF * (if (substr(label, 1, 4) == "2026") hours / 8760 else 1)   # pro rata only for the partial 2026 year; 2025 pays the full charge as in chapter 9
  # distribution: every month in full for 2025, as chapter 9 bills it; the partial 2026 pro rata by the days each month covers
  mo <- unique(s$month); yr <- as.integer(substr(s$date[1], 1, 4))
  dim_days <- as.integer(format(as.Date(sprintf("%d-%02d-01", yr + (mo == 12), mo %% 12 + 1)) - 1, "%d"))
  share <- if (substr(label, 1, 4) == "2026") sapply(mo, function(m) length(unique(s$date[s$month == m]))) / dim_days else 1
  dist_never <- dist_bill(rep(CAP_MW, n), s, share)
  never <- sum(p0) - sum(adders(CAP_MW, s$price)) - dist_never - tcrf_full
  r <- ch9_tune_site(CV[[1]], CV[[2]], FLEET$units[1], FLEET$units[2], FLEET$watts[1], FLEET$watts[2],
                     s$hp_known, s$p_lag, s$hp_real, s$price, CAP_MW)
  prof <- r$r19$prof + r$r21$prof; mw <- r$site_w / 1e6
  mw19 <- c(0, CV[[1]]$p)[r$bi] * FLEET$units[1] / 1e6; mw21 <- c(0, CV[[2]]$p)[r$bj] * FLEET$units[2] / 1e6
  # hashes, not megawatts: an underclocked machine sheds more energy than hashes,
  # so the hashrate the site withholds is smaller than the energy it saves
  th <- c(0, CV[[1]]$h)[r$bi] * FLEET$units[1] + c(0, CV[[2]]$h)[r$bj] * FLEET$units[2]
  th_stock <- CV[[1]]$h[ks[1]] * FLEET$units[1] + CV[[2]]$h[ks[2]] * FLEET$units[2]
  dist_nowin <- dist_bill(mw, s, share)
  flex_nowin <- sum(prof) - sum(adders(mw, s$price)) - dist_nowin - tcrf_full
  window_on <- FALSE; flex <- flex_nowin; dist_opt <- dist_nowin
  if (nrow(o)) {
    selB <- rule_B(s); caught <- sum(o$key %in% s$key[selB])
    dist_win <- dist_bill(ifelse(selB, 0, mw), s, share)   # the window empties the site in its hours; the month's peak falls elsewhere
    with_win <- sum(prof[!selB]) - sum(adders(mw[!selB], s$price[!selB])) - dist_win - CAP_MW * TCRF * (1 - caught / nrow(o))
    if (with_win > flex_nowin) { flex <- with_win; window_on <- TRUE; dist_opt <- dist_win }
  }
  data.frame(case = label, hp_factor = f, hp_mean = mean(s$hp_real), strike19 = mean(s$hp_real) * K / 29.5, strike21 = mean(s$hp_real) * K / 13.5,
             mean_price = mean(s$price), hours = hours, revenue_stock = rev0, never_total = never, optimal_total = flex,
             flex_value = flex - never, flex_pct_profit = 100 * (flex - never) / never, flex_pct_revenue = 100 * (flex - never) / rev0,
             flex_per_mwh = (flex - never) / (CAP_MW * hours), flex_nowin_value = flex_nowin - never,
             flex_nowin_per_mwh = (flex_nowin - never) / (CAP_MW * hours),
             pause19 = 100 * mean(mw19 == 0), pause21 = 100 * mean(mw21 == 0),
             mean_mw = mean(mw), hash_share = mean(th) / th_stock, window_on = window_on,
             dist_never = dist_never, dist_optimal = dist_opt, stringsAsFactors = FALSE)
}
s25 <- rt[rt$year == 2025, ]; o25 <- off[off$year == 2025, ]; ch9_check_calendar(s25, 2025)
out <- do.call(rbind, lapply(c(1, 0.75, 0.5, 0.35, 0.25), function(f) evaluate(s25, o25, f, sprintf("2025 at %.0f%% hashprice", 100 * f))))
s26 <- rt[rt$year == 2026, ]; ch9_check_calendar(s26, 2026, last = max(s26$date))
out <- rbind(out, evaluate(s26, off[off$year == 2026, ], 1, sprintf("2026 actual, %s to %s", min(s26$date), max(s26$date))))
write.csv(out, "analysis/data/ch10_hashprice_sensitivity.csv", row.names = FALSE)
cat(sprintf("%-32s %8s %7s %7s %10s %10s %10s %8s %8s %7s %7s %7s %6s\n", "case", "hp", "V19", "V21", "never $M", "optimal $M", "flex $M", "%margin", "%revenue", "$/MWh", "off19%", "off21%", "win"))
for (k in seq_len(nrow(out))) with(out[k, ], cat(sprintf("%-32s %8.4f %7.0f %7.0f %10.2f %10.2f %10.2f %8.1f %8.1f %7.2f %7.1f %7.1f %6s\n",
  case, hp_mean, strike19, strike21, never_total / 1e6, optimal_total / 1e6, flex_value / 1e6, flex_pct_profit, flex_pct_revenue, flex_per_mwh, pause19, pause21, window_on)))
# The 2026 row's dollar columns cover the months to date, not a year (EXEC-037).
# The table caption scales them to a year for scale only, linearly and with no
# seasonal adjustment (the months hold Fern and the summer but no autumn); the
# TCRF charge is already pro rata in evaluate(), so scaling does not count it twice.
cat(sprintf("distribution (Oncor, the site meter's highest quarter-hour each month, analysis/checks/oncor_distribution.R): never pausing $%s; optimal stack %s ($M by row); lowest monthly peak of any path %.2f MW against the ratchet's 80%% of the %.2f MW connection, %.2f MW; the ratchet binds in %d months\n",
            format(round(out$dist_never[1]), big.mark = ","), paste(sprintf("%.4f", out$dist_optimal / 1e6), collapse = " / "),
            DIST_CHECK$min_ncp, CAP_MW, OD_RATCHET * CAP_MW, DIST_CHECK$binds))
r26 <- tail(out, 1); f26 <- 8760 / r26$hours
cat(sprintf("2026 pro rata to a year (x 8,760 / %.0f h = %.3f; the months hold Fern and the summer, no autumn): never %.2f, optimal %.2f, flexibility %.2f $M\n",
            r26$hours, f26, r26$never_total * f26 / 1e6, r26$optimal_total * f26 / 1e6, r26$flex_value * f26 / 1e6))
cat(sprintf("\nprice-only (no summer window) flexibility, $ per MWh of capacity: 2025 %.2f vs 2026 ytd %.2f; 2025 window added %.2f $M\n",
            out$flex_nowin_per_mwh[1], tail(out$flex_nowin_per_mwh, 1), (out$flex_value[1] - out$flex_nowin_value[1]) / 1e6))
cat(sprintf("crossovers: the S21 XP inherits the S19j Pro's 2025 strike at %.0f%% of the 2025 hashprice (%.2f / %.2f); the S19j Pro's strike falls below the mean price at %.0f%% (%.2f / %.2f)\n",
            100 * out$strike19[1] / out$strike21[1], out$strike19[1], out$strike21[1], 100 * out$mean_price[1] / out$strike19[1], out$mean_price[1], out$strike19[1]))
# The ledger is a margin after power and grid charges, not a profit (EXEC-020):
# the machines, their depreciation, pool and firmware fees, site operation,
# staff and debt are not in it. The never-pausing margin is linear in hashprice
# (revenue scales, the power and grid charges do not), so it reaches zero at
# 1 - never / revenue of the 100% row, and every $100,000 per MW-yr of costs
# the ledger leaves out moves that zero up by 100,000 x CAP_MW / revenue.
stopifnot(abs(out$hp_factor[1] - 1) < 1e-9)
chk <- out[out$hp_factor < 1 & grepl("^2025", out$case), ]
stopifnot(all(abs(chk$never_total - (chk$hp_factor * out$revenue_stock[1] - (out$revenue_stock[1] - out$never_total[1]))) < 1))
cat(sprintf("margin crossover: the never-pausing site's margin after power and grid charges reaches zero at %.1f%% of the 2025 hashprice (1 - %s / %s); every $100,000 per MW-yr of costs outside the ledger raises that line by %.1f points (100,000 x %.2f MW / %s)\n",
            100 * (1 - out$never_total[1] / out$revenue_stock[1]), format(round(out$never_total[1]), big.mark = ","), format(round(out$revenue_stock[1]), big.mark = ","),
            100 * 1e5 * CAP_MW / out$revenue_stock[1], CAP_MW, format(round(out$revenue_stock[1]), big.mark = ",")))
cat(sprintf("mean draw under the optimal stack: %s MW\n", paste(sprintf("%.1f", out$mean_mw), collapse = " / ")))
# the grid sized against the security budget: flexibility per MW-yr x ERCOT's peak mining demand
# Mining demand specifically, from the market monitor, NOT ERCOT's large-load
# program total. The two are different measurements and neither contains the
# other: a mine under 75 MW can be in this figure but not in the program (the
# monitor does not say how it counts), and an AI
# campus over 75 MW is in the program but not here. Both sentences downstream
# are about mining, so this is the right input. Was 5,768 MW, the program total
# (ercot2026llistatus), until 2026-09-20. The monitor gives 4,600 MW as the
# 2025 PEAK of aggregate crypto demand (pp. i, 14, 31), a capacity-like basis:
# it pairs with the per-MW-yr flexibility value (flex value / 67.13 MW of site
# capacity), and the Texas shares below are shares at full output.
ERCOT_MINING_MW <- 4600   # chapter 7: 2025 peak of aggregate crypto demand (potomac2026somercot pp. i, 31)
cat(sprintf("grid sizing: flexibility $%s per MW-yr at 2025 hashprice, $%s at 25%%; x %s MW of ERCOT mining = $%.2f bn and $%.2f bn a year\n",
            format(round(out$flex_value[1] / CAP_MW), big.mark = ","), format(round(out$flex_value[5] / CAP_MW), big.mark = ","),
            format(ERCOT_MINING_MW, big.mark = ","), out$flex_value[1] / CAP_MW * ERCOT_MINING_MW / 1e9, out$flex_value[5] / CAP_MW * ERCOT_MINING_MW / 1e9))
# synchronized curtailment: what one grid's flexible fleet does to the network's hashrate and block interval.
# Megawatts become hashes only through an efficiency, and the one that matters
# here is TEXAS's, not the network's average (DATA-017, 2026-09-26; until then
# this line divided by chapter 1's 24.2 GW, i.e. assumed Texas ran at the
# network's old 26 J/TH). Texas share of hashrate = 4,600 MW / PUE / J_TX / 930 EH/s.
# TX_JTH is an ASSUMPTION proposed in DATA-017 (2026-09-26), pending the
# author's confirmation; it is not a measurement and not yet the author's
# reading. Its efficient end is the listed fleets' hashrate-weighted 17 J/TH
# (analysis/checks/ch1_fleet_efficiency.R), which is NOT a Texas figure; its
# other end is the author's 21.5 J/TH for the whole network (chapter 1). The
# only fleets the repository places in Texas are Riot (Rockdale, Corsicana, and
# also Kentucky) and Cipher's Odessa site (analysis/data/listed_miner_fleets_2026.csv,
# both on Q1 2026 J/TH flagged stale); weighted by hashrate they average about
# 19.6 J/TH, above the efficient end. The line after the loop prints that case
# for the author's decision. The 4,600 MW is metered site demand, so PUE
# converts it to the machines' own draw: CBECI's best-guess 1.10.
# The site's own deficit is then taken in HASHES (hash_share), not energy,
# because the power target sheds energy faster than hashes.
NET_EHS <- 930                                               # chapter 1's printed anchor
LF <- read.csv("analysis/data/listed_miner_fleets_2026.csv", stringsAsFactors = FALSE)
TXF <- LF[LF$ticker %in% c("RIOT", "CIFR"), ]                # the fleets the repository places in Texas
stopifnot(nrow(TXF) == 2, !anyNA(TXF$jth))
TX_DISCLOSED <- sum(TXF$hashrate_ehs * TXF$jth) / sum(TXF$hashrate_ehs)
TX_JTH  <- c(efficient = 17, disclosed = TX_DISCLOSED, author = 21.5)   # assumed range for Texas's fleet, at the machines (the middle value is not printed as an end)
PUE     <- 1.10                                              # CBECI methodology, Assumption 8 (best guess)
tx_ehs  <- ERCOT_MINING_MW / PUE / TX_JTH                    # MW / (J/TH) = EH/s
ERCOT_SHARE <- tx_ehs / NET_EHS
off_energy <- 1 - out$mean_mw / CAP_MW                       # share of the site's energy not consumed under the optimal stack
off_hash <- 1 - out$hash_share                               # share of the site's stock hashrate not delivered
cat(sprintf("Texas fleets in the repository: %s, %.1f EH/s, hashrate-weighted %.2f J/TH (the middle line below; the chapter's range is the first and last)\n",
            paste(sprintf("%s %.1f EH/s at %.1f", TXF$ticker, TXF$hashrate_ehs, TXF$jth), collapse = " and "), sum(TXF$hashrate_ehs), TX_DISCLOSED))
for (k in seq_along(TX_JTH))
  cat(sprintf("synchronized curtailment, Texas fleet at %.1f J/TH and PUE %.2f: ERCOT's peak mining demand hashes at %.0f EH/s, %.1f%% of the network's %d EH/s; if every Texas mine paused at once, blocks would stretch to %.1f minutes until the retarget; if the whole Texas fleet ran the 25%%-hashprice dispatch (site energy off %.0f%%, hashrate off %.1f%%), the network's average hashrate would sit %.1f%% below the same machines always on (%.1f%% on energy, the old basis); at 2025 hashprice (energy off %.0f%%, hashrate off %.0f%%) %.1f%%\n",
              TX_JTH[k], PUE, tx_ehs[k], 100 * ERCOT_SHARE[k], NET_EHS, 10 / (1 - ERCOT_SHARE[k]), 100 * off_energy[5], 100 * off_hash[5],
              100 * ERCOT_SHARE[k] * off_hash[5], 100 * ERCOT_SHARE[k] * off_energy[5], 100 * off_energy[1], 100 * off_hash[1], 100 * ERCOT_SHARE[k] * off_hash[1]))
# for contrast only: the share of the network's POWER, which does depend on the
# network's average (chapter 1's range 18 to 26 J/TH, at the same PUE)
net_mw <- NET_EHS * c(18, 21.5, 26) * PUE
cat(sprintf("for contrast, ERCOT's 4,600 MW against the network's meter draw on chapter 1's range (18 / 21.5 / 26 J/TH): %s MW, %s of it\n",
            paste(format(round(net_mw), big.mark = ","), collapse = " / "), paste(sprintf("%.1f%%", 100 * ERCOT_MINING_MW / net_mw), collapse = " / ")))
cat("\nwrote analysis/data/ch10_hashprice_sensitivity.csv\n")

# ---- context for the 2026 row: reserve prices in the first months under RTC+B ----
as <- read.csv("analysis/data/ercot_dam_as_mcpc.csv.gz"); as$year <- as.integer(substr(as$deliveryDate, 1, 4))
cat("\n=== 2026 reserve prices (day-ahead clearing, $/MW-h) and standing revenue annualised ===\n")
for (y in 2024:2026) {
  a <- as[as$year == y, ]; hrs <- nrow(a)
  cat(sprintf("%d (%s to %s, %d h): RRS $%.2f, ECRS $%.2f, NonSpin $%.2f per MW-h; standing revenue per MW-yr at these means: RRS $%s, ECRS $%s, NonSpin $%s\n",
              y, min(a$deliveryDate), max(a$deliveryDate), hrs, mean(a$rrs, na.rm = TRUE), mean(a$ecrs, na.rm = TRUE), mean(a$nspin, na.rm = TRUE),
              format(round(mean(a$rrs, na.rm = TRUE) * 8760), big.mark = ","), format(round(mean(a$ecrs, na.rm = TRUE) * 8760), big.mark = ","),
              format(round(mean(a$nspin, na.rm = TRUE) * 8760), big.mark = ",")))
}
