# ch8_ers_blocks.R, Chapter 8: what Emergency Response Service paid, block by
# block, and which blocks a strike-running mine could actually hold.
# Run from the repo root:  Rscript analysis/checks/ch8_ers_blocks.R
#
# DATA. analysis/data/ercot_ers_procurement.csv, ERCOT's own procurement
# results (NP3-144-M, MIS reportTypeId 11465), rebuilt by
# analysis/data/fetch_ercot_ers_procurement.py, which reconciles every row to
# ERCOT's projected cost. The program year is the market monitor's: December
# 2024 to November 2025, the four Standard Contract Terms Dec-Mar, Apr-May,
# Jun-Sep and Oct-Nov, whose average clearing price its 2025 report puts at
# $4.36 per MW per hour (potomac2026somercot p. 32). The block values below are
# Non-Weather-Sensitive ERS-30, the program: the other two services clear at
# the same price in every Time Period (the fetcher stops if they do not) on a
# few MW, and part 1 prints their share.
#
# THE CALENDAR. ERCOT counts each Time Period's hours itself, with ERCOT
# Holidays and daylight saving applied, and this script rebuilds that count and
# stops unless it matches every Time Period of every term in the file. The
# ERCOT Holidays are New Year's Day, Martin Luther King Jr. Day, Memorial Day,
# Independence Day, Labor Day, Thanksgiving and the day after, Christmas Eve and
# Christmas Day, as ERCOT's ERS procurement schedule for Dec 2026-Mar 2027 lists
# the winter ones; a holiday on a Saturday is kept on the Friday before and one
# on a Sunday on the Monday after (July 4, 2026 is kept on Friday July 3, which
# ERCOT's June-September 2026 hours require). Without Christmas Eve and Martin
# Luther King Jr. Day the Dec-Mar 2025 weekday blocks come out 8 hours too long
# per four-hour block (336 against ERCOT's 328).
#
# THE STRIKE (part 3). A quarter-hour of a block is one the strike would sit
# out when the LZ_WEST 15-minute settlement point price of that interval
# (analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz, ERCOT MIS 13061) is
# above the machine's breakeven at the previous day's hashprice, the one a
# controller can know (analysis/checks/ch9_hashprice.R, gap-filled):
# breakeven = hashprice x 41,666.7 / J/TH at stock, 29.5 J/TH for the S19j Pro
# and 13.5 for the S21 XP, the constants of analysis/checks/ch8_4cp_rules.R and
# the chapter 9 ledger. ERS counts any interval in which a load draws under 95
# percent of its contracted capacity as unavailable
# (ercot2026protocols 8.1.3.1.3.1(1)(a)(i)), so a share above 5 percent in a
# block is more than a whole term's allowance. The same test at the flat 2025
# breakevens ($71.6 and $156.5, chapter 4) is printed beside it.
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))

e <- read.csv("analysis/data/ercot_ers_procurement.csv", stringsAsFactors = FALSE)
TERMS <- c("2024-12-01" = "Dec-Mar", "2025-04-01" = "Apr-May", "2025-06-01" = "Jun-Sep", "2025-10-01" = "Oct-Nov")
IMM_AVG <- 4.36          # potomac2026somercot p. 32, program year 2025
CAP <- 75e6              # puct25507(b)(2) annual budget cap

# ---- the ERCOT calendar ----------------------------------------------------
nth_wday <- function(y, m, wd, n) {            # n-th weekday wd (1 = Mon) of a month; n = -1 the last
  d <- seq(as.Date(sprintf("%d-%02d-01", y, m)), by = "day", length.out = 31)
  d <- d[as.integer(format(d, "%m")) == m & as.integer(format(d, "%u")) == wd]
  if (n > 0) d[n] else d[length(d)]
}
observed <- function(d) {
  w <- as.integer(format(d, "%u"))
  d + ifelse(w == 6, -1, ifelse(w == 7, 1, 0))
}
ercot_holidays <- function(y) {
  tg <- nth_wday(y, 11, 4, 4)
  c(observed(as.Date(sprintf("%d-01-01", y))), nth_wday(y, 1, 1, 3), nth_wday(y, 5, 1, -1),
    observed(as.Date(sprintf("%d-07-04", y))), nth_wday(y, 9, 1, 1), tg, tg + 1,
    as.Date(sprintf("%d-12-24", y)), as.Date(sprintf("%d-12-25", y)))
}
# Time Period of a quarter-hour from its local start hour (0-23) and day type.
# Weekday blocks, hour ending: 06-09, 10-13, 14-16, 17-19, 20-22; weekend and
# holiday blocks: 06-09 and 16-21; Time Period 8 is every other hour.
tp_of <- function(h, workday) {
  ifelse(workday, ifelse(h >= 5 & h < 9, 1, ifelse(h >= 9 & h < 13, 2, ifelse(h >= 13 & h < 16, 3,
         ifelse(h >= 16 & h < 19, 4, ifelse(h >= 19 & h < 22, 5, 8))))),
         ifelse(h >= 5 & h < 9, 6, ifelse(h >= 15 & h < 21, 7, 8)))
}
term_grid <- function(start, end) {            # every local quarter-hour of a term
  t0 <- as.POSIXct(paste(start, "00:00"), tz = "America/Chicago")
  t1 <- as.POSIXct(paste(as.Date(end) + 1, "00:00"), tz = "America/Chicago")
  t <- seq(t0, t1 - 900, by = 900)
  d <- as.Date(format(t, "%Y-%m-%d", tz = "America/Chicago"))
  hol <- unlist(lapply(unique(as.integer(format(d, "%Y"))), function(y) as.character(ercot_holidays(y))))
  work <- as.integer(format(d, "%u")) <= 5 & !(as.character(d) %in% hol)
  data.frame(date = as.character(d), h = as.integer(format(t, "%H", tz = "America/Chicago")),
             tp = tp_of(as.integer(format(t, "%H", tz = "America/Chicago")), work), stringsAsFactors = FALSE)
}
terms <- unique(e[, c("term_start", "term_end")])
for (i in seq_len(nrow(terms))) {
  g <- term_grid(terms$term_start[i], terms$term_end[i])
  got <- tapply(g$tp, g$tp, length) / 4
  for (r in which(e$term_start == terms$term_start[i])) {
    if (got[[as.character(e$time_period[r])]] != e$hours[r])
      stop(sprintf("calendar: %s %s Time Period %d has %g h here, %d on ERCOT's count",
                   e$service[r], e$term_start[r], e$time_period[r], got[[as.character(e$time_period[r])]], e$hours[r]))
  }
}
cat(sprintf("calendar: ERCOT's hours reproduced for all %d rows (%d terms, %s to %s)\n\n",
            nrow(e), nrow(terms), min(e$term_start), max(e$term_end)))

# ---- 1. the program year's blocks, per MW ---------------------------------
py <- e[e$term_start %in% names(TERMS), ]
stopifnot(setequal(unique(py$term_start), names(TERMS)))
mwh <- tapply(py$mw_procured * py$hours, py$service, sum)
cat(sprintf("1. program year Dec 2024-Nov 2025, MW-hours procured by service: %s; NWS ERS-30 %.1f%%\n",
            paste(sprintf("%s %.0f", names(mwh), mwh), collapse = ", "), 100 * mwh[["NWS ERS-30"]] / sum(mwh)))
n <- py[py$service == "NWS ERS-30", ]
stopifnot(nrow(n) == 32)
n$term <- TERMS[n$term_start]
n$usd_per_mw <- n$hours * n$clearing_price
cat("   NWS ERS-30, clearing price $/MW/h and value $/MW (hours x price) by Time Period:\n")
for (t in TERMS) {
  s <- n[n$term == t, ]; s <- s[order(s$time_period), ]
  cat(sprintf("   %-7s %s\n", t, paste(sprintf("TP%d %dh $%.2f = $%s", s$time_period, s$hours, s$clearing_price,
                                                format(round(s$usd_per_mw), big.mark = ",")), collapse = " | ")))
}
all_blocks <- sum(n$usd_per_mw)
tp45 <- sum(n$usd_per_mw[n$time_period %in% 4:5])
keep <- n$time_period %in% c(1, 6, 7, 8)
kept <- sum(n$usd_per_mw[keep])
winter_tp1 <- n$usd_per_mw[n$term == "Dec-Mar" & n$time_period == 1]
cat(sprintf("   every block of every term: $%s per MW over %d h\n",
            format(round(all_blocks), big.mark = ","), sum(n$hours[!duplicated(paste(n$term, n$time_period))])))
cat(sprintf("   weekday afternoon and evening blocks, TP4 + TP5: $%s (%.0f%%)\n",
            format(round(tp45), big.mark = ","), 100 * tp45 / all_blocks))
cat(sprintf("   the blocks a site keeping its afternoons free can sell (weekday early morning TP1, weekend TP6 and TP7, leftover TP8): $%s per MW for the year; the Dec-Mar TP1 alone $%s (%.0f%%)\n",
            format(round(kept), big.mark = ","), format(round(winter_tp1), big.mark = ","), 100 * winter_tp1 / kept))
js <- n[n$term == "Jun-Sep", ]; js4 <- js[js$time_period == 4, ]
cat(sprintf("   Jun-Sep 2025 afternoon block TP4: %d h x $%.2f = $%s per MW; the term's highest price? %s (next: TP%d $%.2f); %.1fx the program-year average $%.2f\n",
            js4$hours, js4$clearing_price, format(round(js4$usd_per_mw), big.mark = ","),
            js4$clearing_price == max(js$clearing_price),
            js$time_period[order(-js$clearing_price)][2], sort(js$clearing_price, decreasing = TRUE)[2],
            js4$clearing_price / IMM_AVG, IMM_AVG))
cat(sprintf("   program-year dearest block: %s TP%d at $%.2f\n", n$term[which.max(n$clearing_price)],
            n$time_period[which.max(n$clearing_price)], max(n$clearing_price)))
cat(sprintf("   MW-weighted clearing price $%.2f (the monitor prints $%.2f); leftover TP8 by term: %s\n",
            sum(n$mw_procured * n$hours * n$clearing_price) / sum(n$mw_procured * n$hours), IMM_AVG,
            paste(sprintf("%s $%.2f", n$term[n$time_period == 8], n$clearing_price[n$time_period == 8]), collapse = ", ")))
cat(sprintf("   NWS ERS-30 projected cost $%.1fM against the $%.0fM cap; all services $%.1fM\n\n",
            sum(n$projected_cost) / 1e6, CAP / 1e6, sum(py$projected_cost) / 1e6))

# ---- 2. Jun-Sep 2025 afternoon block: the availability margin -------------
cat(sprintf("2. Jun-Sep 2025 TP4: %d obligated hours on ERCOT's count (%d weekdays less the ERCOT Holidays %s, x 3 h); 5%% = %.2f h; four 3-hour 4CP afternoons = 12 h = %.1f%%\n\n",
            js4$hours, js4$hours / 3 + 2, "2025-07-04 and 2025-09-01", 0.05 * js4$hours, 100 * 12 / js4$hours))

# ---- 3. the strike against the blocks -------------------------------------
source("analysis/checks/ch9_hashprice.R")
hp <- ch9_hashprice(verbose = FALSE)
rt <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz", stringsAsFactors = FALSE)
rt <- rt[rt$settlement_point == "LZ_WEST", ]
rt$date <- substr(rt$interval_start, 1, 10)
rt <- rt[rt$date >= "2024-12-01" & rt$date <= "2025-11-30", ]
rt$h <- as.integer(substr(rt$interval_start, 12, 13))
hol <- as.character(c(ercot_holidays(2024), ercot_holidays(2025)))
work <- as.integer(format(as.Date(rt$date), "%u")) <= 5 & !(rt$date %in% hol)
rt$tp <- tp_of(rt$h, work)
rt$term <- ifelse(rt$date < "2025-04-01", "Dec-Mar", ifelse(rt$date < "2025-06-01", "Apr-May",
           ifelse(rt$date < "2025-10-01", "Jun-Sep", "Oct-Nov")))
# the price file must hold every quarter-hour ERCOT counts, block by block
cnt <- tapply(rt$price, paste(rt$term, rt$tp), length) / 4
stopifnot(all(cnt[paste(n$term, n$time_period)] == n$hours))
rt$hp_known <- hp$hp_known[match(rt$date, hp$date)]
stopifnot(!anyNA(rt$hp_known))
FLEETS <- list(c("S19j Pro", 29.5, 71.6), c("S21 XP", 13.5, 156.5))
cat("3. share of each block's quarter-hours in which the LZ_WEST price was above the strike\n")
cat("   (breakeven at the previous day's hashprice; in brackets, at the flat 2025 breakeven)\n")
for (f in FLEETS) {
  be <- rt$hp_known * 41666.7 / as.numeric(f[2])
  over <- rt$price > be; over_flat <- rt$price > as.numeric(f[3])
  cat(sprintf("   %s:\n", f[1]))
  for (t in TERMS) {
    cells <- sapply(c(1, 6, 7, 8, 4), function(p) {
      i <- rt$term == t & rt$tp == p
      sprintf("TP%d %.1f%% [%.1f%%]", p, 100 * mean(over[i]), 100 * mean(over_flat[i]))
    })
    cat(sprintf("     %-7s %s\n", t, paste(cells, collapse = " | ")))
  }
  i <- rt$tp %in% c(1, 6, 7, 8)
  cat(sprintf("     TP1, 6, 7 and 8 over the year: %.1f%%; blocks above the 5%% allowance: %d of 16\n",
              100 * mean(over[i]),
              sum(sapply(TERMS, function(t) sapply(c(1, 6, 7, 8), function(p) mean(over[rt$term == t & rt$tp == p]) > 0.05)))))
}
