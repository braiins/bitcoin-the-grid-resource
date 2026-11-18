# ch8_12cp_haystack.R, Chapter 8: the 12CP version of the haystack.
# Run from the repo root:  Rscript analysis/checks/ch8_12cp_haystack.R
# For each October-September year 2020-2025 (pinned: the year ending September
# 2026 is complete once September 2026 is in the cache and is not counted;
# chapter 8 quotes these six), and for each of its twelve months, count the
# hours of 15-minute intervals within 2% and 5% of that month's peak; sum over
# the year and split summer (Jun-Sep) vs the
# eight other months. The same 12-month haystack is also counted on clock
# half-hours, the 30-minute interval the proposal measures (block after the
# half-hour key below); chapter 8 prints that one. Then price one avoided peak under 12CP at the Oncor
# rider floor ($41,901/MW-yr / 12) and compare with dodging cost at the ch4
# margins ($30 and $115 per MWh paused). Demand: the checked generation-based
# 15-minute series of analysis/checks/ch8_demand.R (complete months only).
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))
source("analysis/checks/ch8_demand.R")
z <- load_demand()
z$year <- as.integer(substr(z$deliveryDate, 1, 4)); z$month <- as.integer(substr(z$deliveryDate, 6, 7))
z$cpyear <- ifelse(z$month >= 10, z$year + 1, z$year)   # Oct-Sep year labeled by its September
res <- do.call(rbind, lapply(2020:2025, function(cy) {
  s <- z[z$cpyear == cy, ]
  stopifnot(length(unique(s$month)) == 12)   # every pinned year complete
  do.call(rbind, lapply(1:12, function(m) {
    sm <- s[s$month == m, ]; pk <- max(sm$demand)
    data.frame(cpyear = cy, month = m, summer = m %in% 6:9,
               h2 = sum(sm$demand >= 0.98 * pk) / 4, h5 = sum(sm$demand >= 0.95 * pk) / 4,
               peak_mw = round(pk))
  }))
}))
agg <- aggregate(cbind(h2, h5) ~ cpyear + summer, res, sum)
print(agg, row.names = FALSE)
tot <- aggregate(cbind(h2, h5) ~ cpyear, res, sum)
cat(sprintf("\n12-month haystack per Oct-Sep year: within 2%%: %.0f-%.0f h (median %.0f); within 5%%: %.0f-%.0f h (median %.0f)\n",
            min(tot$h2), max(tot$h2), median(tot$h2), min(tot$h5), max(tot$h5), median(tot$h5)))
w <- res[!res$summer, ]
cat(sprintf("Non-summer months: median %.0f h within 2%% per month (vs summer months median %.0f h)\n",
            median(w$h2), median(res$h2[res$summer])))
v <- 41901 / 12
cat(sprintf("Value of one avoided 12CP peak at the Oncor floor: $%.0f/MW (vs $%.0f under 4CP)\n", v, 41901 / 4))
for (mg in c(30, 115)) cat(sprintf("  at $%d/MWh margin: median-month 2%%-haystack of %.0f h costs $%.0f/MW per month (%.0fx the peak's value); the 5%%-haystack %.0f h costs $%.0f (%.1fx)\n",
     mg, median(res$h2), median(res$h2) * mg, v / (median(res$h2) * mg), median(res$h5), median(res$h5) * mg, v / (median(res$h5) * mg)))

# --- a no-forecast rule for twelve months: pause weekdays 07:00-09:00 and
# 16:00-18:00 in every month (4 h/weekday). Hours per Oct-Sep year and how
# many of the twelve monthly peaks it covers. The proposal measures each
# monthly peak over a 30-minute interval (proposed 16 TAC 25.192(b)(4),
# puct2026prop58000), so the count that prices the rule is scored on clock
# half-hours: the mean of the quarter-hours starting at :00 and :15, or at
# :30 and :45, keyed with the UTC offset so the repeated fall-back hour stays
# two hours. The windows start and end on the hour, so a half-hour is wholly
# inside them or wholly outside. The 15-minute count, the resolution of the
# 4CP rule and of the haystack above, is printed beside it for comparison.
z$start <- substr(z$deliveryStart, 12, 16)
z$h <- as.integer(substr(z$start, 1, 2)) + as.integer(substr(z$start, 4, 5)) / 60
z$wd <- format(as.Date(z$deliveryDate), "%u")
z$sel <- z$wd %in% c("1","2","3","4","5") & ((z$h >= 7 & z$h < 9) | (z$h >= 16 & z$h < 18))
z$half <- paste0(substr(z$deliveryStart, 1, 13), ifelse(as.integer(substr(z$start, 4, 5)) < 30, ":00", ":30"),
                 substr(z$deliveryStart, 20, 22))

# The 12-month haystack again, on the same clock half-hours: the proposal
# measures each monthly peak over a 30-minute interval, so this is the basis
# that matches the rule chapter 8 prints. Hours of half-hours whose mean demand
# is within 2% (5%) of that month's highest half-hour mean, summed over the
# Oct-Sep year; then the margin a perfectly informed site gives up pausing
# through the median year's 2% haystack at the ch4 margins ($30, $115/MWh).
# The 15-minute haystack above stays for comparison with the 4CP one.
res30 <- do.call(rbind, lapply(unique(res$cpyear), function(cy) {
  s30 <- aggregate(demand ~ half + month, data = z[z$cpyear == cy, ], FUN = mean)
  do.call(rbind, lapply(1:12, function(m) {
    sm <- s30[s30$month == m, ]; pk <- max(sm$demand)
    data.frame(cpyear = cy, month = m, h2 = sum(sm$demand >= 0.98 * pk) / 2, h5 = sum(sm$demand >= 0.95 * pk) / 2)
  }))
}))
tot30 <- aggregate(cbind(h2, h5) ~ cpyear, res30, sum)
cat(sprintf("\n12-month haystack on clock half-hours, per Oct-Sep year: within 2%%: %.0f-%.0f h (median %.0f); within 5%%: %.0f-%.0f h (median %.0f)\n",
            min(tot30$h2), max(tot30$h2), median(tot30$h2), min(tot30$h5), max(tot30$h5), median(tot30$h5)))
cat(sprintf("  by year, within 2%%: %s\n", paste(sprintf("%d %.1f h", tot30$cpyear, tot30$h2), collapse = ", ")))
for (mg in c(30, 115)) cat(sprintf("  median 2%%-haystack %.1f h x $%d/MWh = $%.0f per MW-year (15-minute basis: %.1f h, $%.0f)\n",
     median(tot30$h2), mg, median(tot30$h2) * mg, median(tot$h2), median(tot$h2) * mg))
#
# What the rule is worth, fleet by fleet. Each monthly peak dodged saves
# one twelfth of the annual charge (v above). Two ways to price the margin
# the window gives up:
#   flat   hours x the chapter's 2025 margins, $30 (S19j Pro) and $115 (S21 XP)
#          per MWh, i.e. chapter 4's 2025 breakevens $71.6 and $156.5 less the
#          $42.18 mean settlement price;
#   strike interval by interval at the LZ_WEST 15-minute settlement point price p
#          (analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz, ERCOT MIS
#          13061): a site running the strike is already off when p is above
#          the breakeven, so those intervals cost nothing, and every other
#          interval costs (breakeven - p). Priced at the 2025 breakevens, and
#          also at each day's own hashprice (analysis/data/hashprice_daily_2021on.csv).
#          Prices start in January 2021, so the strike basis covers the
#          Oct-Sep years 2022 to 2025.
rt <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
rt <- rt[rt$settlement_point == "LZ_WEST" & rt$dst_repeated_flag != "Y", ]
price_at <- setNames(rt$price, substr(rt$interval_start, 1, 16))
source("analysis/checks/ch9_hashprice.R")          # the gap-filled daily hashprice
hp <- ch9_hashprice(verbose = FALSE)
hp_at <- setNames(hp$hp, hp$date)
FLEETS <- data.frame(fleet = c("S19j Pro", "S21 XP"), jth = c(29.5, 13.5), be25 = c(71.6, 156.5), flat = c(30, 115))
cat("\nTwo-window weekday rule (07-09 and 16-18, all twelve months), value = 30-minute peaks covered x $", round(v), ":\n", sep = "")
tw <- list()
for (cy in unique(res$cpyear)) {
  s <- z[z$cpyear == cy, ]
  sel <- s$sel
  pk <- do.call(rbind, lapply(1:12, function(m) { sm <- s[s$month == m, ]; sm[which.max(sm$demand), c("deliveryDate", "start")] }))
  caught15 <- sum(paste(pk$deliveryDate, pk$start) %in% paste(s$deliveryDate[sel], s$start[sel]))
  s30 <- aggregate(cbind(demand, sel) ~ half + month, data = s, FUN = mean)
  stopifnot(all(s30$sel %in% c(0, 1)))            # no half-hour straddles a window edge
  caught <- sum(sapply(1:12, function(m) { sm <- s30[s30$month == m, ]; sm$sel[which.max(sm$demand)] == 1 }))
  hrs <- sum(sel) / 4
  p <- price_at[substr(s$deliveryStart[sel], 1, 16)]
  hpd <- hp_at[s$deliveryDate[sel]]
  have_p <- !anyNA(p) && !anyNA(hpd)
  cat(sprintf("  %d: %.0f h paused, %d of 12 monthly 30-minute peaks covered (15-minute peaks: %d), worth $%.0f/MW\n",
              cy, hrs, caught, caught15, caught * v))
  for (k in 1:2) {
    f <- FLEETS[k, ]
    flat <- hrs * f$flat
    s25 <- if (have_p) sum(pmax(0, f$be25 - p)) / 4 else NA
    sown <- if (have_p) sum(pmax(0, hpd * 41666.7 / f$jth - p)) / 4 else NA
    cat(sprintf("      %-8s flat $%6.0f (%.2fx)  strike at 2025 breakeven $%s  strike at own-day hashprice $%s\n",
                f$fleet, flat, caught * v / flat,
                if (have_p) sprintf("%6.0f (%.2fx)", s25, caught * v / s25) else "   n/a (no prices)",
                if (have_p) sprintf("%7.0f (%.2fx)", sown, caught * v / sown) else "   n/a"))
    tw[[length(tw) + 1]] <- data.frame(cpyear = cy, fleet = f$fleet, caught = caught, caught15 = caught15, hours = hrs,
                                       value = caught * v, value15 = caught15 * v, flat = flat, strike25 = s25, strike_own = sown)
  }
}
tw <- do.call(rbind, tw)
cat(sprintf("Hours paused %.0f-%.0f; 30-minute peaks covered %d-%d of 12 (15-minute peaks: %d-%d of 12)\n",
            min(tw$hours), max(tw$hours), min(tw$caught), max(tw$caught), min(tw$caught15), max(tw$caught15)))
summ <- function(t, val, label) {
  ts <- t[!is.na(t$strike25), ]
  cat(sprintf("%-8s %s all years, flat: value/cost %.2fx, ahead in %d of %d years; strike at 2025 breakeven (%d-%d): %.2fx, ahead in %d of %d (%s behind)\n",
              t$fleet[1], label, sum(t[[val]]) / sum(t$flat), sum(t[[val]] > t$flat), nrow(t), min(ts$cpyear), max(ts$cpyear),
              sum(ts[[val]]) / sum(ts$strike25), sum(ts[[val]] > ts$strike25), nrow(ts),
              paste(ts$cpyear[ts[[val]] <= ts$strike25], collapse = ", ")))
}
for (fl in FLEETS$fleet) summ(tw[tw$fleet == fl, ], "value", "30-minute scoring,")
cat("For comparison, the same rule scored on 15-minute monthly peaks:\n")
for (fl in FLEETS$fleet) summ(tw[tw$fleet == fl, ], "value15", "15-minute scoring,")
