# fig_ch6_strike.R, Chapter 6: the strike price, priced on real data
# Output: book/images/strike_sweep.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch6_strike.R
#
# Two panels on LZ_WEST 15-minute settlement prices, calendar 2025
# (analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz; ERCOT MIS 13061):
#   (a) the price duration curve (log scale) with the two machines'
#       breakevens from ch4/ch5 marked;
#   (b) the strike sweep: for a 1-MW always-on load that pauses whenever
#       the settlement price exceeds a strike V, the annual net gain is
#       sum over paused intervals of (price - V) x 0.25 h, because V is
#       what a megawatt-hour is worth to the machine (its breakeven,
#       ch4). Plotted against V, with the paused share of intervals.
# Console prints the values quoted in the chapter text.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages({ library(ggplot2); library(patchwork) })

# NOTE (2026-09-04): repointed off ercot_spp_dam_rtm15_8zones.csv.gz, which
# stamps Central time as a fixed UTC-6 offset (daylight-saving hours land an
# hour late) and drops the nine spring-forward intervals. Both replacements
# carry Central prevailing time natively, from ERCOT's own MIS archive.
z <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
z <- z[z$settlement_point == "LZ_WEST", ]
t <- as.POSIXct(z$interval_start, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Chicago")
p <- z$price[format(t, "%Y") == "2025"]
n <- length(p)

be <- c(`S19j Pro` = 71.6, `S21 XP` = 156.5)  # ch4: 41,666.7 x 0.0507 / eff

# (a) duration curve
dur <- data.frame(pct = 100 * seq_len(n) / n, price = sort(p, decreasing = TRUE))
pa <- ggplot(dur, aes(pct, pmax(price, 1))) +
  geom_line(color = "#3a3a3a", linewidth = 0.55) +
  geom_hline(yintercept = be, linetype = "dashed", color = "grey45",
             linewidth = 0.35) +
  # S19j Pro label hangs below its line, S21 XP label sits above
  # its line, so neither touches a dashed line.
  annotate("text", x = 97, y = be["S19j Pro"] / 1.2, label = "S19j Pro breakeven ($72)",
           hjust = 1, vjust = 1, size = 2.3, color = "grey30") +
  annotate("text", x = 97, y = be["S21 XP"] * 1.2, label = "S21 XP breakeven ($157)",
           hjust = 1, vjust = 0, size = 2.3, color = "grey30") +
  scale_y_log10(breaks = c(1, 10, 100, 1000), labels = scales::comma) +
  labs(x = "Share of 15-minute intervals (%)", y = "Price (USD/MWh, log)",
       subtitle = "(a) How 2025 priced itself: the duration curve") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(4, 8, 2, 4))

# (b) strike sweep
strikes <- c(seq(20, 200, 5), seq(210, 500, 10))
gain <- vapply(strikes, function(S) sum(pmax(p - S, 0)) * 0.25, numeric(1))
paused <- vapply(strikes, function(S) 100 * mean(p > S), numeric(1))
sw <- data.frame(strike = strikes, gain = gain / 1000, paused = paused)

sec_scale <- max(sw$gain) / max(sw$paused)
pb <- ggplot(sw, aes(strike)) +
  geom_line(aes(y = gain), color = "#3a3a3a", linewidth = 0.6) +
  geom_line(aes(y = paused * sec_scale), color = "grey55", linewidth = 0.5,
            linetype = "31") +
  geom_vline(xintercept = be, linetype = "dashed", color = "grey45",
             linewidth = 0.35) +
  annotate("text", x = be["S19j Pro"] + 6, y = max(sw$gain) * 0.97,
           label = "S19j Pro", hjust = 0, size = 2.3, color = "grey30") +
  annotate("text", x = be["S21 XP"] + 6, y = max(sw$gain) * 0.97,
           label = "S21 XP", hjust = 0, size = 2.3, color = "grey30") +
  annotate("text", x = 320, y = max(sw$gain) * 0.52,
           label = "net gain from pausing\nabove the strike (solid)",
           hjust = 0, size = 2.3, lineheight = 0.95, color = "grey25") +
  annotate("text", x = 320, y = max(sw$gain) * 0.16,
           label = "share of intervals\npaused (dashed)",
           hjust = 0, size = 2.3, lineheight = 0.95, color = "grey45") +
  scale_y_continuous(
    name = "Net gain (thousand USD per MW-year)",
    sec.axis = sec_axis(~ . / sec_scale, name = "Intervals paused (%)")
  ) +
  labs(x = "Strike price = the machine's breakeven (USD/MWh)",
       subtitle = "(b) What pausing above a strike was worth in 2025") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(2, 8, 2, 4))

p_all <- pa / pb + plot_layout(heights = c(1, 1.25))

ggsave("book/images/strike_sweep.png", p_all,
       width = 124, height = 118, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/strike_sweep.pdf", p_all,
       width = 124, height = 118, units = "mm", bg = "white")

for (nm in names(be)) {
  S <- be[nm]
  cat(sprintf("%s (strike $%.1f): gain $%.0f/MW-yr, paused %.2f%% of intervals (%.0f h/yr)\n",
              nm, S, sum(pmax(p - S, 0)) * 0.25, 100 * mean(p > S),
              sum(p > S) * 0.25))
}
cat(sprintf("2025 intervals: %d; mean $%.2f; negative: %.1f%%; >$500: %.2f%%; max $%.2f\n",
            n, mean(p), 100 * mean(p < 0), 100 * mean(p > 500), max(p)))
cat("Wrote book/images/strike_sweep.png and .pdf\n")
