# ch1_fleet_efficiency.R -- Chapter 1: what can be said about the network's
# fleet-average efficiency, the one input to its power that nobody measures.
# Run from the repo root:
#   Rscript analysis/checks/ch1_fleet_efficiency.R
#
# Difficulty fixes the hashrate; nothing in the protocol records watts. So
# every published estimate of the network's power rests on an assumption: most
# often an efficiency someone modelled, otherwise the share of revenue spent on
# power or a small measured sample taken to stand for the network (CCAF2025
# p. 60 lists the four approaches), and dividing such an estimate by the
# hashrate only returns that assumption. This script does not produce the network's
# efficiency. It prints what chapter 1 sets beside its range, 18 to 26 J/TH at
# the machines (the author's judgment, with the author's own estimate, 21.5
# J/TH, inside it; ch1_network_energy.R turns both into power and energy):
#   1. the published part: the listed fleets that report a J/TH (self-reported,
#      often from machine ratings, not metered), hashrate-weighted, and the
#      J/TH the rest of the network, which publishes no efficiency, would need
#      for each network average (a consistency check, not a measurement: the
#      rest is the one unknown, and the band's ends are judged, not derived);
#   2. the band in GW, TWh and share of 2025 generation, at the machines and
#      at the site meter;
#   3. economics: the share of the network's revenue each average would spend
#      on power, ON THE METER BASIS (machine J/TH x PUE: a power bill is read
#      at the site meter, not at the machine), at several power prices, and
#      the listed miners' own share, period-matched to the same revenue;
#   4. Cambridge's CBECI, as figures quoted from its website with their date.
#
# NOT HERE: a vintage route (the June 2024 fleet plus what was added since).
# It rests on Cambridge's hashrate-weighted survey figure, which the report
# says leans toward the larger, more efficient firms, and on retirements
# nobody observes, so it can only cap the network's average from above; it
# cannot place a point inside the range, and the chapter does not use it.
#
# BASES. The book's J/TH is the machine's own draw at the wall (Bitmain's
# rating "on wall"; analysis/data/bitmain_flagship_efficiency.csv). A site
# draws more at its meter: fans, cooling, transformers. That ratio is the PUE;
# this script uses CBECI's best-guess 1.10 and its lower bound 1.01.
#
# LICENCES. CBECI and the CCAF report are licensed CC BY-NC-SA 4.0 by the
# Cambridge Centre for Alternative Finance. This script holds only a handful of
# their published figures, quoted with attribution below; no CCAF data file is
# committed, fetched or read.
#
# Inputs (all committed):
#   analysis/data/network_hashrate_daily.csv, btc_price_daily.csv (Braiins
#       Insights), bitcoin_security_budget_daily.csv (blockchain.info fee share)
#   analysis/data/listed_miner_fleets_2026.csv: company filings and releases,
#       one row per fleet, each with its document, URL and a verbatim quote
#   analysis/data/listed_miner_power_share_2026.csv: CoinShares' Q2 2026
#       electricity and revenue per BTC for six listed miners (secondary), with
#       Riot's and MARA's rows checked against their own documents
#   analysis/data/bitmain_flagship_efficiency.csv: reference machines
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))
options(encoding = "UTF-8")

HASH_PRINTED <- 930          # chapter 1's printed anchor, EH/s
GEN_2025_TWH <- 32202        # Energy Institute, Statistical Review 2026 (EIStatReview2026)
BAND   <- c(low = 18, author = 21.5, high = 26)   # chapter 1: range and the author's estimate
WALLS  <- c(floor = 17, ceiling = 30)             # outside the range, printed for context
PUE    <- c(lower = 1.01, best = 1.10)            # CBECI methodology, Assumptions 4 and 8
PRICES <- c(35, 38.5, 42.18, 45, 50, 55)          # $/MWh; 42.18 is the book's anchor
fmt <- function(x, d = 0) formatC(x, format = "f", digits = d, big.mark = ",")

# ---- 0. anchors: 7 days to 2026-08-21, as ch1_network_energy.R ----------------
hr <- read.csv("analysis/data/network_hashrate_daily.csv", stringsAsFactors = FALSE)
px <- read.csv("analysis/data/btc_price_daily.csv", stringsAsFactors = FALSE)
sb <- read.csv("analysis/data/bitcoin_security_budget_daily.csv", stringsAsFactors = FALSE)
between <- function(df, a, b) df[as.Date(df$date) >= as.Date(a) & as.Date(df$date) <= as.Date(b), ]
H   <- mean(between(hr, "2026-08-15", "2026-08-21")$ehs)
BTC <- mean(between(px, "2026-08-15", "2026-08-21")$usd)
stopifnot(nrow(between(hr, "2026-08-15", "2026-08-21")) == 7, nrow(between(px, "2026-08-15", "2026-08-21")) == 7)
# the fee cache lacks 2026-08-17 to 23, so the anchor week takes August's mean fee share
fee_aug <- mean(between(sb, "2026-08-01", "2026-08-31")$fee_share)
HP_SUB  <- 450 * BTC / (H * 1e6)          # $/TH-day, block subsidy only (chapter 1's $0.032)
HP_FEE  <- HP_SUB / (1 - fee_aug)          # with August's fee share: the revenue a power bill is paid from
cat(sprintf("anchor, 7 days to 2026-08-21: %.1f EH/s (printed %d), bitcoin $%s; hashprice $%.5f per TH-day on the subsidy alone, $%.5f with August's fee share of %.2f%%\n\n",
            H, HASH_PRINTED, fmt(BTC), HP_SUB, HP_FEE, 100 * fee_aug))

# ---- 1. the listed fleets that publish a J/TH ---------------------------------
L <- read.csv("analysis/data/listed_miner_fleets_2026.csv", stringsAsFactors = FALSE)
W <- L[L$in_weighted == 1, ]
stopifnot(nrow(W) == 12, !anyNA(W$hashrate_ehs), !anyNA(W$jth), all(nzchar(W$quote_hashrate)))
wavg <- function(ehs, jth) c(ehs = sum(ehs), jth = sum(ehs * jth) / sum(ehs))
A  <- wavg(W$hashrate_ehs, W$jth)
op <- ifelse(is.na(W$operating_ehs), W$hashrate_ehs, W$operating_ehs)
B  <- wavg(op, W$jth)
fresh <- W$jth_stale == "FALSE"
C  <- wavg(W$hashrate_ehs[fresh], W$jth[fresh])
j2 <- W$jth; j2[W$ticker == "WULF"] <- 17.6; j2[W$ticker == "IREN"] <- 380 / 23.2   # the same documents' other figures
D  <- wavg(W$hashrate_ehs, j2)
X  <- L[L$ticker %in% c("CANG", "CORZ"), ]
E  <- wavg(c(W$hashrate_ehs, X$hashrate_ehs), c(W$jth, ifelse(X$ticker == "CORZ", 24.7, 29.5)))
cat("=== 1. Listed fleets that publish a fleet efficiency (analysis/data/listed_miner_fleets_2026.csv) ===\n")
cat(sprintf("%d fleets of %d companies, filings and releases dated %s to %s; hashrate dates %s to %s\n",
            nrow(W), length(unique(W$ticker)), min(W$published_hashrate), max(W$published_hashrate), min(W$hashrate_date), max(W$hashrate_date)))
cat(sprintf("  headline hashrate (each company's own capacity figure): %.1f EH/s, %.1f%% of the anchor's %.1f EH/s; hashrate-weighted %.2f J/TH; %.2f GW at the machines\n",
            A[["ehs"]], 100 * A[["ehs"]] / H, H, A[["jth"]], A[["ehs"]] * A[["jth"]] / 1e3))
cat(sprintf("  operating hashrate where it is published and lower (%s): %.1f EH/s (%.1f%%), %.2f J/TH\n",
            paste(W$ticker[!is.na(W$operating_ehs) & W$operating_ehs < W$hashrate_ehs], collapse = ", "), B[["ehs"]], 100 * B[["ehs"]] / H, B[["jth"]]))
cat(sprintf("  J/TH dated June 2026 or later only (drops Riot, HIVE, IREN, Cipher): %.1f EH/s (%.1f%%), %.2f J/TH\n", C[["ehs"]], 100 * C[["ehs"]] / H, C[["jth"]]))
cat(sprintf("  TeraWulf at its whole-fleet 17.6 and IREN at 380 MW / 23.2 EH/s = %.1f: %.2f J/TH\n", 380 / 23.2, D[["jth"]]))
cat(sprintf("  adding the two that publish none, Cango at the S19 Pro's 29.5 (assumed) and Core Scientific at CoinShares' ~24.7 (secondary): %.1f EH/s (%.1f%%), %.2f J/TH\n",
            E[["ehs"]], 100 * E[["ehs"]] / H, E[["jth"]]))
stopifnot(A[["jth"]] > 15, A[["jth"]] < 19)
ref <- read.csv("analysis/data/bitmain_flagship_efficiency.csv", stringsAsFactors = FALSE)
refj <- setNames(ref$efficiency_j_th, sub("Antminer ", "", ref$model))
cat("  the rest of the network, the part that publishes no efficiency: J/TH it must average for each network average\n")
shares <- c(A[["ehs"]] / H, 0.35, 0.30)
cat(sprintf("  %-26s %s\n", "network average", paste(sprintf("listed %4.1f%%", 100 * shares), collapse = "  ")))
rest <- function(n, s) (n - s * A[["jth"]]) / (1 - s)
for (n in c(WALLS[["floor"]], BAND, WALLS[["ceiling"]]))
  cat(sprintf("  %-26s %s\n", sprintf("%g J/TH", n), paste(sprintf("rest %5.1f  ", sapply(shares, function(s) rest(n, s))), collapse = "  ")))
cat(sprintf("  reference machines, rated at the wall: S21 %.1f, S19 XP %.1f, S19 Pro %.1f J/TH (the S19j Pro is also 29.5)\n",
            refj[["S21"]], refj[["S19 XP"]], refj[["S19 Pro"]]))
cat("  (nameplate share first: capacity figures include machines not always hashing, so the listed share of hashes delivered is lower; 35 and 30 percent show how far that moves the rest)\n")
stopifnot(rest(BAND[["low"]], shares[1]) < refj[["S19 XP"]], rest(BAND[["high"]], shares[1]) > refj[["S19 Pro"]])

# ---- 2. the band at the printed hashrate --------------------------------------
cat("\n=== 2. The band at 930 EH/s ===\n")
cat(sprintf("%8s %9s %10s %10s | %12s %14s %12s\n", "J/TH", "GW", "TWh/year", "of 2025 gen", "GW at meter", "TWh at meter", "of gen, meter"))
for (n in c(WALLS[["floor"]], BAND, WALLS[["ceiling"]])) {
  gw <- HASH_PRINTED * n / 1e3; twh <- gw * 8.76; twh_m <- twh * PUE[["best"]]
  cat(sprintf("%8g %9.2f %10.1f %9.2f%% | %12.1f %14.1f %11.2f%%   %s\n", n, gw, twh, 100 * twh / GEN_2025_TWH, gw * PUE[["best"]], twh_m, 100 * twh_m / GEN_2025_TWH,
              c("floor: the whole network as efficient as the listed fleets", "low end of the range", "the author's estimate",
                "high end of the range", "ceiling: beyond the $45 all-revenue ceiling at any PUE")[match(n, c(17, 18, 21.5, 26, 30))]))
}

# ---- 3. economics, on the meter basis ------------------------------------------
share <- function(n, P, pue) n * pue * 24 * P / (HP_FEE * 1e6)        # power bill / revenue
cat(sprintf("\n=== 3. Share of August 2026 revenue spent on power (hashprice $%.5f with fees), at the meter ===\n", HP_FEE))
for (pu in PUE) {
  cat(sprintf("PUE %.2f %s\n", pu, if (pu == PUE[["best"]]) "(CBECI best guess)" else "(CBECI lower bound: almost no overhead)"))
  cat(sprintf("  %8s %s\n", "J/TH", paste(sprintf("%8s", paste0("$", PRICES)), collapse = "")))
  for (n in c(WALLS[["floor"]], BAND, WALLS[["ceiling"]]))
    cat(sprintf("  %8g %s\n", n, paste(sprintf("%7.0f%%", 100 * share(n, PRICES, pu)), collapse = "")))
  cat(sprintf("  ceiling, every dollar on power: %s J/TH at the machines\n",
              paste(sprintf("$%g %.1f", PRICES, HP_FEE * 1e6 / (24 * PRICES * pu)), collapse = ", ")))
}
cat(sprintf("the machine-level breakeven of chapter 1 (subsidy only, no overhead): 18 / 21.5 / 26 J/TH stay under it for power up to $%.1f / $%.1f / $%.1f per MWh\n",
            HP_SUB * 1e6 / (24 * 18), HP_SUB * 1e6 / (24 * 21.5), HP_SUB * 1e6 / (24 * 26)))
# the listed miners' own share, and the same bills against August's revenue
S <- read.csv("analysis/data/listed_miner_power_share_2026.csv", stringsAsFactors = FALSE)
stopifnot(nrow(S) == 6)
s_q2 <- sum(S$btc_mined * S$electricity_usd_per_btc) / sum(S$btc_mined * S$realised_usd_per_btc)
q2 <- function(df) between(df, "2026-04-01", "2026-06-30")
stopifnot(nrow(q2(hr)) == 91, nrow(q2(px)) == 91, nrow(q2(sb)) == 91)
HP_Q2 <- 450 * mean(q2(px)$usd) / (mean(q2(hr)$ehs) * 1e6) / (1 - mean(q2(sb)$fee_share))
riot <- S[S$ticker == "RIOT", ]; riot_gross <- (73499e3 / riot$btc_mined) / riot$realised_usd_per_btc   # Riot Q2 release: power $73,499k before credits
cat(sprintf("listed miners, Q2 2026 (six fleets, %s BTC; CoinShares, secondary): electricity net of credits %.1f%% of realised revenue (BTC-weighted); Riot %.1f%% net, %.1f%% gross of credits; MARA's row includes hosting fees\n",
            fmt(sum(S$btc_mined)), 100 * s_q2, 100 * riot$electricity_usd_per_btc / riot$realised_usd_per_btc, 100 * riot_gross))
cat(sprintf("  period-matched: network hashprice Q2 2026 $%.5f vs the anchor's $%.5f (same basis: 450 BTC x mean price / mean hashrate / (1 - mean fee share)), so the same bills take %.1f%% of August's revenue (Riot gross %.1f%%)\n",
            HP_Q2, HP_FEE, 100 * s_q2 * HP_Q2 / HP_FEE, 100 * riot_gross * HP_Q2 / HP_FEE))
# cross-check on a second basis: Braiins' own hashprice series for both windows
bh <- read.csv("analysis/data/hashprice_daily.csv", stringsAsFactors = FALSE)
r_braiins <- mean(q2(bh)$usd_th_day) / mean(between(bh, "2026-08-15", "2026-08-21")$usd_th_day)
cat(sprintf("  on Braiins' hashprice series (analysis/data/hashprice_daily.csv) the Q2-to-anchor ratio is %.3f, not %.3f: %.1f%% of August's revenue. Either way about three-fifths\n",
            r_braiins, HP_Q2 / HP_FEE, 100 * s_q2 * r_braiins))
stopifnot(abs(s_q2 * HP_Q2 / HP_FEE - 0.6) < 0.03, abs(s_q2 * r_braiins - 0.6) < 0.03)
cat(sprintf("  for comparison, the listed fleets' own %.2f J/TH at PUE 1.10 and $%.2f would spend %.1f%%\n", A[["jth"]], 42.18, 100 * share(A[["jth"]], 42.18, 1.10)))

# ---- 4. CBECI, quoted ------------------------------------------------------------
# Cambridge Bitcoin Electricity Consumption Index, model v1.8.0 (09 July 2026),
# default 0.05 USD/kWh, values for 2026-09-25 as served to the index page
# https://ccaf.io/cbnsi/cbeci on 2026-09-26 (from its own endpoints
# /cbeci/api/data/stats/0.05 and /cbeci/api/charts/energy_efficiency_of_mining_hardware/actual/0.05).
# (c) Cambridge Centre for Alternative Finance, CC BY-NC-SA 4.0. Quoted, not redistributed.
CB_GW  <- c(lower = 8.78, guess = 17.12, upper = 32.93)     # power, GW (PUE included)
CB_ETA <- c(lower = 9.50, guess = 17.013, upper = 30.00)    # hardware efficiency, J/TH (no PUE)
CB_PUE <- c(lower = 1.01, guess = 1.10, upper = 1.20)       # methodology, Assumptions 4, 8 and 6
# Cambridge Digital Mining Industry Report (CCAF, April 2025), p. 59, Figure 26(b):
# surveys against CBECI's hardware efficiency, J/TH. Same licence.
SURVEY <- c(`2022-06` = 40.6, `2023-06` = 36.9, `2024-06` = 28.2)   # Bitcoin Mining Council 2022-23; CCAF survey 2024
MODEL  <- c(`2022-06` = 41.8, `2023-06` = 34.5, `2024-06` = 25.3)   # CBECI
CB_DEC24 <- 23.7                                                    # p. 63: CBECI hardware efficiency, end of December 2024
cb_h <- CB_GW * 1e3 / (CB_ETA * CB_PUE)
stopifnot(max(cb_h) / min(cb_h) < 1.005)
gap <- SURVEY / MODEL
cat("\n=== 4. Cambridge's CBECI, quoted (values for 2026-09-25, read 2026-09-26) ===\n")
cat(sprintf("power %.2f / %.2f / %.2f GW (lower / best guess / upper); hardware %.2f / %.2f / %.2f J/TH; PUE %.2f / %.2f / %.2f; implied hashrate %.1f EH/s\n",
            CB_GW[1], CB_GW[2], CB_GW[3], CB_ETA[1], CB_ETA[2], CB_ETA[3], CB_PUE[1], CB_PUE[2], CB_PUE[3], mean(cb_h)))
cat(sprintf("best guess at 930 EH/s: %.1f GW at the machines, %.1f GW with PUE 1.10\n", HASH_PRINTED * CB_ETA[["guess"]] / 1e3, HASH_PRINTED * CB_ETA[["guess"]] * 1.10 / 1e3))
cat(sprintf("survey against model: %s; CBECI's best guess scaled by those ratios: %.1f to %.1f J/TH\n",
            paste(sprintf("%s %.1f vs %.1f (x%.3f)", names(gap), SURVEY, MODEL, gap), collapse = "; "),
            min(gap) * CB_ETA[["guess"]], max(gap) * CB_ETA[["guess"]]))
cat(sprintf("CBECI's hardware efficiency on the book's basis: %.1f J/TH on 2024-06-30, %.1f at end-2024, %.2f on 2026-09-25; the book's old 26 J/TH is above all three\n",
            MODEL[["2024-06"]], CB_DEC24, CB_ETA[["guess"]]))
stopifnot(26 > MODEL[["2024-06"]], BAND[["low"]] > min(gap) * CB_ETA[["guess"]])
