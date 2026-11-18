# fig_ch5_optimal_power.R, Chapter 5: the profit-optimal power target
# Output: book/images/optimal_power.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch5_optimal_power.R
#
# Optimal power as a function of the electricity price for the Antminer
# S19j Pro, computed the way the production loop computes it: a
# linear-efficiency model J(p) = J_best + c*(p - p_floor) with hashrate
# H(p) = p/J(p), which has a closed-form profit optimum
# p* = (sqrt(A*a/B) - a)/b (see analysis/ch5-backtest/papo_sim.py, class
# Miner). The model is fitted to the 2026-Q2 telemetry curve's anchor
# points (best-efficiency point and the value at stock power), so this
# figure and fig 5.1 share one data source. Optimizing over the raw
# fleet-average spline instead produces large artificial steps: the
# averaging lumps act as local profit optima a single machine does not
# have. Clamped to the PSU ceiling (3,600 W rating x 95% = 3,420 W)
# above and the modulation floor below; past the floor's breakeven the
# target parks (dashed): pausing belongs to the backstop.
#
# Hashprice fixed at the 2025 mean ($0.0507/TH/day, ch4).
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages(library(ggplot2))

d <- read.csv("analysis/data/miner_efficiency_telemetry_2026q2.csv")
tele <- d[d$model == "S19j Pro", ]
HP <- 0.0507
p_max <- 3420
stock_w <- 3068
# linear-J model anchored to the telemetry: floor at the best-efficiency
# point, slope through the value at stock power (papo_sim.py Miner form)
floor_i <- which.min(tele$avg_jth)
p_floor <- tele$power_w[floor_i]
jth_floor <- tele$avg_jth[floor_i]
jth_stock <- tele$avg_jth[tele$power_w == stock_w]
cc <- (jth_stock - jth_floor) / (stock_w - p_floor)
a <- jth_floor - cc * p_floor            # J(p) = a + b*p
b <- cc
hr <- function(p) p / (a + b * p)        # TH/s
be_floor <- HP * 3.6e9 / (jth_floor * 86400)

opt_power <- function(price) {
  # closed form: maximize A*H(p) - B*p, A = HP/day per TH, B = $/W-day
  A <- HP; B <- price * 24 / 1e6
  p <- (sqrt(A * a / B) - a) / b
  min(p_max, max(p_floor, p))
}
prices <- seq(0.5, 160, by = 0.5)
opt <- vapply(prices, opt_power, numeric(1))
df <- data.frame(price = prices, w = opt,
                 seg = ifelse(prices <= be_floor, "live", "parked"))

# price at which the optimum first slips below stock power
p_stock <- min(df$price[df$w < stock_w])

ink <- "#3a3a3a"

p <- ggplot(df, aes(price, w)) +
  annotate("segment", x = be_floor, xend = be_floor, y = 830, yend = 3600,
           linetype = "dotted", color = "grey55", linewidth = 0.4) +
  geom_hline(yintercept = p_floor, color = "grey70", linewidth = 0.35,
             linetype = "dashed") +
  geom_hline(yintercept = p_max, color = "grey70", linewidth = 0.35,
             linetype = "dashed") +
  geom_line(data = subset(df, seg == "live"), color = ink, linewidth = 0.7) +
  geom_line(data = subset(df, seg == "parked"), color = ink, linewidth = 0.7,
            linetype = "31") +
  annotate("point", x = p_stock, y = stock_w, shape = 21, size = 2.2,
           fill = "white", color = ink, stroke = 0.8) +
  annotate("text", x = p_stock - 3, y = stock_w,
           label = "stock power (3,068 W)", hjust = 1, size = 2.4,
           color = "grey25") +
  annotate("text", x = 2, y = p_max + 120, label = "power ceiling (3,420 W)",
           hjust = 0, size = 2.3, color = "grey45") +
  annotate("text", x = 2, y = p_floor - 140,
           label = sprintf("modulation floor: best-efficiency point (%s W, %.1f J/TH)",
                           format(p_floor, big.mark = ","), jth_floor),
           hjust = 0, size = 2.3, color = "grey45") +
  annotate("text", x = be_floor + 2, y = 900,
           label = sprintf("breakeven at the floor (~$%.0f/MWh)", be_floor),
           hjust = 0, size = 2.3, color = "grey45") +
  annotate("text", x = be_floor + 4, y = p_floor + 330,
           label = "parked at the floor:\npausing belongs to the backstop",
           hjust = 0, size = 2.3, lineheight = 0.95, color = "grey35") +
  annotate("text", x = 4, y = 3290, label = "cheap power: overclock",
           hjust = 0, size = 2.3, color = "grey35") +
  # left of the falling curve (right-aligned like the stock-power label): the
  # gap between the curve and the dotted breakeven line is too narrow for it
  annotate("text", x = 54, y = 2300, label = "expensive power:\nunderclock",
           hjust = 1, size = 2.3, lineheight = 0.95, color = "grey35") +
  scale_x_continuous(expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(limits = c(800, 3680), breaks = seq(1000, 3500, 500),
                     labels = scales::comma) +
  labs(x = "Real-time electricity price (USD/MWh)",
       y = "Profit-optimal power (W)") +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.minor = element_blank(),
    plot.margin = margin(6, 8, 4, 4)
  )

ggsave("book/images/optimal_power.png", p,
       width = 124, height = 84, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/optimal_power.pdf", p,
       width = 124, height = 84, units = "mm", bg = "white")
cat(sprintf("floor %.0f W (%.2f J/TH), floor breakeven $%.1f/MWh, stock crossed at $%.1f\n",
            p_floor, jth_floor, be_floor, p_stock))
cat("Wrote book/images/optimal_power.png and .pdf\n")
