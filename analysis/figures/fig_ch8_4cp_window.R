# fig_ch8_4cp_window.R, Chapter 8: the size of the haystack
# Output: book/images/fourcp_window.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch8_4cp_window.R
#
# For each summer, how many hours of 15-minute intervals came within 2% and
# within 5% of the eventual monthly peak, summed over June-September, and
# on how many distinct days. This is the minimum a load would have had to
# pause if it wanted to be certain of covering the peak while only
# knowing the peak's size to within that tolerance; it is what a 4CP
# forecast is paid to shrink. Data: analysis/data/ercot_fuel_mix_15min_2019on.csv.gz,
# checked for completeness without gap-fill by analysis/checks/ch8_demand.R
# (which returns complete months only).
# The summers are pinned to 2019-2025, the seven complete summers the chapter's
# medians (66 h over 22 days within 2%, 196 h over 46 days within 5%) and
# chapter 9's 66-hour haystack are taken from. A later summer is not picked
# up when the series is extended (author decision 2026-10-04), so a refresh
# of the fuel-mix cache leaves this figure and its console unchanged; adding
# a summer is an edit to SUMMERS below and to every line that quotes them.
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))
suppressMessages(library(ggplot2))
source("analysis/checks/ch8_demand.R")

SUMMERS <- 2019:2025
z <- load_demand()
z$year <- as.integer(substr(z$deliveryDate, 1, 4))
z$month <- as.integer(substr(z$deliveryDate, 6, 7))
z <- z[z$month %in% 6:9 & z$year %in% SUMMERS, ]
years <- SUMMERS
stopifnot(all(sapply(years, function(y) length(unique(z$month[z$year == y])) == 4)))  # every pinned summer complete

rows <- do.call(rbind, lapply(years, function(y) do.call(rbind, lapply(c(0.02, 0.05), function(tol) {
  hrs <- 0; fh <- 0; days <- character(0)
  for (m in 6:9) {
    s <- z[z$year == y & z$month == m, ]
    sel <- s$demand >= max(s$demand) * (1 - tol)
    hrs <- hrs + sum(sel) / 4
    fh <- fh + sum(sel & s$filled) / 4
    days <- c(days, unique(s$deliveryDate[sel]))
  }
  data.frame(year = y, tol = sprintf("within %d%% of the peak", round(100 * tol)),
             hours = hrs, days = length(days), filled_hours = fh)
}))))

ink <- "#3a3a3a"
p <- ggplot(rows, aes(factor(year), hours, fill = tol)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.62) +
  geom_text(aes(label = sprintf("%d d", days)), position = position_dodge(width = 0.7),
            vjust = -0.4, size = 2.1, color = "grey30") +
  scale_fill_manual(values = c("#3a3a3a", "grey72"), name = NULL) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
  labs(x = NULL, y = "Hours per summer near a monthly peak") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
        legend.position = "top", legend.text = element_text(size = 7),
        legend.key.size = unit(3, "mm"),
        plot.margin = margin(4, 8, 2, 4))

ggsave("book/images/fourcp_window.png", p, width = 124, height = 82, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/fourcp_window.pdf", p, width = 124, height = 82, units = "mm", bg = "white")
print(rows, row.names = FALSE)
cat("(filled_hours: zero; the ERCOT fuel-mix proxy needs no gap-fill)\n")
w2 <- rows[rows$tol == "within 2% of the peak", ]
cat(sprintf("within 2%%: %.0f-%.0f h over %d-%d days per summer (median %.0f h, %.0f days)\n",
            min(w2$hours), max(w2$hours), min(w2$days), max(w2$days), median(w2$hours), median(w2$days)))
w5 <- rows[rows$tol == "within 5% of the peak", ]
cat(sprintf("within 5%%: %.0f-%.0f h over %d-%d days per summer (median %.0f h, %.0f days)\n",
            min(w5$hours), max(w5$hours), min(w5$days), max(w5$days), median(w5$hours), median(w5$days)))
cat("Wrote book/images/fourcp_window.png and .pdf\n")
