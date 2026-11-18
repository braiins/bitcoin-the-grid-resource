# fig_ch5_backstop.R, Chapter 5: one cycle of the integral backstop
# Output: book/images/backstop.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch5_backstop.R
#
# SCHEMATIC with an illustrative price trace. The constants are the ones the
# chapter 5 backtests run with, analysis/ch5-backtest/papo_sim.py: trip when
# the accumulated excess above the breakeven at the most efficient power target
# (TelemetryMiner.breakeven_best: 3,200 W on the S21 XP, above its floor)
# reaches $10 per MW of load (K_TRIP); restart only after the price falls to
# 0.9 x breakeven (RESTART_BAND) and stays there 15 minutes (DWELL_S), counted
# as the kit counts it, three calm five-minute prints; 30-minute minimum down
# time (MIN_DOWN_S). The trace is drawn with no feed lag: each print acts in
# its own interval, where the kit's backtests act on it one interval later.
# The shaded area is the trip statistic: price excess above breakeven,
# integrated over time, reset whenever the price dips back below breakeven.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages({ library(ggplot2); library(patchwork) })

BE <- 75            # $/MWh, illustrative breakeven at the most efficient power target
trip_usd_mw <- 10   # $ per MW accumulated excess
restart_level <- 0.9 * BE

t <- seq(0, 240, by = 5)
price <- c(60,62,58,64,90,70,62,60,           # shallow blip: never trips
           65,120,240,420,380,300,240,190,150,120,90,70,
           64,60,58,56,55,56,54,55,53,54,55,56,54,53,55,54,
           56,55,54,56,55,53,54,55,56,54,55,53,54)[seq_along(t)]

excess <- pmax(price - BE, 0)
acc <- numeric(length(t)); tripped <- FALSE; trip_i <- NA; restart_i <- NA
below_since <- NA
for (i in 2:length(t)) {
  if (!tripped) {
    acc[i] <- if (excess[i] > 0) acc[i - 1] + excess[i] * 5 / 60 else 0
    if (acc[i] >= trip_usd_mw * 1) { tripped <- TRUE; trip_i <- i }  # 1 MW basis: $/MWh x h = $/MW
  } else if (is.na(restart_i)) {
    acc[i] <- acc[i - 1]
    if (price[i] <= restart_level) {
      if (is.na(below_since)) below_since <- t[i]
      # three calm prints (below_since, +5, +10) cover 15 minutes, the kit's
      # t_prev - calm_since >= DWELL_S - sec
      if (t[i] - below_since >= 10 && t[i] - t[trip_i] >= 30) restart_i <- i
    } else below_since <- NA
  }
}
power <- ifelse(seq_along(t) < trip_i | (!is.na(restart_i) & seq_along(t) >= restart_i), 1, 0)

ink <- "#3a3a3a"
df <- data.frame(t, price, power)
shade <- df[seq_len(trip_i), ]
shade$ymin <- BE; shade$ymax <- pmax(shade$price, BE)

p1 <- ggplot(df, aes(t, price)) +
  geom_ribbon(data = shade, aes(t, ymin = ymin, ymax = ymax), fill = "grey75",
              alpha = 0.65) +
  geom_hline(yintercept = BE, linetype = "dashed", color = "grey35", linewidth = 0.4) +
  geom_hline(yintercept = restart_level, linetype = "dotted", color = "grey45",
             linewidth = 0.4) +
  geom_step(color = ink, linewidth = 0.55) +
  annotate("point", x = t[trip_i], y = price[trip_i], shape = 21, size = 2.6,
           fill = "white", color = ink, stroke = 0.9) +
  # trip label sits left of the trip point, clear of the spike
  annotate("text", x = t[trip_i] - 6, y = price[trip_i],
           label = "trip: accumulated\nexcess reaches\n$10 per MW", hjust = 1,
           size = 2.3, lineheight = 0.95, color = "grey25") +
  # right-aligned where the trace is calm, so the longer label clears the spike
  annotate("text", x = 240, y = BE + 18,
           label = "breakeven at the most efficient power target",
           hjust = 1, size = 2.3, color = "grey35") +
  # lowered so the price trace above it does not touch the text
  annotate("text", x = 2, y = restart_level - 30,
           label = "resume level: 0.9 x breakeven", hjust = 0, size = 2.3,
           color = "grey45") +
  annotate("text", x = 22, y = 150,
           label = "shallow blip:\narea resets,\nnever trips", hjust = 0.5,
           size = 2.2, lineheight = 0.95, color = "grey40") +
  labs(x = NULL, y = "Price (USD/MWh)") +
  scale_x_continuous(breaks = seq(0, 240, 60), labels = function(x) sprintf("%d min", x)) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), plot.margin = margin(4, 8, 0, 4))

p2 <- ggplot(df, aes(t, power)) +
  geom_step(color = ink, linewidth = 0.55) +
  annotate("text", x = t[restart_i] + 4, y = 0.45,
           label = "resume: price 10% below breakeven,\nheld 15 minutes (and 30 min minimum pause)",
           hjust = 0, size = 2.2, lineheight = 0.95, color = "grey30") +
  scale_x_continuous(breaks = seq(0, 240, 60), labels = function(x) sprintf("%d min", x)) +
  scale_y_continuous(breaks = c(0, 1), labels = c("paused", "running"),
                     limits = c(-0.15, 1.15)) +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        plot.margin = margin(0, 8, 2, 4))

p <- p1 / p2 + plot_layout(heights = c(2.2, 1))

ggsave("book/images/backstop.png", p,
       width = 124, height = 100, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/backstop.pdf", p,
       width = 124, height = 100, units = "mm", bg = "white")
cat(sprintf("trip at %d min, restart at %d min\n", t[trip_i], t[restart_i]))
# the size of spike that trips on a single print: $10 per MW over the print's hours
cat(sprintf("one print trips on its own at $%.0f/MWh above breakeven (five-minute print) or $%.0f (15-minute print)\n",
            trip_usd_mw / (5 / 60), trip_usd_mw / (15 / 60)))
cat("Wrote book/images/backstop.png and .pdf\n")
