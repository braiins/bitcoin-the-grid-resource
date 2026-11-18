# fig_ch5_efficiency_curves.R, Chapter 5: measured efficiency curves
# Output: book/images/efficiency_curves.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch5_efficiency_curves.R
#
# Average empirical efficiency curves for the Antminer S19j Pro (104 TH
# variant) and Antminer S21 XP (270 TH variant), from Braiins OS fleet
# telemetry, 2026-Q2 aggregation (analysis/data/
# miner_efficiency_telemetry_2026q2.csv; Braiins' own data, published
# with the book). Open squares mark the manufacturer nameplate efficiency at
# stock power. Lower J/TH is better: less energy for the same hashing.
# The S19j Pro's fleet average turns back up below 1,200 W (its best point).
# I read such a bottom as the V-floor, the power supply's minimum
# output voltage; a Braiins OS chip-autotuning engineer confirms that mechanism
# for the break on his modelled S19j Pro curve (personal communication
# documented in Chapter 5 source comments): below the floor only the frequency drops, and the
# surplus voltage turns into heat. The telemetry itself does not show the
# mechanism. His model puts the S19j Pro's V-floor at about 1,850 to 1,900 W,
# well above the fleet average's 1,200 W upturn (analysis/checks/ch5_vfloor.py,
# part 2); since 2026-10-13 (author decision) neither the figure nor chapter 5
# prints the modeled wattage, only the fleet's 1,200 W.
# So the arrow names the fleet upturn, not the V-floor. The S21 XP's telemetry
# ends at 2,000 W, 1.0% worse than its 2,200 W best point (ch5_vfloor.py,
# part 1).
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages(library(ggplot2))

d <- read.csv("analysis/data/miner_efficiency_telemetry_2026q2.csv")

nameplate <- data.frame(
  model = c("S19j Pro", "S21 XP"),
  power_w = c(3068, 3645),
  avg_jth = c(29.5, 13.5)
)  # src: Bitmain specs (bitmain2021s19jpro, bitmain2024s21xp)

best <- do.call(rbind, lapply(split(d, d$model), function(g) g[which.min(g$avg_jth), ]))

ink <- "#3a3a3a"

lab <- data.frame(   # S19j Pro label sits up and left, clear of the rising line
  x = c(3350, 4050),
  y = c(33.7, 14.9),
  text = c("S19j Pro (2021)", "S21 XP (2024)")
)

p <- ggplot(d, aes(power_w, avg_jth, group = model)) +
  geom_line(color = ink, linewidth = 0.55) +
  geom_point(color = ink, size = 0.9) +
  geom_point(data = nameplate, shape = 22, size = 2.6, fill = "white",
             color = ink, stroke = 0.8) +
  geom_point(data = best, shape = 21, size = 2.4, fill = "grey20",
             color = "white", stroke = 0.6) +
  geom_text(data = lab, aes(x, y, label = text), inherit.aes = FALSE,
            size = 2.6, fontface = "bold", color = ink, hjust = 0) +
  annotate("text", x = 2200, y = 31.6,
           label = "nameplate: 29.5 J/TH at 3,068 W", hjust = 0, size = 2.3,
           color = "grey35") +
  annotate("segment", x = 2870, xend = 3020, y = 31.3, yend = 29.8,
           color = "grey60", linewidth = 0.3) +
  # text ends before the leader starts, so the leader does not cut the label
  annotate("text", x = 2150, y = 15.7,
           label = "nameplate: 13.5 J/TH at 3,645 W", hjust = 0, size = 2.3,
           color = "grey35") +
  annotate("segment", x = 3480, xend = 3630, y = 15.45, yend = 13.85,
           color = "grey60", linewidth = 0.3) +
  annotate("text", x = 1300, y = 22.4,
           label = "best point: 23.8 J/TH at 1,200 W", hjust = 0, size = 2.3,
           color = "grey25") +
  annotate("text", x = 2300, y = 11.6,
           label = "best point: 12.4 J/TH at 2,200 W", hjust = 0, size = 2.3,
           color = "grey25") +
  # label to the right of the dip, clear of the curve; the arrow points back at the upturn
  annotate("segment", x = 1290, xend = 1115, y = 26.6, yend = 26.45,
           color = "grey40", linewidth = 0.35,
           arrow = arrow(length = unit(1.6, "mm"), type = "closed")) +
  annotate("text", x = 1310, y = 26.6, label = "fleet upturn (~1,200 W)",
           hjust = 0, size = 2.2, color = "grey30") +
  annotate("text", x = 700, y = 18.8,
           label = "Below about 1,200 W the fleet average worsens\nagain (see text). The S21 XP's data\nends at 2,000 W, only about 1% worse\nthan its best point",
           hjust = 0, size = 2.2, lineheight = 0.97, color = "grey30") +
  scale_x_continuous(labels = scales::comma, breaks = seq(1000, 4500, 500),
                     expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(limits = c(11, 35), breaks = seq(12, 34, 4)) +
  labs(x = "Power target (W)",
       y = "Efficiency (J/TH, lower is better)") +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.minor = element_blank(),
    plot.margin = margin(6, 8, 4, 4)
  )

ggsave("book/images/efficiency_curves.png", p,
       width = 124, height = 92, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/efficiency_curves.pdf", p,
       width = 124, height = 92, units = "mm", bg = "white")
print(best[, c("model", "power_w", "avg_jth")])
cat("Wrote book/images/efficiency_curves.png and .pdf\n")
