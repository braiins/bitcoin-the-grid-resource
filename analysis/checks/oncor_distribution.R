# oncor_distribution.R -- the distribution line of chapter 6's ledger (Table 6.1),
# billed the way the wires utility bills it, defined once for every script that
# books it: analysis/checks/ch6_btm_ledger.R (the 100 MW ledger line),
# ch9_optimal_stack.R, ch10_hashprice_sensitivity.R and ch9_calculator_export.R,
# whose page (analysis/calculator/ch9_calculator.html) bills it from the
# constants and the monthly sums this file defines. Sourced from the repo root;
# it reads no data and prints nothing.
#
# THE TARIFF. Oncor Tariff for Retail Delivery Service, Transmission Service
# class (oncor2026retailtariff sec. 6.1.1.1.7), the 2025 rates chapter 6 holds,
# kept for every year as the ledgers keep chapter 6's other 2025 charges:
#   Distribution System Charge  $0.331004 per billing kW per month
#   Rider DCRF                  $0.008179 per billing kW per month (effective May 2025)
#   Customer Charge             $258.80 per month, per meter
#   Metering Charge             $321.63 per month, per meter
# Rider IS (an interim surcharge from January 2026) and Rider RCE are 2026
# instruments and stay out, as chapter 6 leaves them out of its 2025 ledger.
#
# BILLING kW. The tariff bills the Distribution System Charge on "the higher of
# the 15-minute NCP kW for the current billing month or 80% of the highest
# monthly 15-minute NCP kW established in the 11 months preceding the current
# billing month (80% ratchet)" (the text chapter 6 quotes). NCP is the meter's
# own highest quarter-hour of the month, not its draw at the system peak, so a
# pause avoids this line only where it lowers the month's highest quarter-hour,
# and the ratchet then keeps 80 percent of a past month's peak billable. The
# ratchet here runs on NCP, as the tariff writes it, not on past billing kW; the
# two differ only in a month the ratchet binds, and none of the ledgers that
# source this file has such a month (each prints its check).
#
# HISTORY. The ledgers bill each year on its own months: the ratchet looks back
# over the months of the same series, so a year's first month carries none.
# A month's NCP can never exceed the connection, so where every month of a path
# reaches 80 percent of the connection the ratchet cannot bind whatever came
# before; the ledgers print the lowest monthly NCP of every path they score
# against that line, which is the check that the missing history moves nothing.
#
# METERS. One site meter: the grid site takes delivery at one point, so the
# customer and metering charges are billed once a month whatever the fleet
# mix, and the billing kW is the site's highest quarter-hour of total draw, not
# a sum of each fleet's own peak. The calculator adds per-fleet monthly peaks;
# that is exact where both fleets peak in the same quarter-hour (see
# ch9_calculator_export.R). The ledgers bill the machines' draw, as they bill
# every other charge, because they assume the site draws nothing beyond its
# machines (chapter 9, "One Site, Five Markets").
#
# Until 2026-10-03 chapters 9 and 10 and the calculator booked this line as
# $0.50 per MWh consumed (chapter 6's 100 MW ledger line, which divides the same
# bill by a 95 percent capacity factor's megawatt-hours), so every pause and
# every underclocked quarter-hour appeared to save it.

OD_DSC      <- 0.331004   # Distribution System Charge, $ per billing kW-month (Transmission Service, 2025)
OD_DCRF     <- 0.008179   # Rider DCRF, $ per billing kW-month (effective May 2025)
OD_CUSTOMER <- 258.80     # Customer Charge, $ per meter-month
OD_METERING <- 321.63     # Metering Charge, $ per meter-month
OD_RATCHET  <- 0.80       # share of the highest NCP of the preceding months that stays billable
OD_RATCHET_MONTHS <- 11   # how many preceding months the ratchet looks back over
OD_KW_MONTH <- OD_DSC + OD_DCRF            # $0.339183 per billing kW-month
OD_FIXED_MONTH <- OD_CUSTOMER + OD_METERING  # $580.43 per meter-month

# Monthly NCP in MW: the highest quarter-hour of a draw series (MW per interval)
# in each billing month, in the order the months first appear in `month`.
od_ncp <- function(mw, month) {
  f <- factor(month, levels = unique(month))
  as.numeric(tapply(mw, f, max))
}

# Billing MW per month: the month's NCP or 80 percent of the highest NCP of the
# up to 11 preceding months, whichever is higher. `history` holds the NCPs of
# months before the first (oldest first); the ledgers pass none.
od_billing <- function(ncp, history = numeric(0)) {
  all <- c(history, ncp); h <- length(history)
  vapply(seq_along(ncp), function(i) {
    at <- h + i
    prev <- if (at > 1) all[max(1, at - OD_RATCHET_MONTHS):(at - 1)] else numeric(0)
    max(ncp[i], if (length(prev)) OD_RATCHET * max(prev) else 0)
  }, 0)
}

# The bill in dollars for a vector of monthly billing MW. `share` is the
# fraction of each month the series covers (1 for a whole month; chapter 10's
# partial 2026 bills its last month pro rata, as it bills TCRF pro rata).
od_bill <- function(billing_mw, meters = 1, share = 1) {
  sum(share * (billing_mw * 1e3 * OD_KW_MONTH + meters * OD_FIXED_MONTH))
}

# All three steps for one draw series: the bill, and what the checks need.
od_year <- function(mw, month, meters = 1, share = 1) {
  ncp <- od_ncp(mw, month); billing <- od_billing(ncp)
  list(bill = od_bill(billing, meters, share), ncp = ncp, billing = billing,
       binds = sum(billing > ncp + 1e-9))
}
