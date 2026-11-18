# ch8_4cp_peaks.R, Chapter 8: reconstruct the ERCOT monthly peak-demand
# intervals from public 15-minute system demand. Run from the repo root:
#   Rscript analysis/checks/ch8_4cp_peaks.R
#
# Data: ERCOT Fuel Mix Report, generation-based demand proxy (sum of fuel
# MWh including negative WSL, times four; DC-tie flows omitted). The loader
# asserts complete Central days and months, with no gap-fill. See ch8_demand.R.
# Official settlement peaks remain authoritative; this is a reconstruction.
#
# Console output (everything the chapter quotes):
#   1. monthly peak interval (date, time-ending, MW, weekday) for every
#      month with data, 2019 to the data edge;
#   2. summer (Jun-Sep) 4CP intervals per year, and their time-ending and
#      weekday distributions across years;
#   3. "near-miss" statistics: how many 15-minute intervals, and how many
#      distinct days, came within 1%, 2%, and 5% of each month's peak;
#   4. the twelve-month (12CP) view: peaks of every month, and the hour
#      distribution of the non-summer peaks.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))

source("analysis/checks/ch8_demand.R")
z <- load_demand()
z$year <- as.integer(substr(z$deliveryDate, 1, 4))
z$month <- as.integer(substr(z$deliveryDate, 6, 7))
z$wday <- weekdays(as.Date(z$deliveryDate))
z$he <- as.integer(substr(z$timeEnding, 1, 2)) + ifelse(substr(z$timeEnding, 4, 5) == "00", 0, 1)
# hour-ending of the interval's hour: an interval ending 17:15/17:30/17:45/18:00 is in HE 18

peaks <- do.call(rbind, lapply(split(z, list(z$year, z$month), drop = TRUE), function(s) {
  i <- which.max(s$demand)
  data.frame(year = s$year[i], month = s$month[i], date = s$deliveryDate[i],
             time_ending = s$timeEnding[i], he = s$he[i], mw = s$demand[i],
             wday = s$wday[i], n_intervals = nrow(s), n_filled = sum(s$filled),
             peak_filled = s$filled[i], n_days = length(unique(s$deliveryDate)))
}))
peaks <- peaks[order(peaks$year, peaks$month), ]
rownames(peaks) <- NULL
# every month here is complete (load_demand() asserts every day's count);
# check the day count per month too, and say whether any month's peak sits
# on a gap-filled hour, which would make its time and MW approximate
first <- as.Date(sprintf("%d-%02d-01", peaks$year, peaks$month))
dim_ <- as.integer(format(as.Date(sapply(first, function(d) seq(d, by = "month", length.out = 2)[2] - 1),
                                  origin = "1970-01-01"), "%d"))
stopifnot(all(peaks$n_days == dim_))
cat(sprintf("%d complete months, %s to %s; months with gap-filled intervals: %d; monthly peaks on a filled interval: %d%s\n\n",
            nrow(peaks), min(peaks$date), max(peaks$date), sum(peaks$n_filled > 0), sum(peaks$peak_filled),
            if (any(peaks$peak_filled)) paste0(" (", paste(peaks$date[peaks$peak_filled], collapse = ", "), ")") else ""))
peaks$n_days <- NULL

cat("=== Monthly peak intervals (all months) ===\n")
print(peaks[, c("year", "month", "date", "time_ending", "mw", "wday", "n_intervals", "n_filled")],
      row.names = FALSE, digits = 7)

summer <- peaks[peaks$month %in% 6:9, ]
cat("\n=== Reconstructed 4CP intervals (June-September) ===\n")
print(summer[, c("year", "month", "date", "time_ending", "mw", "wday")],
      row.names = FALSE, digits = 7)

full_years <- names(which(table(summer$year) == 4))
s4 <- summer[summer$year %in% full_years, ]
cat("\nTime-ending distribution of the summer peaks (complete years", paste(full_years, collapse = ", "), "):\n")
print(table(s4$time_ending))
cat("Hour-ending distribution:\n"); print(table(s4$he))
cat("Weekday distribution:\n"); print(table(s4$wday))
cat(sprintf("Share of summer peaks in HE 17 or HE 18: %.0f%%\n",
            100 * mean(s4$he %in% 17:18)))
cat(sprintf("Share on a weekend day: %.0f%%\n",
            100 * mean(s4$wday %in% c("Saturday", "Sunday"))))

cat("\n=== Near-miss statistics per summer month ===\n")
nm <- do.call(rbind, lapply(seq_len(nrow(summer)), function(k) {
  s <- z[z$year == summer$year[k] & z$month == summer$month[k], ]
  pk <- summer$mw[k]
  f <- function(tol) {
    sel <- s$demand >= pk * (1 - tol)
    c(intervals = sum(sel), days = length(unique(s$deliveryDate[sel])))
  }
  data.frame(year = summer$year[k], month = summer$month[k],
             int1 = f(.01)["intervals"], days1 = f(.01)["days"],
             int2 = f(.02)["intervals"], days2 = f(.02)["days"],
             int5 = f(.05)["intervals"], days5 = f(.05)["days"])
}))
print(nm, row.names = FALSE)
cat(sprintf("\nMedian per month: within 1%%: %.0f intervals on %.0f days; within 2%%: %.0f on %.0f; within 5%%: %.0f on %.0f\n",
            median(nm$int1), median(nm$days1), median(nm$int2), median(nm$days2),
            median(nm$int5), median(nm$days5)))
for (y in full_years) {
  v <- nm[nm$year == as.integer(y), ]
  cat(sprintf("%s: hours within 2%% of the four monthly peaks = %.1f h over %d days; within 5%% = %.1f h over %d days\n",
              y, sum(v$int2) / 4, sum(v$days2), sum(v$int5) / 4, sum(v$days5)))
}

cat("\n=== 12CP view: non-summer monthly peaks, hour-ending distribution ===\n")
ns <- peaks[!(peaks$month %in% 6:9), ]   # every complete non-summer month
cat(sprintf("%d non-summer months, %s to %s\n", nrow(ns), min(ns$date), max(ns$date)))
print(table(ns$he))
cat(sprintf("Non-summer peaks in the morning (HE 7-10): %.0f%%; in the evening (HE 17-21): %.0f%%\n",
            100 * mean(ns$he %in% 7:10), 100 * mean(ns$he %in% 17:21)))
for (y in sort(unique(peaks$year))) {
  p <- peaks[peaks$year == y, ]
  cat(sprintf("%d%s: annual peak %.0f MW on %s (%s); lowest monthly peak %.0f MW in month %d\n",
              y, if (nrow(p) < 12) sprintf(" (%d months only)", nrow(p)) else "",
              max(p$mw), p$date[which.max(p$mw)], p$time_ending[which.max(p$mw)],
              min(p$mw), p$month[which.min(p$mw)]))
}

cat("\n=== Official ERCOT 4CP intervals (analysis/data/ercot_official_4cp_2018_2025.csv) ===\n")
# read through analysis/checks/official_4cp.R: ERCOT's label is the interval's
# END (interval_ending_cpt); the start is derived there, label - 15 min
source("analysis/checks/official_4cp.R")
off <- read_official_4cp()
lh <- as.integer(substr(off$interval_ending_cpt, 1, 2)) + as.integer(substr(off$interval_ending_cpt, 4, 5)) / 60   # the label
wkend <- off$weekday %in% c("Saturday", "Sunday")
cat(sprintf("%d official intervals %d-%d; labeled 17:00: %d; labels between 14:30 and 17:45: %d; labels between 16:30 and 17:45: %d; weekend: %d (%s)\n",
            nrow(off), min(off$year), max(off$year), sum(off$interval_ending_cpt == "17:00"),
            sum(lh >= 14.5 & lh <= 17.75), sum(lh >= 16.5 & lh <= 17.75),
            sum(wkend), paste(off$date[wkend], collapse = ", ")))
cat(sprintf("as intervals (start = label - 15 min): earliest start %s, latest end %s; within 16:15-17:45 (the six quarter-hours labelled 16:30 to 17:45): %d of %d\n",
            min(off$interval_start_cpt), max(off$interval_ending_cpt),
            sum(off$start_h >= 16.25 & off$start_h + 0.25 <= 17.75), nrow(off)))
# ERS Time Period 4: weekdays HE 17-19 (16:00-19:00), excluding ERCOT holidays;
# the only ERCOT holidays in June-September are July 4 and Labor Day
d <- as.Date(off$date)
holiday <- format(d, "%m-%d") == "07-04" | (format(d, "%m") == "09" & weekdays(d) == "Monday" & as.integer(format(d, "%d")) <= 7)
tp4 <- !wkend & !holiday & off$start_h >= 16 & off$start_h < 19
cat(sprintf("ERS Time Period 4 (weekday, not an ERCOT holiday, interval inside 16:00-19:00): %d of %d; ERCOT holidays among the dates: %d; outside: %s\n",
            sum(tp4), nrow(off), sum(holiday),
            paste(sprintf("%s %s-%s%s", off$date[!tp4], off$interval_start_cpt[!tp4], off$interval_ending_cpt[!tp4],
                          ifelse(wkend[!tp4], sprintf(" (%s)", off$weekday[!tp4]), "")), collapse = ", ")))
both <- merge(off, summer, by = c("year", "month"), suffixes = c(".off", ".rec"))
cat(sprintf("official vs reconstructed (years in both): %d of %d dates match; differ: %s\n",
            sum(both$date.off == both$date.rec), nrow(both),
            paste(both$date.off[both$date.off != both$date.rec], collapse = ", ")))
print(off[, c("year", "month", "date", "interval_ending_cpt", "interval_start_cpt", "weekday", "cp_load_mw")], row.names = FALSE)

# The convention check: on each official day in the demand series, compare the
# quarter-hour that ENDS at ERCOT's label with the one that STARTS at it. The
# series is stamped by interval start (deliveryStart) and carries its end
# (timeEnding), both in Central prevailing time.
cat("\n=== Label convention check: official labels against the day's demand (2019 on) ===\n")
z$st <- substr(z$deliveryStart, 12, 16)
cv <- do.call(rbind, lapply(which(off$date %in% z$deliveryDate), function(i) {
  s <- z[z$deliveryDate == off$date[i], ]
  j <- which.max(s$demand); lab <- off$interval_ending_cpt[i]
  data.frame(date = off$date[i], label = lab, day_max = paste0(s$st[j], "-", s$timeEnding[j]),
             mw_ending_at_label = s$demand[s$timeEnding == lab], mw_starting_at_label = s$demand[s$st == lab],
             cp_load_mw = off$cp_load_mw[i],
             gap_mw = s$demand[s$timeEnding == lab] - off$cp_load_mw[i],
             is_day_max = s$demand[s$timeEnding == lab] == max(s$demand),
             is_month_max = s$demand[s$timeEnding == lab] == max(z$demand[substr(z$deliveryDate, 1, 7) == substr(off$date[i], 1, 7)]),
             filled = any(s$filled[s$timeEnding == lab | s$st == lab]))
}))
print(cv, row.names = FALSE, digits = 9)
write.csv(cv, "analysis/data/ercot_fuel_mix_4cp_validation.csv", row.names = FALSE)
cat(sprintf("Official labels are daily maxima: %d/%d; monthly maxima: %d/%d; MW gap range %.2f to %.2f, mean absolute %.2f\n",
            sum(cv$is_day_max), nrow(cv), sum(cv$is_month_max), nrow(cv), min(cv$gap_mw), max(cv$gap_mw), mean(abs(cv$gap_mw))))
stopifnot(nrow(cv) == 28, sum(cv$is_day_max) >= 19,
          sum(cv$mw_ending_at_label > cv$mw_starting_at_label) >= 23)
cat(sprintf("the day's peak interval ENDS at the label on %d of %d days and STARTS at it on %d; the interval ending at the label carries more demand than the one starting at it on %d of %d (ties %d; gap-filled intervals among them: %d)\n",
            sum(sub(".*-", "", cv$day_max) == cv$label), nrow(cv), sum(sub("-.*", "", cv$day_max) == cv$label),
            sum(cv$mw_ending_at_label > cv$mw_starting_at_label), nrow(cv),
            sum(cv$mw_ending_at_label == cv$mw_starting_at_label), sum(cv$filled)))

cat("\n=== Annual energy of the checked series (the chapter's nominal cross-check on ERCOT's TCOS per MWh) ===\n")
en <- tapply(z$demand, z$year, sum) / 4 / 1e6   # TWh
for (y in names(en)) {   # a year short of twelve months says which months it has
  mo <- range(z$month[z$year == as.integer(y)])
  cat(sprintf("%s: %.1f TWh%s\n", y, en[[y]],
              if (mo[2] - mo[1] < 11) sprintf(" (%s to %s only)", month.name[mo[1]], month.name[mo[2]]) else ""))
}
cat(sprintf("2025: $5,446,864,795 TCOS (puct2025docket57491matrix) / %.1f TWh = $%.2f/MWh\n",
            en[["2025"]], 5446864795 / (en[["2025"]] * 1e6)))
write.csv(peaks,"analysis/data/ercot_monthly_peak_intervals_reconstructed.csv", row.names = FALSE)
cat("\nWrote analysis/data/ercot_monthly_peak_intervals_reconstructed.csv\n")
