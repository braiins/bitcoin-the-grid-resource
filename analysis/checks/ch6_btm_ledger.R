# ch6_btm_ledger.R -- Chapter 6: what a grid-connected mine pays on top of energy,
# and what a behind-the-meter (netted) configuration escapes.
# Run from the repo root:  Rscript analysis/checks/ch6_btm_ledger.R
#
# Case: a 100 MW mine connected at transmission voltage in Oncor's territory,
# 2025, running at a 95% capacity factor. Every line is a charge a reader can
# look up; the retail provider's adder is private and is excluded, as is
# unaccounted-for energy. Energy is taken from the repo's own settlement archive;
# the bargaining band at the end weights it by ERCOT's 15-minute generation by
# fuel (analysis/data/fetch_ercot_fuel_mix.py), so both of its ends price the
# same megawatt-hours.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))

MW <- 100; CF <- 0.95
mwh <- MW * 8760 * CF                                        # 832,200 MWh

# energy: LZ_WEST 2025 mean 15-minute settlement price (ERCOT MIS 13061)
z <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
energy <- mean(z$price[z$settlement_point == "LZ_WEST" & substr(z$interval_start, 1, 4) == "2025"])

# transmission losses: ERCOT LMPs carry no loss term (ch3); losses are recovered
# by scaling metered load. Actual settlement transmission loss factor, mean of
# the 15-minute values ERCOT published for Jan-Jul 2026: 2.155%.
TLF <- 0.02155
loss <- energy * TLF

# ancillary services and uplift allocated to load, 2025 (IMM 2025 SOM pp. 2-3);
# uplift includes the ERCOT System Administration Fee ($0.630/MWh in 2025)
anc <- 0.39; uplift <- 1.38

# Oncor Rider TCRF, Transmission Service class, $ per 4CP kW per month, weighted
# over calendar 2025 under the March 1 / September 1 update cycle
# (Oncor Tariff for Retail Delivery Service, Rider TCRF rate history):
tcrf_rate <- (2 * 4.854456 + 6 * 3.960773 + 4 * 3.395215)    # $47.054 per 4CP kW-yr
tcrf_full <- tcrf_rate * MW * 1000 / mwh                     # 4CP demand = full load

# distribution-side charges for the Transmission Service class (same tariff):
#   Distribution System Charge $0.331004 per billing kW-month and Rider DCRF
#   $0.008179 (effective May 2025); Customer $258.80 and Metering $321.63 per month.
# Rider IS (an interim surcharge recovering the Docket 58306 rate difference from
# January 2026) and Rider RCE are 2026 instruments and are deliberately left out
# of a 2025 ledger, which makes this line conservative (higher) for 2025.
# The constants and the billing rule live in analysis/checks/oncor_distribution.R,
# which chapters 9 and 10 and the calculator share: one meter, billed every month
# on the month's highest quarter-hour, here 100 MW in all twelve, divided by the
# 95% capacity factor's megawatt-hours to make a per-MWh table line. It equals
# ((0.331004 + 0.008179) x 100,000 kW x 12 + (258.80 + 321.63) x 12) / mwh.
source("analysis/checks/oncor_distribution.R")
dist <- od_bill(od_billing(rep(MW, 12)), meters = 1) / mwh
stopifnot(abs(dist - ((0.331004 + 0.008179) * MW * 1000 * 12 + (258.80 + 321.63) * 12) / mwh) < 1e-12)

line <- function(lbl, v) cat(sprintf("  %-46s %7.2f\n", lbl, v))
cat(sprintf("100 MW transmission-connected mine, Oncor, 2025, %.0f%% capacity factor (%s MWh)\n\n",
            100 * CF, format(round(mwh), big.mark = ",")))
line("Wholesale energy, LZ_WEST mean", energy)
line(sprintf("Transmission loss gross-up (%.3f%%)", 100 * TLF), loss)
line("Ancillary services allocated to load", anc)
line("Uplift incl. system administration fee", uplift)
line(sprintf("Oncor Rider TCRF at $%.2f per 4CP kW-yr", tcrf_rate), tcrf_full)
line("Distribution, customer, metering, riders (net)", dist)
stack <- loss + anc + uplift + tcrf_full + dist
cat(sprintf("  %-46s %7.2f   (non-energy stack %.2f)\n", "Delivered, no 4CP avoidance", energy + stack, stack))
cat(sprintf("  %-46s %7.2f   (non-energy stack %.2f)\n", "Delivered, all four 4CP intervals avoided",
            energy + stack - tcrf_full, stack - tcrf_full))
cat(sprintf("\nA netted behind-the-meter site avoids the whole $%.2f stack; a grid-connected\n", stack))
cat(sprintf("site that dodges 4CP already avoids $%.2f of it, leaving $%.2f between the two.\n",
            tcrf_full, stack - tcrf_full))
# --- The bargaining band on the energy line, both ends on the SAME megawatt-hours.
# Bottom: the generator's alternative, the IMM's 2025 captured price, "the
# weighted-average energy price paid to generators for the energy they produce"
# at their own nodes, ERCOT-wide: wind $19, solar $21 (2025 SOM p. 19 definition, p. 20 values). It is
# output-weighted by construction.
# Top: the miner's alternative, buying those same megawatt-hours from the grid at
# LZ_WEST as a site that already dodges 4CP. A flat load's time-weighted mean
# ($42.18) prices different hours: a behind-the-meter mine takes the generator's
# megawatt-hours when the generator produces them. So the zone price is weighted
# by ERCOT's own interval output of that fuel (Fuel Mix Report, 15-minute,
# analysis/data/ercot_fuel_mix_15min_2025.csv.gz), the same weights the captured
# price carries. The loss line is a percentage of energy and is reweighted with
# it; the ancillary, uplift and distribution lines are the ledger's per-MWh
# allocations and are kept. The location basis is deliberate, not a mismatch:
# a generator's node price against a load's zone price is what the deal trades.
# The ratio divides by the whole non-energy stack printed above.
captured <- c(Wind = 19, Solar = 21)                         # IMM 2025 SOM p. 20
fm <- read.csv("analysis/data/ercot_fuel_mix_15min_2025.csv.gz", check.names = FALSE)
zw <- z[z$settlement_point == "LZ_WEST" & substr(z$interval_start, 1, 4) == "2025", ]
j  <- merge(zw, fm, by = c("interval_start", "dst_repeated_flag"))
stopifnot(nrow(j) == nrow(zw), nrow(j) == nrow(fm))          # every 2025 interval, once
cat(sprintf("\nBargaining band on the energy line, both ends on the same MWh (%d intervals of 2025 joined):\n", nrow(j)))
cat(sprintf("  LZ_WEST real-time mean, flat load (time-weighted)        %6.2f\n", mean(j$price)))
top_flat <- energy + stack - tcrf_full
for (fuel in names(captured)) {
  w   <- pmax(j[[fuel]], 0)                                  # solar reports ~0 at night
  pw  <- sum(j$price * w) / sum(w)
  top <- pw * (1 + TLF) + anc + uplift + dist                # delivered, 4CP avoided
  band <- top - captured[[fuel]]
  cat(sprintf("  %-5s LZ_WEST price weighted by ERCOT %-5s output       %6.2f\n", fuel, tolower(fuel), pw))
  cat(sprintf("        top of band, those MWh delivered, 4CP avoided      %6.2f\n", top))
  cat(sprintf("        bottom, IMM captured price at the nodes            %6.2f\n", captured[[fuel]]))
  cat(sprintf("        BAND %s: $%.2f wide = %.2f times the $%.2f non-energy stack\n",
              fuel, band, band / stack, stack))
  cat(sprintf("        [ref] the flat-load top ($%.2f) overstates this band by $%.2f\n",
              top_flat, top_flat - top))
}
cat(sprintf("  [ref] unmatched band, flat-load top minus wind captured: $%.2f, %.1f times the stack\n",
            top_flat - captured[["Wind"]], (top_flat - captured[["Wind"]]) / stack))

# The residual the fence must pay for, against the neighbor that already dodges 4CP.
# An islanded site sheds the whole stack; a netted site that keeps a grid tie still
# pays the distribution line, which is billed per meter on the month's highest net
# draw (with Oncor's 80% ratchet over the next 11 months; not binding for a site at
# 100 MW NCP every month), not on 4CP, and a wind-backed 100 MW site reaches full
# draw in some interval of every month (od_billing in oncor_distribution.R).
cat(sprintf("\nResidual against the 4CP-dodging neighbor: islanded $%.2f (%.1f%% of $%.2f delivered); grid-tied, still paying the distribution line, $%.2f (%.1f%%)\n",
            stack - tcrf_full, 100 * (stack - tcrf_full) / (energy + stack), energy + stack,
            stack - tcrf_full - dist, 100 * (stack - tcrf_full - dist) / (energy + stack)))

# --- Wind coverage: how much of a wind-backed mine's energy the farm supplies.
# The band above prices the megawatt-hours the wind delivers; it says nothing
# about how many there are. Here ERCOT's own 2025 wind output (the Fuel Mix
# Report, MWh per 15-minute interval, joined above) is divided by the wind
# nameplate in service that month (EIA-860M July 2026, group "wind" of
# analysis/data/ercot_capacity_additions_2026-07.csv, units counted from their
# operating month) to give the fleet's capacity factor, and that per-MW profile
# is then scaled to one farm feeding a flat mine. Caveats, both small: the fuel
# mix is DELIVERED output, net of the roughly 4.7% of wind ERCOT curtailed in
# 2025 (IMM 2025 SOM p. 17), energy a mine beside the farm could have taken, so
# coverage is slightly understated; and EIA-860M lists operating units only, so
# wind retired before July 2026 is missing from the nameplate and the capacity
# factor is slightly overstated. A single farm's output is lumpier than the
# fleet's, so the coverage figures are indicative, the system's profile.
cap <- read.csv("analysis/data/ercot_capacity_additions_2026-07.csv")
wcap <- cap[cap$group == "wind", ]
wcap$ym <- wcap$op_year * 100 + wcap$op_month
j$ym <- as.integer(substr(j$interval_start, 1, 4)) * 100 + as.integer(substr(j$interval_start, 6, 7))
name_mw <- vapply(sort(unique(j$ym)), function(m) sum(wcap$mw[wcap$ym <= m]), 0)
names(name_mw) <- sort(unique(j$ym))
j$wind_nameplate <- name_mw[as.character(j$ym)]
wind_twh <- sum(j$Wind) / 1e6
gen_cols <- c("Biomass", "Coal", "Gas", "Gas-CC", "Hydro", "Nuclear", "Other", "Solar", "Wind")
cat(sprintf("\nWind coverage, ERCOT 2025: wind %.2f TWh = %.1f%% of listed generation (WSL excluded)\n",
            wind_twh, 100 * sum(j$Wind) / sum(as.matrix(j[, gen_cols]))))
cat(sprintf("  mean in-service wind nameplate %.0f MW (EIA-860M July 2026, monthly); capacity factor %.1f%%\n",
            mean(name_mw), 100 * sum(j$Wind) / sum(j$wind_nameplate * 0.25)))
cf_mo <- tapply(j$Wind, j$ym, sum) / tapply(j$wind_nameplate * 0.25, j$ym, sum)
cat("  by month:", paste(sprintf("%s %.1f%%", month.abb, 100 * cf_mo), collapse = ", "), "\n")
per_mw <- j$Wind * 4 / j$wind_nameplate                      # the fleet's output per MW of nameplate
for (ratio in c(150 / 100, 150 / 98, 1)) {
  farm <- per_mw * ratio                                     # per MW of flat mine load
  cat(sprintf("  farm %.2f times the mine's load: %.1f%% of the mine's energy across the fence, fully covered in %.1f%% of intervals\n",
              ratio, 100 * mean(pmin(farm, 1)), 100 * mean(farm >= 1)))
}
