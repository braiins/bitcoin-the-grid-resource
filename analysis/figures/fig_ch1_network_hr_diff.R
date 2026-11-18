# fig_ch1_network_hr_diff.R, Chapter 1: network hashrate & difficulty
# Output: book/images/network_hr_diff_v2.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch1_network_hr_diff.R
#
# Paired logarithmic and linear full-history panels with a shared event key.
# The same committed observations are used in both views.
# Data: Braiins Insights API (global hashrate series + difficulty), read from the
# committed snapshot analysis/data/braiins_hashrate_difficulty_all.json
# (retrieved 2026-09-14: 104 points, 2009-03-19 to 2026-09-14).
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
library(httr)
library(jsonlite)
library(dplyr)
library(ggplot2)
library(patchwork)
library(scales)

# The Braiins Insights endpoint returns a ROLLING window that always ends at the
# moment of the request, so fetching live at build time makes the printed figure
# unreproducible: a later run draws a different chart. Read the committed
# snapshot by default. To refresh it deliberately, run with REFRESH=1, which
# overwrites the snapshot and leaves the change visible in the diff.
url  <- "https://learn.braiins.com/api/v1.0/hashrate-and-difficulty-history?timeframe=all"
snap <- "analysis/data/braiins_hashrate_difficulty_all.json"

if (identical(Sys.getenv("REFRESH"), "1") || !file.exists(snap)) {
  resp <- GET(url, config(followlocation = TRUE))
  stopifnot(status_code(resp) == 200)
  writeLines(content(resp, as = "text", encoding = "UTF-8"), snap)
  message("refreshed snapshot: ", snap)
}
raw <- fromJSON(snap)

difficulty_df <- bind_rows(raw$difficulty) %>%
  mutate(date = as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%OS")) %>%
  transmute(date, difficulty = y)

hashrate_df <- bind_rows(
  lapply(raw$hashrate, function(series) {
    bind_rows(series) %>%
      mutate(x = as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%OS"))
  }),
  .id = "manufacturer"
) %>%
  filter(manufacturer == "global") %>%
  group_by(x) %>%
  summarise(hashrate_eh = sum(y), .groups = "drop")

combined_df <- inner_join(difficulty_df, hashrate_df, by = c("date" = "x")) %>%
  filter(date >= as.POSIXct("2010-07-01"), hashrate_eh > 0, difficulty > 0)

events <- data.frame(
  date = as.POSIXct(c("2012-11-28", "2016-07-09", "2020-05-11", "2021-06-21",
                      "2024-04-20", "2026-02-17")),
  label = c("1st halving", "2nd halving", "3rd halving", "China ban",
            "4th halving", "2026 pullback"),
  row = c(1, 1, 1, 2, 1, 2)  # staggered label rows above the top panel
)

ink <- "#3a3a3a"
event_col <- "grey55"

hr_breaks <- c(1e-9, 1e-6, 1e-3, 1, 1e3)
hr_labels <- c("1 GH/s", "1 TH/s", "1 PH/s", "1 EH/s", "1 ZH/s")

# Identical limits, ticks, observations and event guides in every panel.
# Letter labels avoid six overlapping event names at A5 print size; the full
# descriptions are printed in a shared key immediately below the panels.
events$key <- LETTERS[seq_len(nrow(events))]
x_limits <- as.POSIXct(c("2010-07-01", "2027-01-01"))
x_breaks <- as.POSIXct(paste0(seq(2012, 2024, 4), "-01-01"))
book_theme <- theme_minimal(base_size = 8) +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        plot.title = element_text(size = 8, face = "bold", margin = margin(b = 10)),
        axis.title.y = element_text(size = 8),
        plot.margin = margin(9, 4, 3, 2))
plot_series <- function(data, variable, title, ylab) {
  ggplot(data, aes(x = date, y = .data[[variable]])) +
    geom_vline(xintercept = events$date, color = "grey65",
               linetype = "dashed", linewidth = 0.25) +
    geom_line(color = ink, linewidth = 0.5) +
    geom_text(data = events, aes(x = date, y = Inf, label = key),
              inherit.aes = FALSE, vjust = -0.5, size = 2.1, color = "grey35") +
    scale_x_datetime(limits = x_limits, breaks = x_breaks, date_labels = "%Y",
                     expand = expansion(mult = 0)) +
    coord_cartesian(clip = "off") +
    labs(title = title, y = ylab, x = NULL) + book_theme
}
p1 <- plot_series(combined_df, "hashrate_eh", "Logarithmic", "Hashrate") +
  scale_y_log10(breaks = hr_breaks, labels = hr_labels,
               limits = c(1e-9, 2e3))
p2 <- plot_series(combined_df, "difficulty", "", "Difficulty") +
  scale_y_log10(breaks = 10^seq(2, 14, 4), labels = trans_format("log10", math_format(10^.x)),
               limits = c(1e2, 5e14))
p3 <- plot_series(combined_df, "hashrate_eh", "Linear", "Hashrate (EH/s)") +
  scale_y_continuous(limits = c(0, 1150), breaks = c(0, 500, 1000))
p4 <- plot_series(mutate(combined_df, difficulty = difficulty / 1e12), "difficulty", "", "Difficulty (trillion)") +
  scale_y_continuous(limits = c(0, NA))
event_key <- data.frame(
  x = rep(c(0, 0.53), each = 3), y = rep(3:1, 2),
  label = paste0(events$key, "  ", events$label, " (", format(events$date, "%Y"), ")"))
event_key$label[6] <- "F  2026 pullback"
key_plot <- ggplot(event_key, aes(x, y, label = label)) +
  geom_text(hjust = 0, size = 2.5, color = ink) +
  scale_x_continuous(limits = c(0, 1), expand = expansion(mult = 0)) +
  scale_y_continuous(limits = c(0.5, 3.5), expand = expansion(mult = 0)) +
  theme_void() + theme(plot.margin = margin(3, 4, 0, 8))
p <- wrap_plots(p1, p3, p2, p4, key_plot, design = "AB\nCD\nEE",
                heights = c(1, 1, 0.29))
ggsave("book/images/network_hr_diff_v2.png", p,
       width = 124, height = 118, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/network_hr_diff_v2.pdf", p,
       width = 124, height = 118, units = "mm", bg = "white")
cat("Data through:", format(max(combined_df$date)), "\n")
cat("Wrote book/images/network_hr_diff_v2.png and .pdf\n")
