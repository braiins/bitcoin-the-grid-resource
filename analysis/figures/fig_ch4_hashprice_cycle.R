# fig_ch4_hashprice_cycle.R, Chapter 4: hashprice, bitcoin price, and hashrate
# Output: book/images/hashprice_cycle.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch4_hashprice_cycle.R
#
# Three stacked panels sharing the x axis (Jan 2024 - Aug 2026): bitcoin
# price, network hashrate, and hashprice, with the April 20, 2024 halving
# marked. Together they show the feedback loop: a rising price lifts
# hashprice, high hashprice attracts hashrate, new hashrate dilutes
# hashprice; and in 2026 the loop runs backward.
#
# Data: Braiins Insights public API (no auth). Each timeframe returns at
# most 500 chart points, so a single 5y call is ~3.6-day resolution. This
# script stitches timeframes (5y, 2y, 1y, 6m, 3m), keeping the
# highest-resolution frame covering each date, then interpolates to a daily
# grid. Effective resolution: daily from Aug 2024 onward (2y frame and
# finer); Jan-Aug 2024 rests on the 5y frame (~3.6-day spacing,
# interpolated). The same stitching is used by the author's fleet
# calculator export.
#   price + hashrate: /api/v1.0/hashrate-and-difficulty-history
#   hashprice:        /api/v1.0/hashrate-value-history (key hashrate_price)
# Cached copies in analysis/data/ (rebuilt here if missing).
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages({ library(ggplot2); library(jsonlite) })

dir.create("analysis/data", showWarnings = FALSE)
hp_path  <- "analysis/data/hashprice_daily.csv"
btc_path <- "analysis/data/btc_price_daily.csv"
hr_path  <- "analysis/data/network_hashrate_daily.csv"

fetch_stitched_daily <- function(endpoint, key, from = as.Date("2024-01-01")) {
  frames <- c("5y", "2y", "1y", "6m", "3m")  # coarse to fine; finer overwrite
  pts <- NULL
  for (tf in frames) {
    u <- sprintf("https://insights.braiins.com/api/v1.0/%s?timeframe=%s",
                 endpoint, tf)
    usable <- function(s) !is.null(s) && !is.null(s$x) && !is.null(s$y) &&
      length(s$y) > 0
    s <- NULL
    for (attempt in 1:4) {
      # the series arrives as a data.frame of x/y, except "hashrate", which
      # nests its data.frame one level down under $global
      s <- tryCatch(fromJSON(u)[[key]], error = function(e) NULL)
      if (!is.null(s$global)) s <- s$global
      if (usable(s)) break
      Sys.sleep(2 * attempt)
    }
    if (!usable(s)) {
      stop("no usable response for ", endpoint, " timeframe ", tf)
    }
    df <- data.frame(date = as.Date(substr(s$x, 1, 10)), y = s$y)
    Sys.sleep(1)
    df <- aggregate(y ~ date, df, mean)
    if (is.null(pts)) {
      pts <- df
    } else {
      keep <- pts[pts$date < min(df$date), ]
      pts <- rbind(keep, df)
    }
  }
  grid <- data.frame(date = seq(max(from, min(pts$date)), max(pts$date), by = "day"))
  grid$y <- approx(as.numeric(pts$date), pts$y, xout = as.numeric(grid$date))$y
  grid[!is.na(grid$y), ]
}

if (!file.exists(hp_path)) {
  d <- fetch_stitched_daily("hashrate-value-history", "hashrate_price")
  names(d)[2] <- "usd_th_day"
  write.csv(d, hp_path, row.names = FALSE)
}
if (!file.exists(btc_path)) {
  d <- fetch_stitched_daily("hashrate-and-difficulty-history", "price")
  names(d)[2] <- "usd"
  write.csv(d, btc_path, row.names = FALSE)
}
if (!file.exists(hr_path)) {
  d <- fetch_stitched_daily("hashrate-and-difficulty-history", "hashrate")
  # API returns EH/s directly (~100 points per timeframe, coarser than price)
  names(d)[2] <- "ehs"
  write.csv(d, hr_path, row.names = FALSE)
}

hp  <- read.csv(hp_path);  hp$date  <- as.Date(hp$date)
btc <- read.csv(btc_path); btc$date <- as.Date(btc$date)
hr  <- read.csv(hr_path);  hr$date  <- as.Date(hr$date)

halving <- as.Date("2024-04-20") # block 840,000; subsidy 6.25 -> 3.125 BTC

panels <- rbind(
  data.frame(date = btc$date, value = btc$usd / 1000,
             panel = "Bitcoin price (thousand USD)"),
  data.frame(date = hr$date, value = hr$ehs,
             panel = "Network hashrate (EH/s)"),
  data.frame(date = hp$date, value = hp$usd_th_day,
             panel = "Hashprice (USD/TH/day)")
)
panels$panel <- factor(panels$panel, levels = unique(panels$panel))

# ATH: intraday record $126,198 on Oct 6, 2025 (widely reported); this
# daily-snapshot series tops out at $123,840 on Oct 7 because it clips
# intraday spikes -- hence "~$126,000" as the event annotation.
ann <- data.frame(
  panel = factor(c("Hashprice (USD/TH/day)", "Bitcoin price (thousand USD)"),
                 levels = levels(panels$panel)),
  x = c(halving, as.Date("2025-10-06")),
  y = c(0.115, 128),
  label = c("halving:\nblock subsidy halves", "all-time high ~$126,000 (Oct 2025)"),
  hjust = c(-0.06, 1.02)
)

ink <- "#3a3a3a"

p <- ggplot(panels, aes(date, value)) +
  geom_vline(xintercept = as.numeric(halving), linetype = "dashed",
             color = "grey45", linewidth = 0.4) +
  geom_line(color = ink, linewidth = 0.45) +
  geom_text(data = ann, aes(x, y, label = label, hjust = hjust),
            size = 2.3, lineheight = 0.95, color = "grey35", vjust = 1) +
  facet_wrap(~panel, ncol = 1, scales = "free_y", strip.position = "left") +
  scale_x_date(date_breaks = "6 months", date_labels = "%b %Y",
               expand = expansion(mult = c(0.02, 0.02))) +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.minor = element_blank(),
    strip.placement = "outside",
    strip.text = element_text(size = 7.5, color = "grey20"),
    plot.margin = margin(6, 8, 4, 4)
  )

ggsave("book/images/hashprice_cycle.png", p,
       width = 124, height = 128, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/hashprice_cycle.pdf", p,
       width = 124, height = 128, units = "mm", bg = "white")

# ---- console stats used by the chapter text (% src anchors) ---------------
j <- merge(hp, btc, by = "date")
r_win <- function(d0, d1 = NULL) {
  s <- j[j$date >= as.Date(d0) & (if (is.null(d1)) TRUE else j$date <= as.Date(d1)), ]
  c(n = nrow(s), r = round(cor(s$usd_th_day, s$usd), 3))
}
cat("corr full 2024-2026:", r_win("2024-01-01"), "\n")
cat("corr post-halving:  ", r_win("2024-04-21"), "\n")
cat("corr 2025:          ", r_win("2025-01-01", "2025-12-31"), "\n")
cat("corr 2026 YTD:      ", r_win("2026-01-01"), "\n")
land <- function(d) {
  i <- which.min(abs(hr$date - as.Date(d)))
  cat(sprintf("hashrate %s: %.0f EH/s\n", hr$date[i], hr$ehs[i]))
}
land("2024-01-01"); land("2026-01-31"); cat("hashrate max:", round(max(hr$ehs)),
    "EH/s on", format(hr$date[which.max(hr$ehs)]), "\n"); land(max(hr$date))
cat("Wrote book/images/hashprice_cycle.png and .pdf\n")
