# fig_ch6_duck.R, Chapter 6: what renewables did to the shape of the day
# Output: book/images/duck_lzwest.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch6_duck.R
#
# Two panels, LZ_WEST, Central time:
#   (a) average hourly DAM price by hour of day, per year (2024, 2025):
#       the deepening midday solar trough and the evening ramp;
#   (b) share of 15-minute settlement intervals with a NEGATIVE price,
#       by hour of day, per year.
# Data, both stamped in Central prevailing time at source (see the note below):
#   day-ahead  analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz (ERCOT MIS 13060)
#   real-time  analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz (ERCOT MIS 13061)
# NOTE (2026-09-04): this figure previously read ercot_spp_dam_rtm15_8zones.csv.gz,
# which stores Central time as a fixed UTC-6 offset and therefore labels every
# daylight-saving hour an hour late. For an hour-of-day figure that is fatal: it
# put the solar trough at hour 12 instead of 11 and the evening peak at 21
# instead of 20, and understated the evening ramp by about $13/MWh.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages({ library(ggplot2); library(patchwork) })

d <- read.csv("analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz")
d <- d[d$settlement_point == "LZ_WEST", ]
d$hour <- as.integer(substr(d$hour_start, 12, 13))
d$year <- substr(d$hour_start, 1, 4)
dam <- d[d$year %in% c("2024", "2025"), ]
prof <- aggregate(price ~ hour + year, dam, mean)

r <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
r <- r[r$settlement_point == "LZ_WEST", ]
r$hour <- as.integer(substr(r$interval_start, 12, 13))
r$year <- substr(r$interval_start, 1, 4)
rtm <- r[r$year %in% c("2024", "2025"), ]
rtm$neg <- rtm$price < 0
negs <- aggregate(neg ~ hour + year, rtm, function(v) 100 * mean(v))

ink <- "#3a3a3a"

pa <- ggplot(prof, aes(hour, price, linetype = year)) +
  geom_line(color = ink, linewidth = 0.55) +
  scale_linetype_manual(values = c(`2024` = "31", `2025` = "solid")) +
  scale_x_continuous(breaks = seq(0, 24, 6),
                     labels = function(h) sprintf("%02d:00", h)) +
  labs(x = NULL, y = "Mean DAM price (USD/MWh)", linetype = NULL,
       subtitle = "(a) The average day, hour by hour") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom",
        legend.text = element_text(size = 7),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(4, 8, 0, 4))

pb <- ggplot(negs, aes(hour, neg, linetype = year)) +
  geom_line(color = ink, linewidth = 0.55) +
  scale_linetype_manual(values = c(`2024` = "31", `2025` = "solid"),
                        guide = "none") +
  scale_x_continuous(breaks = seq(0, 24, 6),
                     labels = function(h) sprintf("%02d:00", h)) +
  labs(x = "Hour of day (Central time)",
       y = "Negative intervals (%)",
       subtitle = "(b) How often the price went below zero") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(0, 8, 2, 4))

p <- pa / pb + plot_layout(heights = c(1.2, 1))
ggsave("book/images/duck_lzwest.png", p,
       width = 124, height = 112, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/duck_lzwest.pdf", p,
       width = 124, height = 112, units = "mm", bg = "white")

for (y in c("2024", "2025")) {
  r <- rtm[rtm$year == y, ]
  cat(sprintf("%s: negative rtm15 share %.1f%%; midday (11-15h) DAM mean $%.1f; evening (18-21h) $%.1f\n",
              y, 100 * mean(r$neg),
              mean(dam$price[dam$year == y & dam$hour %in% 11:14]),
              mean(dam$price[dam$year == y & dam$hour %in% 18:20])))
}
cat("Wrote book/images/duck_lzwest.png and .pdf\n")
