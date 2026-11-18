# ch9_hashprice.R -- the daily hashprice every chapter 9 and chapter 10 ledger
# runs on, with the calendar checked. Sourced by ch9_flexibility_stack.R,
# ch9_optimal_stack.R, ch9_control_friction.R, ch9_calculator_export.R,
# ch10_hashprice_sensitivity.R and analysis/figures/fig_ch9_moving_strike.R, so
# that one fill and one assertion serve them all.
#
# THE GAP. analysis/data/hashprice_daily_2021on.csv (column usd_th_day_spliced)
# has no row for ten days, 2025-11-13 to 15 and 2026-08-17 to 23: the days
# blockchain.info's charts did not serve, which fetch_hashprice_history.py
# skipped. Until 2026-09-25 every ledger matched its intervals to that file and
# silently dropped any interval without a hashprice, so "2025" ran on 8,688
# hours at a mean settlement price of $42.35/MWh instead of the calendar's 8,760
# at $42.18, and "2026 to date" on 234 days instead of 241.
#
# THE FILL, and why it is exact. From 2024 until hashprice_daily.csv ends
# (2026-08-24) the spliced column is not a second construction:
# fetch_hashprice_history.py copies analysis/data/hashprice_daily.csv (Braiins
# Insights) into it wherever that file has the day. Before 2024, and after that
# file ends, the column is the blockchain.info series times 0.98 (spliced_source
# "derived_scaled"), the trimmed-mean ratio of the two series on their overlap,
# so the halving-day fee spike does not set the level. hashprice_daily.csv has
# all ten missing days. So the fill takes them from hashprice_daily.csv, after
# measuring, on every day both files carry, how far the two disagree. They
# agree to rounding (957 shared days, largest difference below $1e-8 per
# TH/day), so the measured offset is zero and no carry-forward or
# interpolation is needed. The run STOPS if the overlap disagrees by more than
# $1e-6, or if a missing day is one hashprice_daily.csv cannot supply.
#
# THE ASSERTION. ch9_attach_hashprice() refuses to drop an interval for want of
# a hashprice, with one documented exception: the series' first day,
# 2021-01-01. The loop decides each day on the PREVIOUS day's hashprice and the
# series begins that day, so every ledger starts on 2021-01-02 and "2021" is
# 364 days. ch9_check_calendar() then stops the run if a ledger year is missing
# any date or any quarter-hour of its local calendar (Central prevailing time,
# so 92 intervals on the spring-forward day and 100 on the fall-back day).

ch9_hashprice <- function(verbose = TRUE) {
  a <- read.csv("analysis/data/hashprice_daily_2021on.csv", stringsAsFactors = FALSE)
  hp <- data.frame(date = as.character(a$date), hp = a$usd_th_day_spliced,
                   source = a$spliced_source, stringsAsFactors = FALSE)
  hp <- hp[order(hp$date), ]
  stopifnot(!any(duplicated(hp$date)), !any(is.na(hp$hp)))
  cal <- as.character(seq(as.Date(hp$date[1]), as.Date(tail(hp$date, 1)), by = 1))
  miss <- setdiff(cal, hp$date)
  bk <- read.csv("analysis/data/hashprice_daily.csv", stringsAsFactors = FALSE)
  bk$date <- as.character(bk$date)
  both <- intersect(hp$date, bk$date)
  dev <- abs(hp$hp[match(both, hp$date)] - bk$usd_th_day[match(both, bk$date)])
  if (length(miss)) {
    if (max(dev) > 1e-6)
      stop(sprintf("hashprice fill refused: the spliced series and hashprice_daily.csv differ by up to %.3g on their %d shared days",
                   max(dev), length(both)))
    if (!all(miss %in% bk$date))
      stop(sprintf("hashprice gap hashprice_daily.csv cannot fill: %s", paste(setdiff(miss, bk$date), collapse = ", ")))
    hp <- rbind(hp, data.frame(date = miss, hp = bk$usd_th_day[match(miss, bk$date)],
                               source = "filled_from_hashprice_daily", stringsAsFactors = FALSE))
    hp <- hp[order(hp$date), ]
  }
  stopifnot(identical(hp$date, cal))                       # one row per calendar day, no gaps
  hp$hp_known <- c(NA, head(hp$hp, -1))                     # yesterday's, the decidable one
  if (verbose)
    cat(sprintf("hashprice: %s to %s, %d calendar days; %d missing from the spliced series (%s) filled from hashprice_daily.csv, which matches the spliced column on all %d days both carry (largest difference %.1e $/TH/day)\n",
                cal[1], tail(cal, 1), length(cal), length(miss), ch9_ranges(miss), length(both), max(dev)))
  hp
}

# "2025-11-13 to 15, 2026-08-17 to 23" from a vector of dates
ch9_ranges <- function(d) {
  if (!length(d)) return("none")
  d <- sort(as.Date(d)); brk <- c(TRUE, diff(d) != 1)
  g <- split(d, cumsum(brk))
  paste(sapply(g, function(x) if (length(x) == 1) format(x[1]) else
    paste(format(x[1]), "to", format(x[length(x)], "%d"))), collapse = ", ")
}

# Attach the booking (hp_real) and decision (hp_known) hashprice to a
# quarter-hour frame with a `date` column, and drop only what may be dropped.
ch9_attach_hashprice <- function(z, hp, other_ok = NULL) {
  i <- match(z$date, hp$date)
  if (any(is.na(i) & z$date >= hp$date[1] & z$date <= tail(hp$date, 1)))
    stop("an interval inside the hashprice series found no hashprice")
  z$hp_real <- hp$hp[i]; z$hp_known <- hp$hp_known[i]
  bad <- is.na(z$hp_real) | is.na(z$hp_known)
  if (!is.null(other_ok)) bad <- bad | !other_ok
  if (any(bad & z$date != hp$date[1] & z$date <= tail(hp$date, 1)))
    stop(sprintf("ledger would drop intervals on %s", ch9_ranges(unique(z$date[bad & z$date != hp$date[1]]))))
  z[!bad, ]
}

# Every date of the year present, and every quarter-hour of each local day.
ch9_check_calendar <- function(s, y, first = sprintf("%d-01-01", y), last = sprintf("%d-12-31", y)) {
  cal <- seq(as.Date(first), as.Date(last), by = 1)
  if (!identical(sort(unique(s$date)), as.character(cal)))
    stop(sprintf("%d ledger: dates missing (%s)", y, ch9_ranges(setdiff(as.character(cal), s$date))))
  t0 <- as.POSIXct(paste(format(cal), "00:00"), tz = "America/Chicago")
  t1 <- as.POSIXct(paste(format(cal + 1), "00:00"), tz = "America/Chicago")
  want_d <- as.numeric(difftime(t1, t0, units = "mins")) / 15
  want <- sum(want_d)
  if (nrow(s) != want) stop(sprintf("%d ledger: %d intervals, calendar has %d", y, nrow(s), want))
  # the total can balance a missing quarter-hour on one day against a duplicate
  # on another, so each day is checked on its own as well
  tab <- table(s$date)
  bad <- format(cal)[as.vector(tab[format(cal)]) != want_d]
  if (length(bad)) stop(sprintf("%d ledger: wrong interval count on %s", y, ch9_ranges(bad)))
  invisible(want)
}
