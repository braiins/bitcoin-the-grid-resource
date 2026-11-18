# fig_ch5_oracle_benchmark.R, Chapter 5: the control loop vs the oracle
# Output: book/images/oracle_benchmark.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch5_oracle_benchmark.R
#
# Share of the perfect-foresight ("oracle") gain captured by four real
# configurations, LZ_WEST out-of-sample, settled on the 15-minute settlement
# point price. "Gain" is profit above running every machine at stock power
# without ever pausing (the kit's S0), so capture = (strategy - S0) /
# (oracle - S0), the kit's pct_of_s1 column. The oracle reacts to the
# settlement price with perfect foresight and zero friction: it is the
# ceiling, not a strategy.
#
# The values are READ from the replication kit's own output, so the figure
# cannot drift from the study again (until 2026-09 they were typed into a
# vector here, and went stale when the kit's inputs changed):
#   python3 analysis/ch5-backtest/build_prices_db.py
#   cd analysis/ch5-backtest && python3 mixed_basis_study.py
# writes output/trend_study/mixed_basis.csv; this script takes window
# TEST-2025-26, zone LZ_WEST, deadband 10 percent of default power, and prints
# the window's paired-interval count and span to the console.
#
# Inputs behind that file: ERCOT MIS 13061 settlement point prices and the
# NP6-788 five-minute prints (both ERCOT market facts, committed), the 2026-Q2
# Braiins OS fleet telemetry curves that fig_ch5_efficiency_curves.R draws,
# and the modulation floors of telemetry_miner.modulation_floor: 1,200 W, the
# S19j Pro's best-efficiency point, and 2,774 W, the S21 XP's Braiins OS
# default minimum power target (its 2,200 W best point until 2026-09-26).
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))
suppressMessages(library(ggplot2))

KIT <- "analysis/ch5-backtest/output/trend_study/mixed_basis.csv"
CONFIGS <- c("decide-15 S14"         = "first print of each 15 min, plain 30-min hold",
             "decide-5 S14"          = "every 5-min print, plain 30-min hold",
             "decide-15 +deadband10" = "first print of each 15 min + price deadband",
             "decide-5 +deadband10"  = "every 5-min print + price deadband (the full loop)")
FLEETS <- c(S21XP = "S21 XP", S19jPro = "S19j Pro")
kit <- read.csv(KIT, stringsAsFactors = FALSE)
kit <- kit[kit$window == "TEST-2025-26" & kit$zone == "LZ_WEST" &
           kit$variant %in% names(CONFIGS) & kit$miner %in% names(FLEETS), ]
stopifnot(nrow(kit) == length(CONFIGS) * length(FLEETS))
d <- data.frame(config = unname(CONFIGS[kit$variant]),
                fleet = unname(FLEETS[kit$miner]),
                pct = kit$pct_of_s1)
d$config <- factor(d$config, levels = rev(unname(CONFIGS)))
d <- d[order(d$config, d$fleet), ]

ink <- "#3a3a3a"

p <- ggplot(d, aes(pct, config)) +
  geom_vline(xintercept = 100, color = "grey30", linewidth = 0.5) +
  geom_line(aes(group = config), color = "grey65", linewidth = 0.5) +
  annotate("text", x = 99.8, y = 4.62, label = "oracle = 100: perfect foresight, zero friction",
           hjust = 1, vjust = 0, size = 2.3, color = "grey35") +
  geom_point(aes(shape = fleet), size = 2.4, color = ink, fill = "white",
             stroke = 0.8) +
  geom_text(data = subset(d, fleet == "S19j Pro"),
            aes(label = sprintf("%.1f", pct)), vjust = -1.1, size = 2.3,
            color = "grey30") +
  geom_text(data = subset(d, fleet == "S21 XP"),
            aes(label = sprintf("%.1f", pct)), vjust = 2.1, size = 2.3,
            color = "grey30") +
  scale_shape_manual(values = c("S21 XP" = 16, "S19j Pro" = 21)) +
  scale_x_continuous(limits = c(floor(min(d$pct)) - 0.6, 100.6),
                     breaks = seq(2 * floor(min(d$pct) / 2), 100, 2)) +
  scale_y_discrete(expand = expansion(add = c(0.6, 0.9))) +
  labs(x = "Share of the oracle's gain captured (%)", y = NULL, shape = NULL) +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_blank(),
    axis.text.y = element_text(size = 7.3, color = "grey15"),
    # more room between the tick labels and the x-axis title
    axis.title.x = element_text(margin = margin(t = 6)),
    legend.position = "bottom",
    legend.text = element_text(size = 7),
    plot.margin = margin(6, 10, 2, 4)
  )

ggsave("book/images/oracle_benchmark.png", p,
       width = 124, height = 76, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/oracle_benchmark.pdf", p,
       width = 124, height = 76, units = "mm", bg = "white")
for (i in seq_len(nrow(kit)))
  cat(sprintf("%-38s %-9s %5.1f%%\n", CONFIGS[kit$variant[i]], FLEETS[kit$miner[i]],
              kit$pct_of_s1[i]))
cat(sprintf("window: %s paired 5-minute intervals, %s .. %s (UTC)\n",
            format(unique(kit$n_paired), big.mark = ","), unique(kit$first_utc),
            unique(kit$last_utc)))
cat("Wrote book/images/oracle_benchmark.png and .pdf\n")
