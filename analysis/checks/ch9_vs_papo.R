# ch9_vs_papo.R -- cross-check the chapter 9 engine against the Braiins fleet
# calculator's Price Adapt optimiser. Run from the repo root:
#   Rscript analysis/checks/ch9_vs_papo.R
#
# The two answer the same question -- what is the profit-maximising power level
# for each machine, given a hashprice and an electricity price, subject to the
# site's connection -- so on identical inputs they should agree closely. They
# are not identical implementations, and the differences are deliberate:
#   * Both interpolate J/TH between measured points on a 100 W grid (this
#     engine's ch9_curve mirrors the calculator's; an earlier version optimised
#     over the measured points alone, 13 and 10 of them, and was a lower bound).
#   * Price Adapt allocates a binding connection by greedy marginal steps along
#     the concave envelope of each grid; this engine evaluates every feasible
#     pair of grid points (ch9_tune_site, 375 combinations, 500 on the S21
#     XP's earlier 2,200 W floor; it once raised a shadow price until the site
#     fitted). For concave grids the two find the same optimum.
#   * The chapter's headline controller decides on LAGGED information (last
#     published price, previous day's hashprice); Price Adapt is given the
#     current price. Both variants are reported here so the comparison isolates
#     the optimiser from the controller.
# Reference: PAPO's own numbers are produced by a separate harness, not in this
# repository (papo_year.js), reading assets/js/papo.js and assets/data/miners.json.
#
# THERE ARE TWO PAPO IMPLEMENTATIONS AND THEY DISAGREE WITH EACH OTHER.
#   papo.js   the shipping fleet calculator. Interpolates J/TH between MEASURED
#             telemetry points on a 100 W grid. This engine matches it: total
#             2025 profit agrees to 0.08%.
#   papo_sim.py  the chapter 5 backtest. Originally a LINEAR model
#             J(p) = a + b*p fitted through two anchors, with its own constants:
#               S19j Pro  p_min 1630 W, j_best 23.81, j_def 28.53, p_max 3420
#               S21 XP    p_min 2760 W, j_best 10.93, j_def 12.82, p_max 3990
#             which reproduce the PAPO report's published breakevens (78/65 and
#             169/144 $/MWh at $44.31/PH/day). SINCE 2026-08-27 papo_sim.py runs
#             the measured 2026-Q2 telemetry instead (telemetry_miner.py), and
#             since 2026-09-26 its modulation floor is Braiins OS's default
#             minimum power target, or the best-efficiency point where that is
#             higher: 1,200 W and 2,774 W, as chapter 5 prints (2,200 W for the
#             S21 XP, its best point, from 2026-09 to 2026-09-26).
#             The linear constants above now apply only under PAPO_PARAMETRIC=1;
#             the comparison below uses them to show what the old curve did.
# On the S19j Pro the two agree closely. On the S21 XP they do not: extrapolated
# to the 3,990 W ceiling the linear model says 13.56 J/TH while the telemetry
# measures 12.94, which is 4.8% more hashrate at the very power level the
# efficient machine occupies almost all the time. Driving THIS engine with
# papo_sim's constants reproduces papo_sim's answer (+3.75% against its +3.77%
# for the S21 XP in 2025), which shows the difference is the curve and not the
# algorithm. Chapter 9 stays on the measured telemetry, because that is what
# chapter 5's prose describes, what the shipping calculator uses, and what the
# repo commits.
# ONE ENVELOPE DIFFERENCE since 2026-09-26: this engine floors the S21 XP at
# Braiins OS's default minimum power target, 2,774 W (ch9_tuning.R ch9_floor);
# papo.js floors it at the telemetry's best-efficiency point, 2,200 W. The
# S19j Pro's floor, 1,200 W, is the same in both. Price Adapt's figures below
# were produced with the 2,200 W floor and are not re-run here.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
source("analysis/checks/ch9_tuning.R")

K <- 41666.7; H <- 0.25
FLEET <- data.frame(machine = c("S19j Pro", "S21 XP"), units = c(10000, 10000),
                    watts = c(3068, 3645), jth = c(29.5, 13.5), stringsAsFactors = FALSE)
FLEET$mw <- FLEET$units * FLEET$watts / 1e6
CV <- list("S19j Pro" = ch9_curve("S19j Pro"), "S21 XP" = ch9_curve("S21 XP"))
CAP <- sum(FLEET$mw)

hp <- read.csv("analysis/data/hashprice_daily_2021on.csv"); hp$date <- as.character(hp$date)
hp <- hp[order(hp$date), ]; hp$known <- c(NA, head(hp$usd_th_day_spliced, -1))
z <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
z <- z[z$settlement_point == "LZ_WEST", ]; z <- z[order(z$interval_start), ]
z$date <- substr(z$interval_start, 1, 10)
z$year <- as.integer(substr(z$interval_start, 1, 4))
z$p_lag <- c(NA, head(z$price, -1))
i <- match(z$date, hp$date); z$hp <- hp$usd_th_day_spliced[i]; z$hp_known <- hp$known[i]
s <- z[z$year == 2025 & !is.na(z$hp) & !is.na(z$p_lag) & !is.na(z$hp_known), ]

cat(sprintf("2025 LZ_WEST: %d intervals, mean price $%.2f, mean hashprice $%.5f\n\n",
            nrow(s), mean(s$price), mean(s$hp)))
cat("operating envelope, the fleet calculator's rule except the S21 XP's floor\n")
cat("(Braiins OS's default minimum, 2,774 W, against the calculator's 2,200 W):\n")
for (n in names(CV)) cat(sprintf("  %-9s floor %d W, ceiling %d W, %d measured operating points (stock %d)\n",
    n, CV[[n]]$p_floor, CV[[n]]$p_max, length(CV[[n]]$p), FLEET$watts[FLEET$machine == n]))

# stock-power baseline that never pauses -- the same baseline Price Adapt uses
baseline <- sum(sapply(seq_len(nrow(FLEET)), function(m) {
  cv <- CV[[FLEET$machine[m]]]; k <- which.min(abs(cv$p - FLEET$watts[m]))
  sum(s$hp * cv$h[k] / 96 - s$price * cv$p[k] / 1e6 * H) * FLEET$units[m]
}))

run <- function(dec_price, dec_hp, label) {
  st <- ch9_tune_site(CV[["S19j Pro"]], CV[["S21 XP"]], FLEET$units[1], FLEET$units[2],
                      FLEET$watts[1], FLEET$watts[2], dec_hp, dec_price, s$hp, s$price, CAP)
  gain <- st$gain19 + st$gain21
  cat(sprintf("  %-34s %14s   uplift %5.1f%%   mean site draw %.1f MW\n",
              label, format(round(baseline + gain), big.mark = ","),
              100 * gain / baseline, st$mean_site_mw))
  invisible(gain)
}

cat(sprintf("\nstock-power baseline, never pauses: $%s\n\n", format(round(baseline), big.mark = ",")))
cat("this engine, strike and tuning together, 67.13 MW connection:\n")
g_now <- run(s$price, s$hp,          "same-interval information")
g_lag <- run(s$p_lag, s$hp_known,    "lagged, the chapter's headline")

cat(sprintf("\n  gain with same-interval information : $%s\n", format(round(g_now), big.mark = ",")))
cat(sprintf("  gain with lagged information        : $%s (%.0f%% of the above)\n",
            format(round(g_lag), big.mark = ","), 100 * g_lag / g_now))
cat("\nPrice Adapt on the same inputs (assets/js/papo.js, same fleet, same cap,\n")
cat("same 2025 series, same-interval information): profit $52,536,117 on a\n")
cat("baseline of $47,533,842, a gain of $5,002,276 and an uplift of 10.5%.\n")
cat(sprintf("\nAgreement on the comparable variant: %.1f%% of Price Adapt's gain.\n",
            100 * g_now / 5002276))
