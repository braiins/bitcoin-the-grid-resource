# official_4cp.R, the one place the official ERCOT 4CP intervals are read.
# Sourced (not run) by every script that uses them: ch8_4cp_peaks.R,
# ch8_4cp_prices.R, ch8_4cp_rules.R, ch9_flexibility_stack.R,
# ch9_optimal_stack.R, ch9_calculator_export.R, ch10_hashprice_sensitivity.R,
# fig_ch7_as_history.R and fig_ch8_4cp_calendar.R.
#
# THE LABEL CONVENTION. analysis/data/ercot_official_4cp_2018_2025.csv keeps
# ERCOT's own label for each interval, verbatim, in interval_ending_cpt. ERCOT
# labels a fifteen-minute settlement interval by the time it ENDS, so the
# official interval labelled 17:00 ran from 16:45 to 17:00 (Central prevailing
# time). ERCOT's 2022-2025 NP9-83-M workbooks print the bare label and do not
# say so; its own documents do:
#   * the 1996-2020 archive (bib ercot4cphistzip): the 2003-2006 filing
#     workbooks and the 2007 preliminary monthly workbooks write "at interval
#     ending HH:MM", and 2006/FILING_20064CP.xls carries both the bare header
#     "June 6/13/2006 16:15" (the format ERCOT still uses) and, on its JUNE
#     sheet, "Peak Demand on 06/13/2006 at interval ending 16:15";
#   * ERCOT's report on the 2016 4CP, PUCT Docket 46604 Item 13 (bib
#     ercot4cp2016puct), p. 2: the July peak "occurred at Interval Ending (IE)
#     16:00", the interval in which the East DC Tie tripped at 15:50; its
#     workbook labels that interval "7/14/2016 16:00";
#   * ERCOT Nodal Protocols sec. 10.9.1(2)(h) and 10.9.2(1)(h) (bib
#     ercot2026protocols): "Divide each hour into Settlement Intervals ending
#     as follows: XX:15:00 XX:30:00 XX:45:00 XX:00:00";
#   * for 2024, AEP Texas in PUCT Docket 58315 Item 53 (bib aeptexas58315):
#     the Docket 57491 matrix peaks, Sep 20 16:00 among them, "represent the
#     peaks at the 15-minute interval ending times".
# The committed demand series agrees: analysis/checks/ch8_4cp_peaks.R prints
# the check (on 23 of the 28 official days of 2019-2025 the quarter-hour
# ending at the label carried more demand than the one starting at it).
#
# read_official_4cp() returns the file with the derived columns every
# consumer uses, so no script derives the start on its own:
#   interval_ending_cpt  ERCOT's label, verbatim (the interval's end)
#   interval_start_cpt   label - 15 min, "HH:MM", the key the price and demand
#                        series use (both are stamped by interval start)
#   start_h              the start as a decimal hour, for clock-window rules
#   he                   the hour ending that contains the interval: label
#                        17:00 (16:45-17:00) is HE17, 17:45 is HE18, 16:00 is HE16
#   key                  paste(date, interval_start_cpt)
# No label is 00:00, which the function asserts, so subtracting fifteen
# minutes never changes the date or the weekday.
read_official_4cp <- function(path = "analysis/data/ercot_official_4cp_2018_2025.csv") {
  off <- read.csv(path, stringsAsFactors = FALSE)
  lab <- off$interval_ending_cpt
  stopifnot(!is.null(lab), grepl("^[0-2][0-9]:(00|15|30|45)$", lab), !any(lab == "00:00"))
  end <- as.POSIXct(paste(off$date, lab), format = "%Y-%m-%d %H:%M", tz = "UTC")   # clock arithmetic only
  start <- end - 900
  stopifnot(!anyNA(start), format(start, "%Y-%m-%d") == off$date)
  off$interval_start_cpt <- format(start, "%H:%M")
  off$start_h <- as.integer(format(start, "%H")) + as.integer(format(start, "%M")) / 60
  off$he <- as.integer(format(start, "%H")) + 1
  off$key <- paste(off$date, off$interval_start_cpt)
  off
}
