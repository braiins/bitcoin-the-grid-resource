# fetch_ercot_native_load.R: ERCOT's hourly Native Load archive, 2019 to
# date, as one small CSV. Run from the repo root:
#   Rscript analysis/data/fetch_ercot_native_load.R
#
# Source: ERCOT, "Hourly Load Data Archives",
#   https://www.ercot.com/gridinfo/load/load_hist
# one Native_Load_YYYY.zip per year, each holding an xlsx with the hourly
# load of the eight weather zones and the ERCOT total in MW, labelled by
# hour ending in Central prevailing time ("01/01/2019 01:00" ... "24:00").
# The spring-forward hour is absent and the repeated fall-back hour carries
# a " DST" suffix. ERCOT posts the previous month around the 9th, so the
# current year's file grows in place. Credential-free; ercot.com wants a
# browser User-Agent.
#
# Output: analysis/data/ercot_native_load_hourly_2019on.csv.gz, one row per
# hour: hour_ending (ERCOT's label, verbatim), start_utc (start of the hour,
# ISO 8601 UTC), ercot_mw (the ERCOT column). Chapter 8 uses it only to fill
# the gaps in the 15-minute system-demand cache (analysis/checks/ch8_demand.R).
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))
suppressMessages({ library(httr); library(readxl) })

UA   <- user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15")
PAGE <- "https://www.ercot.com/gridinfo/load/load_hist"
OUT  <- "analysis/data/ercot_native_load_hourly_2019on.csv.gz"

html  <- content(GET(PAGE, UA, timeout(120)), "text", encoding = "UTF-8")
links <- unique(regmatches(html, gregexpr("https://www\\.ercot\\.com/files/docs/[0-9/]+[Nn]ative_[Ll]oad_20[0-9]{2}\\.zip", html))[[1]])
yr    <- as.integer(sub(".*_(20[0-9]{2})\\.zip$", "\\1", links))
links <- links[yr >= 2019]; yr <- yr[yr >= 2019]
stopifnot(length(links) > 0, !anyDuplicated(yr))

tmp <- tempfile(); dir.create(tmp)
out <- list()
for (k in order(yr)) {
  y <- yr[k]; zf <- file.path(tmp, basename(links[k]))
  cat("GET", links[k], "\n")
  r <- GET(links[k], UA, timeout(300), write_disk(zf, overwrite = TRUE))
  stopifnot(status_code(r) == 200)
  xl <- unzip(zf, exdir = tmp)
  d <- read_excel(xl[grepl("\\.xlsx?$", xl, ignore.case = TRUE)][1], col_types = "text")
  lab <- d[[1]]
  # one 2022 label is stored as an Excel date serial rather than text
  num <- grepl("^[0-9]+(\\.[0-9]+)?$", lab)
  lab[num] <- format(as.POSIXct(round((as.numeric(lab[num]) - 25569) * 86400 / 60) * 60,
                                origin = "1970-01-01", tz = "UTC"), "%m/%d/%Y %H:%M")
  mw <- as.numeric(d[["ERCOT"]])
  keep <- !is.na(lab) & !is.na(mw)
  lab <- lab[keep]; mw <- mw[keep]
  # rows are chronological: hour i starts (i - 1) hours after local midnight
  # of January 1, which is 06:00 UTC (CST)
  start <- as.POSIXct(sprintf("%d-01-01 06:00:00", y), tz = "UTC") + (seq_along(lab) - 1) * 3600
  # check every label against the clock: the end of each hour, in Central
  # prevailing time, with midnight written as 24:00 of the previous day
  end_local <- start + 3600
  chk <- format(end_local, "%m/%d/%Y %H:%M", tz = "America/Chicago")
  mid <- format(end_local, "%H:%M", tz = "America/Chicago") == "00:00"
  chk[mid] <- paste(format(end_local[mid] - 60, "%m/%d/%Y", tz = "America/Chicago"), "24:00")
  bad <- chk != sub(" DST$", "", lab)
  # ERCOT writes the two transition hours by its own convention: on the
  # spring-forward day the hour 01:00-02:00 CST is "02:00" (the clock reads
  # 03:00 CDT at its end), and on the fall-back day the first 01:00-02:00
  # (CDT) is "02:00" (the clock reads 01:00 CST at its end). Accept exactly
  # those two, and nothing else.
  off <- format(start, "%z", tz = "America/Chicago") != format(end_local, "%z", tz = "America/Chicago")
  ok_dst <- bad & off & substr(chk, 1, 10) == substr(lab, 1, 10) &
    substr(lab, 12, 16) == "02:00" & substr(chk, 12, 16) %in% c("01:00", "03:00")
  if (any(bad & !ok_dst)) stop(sprintf("%d: %d labels do not match the clock, first %s vs %s",
                                       y, sum(bad & !ok_dst), lab[bad & !ok_dst][1], chk[bad & !ok_dst][1]))
  out[[as.character(y)]] <- data.frame(hour_ending = lab,
                                       start_utc = format(start, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                                       ercot_mw = round(mw, 2))
  cat(sprintf("  %d: %d hours, %s to %s\n", y, length(lab), lab[1], lab[length(lab)]))
}
nl <- do.call(rbind, out)
stopifnot(!anyDuplicated(nl$start_utc))
con <- gzfile(OUT, "w"); write.csv(nl, con, row.names = FALSE); close(con)
cat(sprintf("Wrote %s: %d hours, %s to %s\n", OUT, nrow(nl), nl$hour_ending[1], nl$hour_ending[nrow(nl)]))
