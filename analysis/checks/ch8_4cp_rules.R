# ch8_4cp_rules.R, Chapter 8: what dodging 4CP costs WITHOUT a forecast.
# Run from the repo root:  Rscript analysis/checks/ch8_4cp_rules.R
# Rule definitions need no forecast. Demand-threshold scores are retrospective
# estimates on a settlement proxy, not a backtest of a real-time feed:
#   A  pause every day 14:00-18:00, June-September
#   B  pause weekdays 16:00-18:00, June-September
#   C95/C97  pause whenever live 15-minute demand is at or above 95% / 97%
#            of the previous year's highest official 4CP interval (known
#            before the season starts)
# For each summer 2019-2025: hours paused, and how many of that year's four
# official 4CP intervals (analysis/data/ercot_official_4cp_2018_2025.csv)
# fell inside the paused set.
# A and B are calendar rules, so their hours are calendar arithmetic (four
# hours on each of the 122 days, two hours on each Monday-to-Friday) and
# their catches are read off the official intervals' start times and
# weekdays; neither needs demand data. C95 and C97 need demand: they run on
# the checked generation-based 15-minute series of analysis/checks/ch8_demand.R.
# The official intervals are read through analysis/checks/official_4cp.R:
# ERCOT's label names the interval's END, so the interval labelled 16:00 on
# 2024-09-20 ran 15:45-16:00 and falls outside a 16:00-18:00 window. Every
# rule here tests the interval's start, as the demand series is stamped.
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))
source("analysis/checks/ch8_demand.R")
source("analysis/checks/official_4cp.R")
off <- read_official_4cp()
oh <- off$start_h
owd <- format(as.Date(off$date), "%u") %in% as.character(1:5)

# Rules A and B, from the calendar alone
cal <- do.call(rbind, lapply(2019:2025, function(y) {
  d <- seq(as.Date(sprintf("%d-06-01", y)), as.Date(sprintf("%d-09-30", y)), by = "day")
  wd <- format(d, "%u") %in% as.character(1:5)
  o <- off$year == y
  rbind(data.frame(year = y, rule = "A", hours = 4 * length(d), days = length(d),
                   caught = sum(oh[o] >= 14 & oh[o] < 18), of = sum(o)),
        data.frame(year = y, rule = "B", hours = 2 * sum(wd), days = sum(wd),
                   caught = sum(oh[o] >= 16 & oh[o] < 18 & owd[o]), of = sum(o)))
}))

# Rules C95 and C97, on demand
z <- load_demand()
z$year <- as.integer(substr(z$deliveryDate, 1, 4)); z$month <- as.integer(substr(z$deliveryDate, 6, 7))
z <- z[z$month %in% 6:9, ]
z$start <- substr(z$deliveryStart, 12, 16)   # interval start, Central prevailing
z$h <- as.integer(substr(z$start, 1, 2)) + as.integer(substr(z$start, 4, 5)) / 60
z$wd <- format(as.Date(z$deliveryDate), "%u")
dem <- do.call(rbind, lapply(2019:2025, function(y) {
  s <- z[z$year == y, ]; o <- off[off$year == y, ]
  prior <- max(off$cp_load_mw[off$year == y - 1])
  key_o <- o$key   # date and derived interval start
  stopifnot(all(key_o %in% paste(s$deliveryDate, s$start)))   # every official interval is in the series
  rules <- list(
    A = s$h >= 14 & s$h < 18,
    B = s$h >= 16 & s$h < 18 & s$wd %in% c("1","2","3","4","5"),
    C95 = s$demand >= 0.95 * prior,
    C97 = s$demand >= 0.97 * prior)
  do.call(rbind, lapply(names(rules), function(r) {
    sel <- rules[[r]]
    caught <- sum(key_o %in% paste(s$deliveryDate[sel], s$start[sel]))
    data.frame(year = y, rule = r, hours = sum(sel) / 4, days = length(unique(s$deliveryDate[sel])),
               caught = caught, of = nrow(o), filled_h = sum(sel & s$filled) / 4,
               prior_peak_mw = round(prior))
  }))
}))
# the calendar and the complete demand grid must agree on A and B
chk <- merge(cal, dem[dem$rule %in% c("A", "B"), ], by = c("year", "rule"))
stopifnot(all(chk$hours.x == chk$hours.y), all(chk$caught.x == chk$caught.y))

res <- rbind(cbind(cal, filled_h = 0, prior_peak_mw = NA), dem[dem$rule %in% c("C95", "C97"), ])
res <- res[order(res$year, res$rule), ]
print(res, row.names = FALSE)
cat("(filled_h: hours of the paused set that fall on gap-filled demand; A and B need no demand data)\n")
for (r in c("A", "B", "C95", "C97")) {
  v <- res[res$rule == r, ]
  cat(sprintf("%-4s median %.0f h/summer (range %.0f-%.0f), caught %d of %d official intervals (2019-2025)\n",
              r, median(v$hours), min(v$hours), max(v$hours), sum(v$caught), sum(v$of)))
}
o19 <- off[off$year %in% 2019:2025, ]
missB <- !(o19$start_h >= 16 & o19$start_h < 18 & format(as.Date(o19$date), "%u") %in% as.character(1:5))
cat(sprintf("rule B lets through: %s\n", paste(sprintf("%s %s-%s (label %s, %s)", o19$date[missB], o19$interval_start_cpt[missB],
                                                     o19$interval_ending_cpt[missB], o19$interval_ending_cpt[missB], o19$weekday[missB]), collapse = "; ")))

# What rule B's window cost each fleet, year by year, against the prize.
# flat: hours x the chapter's 2025 margins ($30 and $115 per MWh). strike: interval
# by interval at the LZ_WEST 15-minute settlement point price p (ERCOT MIS 13061,
# analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz) and each day's own
# hashprice (analysis/data/hashprice_daily_2021on.csv): a site running the strike
# is off anyway when p is above its breakeven, so those intervals cost nothing,
# and the rest cost (breakeven - p). Prize: the Oncor floor, $41,901 per MW-year.
rt <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
rt <- rt[rt$settlement_point == "LZ_WEST" & rt$dst_repeated_flag != "Y", ]
rt$date <- substr(rt$interval_start, 1, 10); rt$month <- as.integer(substr(rt$date, 6, 7))
rt$h <- as.integer(substr(rt$interval_start, 12, 13)) + as.integer(substr(rt$interval_start, 15, 16)) / 60
selB <- rt$month %in% 6:9 & rt$h >= 16 & rt$h < 18 & format(as.Date(rt$date), "%u") %in% as.character(1:5)
rt <- rt[selB, ]; rt$year <- as.integer(substr(rt$date, 1, 4))
rt <- rt[rt$year %in% 2021:2025, ]   # the summers of the table that have prices
source("analysis/checks/ch9_hashprice.R")          # the gap-filled daily hashprice
hp <- ch9_hashprice(verbose = FALSE)
rt$hp <- hp$hp[match(rt$date, hp$date)]
stopifnot(!anyNA(rt$hp))
cat("\nRule B window cost per MW, by fleet (prize $41,901, the Oncor floor):\n")
for (y in sort(unique(rt$year))) {
  s <- rt[rt$year == y, ]
  stopifnot(nrow(s) / 4 == cal$hours[cal$year == y & cal$rule == "B"])
  line <- sprintf("  %d: %.0f h, window mean price $%.2f", y, nrow(s) / 4, mean(s$price))
  for (f in list(c("S19j Pro", 29.5, 30), c("S21 XP", 13.5, 115))) {
    be <- s$hp * 41666.7 / as.numeric(f[2])
    cost <- sum(pmax(0, be - s$price)) / 4
    line <- paste0(line, sprintf(" | %s flat $%.0f, strike at own hashprice $%.0f (prize %.1fx)",
                                 f[1], nrow(s) / 4 * as.numeric(f[3]), cost, 41901 / cost))
  }
  cat(line, "\n")
}
