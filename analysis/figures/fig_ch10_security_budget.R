# fig_ch10_security_budget.R -- Chapter 10: the security budget, its two parts,
# and the halving schedule against a price path. Data: analysis/data/
# ch10_security_budget_annual.csv and ch10_subsidy_schedule.csv, written by
# analysis/checks/ch10_subsidy_arithmetic.R. Run from the repo root:
#   Rscript analysis/figures/fig_ch10_security_budget.R
# Output: book/images/ch10_security_budget.png (+ .pdf).
#   (a) miner revenue by year, subsidy and fees, in USD billions, with the fee share
#   (b) the price of one bitcoin that would hold the 2025 subsidy in dollars
#       through the coming halvings, and the market value of 21 million coins it
#       implies, against the value of all gold ever mined and world GDP
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages({ library(ggplot2); library(patchwork) })
ann <- read.csv("analysis/data/ch10_security_budget_annual.csv", stringsAsFactors = FALSE)
ann <- ann[ann$year >= 2019, ]; ann$label <- ifelse(ann$days < 360, paste0(ann$year, "*"), as.character(ann$year))
bars <- rbind(data.frame(year = ann$label, part = "block subsidy", usd = (ann$rev - ann$fees) / 1e9),
              data.frame(year = ann$label, part = "transaction fees", usd = ann$fees / 1e9))
bars$part <- factor(bars$part, levels = c("transaction fees", "block subsidy"))
lab <- data.frame(year = ann$label, y = ann$rev / 1e9, txt = sprintf("fees %.1f%%", 100 * ann$fees / ann$rev))
pa <- ggplot(bars, aes(year, usd, fill = part)) +
  geom_col(width = 0.7, color = "grey30", linewidth = 0.2) +
  # labels sit on a fixed gap above each column, not across its top edge
  geom_text(data = lab, aes(year, y, label = txt), inherit.aes = FALSE, size = 2.3, color = "grey30", vjust = -0.7) +
  scale_y_continuous(expand = expansion(mult = c(0.05, 0.12))) +
  scale_fill_manual(values = c(`transaction fees` = "grey80", `block subsidy` = "grey40"), name = NULL) +
  labs(x = NULL, y = "Miner revenue (USD billions)", subtitle = "(a) The security budget: what miners were paid, by year (* partial year)") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(), legend.position = "top",
        legend.text = element_text(size = 7), legend.key.size = unit(3.5, "mm"),
        plot.subtitle = element_text(size = 8, color = "grey20"), plot.margin = margin(4, 8, 2, 4))
ep <- read.csv("analysis/data/ch10_subsidy_schedule.csv", stringsAsFactors = FALSE)
ep$yr <- as.integer(substr(ep$start, 1, 4))
ref <- list(gold = 29.0, gdp = 118.35)
pb <- ggplot(ep, aes(yr, cap_const / 1e12)) +
  geom_hline(yintercept = ref$gdp, color = "grey55", linetype = "dashed", linewidth = 0.4) +
  geom_hline(yintercept = ref$gold, color = "grey55", linetype = "dotted", linewidth = 0.4) +
  annotate("text", x = 2024, y = ref$gdp * 1.35, label = "world GDP, 2025", hjust = 0, size = 2.2, color = "grey40") +
  annotate("text", x = 2024, y = ref$gold * 1.35, label = "all gold ever mined", hjust = 0, size = 2.2, color = "grey40") +
  geom_line(color = "grey20", linewidth = 0.6) + geom_point(color = "grey20", size = 1.8) +
  geom_text(data = ep[ep$yr != min(ep$yr), ], aes(label = sprintf("$%sk", trimws(format(round(price_const / 1000), big.mark = ",")))), nudge_y = 0.16, size = 2.2, color = "grey25") +
  geom_text(data = ep[ep$yr == min(ep$yr), ], aes(label = sprintf("$%sk, the 2025 average", trimws(format(round(price_const / 1000), big.mark = ",")))),   # the first point is 2025 itself, not a 2024 price
            nudge_x = 0.6, hjust = 0, size = 2.2, color = "grey25") +
  scale_x_continuous(breaks = ep$yr, labels = paste0(ep$yr, "-", substr(ep$yr + 4, 3, 4), "\n", sprintf("%.4g", ep$subsidy))) +   # each point is a four-year subsidy era, not one year
  scale_y_log10(breaks = c(1, 3, 10, 30, 100), labels = function(v) sprintf("$%g tn", v)) +
  labs(x = "subsidy era, halving to halving, and block subsidy (BTC)", y = "Value of 21 million coins (log)",
       subtitle = "(b) The coin price that holds the 2025 subsidy in dollars,\nand the value of 21M coins at that price") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), axis.text.x = element_text(size = 6.5, lineheight = 0.9),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(10, 8, 2, 4))
p <- pa / pb + plot_layout(heights = c(1, 1.15))
ggsave("book/images/ch10_security_budget.png", p, width = 124, height = 128, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/ch10_security_budget.pdf", p, width = 124, height = 128, units = "mm", bg = "white")
cat("Wrote book/images/ch10_security_budget.png and .pdf\n")
