# fig_ch10_hashprice_sensitivity.R -- Chapter 10: the flexibility stack as
# hashprice falls, for chapter 9's reference site on 2025 LZ_WEST prices.
# Data: analysis/data/ch10_hashprice_sensitivity.csv (ch10_hashprice_sensitivity.R).
# Run from the repo root: Rscript analysis/figures/fig_ch10_hashprice_sensitivity.R
# Output: book/images/ch10_hashprice_sensitivity.png (+ .pdf).
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages({ library(ggplot2); library(patchwork) })
d <- read.csv("analysis/data/ch10_hashprice_sensitivity.csv", stringsAsFactors = FALSE)
s <- d[grepl("^2025", d$case), ]; s$pct <- 100 * s$hp_factor
lines <- rbind(data.frame(pct = s$pct, usd = s$never_total / 1e6, series = "never pausing"),
               data.frame(pct = s$pct, usd = s$optimal_total / 1e6, series = "optimal stack"))
pa <- ggplot(lines, aes(pct, usd, linetype = series, shape = series)) +
  geom_hline(yintercept = 0, color = "grey60", linewidth = 0.3) +
  geom_line(color = "grey20", linewidth = 0.6) + geom_point(color = "grey20", size = 2, fill = "white") +
  geom_text(data = s, aes(pct, optimal_total / 1e6 + 7, label = sprintf("+$%.1fM", flex_value / 1e6)), inherit.aes = FALSE, size = 2.2, color = "grey25") +
  scale_x_reverse(breaks = s$pct, labels = sprintf("%d%%\n$%.4f\n$%.0f / $%.0f", s$pct, s$hp_mean, s$strike19, s$strike21), expand = expansion(mult = 0.06)) +
  scale_linetype_manual(values = c("dashed", "solid"), name = NULL) + scale_shape_manual(values = c(21, 19), name = NULL) +
  labs(x = "Label rows: share of 2025 hashprice; hashprice, $/TH/day; strikes S19j Pro / S21 XP, $/MWh", y = "Margin after power and\ngrid charges (USD millions)",
       subtitle = "(a) The site's margin as hashprice falls: never pausing against the optimal stack") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), legend.position = "top", legend.text = element_text(size = 7), legend.key.width = unit(9, "mm"),
        axis.text.x = element_text(size = 6.5, lineheight = 0.9), axis.title.x = element_text(size = 7, color = "grey25", margin = margin(t = 3)), plot.subtitle = element_text(size = 8, color = "grey20"), plot.margin = margin(4, 8, 14, 4))   # the bottom margin keeps the axis title clear of panel (b)
shares <- rbind(data.frame(pct = s$pct, v = s$flex_pct_revenue, series = "flexibility, share of mining revenue"),
                data.frame(pct = s$pct, v = s$pause19, series = "S19j Pro off, share of quarter-hours"),
                data.frame(pct = s$pct, v = s$pause21, series = "S21 XP off, share of quarter-hours"))
pb <- ggplot(shares, aes(pct, v, linetype = series, shape = series)) +
  geom_line(color = "grey30", linewidth = 0.55) + geom_point(color = "grey30", size = 1.8, fill = "white") +
  scale_x_reverse(breaks = s$pct, labels = sprintf("%d%%\n$%.4f", s$pct, s$hp_mean), expand = expansion(mult = 0.06)) +
  scale_linetype_manual(values = c("solid", "dashed", "dotted"), name = NULL) + scale_shape_manual(values = c(19, 21, 24), name = NULL) +
  labs(x = "Label rows: share of 2025 hashprice; hashprice, $/TH/day", y = "Percent", subtitle = "(b) What the grid gets: the flexibility share of revenue, and how often each fleet is off") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), legend.position = "inside", legend.position.inside = c(0.01, 0.99), legend.justification = c(0, 1),
        legend.background = element_rect(fill = "white", color = NA), legend.text = element_text(size = 6.5), legend.key.width = unit(8, "mm"), legend.key.height = unit(3.5, "mm"),
        axis.text.x = element_text(size = 6.5, lineheight = 0.9), axis.title.x = element_text(size = 7, color = "grey25", margin = margin(t = 3)),   # same axis style as panel (a)
        plot.subtitle = element_text(size = 8, color = "grey20"), plot.margin = margin(2, 8, 2, 4)) +
  guides(linetype = guide_legend(nrow = 3), shape = guide_legend(nrow = 3))
p <- pa / pb + plot_layout(heights = c(1, 1))
ggsave("book/images/ch10_hashprice_sensitivity.png", p, width = 124, height = 130, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/ch10_hashprice_sensitivity.pdf", p, width = 124, height = 130, units = "mm", bg = "white")
cat("Wrote book/images/ch10_hashprice_sensitivity.png and .pdf\n")
