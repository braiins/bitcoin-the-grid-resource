# fig_ch9_moving_strike.R -- Chapter 9: five markets, one strike, and the first
# months after RTC+B. Monthly mean LZ_WEST settlement price against the two
# machines' monthly mean strikes, with the share of intervals each fleet paused,
# January 2021 to the end of the settlement data (August 2026). Computed here
# directly from the two committed series with the chapter's own conventions:
# strike = hashprice x 41,666.7 / J/TH at the nameplate 29.5 and 13.5 J/TH; a
# fleet pauses a quarter-hour when the last published price exceeds the strike
# built on the previous day's hashprice (the lagged rule of ch9_flexibility_stack.R).
# Run from the repo root:  Rscript analysis/figures/fig_ch9_moving_strike.R
# Output: book/images/ch9_moving_strike.png (+ .pdf).
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages(library(ggplot2))
K <- 41666.7
# hashprice through chapter 9's shared loader (analysis/checks/ch9_hashprice.R):
# the ten days missing from the spliced series filled, none dropped silently
source("analysis/checks/ch9_hashprice.R")
hp <- ch9_hashprice()
z <- read.csv("analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz")
z <- z[z$settlement_point == "LZ_WEST", ]; z <- z[order(z$interval_start), ]
z$date <- substr(z$interval_start, 1, 10); z$ym <- substr(z$interval_start, 1, 7)
z$p_lag <- c(NA, head(z$price, -1))
z <- ch9_attach_hashprice(z, hp, !is.na(z$p_lag)); z$hp <- z$hp_real
m <- aggregate(cbind(price = z$price, s19 = z$hp * K / 29.5, s21 = z$hp * K / 13.5,
                     paused19 = z$p_lag > z$hp_known * K / 29.5, paused21 = z$p_lag > z$hp_known * K / 13.5),
               by = list(ym = z$ym), FUN = mean)
m$t <- as.Date(paste0(m$ym, "-15"))
lines <- rbind(data.frame(t = m$t, y = m$price, series = "mean settlement price"),
               data.frame(t = m$t, y = m$s19, series = "S19j Pro strike"),
               data.frame(t = m$t, y = m$s21, series = "S21 XP strike"))
lines$series <- factor(lines$series, levels = c("mean settlement price", "S19j Pro strike", "S21 XP strike"))
bars <- rbind(data.frame(t = m$t - 6, share = 100 * m$paused19, machine = "S19j Pro paused (%)"),
              data.frame(t = m$t + 6, share = 100 * m$paused21, machine = "S21 XP paused (%)"))
ymax <- 3000
ann <- data.frame(t = as.Date(c("2021-02-15", "2023-06-15", "2025-12-05")), y = c(2600, 2600, 2600),
                  label = c("Winter Storm Uri", "ECRS launches", "RTC+B go-live"), hj = c(-0.05, -0.05, 1.05))
p <- ggplot() +
  geom_col(data = bars, aes(t, 10^(share / 100 * log10(ymax)), fill = machine), width = 11, position = "identity", alpha = 0.55) +
  geom_line(data = lines, aes(t, pmax(y, 1), color = series, linetype = series), linewidth = 0.6) +
  geom_vline(xintercept = ann$t, color = "grey60", linetype = "dotted", linewidth = 0.35) +
  geom_text(data = ann, aes(t, y, label = label, hjust = hj), size = 2.2, color = "grey35") +
  scale_y_log10(breaks = c(1, 10, 100, 1000), labels = scales::comma,
                sec.axis = sec_axis(~ 100 * log10(.) / log10(ymax), name = "Share of the month's intervals paused (%)", breaks = seq(0, 100, 25))) +
  scale_color_manual(values = c("grey15", "grey40", "grey40"), name = NULL) +
  scale_linetype_manual(values = c("solid", "dashed", "dotted"), name = NULL) +
  scale_fill_manual(values = c("grey82", "grey55"), name = NULL) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  coord_cartesian(ylim = c(1, ymax)) +
  labs(x = NULL, y = "USD/MWh, monthly mean (log)") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), legend.position = "top", legend.text = element_text(size = 7),
        legend.key.width = unit(8, "mm"), legend.box = "vertical", legend.spacing.y = unit(0, "mm"),
        legend.justification = "left", legend.margin = margin(0, 0, 0, 0),
        plot.margin = margin(4, 8, 2, 4)) +
  guides(fill = guide_legend(order = 2, nrow = 1), color = guide_legend(order = 1, nrow = 1), linetype = guide_legend(order = 1, nrow = 1))
ggsave("book/images/ch9_moving_strike.png", p, width = 124, height = 92, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/ch9_moving_strike.pdf", p, width = 124, height = 92, units = "mm", bg = "white")
m$year <- substr(m$ym, 1, 4)
for (y in sort(unique(m$year))) { r <- m[m$year == y, ]
  cat(sprintf("%s (%d months): mean price $%.0f, S19j strike $%.0f, S21 strike $%.0f, paused %.1f%% / %.1f%%\n", y, nrow(r),
              mean(r$price), mean(r$s19), mean(r$s21), 100 * mean(r$paused19), 100 * mean(r$paused21))) }
post <- m[m$t >= as.Date("2025-12-05") | m$ym >= "2025-12", ]
cat(sprintf("post RTC+B (%s to %s): mean price $%.0f, S19j strike $%.0f, S21 strike $%.0f, paused %.1f%% / %.1f%%\n",
            min(post$ym), max(post$ym), mean(post$price), mean(post$s19), mean(post$s21), 100 * mean(post$paused19), 100 * mean(post$paused21)))
cat("Wrote book/images/ch9_moving_strike.png and .pdf\n")
