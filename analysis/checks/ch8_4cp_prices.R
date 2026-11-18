# ch8_4cp_prices.R, Chapter 8: was electricity expensive when the 4CP peak hit?
# Run from the repo root:  Rscript analysis/checks/ch8_4cp_prices.R
# For each official ERCOT 4CP interval 2021-2025 (analysis/data/
# ercot_official_4cp_2018_2025.csv, read through analysis/checks/official_4cp.R:
# ERCOT's label names the interval's END, so the interval labelled 17:00 is
# 16:45-17:00 and sits in hour ending 17):
#   * the LZ_WEST day-ahead price for the peak's hour, its percentile rank among
#     that month's hours, and the hour of the month's priciest day-ahead hour
#     (analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz, ERCOT MIS report
#     13060 via fetch_ercot_rtm15_spp_history.py);
#   * the LZ_WEST and LZ_NORTH 15-minute real-time settlement price in the
#     interval itself, from analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz
#     (ERCOT MIS report 13061 via fetch_ercot_rtm15_spp_history.py).
#     NOTE: this replaced ercot_spp_dam_rtm15_8zones.csv.gz on 2026-09-04, which
#     stores Central time as a fixed UTC-6 offset and so labels every daylight-
#     saving interval an hour late -- and every 4CP interval is in summer.
# Then: how many of the 20 peak hours would a breakeven strike (ch4: $72 S19j
# Pro, $157 S21 XP) have paused, and how often the month's priciest hour was
# the peak hour at all.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
dam <- read.csv("analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz")
dam <- dam[dam$settlement_point == "LZ_WEST" & dam$dst_repeated_flag == "N", ]   # one row per (date, hour ending)
dam$deliveryDate <- substr(dam$hour_start, 1, 10); dam$settlementPointPrice <- dam$price
dam$he <- as.integer(substr(dam$hour_start, 12, 13)) + 1L                        # hour ending, 1-24
dam$year <- as.integer(substr(dam$deliveryDate, 1, 4)); dam$month <- as.integer(substr(dam$deliveryDate, 6, 7))
source("analysis/checks/official_4cp.R")
off <- read_official_4cp(); off <- off[off$year >= 2021, ]   # he: the hour ending that contains the interval
rt <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
rt$date <- substr(rt$interval_start, 1, 10); rt$hhmm <- substr(rt$interval_start, 12, 16)
rows <- do.call(rbind, lapply(seq_len(nrow(off)), function(i) {
  d <- off$date[i]; m <- dam[dam$year == off$year[i] & dam$month == off$month[i], ]
  p <- m$settlementPointPrice[m$deliveryDate == d & m$he == off$he[i]]
  j <- which.max(m$settlementPointPrice)
  day <- m[m$deliveryDate == d, ]; k <- which.max(day$settlementPointPrice)
  w <- rt$price[rt$settlement_point == "LZ_WEST" & rt$date == d & rt$hhmm == off$interval_start_cpt[i]]
  n <- rt$price[rt$settlement_point == "LZ_NORTH" & rt$date == d & rt$hhmm == off$interval_start_cpt[i]]
  stopifnot(length(p) == 1, length(w) == 1, length(n) == 1)
  data.frame(date = d, label = off$interval_ending_cpt[i], interval = paste0(off$interval_start_cpt[i], "-", off$interval_ending_cpt[i]),
             he = off$he[i], dam_west = p,
             pct_in_month = round(100 * mean(m$settlementPointPrice <= p)),
             month_max = round(m$settlementPointPrice[j]), month_max_at = paste0(m$deliveryDate[j], " HE", m$he[j]),
             day_max_he = day$he[k], day_max = round(day$settlementPointPrice[k]),
             rt_west = w, rt_north = n)
}))
# statistics on the unrounded prices; the table rounds for display only
print(transform(rows, dam_west = round(dam_west, 1), rt_west = round(rt_west, 1), rt_north = round(rt_north, 1)), row.names = FALSE)
cat(sprintf("\nDAM LZ_WEST at the 20 official 4CP hours: median $%.2f, mean $%.0f, range $%.2f-$%.2f\n",
            median(rows$dam_west), mean(rows$dam_west), min(rows$dam_west), max(rows$dam_west)))
cat(sprintf("Above the S19j Pro breakeven ($72): %d of 20; above the S21 XP breakeven ($157): %d of 20; above $500: %d; in the month's top decile of hours: %d of 20\n",
            sum(rows$dam_west > 72), sum(rows$dam_west > 157), sum(rows$dam_west > 500), sum(rows$pct_in_month >= 90)))
mm <- rows$month_max_at == paste0(rows$date, " HE", rows$he)
cat(sprintf("Month's priciest DAM hour was the 4CP hour in %d of 20 months (%s); the 4CP day's priciest hour was the 4CP hour on %d of 20 days (day max later than the peak on %d days, at HE %s)\n",
            sum(mm), paste(rows$month_max_at[mm], collapse = ", "), sum(rows$day_max_he == rows$he), sum(rows$day_max_he > rows$he),
            paste(sort(unique(rows$day_max_he[rows$day_max_he > rows$he])), collapse = "/")))
cat("Hour-ending of the month's priciest DAM hour, 2021-2025 4CP months: "); print(table(sub(".* HE", "", rows$month_max_at)))
summer <- dam[dam$month %in% 6:9 & dam$year %in% 2021:2025, ]
cat(sprintf("Summer 2021-2025 DAM LZ_WEST: mean $%.0f, P90 $%.0f, P99 $%.0f; by year: %s\n", mean(summer$settlementPointPrice),
            quantile(summer$settlementPointPrice, .9), quantile(summer$settlementPointPrice, .99),
            paste(sprintf("%d $%.0f", 2021:2025, tapply(summer$settlementPointPrice, summer$year, mean)), collapse = ", ")))
cat(sprintf("Real-time 15-min LZ_WEST in all %d official intervals: median $%.2f, range $%.2f to $%.2f; above $71.6: %d; above $156.5: %d\n",
            nrow(rows), median(rows$rt_west), min(rows$rt_west), max(rows$rt_west),
            sum(rows$rt_west > 71.6), sum(rows$rt_west > 156.5)))
r8 <- rows[rows$date >= "2024-01-01", ]
cat(sprintf("The eight 2024-2025 intervals: %s (range $%.2f to $%.2f, median $%.2f); LZ_NORTH median $%.2f\n",
            paste(sprintf("$%.0f", r8$rt_west), collapse = ", "), min(r8$rt_west), max(r8$rt_west), median(r8$rt_west), median(r8$rt_north)))
a8 <- r8[r8$rt_west > 71.6, ]
cat(sprintf("Of those eight, above the S19j Pro breakeven ($71.6): %d (%s)\n", nrow(a8),
            paste(sprintf("%s at $%.2f, $%.2f over", a8$date, a8$rt_west, a8$rt_west - 71.6), collapse = "; ")))
cat(sprintf("Their day-ahead hours: %s; below $72: %d of 8; highest $%.2f (%s HE%d)\n",
            paste(sprintf("$%.0f", r8$dam_west), collapse = ", "), sum(r8$dam_west < 72),
            max(r8$dam_west), r8$date[which.max(r8$dam_west)], r8$he[which.max(r8$dam_west)]))
# bounded at 2025: the cache runs into 2026, and an open-ended filter would
# move this comparison every time the cache is refetched
summer2 <- rt[rt$settlement_point == "LZ_WEST" & substr(rt$date, 6, 7) %in% c("06","07","08","09") &
              rt$date >= "2024-01-01" & rt$date < "2026-01-01", ]
cat(sprintf("Summer (June-September) 2024-2025 LZ_WEST real-time mean, for comparison: $%.2f (2024 $%.2f, 2025 $%.2f)\n",
            mean(summer2$price), mean(summer2$price[substr(summer2$date, 1, 4) == "2024"]),
            mean(summer2$price[substr(summer2$date, 1, 4) == "2025"])))
