# fig_ch9_btm.R -- Chapter 9: the behind-the-meter indifference price, from
# analysis/data/ch9_btm_indifference.csv and ch9_optimal_stack.csv (written by
# analysis/checks/ch9_optimal_stack.R). Run from the repo root:
#   Rscript analysis/figures/fig_ch9_btm.R
# Output: book/images/ch9_btm.png (+ .pdf).
# For each year, the negotiated price at which a firm behind-the-meter supply
# earns the reference fleet exactly what the grid-connected site earns: against
# the planned site (annual switches set in advance, the chapter's headline),
# against the best annual choice in hindsight (the ceiling), and against the
# same site never pausing. The price range tested is shaded, from the wind
# captured price ($19) to the flat grid price with the peaks dodged ($45); the
# year's mean LZ_WEST settlement price is marked.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages(library(ggplot2))
ind <- read.csv("analysis/data/ch9_btm_indifference.csv", stringsAsFactors = FALSE)
r <- read.csv("analysis/data/ch9_optimal_stack.csv", stringsAsFactors = FALSE)
f <- ind[ind$variant == "firm", ]
LV <- c("mean LZ_WEST settlement price", "vs the grid site never pausing",
        "vs the planned grid site", "vs the best annual choice in hindsight")
f$series <- factor(c(never = LV[2], planned = LV[3], hindsight = LV[4])[f$reference], levels = LV)
mp <- data.frame(year = r$year, p_star = r$mean_price, series = factor(LV[1], levels = LV))
lo <- -140; hi <- 215
f$shown <- pmax(pmin(f$p_star, hi), lo)
# labels: never above its point, planned above-left, hindsight below-right and
# only where it differs from the planned site
pl <- f$p_star[f$reference == "planned"][match(f$year, f$year[f$reference == "planned"])]
f$lx <- f$year + c(never = 0, planned = -0.1, hindsight = 0.1)[f$reference]
f$ly <- f$shown + c(never = 11, planned = 6, hindsight = -8)[f$reference]
f$hj <- c(never = 0.5, planned = 1, hindsight = 0)[f$reference]
f$ly[f$year == 2023 & f$reference == "planned"] <- f$ly[f$year == 2023 & f$reference == "planned"] + 6   # off the dotted path
f$show_lab <- !(f$reference == "hindsight" & abs(f$p_star - pl) < 0.5)
# 2022 planned label goes right of its dot, into the gap between
# the never-pausing and mean-price lines
k <- f$year == 2022 & f$reference == "planned"
f$lx[k] <- 2022.1; f$ly[k] <- 73; f$hj[k] <- 0
band <- data.frame(xmin = 2020.5, xmax = 2025.5, ymin = unique(ind$band_lo), ymax = unique(ind$band_hi))
p <- ggplot() +
  geom_rect(data = band, aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax), fill = "grey88") +
  # band label just below the band, clear of the lines and labels above
  annotate("text", x = 2022.55, y = 12, hjust = 0, size = 2.0, color = "grey35",
           label = "$19 (wind captured price) to $45 (flat grid price, peaks dodged)") +
  geom_hline(yintercept = 0, color = "grey60", linewidth = 0.3) +
  geom_line(data = mp, aes(year, p_star, linetype = series), color = "grey55", linewidth = 0.5) +
  geom_point(data = mp, aes(year, p_star, shape = series), color = "grey55", size = 1.5) +
  geom_line(data = f, aes(year, shown, group = series, linetype = series), color = "grey20", linewidth = 0.6) +
  geom_point(data = f, aes(year, shown, shape = series), color = "grey20", size = 2.1, fill = "white") +
  # value labels on a white backing so lines pass behind them
  geom_label(data = f[f$show_lab, ], aes(lx, ly, label = ifelse(p_star < 0, sprintf("-$%.0f", -p_star), sprintf("$%.0f", p_star)), hjust = hj), size = 2.3, color = "grey20",
             fill = "white", label.size = NA, label.padding = unit(0.6, "pt"), label.r = unit(0, "pt")) +
  scale_shape_manual(values = c(4, 21, 19, 23), name = NULL, drop = FALSE) +
  scale_linetype_manual(values = c("31", "dashed", "solid", "dotted"), name = NULL, drop = FALSE) +
  scale_x_continuous(breaks = 2021:2025) +
  scale_y_continuous(breaks = seq(-100, 200, 50), labels = function(v) ifelse(v < 0, sprintf("-$%d", -v), sprintf("$%d", v))) +
  coord_cartesian(ylim = c(lo, hi), xlim = c(2020.5, 2025.5), expand = FALSE) +
  guides(shape = guide_legend(nrow = 2), linetype = guide_legend(nrow = 2)) +
  labs(x = NULL, y = "Firm behind-the-meter price (USD/MWh)",
       subtitle = "Below a line the behind-the-meter deal wins; above it the grid site does") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), legend.position = "top", legend.justification = "left",
        legend.text = element_text(size = 7), legend.key.width = unit(9, "mm"), legend.key.height = unit(3.5, "mm"),
        legend.margin = margin(0, 0, 0, 0),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(4, 8, 2, 4))
ggsave("book/images/ch9_btm.png", p, width = 124, height = 108, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/ch9_btm.pdf", p, width = 124, height = 108, units = "mm", bg = "white")
print(f[, c("year", "reference", "p_star")], row.names = FALSE)
cat("Wrote book/images/ch9_btm.png and .pdf\n")
