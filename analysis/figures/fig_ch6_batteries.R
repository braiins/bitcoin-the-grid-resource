# fig_ch6_batteries.R, Chapter 6: batteries vs the spreads miners feed on
# Output: book/images/batteries_spreads.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch6_batteries.R
#
# Top panel: cumulative ERCOT battery nameplate capacity (EIA-860M, July
# 2026 edition: operating units by their operating date; retirement-blind,
# which for batteries is a negligible simplification). Bottom panel: the
# monthly mean DAILY price spread (max minus min of the day's hourly DAM
# prices, Central time) at LZ_WEST, the spread a storage asset or a
# flexible load arbitrages. Console prints the values quoted in the text.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages({ library(ggplot2); library(patchwork) })

# battery capacity by month
cap <- read.csv("analysis/data/ercot_capacity_additions_2026-07.csv")
b <- cap[cap$group == "battery", ]
b$ym <- as.Date(sprintf("%d-%02d-01", b$op_year, b$op_month))
months <- seq(as.Date("2021-01-01"), as.Date("2026-07-01"), by = "month")
cum <- vapply(months, function(m) sum(b$mw[b$ym <= m]) / 1000, numeric(1))
bat <- data.frame(month = months, gw = cum)

# monthly mean daily DAM spread, LZ_WEST, Central time
# NOTE (2026-09-04): repointed off ercot_spp_dam_rtm15_8zones.csv.gz, which
# stamps Central time as a fixed UTC-6 offset (daylight-saving hours land an
# hour late) and drops the nine spring-forward intervals. Both replacements
# carry Central prevailing time natively, from ERCOT's own MIS archive.
z <- read.csv("analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz")
z <- z[z$settlement_point == "LZ_WEST", ]
t <- as.POSIXct(z$hour_start, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Chicago")
day <- as.Date(t, tz = "America/Chicago")
spread_by_day <- tapply(z$price, day, function(v) max(v) - min(v))
mo <- as.Date(format(as.Date(names(spread_by_day)), "%Y-%m-01"))
sp <- data.frame(month = unique(mo),
                 spread = as.numeric(tapply(spread_by_day, mo, mean)))
sp <- sp[sp$month >= as.Date("2024-01-01") & sp$month <= as.Date("2026-03-01"), ]

ink <- "#3a3a3a"

pa <- ggplot(bat[bat$month >= as.Date("2021-01-01"), ], aes(month, gw)) +
  geom_area(fill = "grey85") +
  geom_line(color = ink, linewidth = 0.55) +
  labs(x = NULL, y = "Battery capacity (GW)",
       subtitle = "(a) ERCOT grid batteries: nameplate capacity") +
  scale_x_date(limits = c(as.Date("2021-01-01"), as.Date("2026-07-01")),
               date_breaks = "1 year", date_labels = "%Y") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(4, 8, 2, 4))

pb <- ggplot(sp, aes(month, spread)) +
  geom_col(fill = "grey60", width = 24) +
  geom_smooth(method = "lm", se = FALSE, color = ink, linewidth = 0.5,
              linetype = "31") +
  labs(x = NULL, y = "Mean daily spread (USD/MWh)",
       subtitle = "(b) The daily high-minus-low of LZ_WEST day-ahead prices") +
  scale_x_date(limits = c(as.Date("2024-01-01"), as.Date("2026-04-01")),
               date_breaks = "6 months", date_labels = "%b %Y") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(2, 8, 2, 4))

p <- pa / pb
ggsave("book/images/batteries_spreads.png", p,
       width = 124, height = 108, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/batteries_spreads.pdf", p,
       width = 124, height = 108, units = "mm", bg = "white")

for (y in c("2024", "2025")) {
  v <- spread_by_day[format(as.Date(names(spread_by_day)), "%Y") == y]
  cat(sprintf("mean daily DAM spread %s: $%.1f\n", y, mean(v)))
}
cat(sprintf("battery GW: 2024-01 %.1f -> 2025-01 %.1f -> 2026-01 %.1f -> 2026-07 %.1f\n",
            bat$gw[bat$month == as.Date("2024-01-01")],
            bat$gw[bat$month == as.Date("2025-01-01")],
            bat$gw[bat$month == as.Date("2026-01-01")],
            bat$gw[bat$month == as.Date("2026-07-01")]))
cat("Wrote book/images/batteries_spreads.png and .pdf\n")
