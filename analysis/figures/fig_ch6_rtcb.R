# fig_ch6_rtcb.R, Chapter 6: real-time volatility before and after RTC+B
# Output: book/images/rtcb_volatility.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch6_rtcb.R
#
# RTC+B went live December 5, 2025. Season-matched comparison of LZ_WEST
# 15-minute settlement prices over the two windows Dec 5 - Apr 20:
# 2024-25 (the last pre-RTC+B winter) vs 2025-26 (the first post-RTC+B
# winter). Duration curves on a log scale plus the summary statistics the
# text quotes. One-winter sample, and each window contains a winter storm
# (Kingston in Feb 2025; Fern in Jan 2026): a first look, not a verdict.
# Data: analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz (ERCOT MIS 13061).
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages(library(ggplot2))

# NOTE (2026-09-04): repointed off ercot_spp_dam_rtm15_8zones.csv.gz, which
# stamps Central time as a fixed UTC-6 offset (daylight-saving hours land an
# hour late) and drops the nine spring-forward intervals. Both replacements
# carry Central prevailing time natively, from ERCOT's own MIS archive.
z <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
z <- z[z$settlement_point == "LZ_WEST", ]
t <- as.POSIXct(z$interval_start, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Chicago")

win <- function(t0, t1) z$price[t >= as.POSIXct(t0, tz = "America/Chicago") &
                                t <  as.POSIXct(t1, tz = "America/Chicago")]
pre  <- win("2024-12-05", "2025-04-21")
post <- win("2025-12-05", "2026-04-21")

stats <- function(v) c(n = length(v), mean = mean(v), sd = sd(v),
                       p95 = quantile(v, .95), p99 = quantile(v, .99),
                       gt100 = 100 * mean(v > 100), neg = 100 * mean(v < 0),
                       max = max(v))
cat("pre  (Dec 2024 - Apr 2025):", sprintf("%.2f", stats(pre)), "\n")
cat("post (Dec 2025 - Apr 2026):", sprintf("%.2f", stats(post)), "\n")

dur <- rbind(
  data.frame(win = "Dec 2024 - Apr 2025 (before RTC+B)",
             pct = 100 * seq_along(pre) / length(pre),
             price = sort(pre, decreasing = TRUE)),
  data.frame(win = "Dec 2025 - Apr 2026 (after RTC+B)",
             pct = 100 * seq_along(post) / length(post),
             price = sort(post, decreasing = TRUE))
)

ink <- "#3a3a3a"
# The before curve gets its own color AND a longer dash so the two windows
# stay distinguishable at A5 print size (same-ink fine dashes read as one
# solid line); direct labels replace squinting at the legend.
p <- ggplot(dur, aes(pct, pmax(price, 1), linetype = win, color = win)) +
  geom_line(linewidth = 0.55) +
  scale_linetype_manual(values = setNames(c("42", "solid"), unique(dur$win))) +
  scale_color_manual(values = setNames(c("grey55", ink), unique(dur$win))) +
  annotate("text", x = 44, y = 47, label = "before RTC+B",
           hjust = 0, size = 2.5, color = "grey45") +
  annotate("text", x = 33, y = 16.5, label = "after RTC+B",
           hjust = 1, size = 2.5, color = ink, fontface = "bold") +
  scale_y_log10(breaks = c(1, 10, 100, 1000), labels = scales::comma) +
  labs(x = "Share of 15-minute intervals (%)",
       y = "Price (USD/MWh, log)", linetype = NULL, color = NULL) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom",
        legend.text = element_text(size = 7),
        legend.key.width = unit(9, "mm"),
        plot.margin = margin(6, 8, 2, 4))

ggsave("book/images/rtcb_volatility.png", p,
       width = 124, height = 88, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/rtcb_volatility.pdf", p,
       width = 124, height = 88, units = "mm", bg = "white")
cat("Wrote book/images/rtcb_volatility.png and .pdf\n")
