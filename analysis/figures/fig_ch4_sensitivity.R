# fig_ch4_sensitivity.R, Chapter 4: profitability vs hashprice, two miners
# Output: book/images/miner_sensitivity.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch4_sensitivity.R
#
# Margin per MWh consumed as a function of hashprice, holding everything
# else fixed (ceteris paribus): efficiency at the stock operating point,
# power price at the 2025 mean LZ_WEST real-time price. The identity:
#   margin [$/MWh] = hashprice [$/TH/day] * 3.6e9 / (eff [J/TH] * 86400) - P
# i.e. revenue per MWh = 41,666.7 * hashprice / efficiency.
#
# Constants (sources):
#   S19j Pro: 104 TH/s, 3,068 W = 29.5 J/TH   % src: Bitmain spec (verify pass)
#   S21 XP:   270 TH/s, 3,645 W = 13.5 J/TH   % src: Bitmain spec (verify pass)
#   P = 42.18 $/MWh: mean ERCOT 15-min real-time settlement price, LZ_WEST,
#       calendar 2025 (n = 35,040; ERCOT MIS 13061)
#       % src: analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz
#   Hashprice landmarks: Braiins Insights hashrate-value-history (public API),
#       cached in analysis/data/hashprice_daily.csv
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages(library(ggplot2))

P <- 42.18  # $/MWh, LZ_WEST 15-min real-time settlement mean, calendar 2025
            # (ERCOT MIS report 13061, all 35,040 intervals; see
            #  analysis/data/fetch_ercot_rtm15_spp_history.py)

miners <- data.frame(
  model = c("Antminer S19j Pro", "Antminer S21 XP"),
  ths = c(104, 270),
  watts = c(3068, 3645)
)
miners$eff <- miners$watts / miners$ths            # J/TH
miners$hp_be <- miners$eff * 86400 * P / 3.6e9     # breakeven hashprice $/TH/day

hp_grid <- seq(0.005, 0.125, by = 0.001)
curves <- do.call(rbind, lapply(seq_len(nrow(miners)), function(i) {
  data.frame(model = miners$model[i], hp = hp_grid,
             margin = hp_grid * 3.6e9 / (miners$eff[i] * 86400) - P)
}))

# The three landmarks are read out of the cache rather than typed in, so the
# dotted verticals, the console table and chapter 4's table cannot drift apart.
# They were hardcoded once and drifted: the peak stood at 0.1234 labelled April
# 2024, a value and a month that appear nowhere in this series.
hp_hist <- read.csv("analysis/data/hashprice_daily.csv", stringsAsFactors = FALSE)
hp_hist <- hp_hist[!is.na(hp_hist$usd_th_day), ]
hp_yr <- substr(hp_hist$date, 1, 4)
pk24  <- hp_hist[hp_yr == "2024", ][which.max(hp_hist$usd_th_day[hp_yr == "2024"]), ]
mn25  <- mean(hp_hist$usd_th_day[hp_yr == "2025"])
lo26  <- hp_hist[hp_yr == "2026", ][which.min(hp_hist$usd_th_day[hp_yr == "2026"]), ]

landmarks <- data.frame(
  hp = c(pk24$usd_th_day, mn25, lo26$usd_th_day),
  label = c(paste0(format(as.Date(pk24$date), "%b %Y"), "\npre-halving peak"),
            "2025\nmean", "2026\nlow"),
  hjust = c(1.1, -0.16, -0.16)  # beside the dotted line, not on it
)  # src: analysis/data/hashprice_daily.csv (2024 max; 2025 mean; 2026 min)

ink <- "#3a3a3a"

lab_pts <- data.frame(
  model = miners$model,
  # both labels right-aligned to the upper left of their lines
  x = c(0.098, 0.073),
  y = c(0.101 * 3.6e9 / (miners$eff[1] * 86400) - P + 14,
        0.076 * 3.6e9 / (miners$eff[2] * 86400) - P + 14),
  hjust = c(1, 1),
  text = c("S19j Pro (29.5 J/TH)", "S21 XP (13.5 J/TH)")
)

be_pts <- data.frame(hp = miners$hp_be, margin = 0,
                     label = sprintf("breakeven\n$%.3f", miners$hp_be),
                     # S21 XP label above-left, clear of the S19j dashed line
                     hjust = c(-0.08, 1.12), vjust = c(1.25, -0.3))

p <- ggplot(curves, aes(hp, margin, linetype = model)) +
  geom_vline(data = landmarks, aes(xintercept = hp), color = "grey62",
             linewidth = 0.35, linetype = "dotted") +
  geom_text(data = landmarks, aes(x = hp, y = 405, label = label, hjust = hjust),
            inherit.aes = FALSE, size = 2.1, color = "grey45",
            lineheight = 0.95, vjust = 1) +
  geom_hline(yintercept = 0, color = "grey30", linewidth = 0.4) +
  geom_line(color = ink, linewidth = 0.6, show.legend = FALSE) +
  geom_point(data = be_pts, aes(hp, margin), inherit.aes = FALSE,
             shape = 21, fill = "white", color = ink, size = 2, stroke = 0.7) +
  geom_text(data = be_pts, aes(hp, margin, label = label, hjust = hjust, vjust = vjust),
            inherit.aes = FALSE, size = 2.2, color = "grey30",
            lineheight = 0.95) +
  geom_text(data = lab_pts, aes(x, y, label = text, hjust = hjust), inherit.aes = FALSE,
            size = 2.5, color = ink, fontface = "bold") +
  scale_linetype_manual(values = c("Antminer S19j Pro" = "longdash",
                                   "Antminer S21 XP" = "solid")) +
  scale_x_continuous(breaks = seq(0.02, 0.12, 0.02),
                     labels = function(x) sprintf("%.2f", x),
                     expand = expansion(mult = c(0.06, 0.02))) +
  scale_y_continuous(breaks = seq(0, 300, 100), limits = c(NA, 405)) +
  labs(x = "Hashprice (USD/TH/day)",
       y = "Margin per MWh consumed (USD)") +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.minor = element_blank(),
    axis.title.x = element_text(margin = margin(t = 6)),
    plot.margin = margin(6, 8, 4, 4)
  )

ggsave("book/images/miner_sensitivity.png", p,
       width = 124, height = 88, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/miner_sensitivity.pdf", p,
       width = 124, height = 88, units = "mm", bg = "white")

# console check: table tab:miner-sensitivity is read straight off this output.
cat(sprintf("landmarks: %s peak $%.4f (%s); 2025 mean $%.4f; 2026 low $%.4f (%s)\n",
            format(as.Date(pk24$date), "%b %Y"), pk24$usd_th_day, pk24$date,
            mn25, lo26$usd_th_day, lo26$date))
for (i in seq_len(nrow(miners))) {
  m <- miners[i, ]
  cat(sprintf("%s: eff %.1f J/TH, %.1f kWh/day, power $%.2f/day, breakeven %.4f $/TH/day\n",
              m$model, m$eff, m$watts * 24 / 1e3, (m$watts * 24 / 1e6) * P, m$hp_be))
  for (j in rev(seq_len(nrow(landmarks)))) {
    hp <- landmarks$hp[j]
    profit <- hp * m$ths - (m$watts * 24 / 1e6) * P
    cat(sprintf("  HP %.4f (%s): profit %+.2f $/day\n", hp,
                gsub("\n", " ", landmarks$label[j]), profit))
  }
}
cat("Wrote book/images/miner_sensitivity.png and .pdf\n")
