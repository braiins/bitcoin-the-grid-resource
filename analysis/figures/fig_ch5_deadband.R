# fig_ch5_deadband.R, Chapter 5: the 30-minute hold and the price deadband
# Output: book/images/deadband.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch5_deadband.R
#
# SCHEMATIC with an illustrative 5-minute price trace (the constants are the
# measured configuration: 30-minute hold, price deadband = 10% of default
# power, each print seen one interval late as in the backtests).
# Top panel: a calm, slowly drifting price, a gap up to a new level, and a gap
# back. Bottom panel: the ideal power target (recomputed from every print,
# dashed) against the applied target (solid). Through the calm stretches the
# ideal wiggles inside the deadband and the applied target moves only on the
# routine 30-minute cadence; on each gap the ideal jumps past the deadband, it
# fires (circles), and the fleet reprices on the print after the gap instead
# of waiting out the hold.
#
# Machine and optimizer: the SAME as Figure 5.2 (fig_ch5_optimal_power.R), the
# S19j Pro's linear-efficiency model anchored to the 2026-Q2 telemetry at its
# best-efficiency point (the modulation floor, 1,200 W) and at stock power,
# with the closed-form optimum clamped between the floor and the 3,420 W
# ceiling; 2025-mean hashprice. Until 2026-09 this figure optimized over a
# spline through the raw fleet-average curve instead, which Figure 5.2 had
# dropped on 2026-08-28 because the averaging lumps create an artificial cliff
# in the optimum; on that cliff the deadband also fired inside the calm drift.
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))
suppressMessages({ library(ggplot2); library(patchwork) })

d <- read.csv("analysis/data/miner_efficiency_telemetry_2026q2.csv")
tele <- d[d$model == "S19j Pro", ]
HP <- 0.0507; p_max <- 3420; stock_w <- 3068
floor_i <- which.min(tele$avg_jth)
p_floor <- tele$power_w[floor_i]
jth_floor <- tele$avg_jth[floor_i]
jth_stock <- tele$avg_jth[tele$power_w == stock_w]
cc <- (jth_stock - jth_floor) / (stock_w - p_floor)
a <- jth_floor - cc * p_floor; b <- cc          # J(p) = a + b*p
opt_power <- function(price) {                  # identical to fig 5.2
  A <- HP; B <- price * 24 / 1e6
  min(p_max, max(p_floor, (sqrt(A * a / B) - a) / b))
}

# illustrative price trace: 3 hours of 5-minute prints (fixed, not random)
t <- seq(0, 180, by = 5)
wig <- 0.6 * c(0, 1, -1, 1, -1, 0, 1, -1, 0, 1, -1, 1, 0, -1, 1, 0, -1, 1, -1,
               0, 1, -1, 0, 1, -1, 0, 1, -1, 1, 0, -1, 0, 1, -1, 0, 1, -1)
base <- ifelse(t < 75, 57 + t * (2 / 75), ifelse(t < 130, 73, 57.5))
price <- base + wig[seq_along(t)]

deadband <- 0.10 * stock_w        # 10% of default power
HOLD <- 30
# the loop sees each print one interval late (Rule 1), so the ideal target at
# print i is computed from print i-1
ideal <- vapply(c(price[1], head(price, -1)), opt_power, numeric(1))
applied <- numeric(length(t)); applied[1] <- ideal[1]
last_change <- t[1]; fired <- logical(length(t)); routine_move <- logical(length(t))
for (i in 2:length(t)) {
  applied[i] <- applied[i - 1]
  if (abs(ideal[i] - applied[i]) > 1) {
    routine <- (t[i] - last_change) >= HOLD
    override <- abs(ideal[i] - applied[i]) > deadband
    if (routine || override) {
      applied[i] <- ideal[i]; last_change <- t[i]
      fired[i] <- override && !routine
      routine_move[i] <- routine
    }
  }
}
calm <- t < 75 | t >= 135
max_calm_gap <- max(abs(ideal - applied)[calm])

ink <- "#3a3a3a"
xs <- scale_x_continuous(breaks = seq(0, 180, 30), limits = c(0, 180),
                         labels = function(x) sprintf("%d min", x))
top <- data.frame(t, price)
bot <- rbind(data.frame(t, w = ideal, series = "ideal target (every print)"),
             data.frame(t, w = applied, series = "applied target"))
fire_pts <- data.frame(t = t[fired], w = applied[fired])

p1 <- ggplot(top, aes(t, price)) +
  geom_step(color = ink, linewidth = 0.5) +
  annotate("text", x = 2, y = 68, hjust = 0, size = 2.3, color = "grey40",
           label = "calm: small wiggles,\nslow drift") +
  annotate("text", x = 102.5, y = 65.5, hjust = 0.5, size = 2.3, color = "grey40",
           lineheight = 0.95, label = "the price gaps up,\nthen back down") +
  xs + scale_y_continuous(limits = c(54, 76), breaks = seq(55, 75, 5)) +
  labs(x = NULL, y = "Price (USD/MWh)") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), plot.margin = margin(4, 8, 0, 4))

p2 <- ggplot(bot, aes(t, w, linetype = series)) +
  geom_step(color = ink, linewidth = 0.5) +
  geom_point(data = fire_pts, aes(t, w), inherit.aes = FALSE, shape = 21,
             size = 2.4, fill = "white", color = ink, stroke = 0.8) +
  annotate("text", x = 107.5, y = 2150, hjust = 0.5, size = 2.3,
           lineheight = 0.95, color = "grey25",
           label = "price deadband\nfires (circles):\nreprice on the\nprint after the gap,\nnot at the end\nof the hold") +
  annotate("text", x = 2, y = 1750, hjust = 0, size = 2.3, lineheight = 0.95,
           color = "grey40",
           label = "calm: the ideal stays\ninside the deadband;\nthe applied target moves\nonly every 30 minutes") +
  scale_linetype_manual(values = c("applied target" = "solid",
                                   "ideal target (every print)" = "31")) +
  xs + scale_y_continuous(limits = c(1200, 3000), breaks = seq(1250, 3000, 250),
                          labels = scales::comma) +
  labs(x = NULL, y = "Power target (W)", linetype = NULL) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        legend.position = "bottom", legend.key.width = unit(1.1, "cm"),
        legend.text = element_text(size = 7),
        plot.margin = margin(0, 8, 2, 4))

p <- p1 / p2 + plot_layout(heights = c(1, 1.5))

ggsave("book/images/deadband.png", p,
       width = 124, height = 105, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/deadband.pdf", p,
       width = 124, height = 105, units = "mm", bg = "white")
cat(sprintf("model: floor %.0f W (%.2f J/TH), stock %.2f J/TH, ceiling %d W, deadband %.0f W\n",
            p_floor, jth_floor, jth_stock, p_max, deadband))
cat(sprintf("deadband fires: %d times, at %s min (price gaps at 75 and 130 min)\n",
            sum(fired), paste(t[fired], collapse = ", ")))
cat(sprintf("routine 30-minute moves: %d, at %s min\n", sum(routine_move),
            paste(t[routine_move], collapse = ", ")))
cat(sprintf("largest ideal-vs-applied gap in the calm stretches: %.0f W (deadband %.0f W)\n",
            max_calm_gap, deadband))
cat(sprintf("applied target: %.0f W calm, %.0f W after the gap up\n",
            applied[t == 70], applied[t == 85]))
cat("Wrote book/images/deadband.png and .pdf\n")
