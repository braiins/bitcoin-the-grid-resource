# fig_ch9_dispatch_week.R -- Chapter 9: one summer week, two fleets, one
# connection. Data: analysis/data/ch9_dispatch_week_2025.csv (written by
# analysis/checks/ch9_optimal_stack.R): the calendar week of August 2025 that
# holds the month's official 4CP interval, at 15-minute resolution.
#   (a) the LZ_WEST settlement price with the two strikes
#   (b) the two fleets' dispatched megawatts against the 67.13 MW connection,
#       with the summer window (weekdays 4 to 6 p.m.) shaded and the official
#       4CP interval marked at its start (ERCOT labels it 17:00, its end: the
#       interval ran 16:45-17:00; see analysis/checks/official_4cp.R)
# Run from the repo root: Rscript analysis/figures/fig_ch9_dispatch_week.R
# Output: book/images/ch9_dispatch_week.png (+ .pdf).
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages({ library(ggplot2); library(patchwork) })
w <- read.csv("analysis/data/ch9_dispatch_week_2025.csv", stringsAsFactors = FALSE)
w$t <- as.POSIXct(w$interval_start, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Chicago")
cap <- 67.13
win <- w[w$window, ]; win$day <- as.Date(win$t, tz = "America/Chicago")
shade <- do.call(rbind, lapply(split(win, win$day), function(d) data.frame(xmin = min(d$t), xmax = max(d$t) + 900)))
peak <- w[w$official_4cp, ]
# both panels run ~0.75 day past the data so the strike labels
# can sit at the end of their lines, clear of the price trace
xl <- c(min(w$t), max(w$t) + 3600 * 20)
xe <- expansion(mult = c(0.05, 0))   # no right padding: the axis stops before Tue 26
pa <- ggplot(w, aes(t)) +
  geom_rect(data = shade, aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf), inherit.aes = FALSE, fill = "grey90") +
  geom_line(aes(y = price), color = "grey20", linewidth = 0.45) +
  geom_line(aes(y = strike19), color = "grey45", linetype = "dashed", linewidth = 0.45) +
  geom_line(aes(y = strike21), color = "grey45", linetype = "31", linewidth = 0.45) +
  geom_vline(xintercept = peak$t, color = "grey30", linewidth = 0.5) +
  annotate("text", x = peak$t[1], y = 300, label = "official 4CP interval,\nMon 4:45-5 p.m.", hjust = -0.04, lineheight = 0.95, size = 2.2, color = "grey30") +
  annotate("text", x = max(w$t) + 3600 * 2, y = tail(w$strike19, 1), label = "S19j Pro\nstrike", hjust = 0, lineheight = 0.95, size = 2.2, color = "grey45") +
  annotate("text", x = max(w$t) + 3600 * 2, y = tail(w$strike21, 1), label = "S21 XP\nstrike", hjust = 0, lineheight = 0.95, size = 2.2, color = "grey45") +
  scale_x_datetime(limits = xl, expand = xe) +
  labs(x = NULL, y = "USD/MWh", subtitle = "(a) At the peak the price sat far below both strikes; the shaded window emptied the site") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), plot.subtitle = element_text(size = 8, color = "grey20"), plot.margin = margin(4, 8, 2, 4))
mw <- rbind(data.frame(t = w$t, mw = w$mw21, fleet = "S21 XP"), data.frame(t = w$t, mw = w$mw19, fleet = "S19j Pro"))
mw$fleet <- factor(mw$fleet, levels = c("S19j Pro", "S21 XP"))
pb <- ggplot() +
  geom_rect(data = shade, aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf), fill = "grey90") +
  geom_area(data = mw, aes(t, mw, fill = fleet), position = "stack", alpha = 0.9) +
  geom_hline(yintercept = cap, color = "grey20", linetype = "dashed", linewidth = 0.4) +
  geom_hline(yintercept = 39.9, color = "grey45", linetype = "dotted", linewidth = 0.35) +
  annotate("label", x = max(w$t) - 3600 * 6, y = 33, label = "S21 XP at its 3,990 W ceiling (39.9 MW)", hjust = 1, size = 2.1, color = "grey25", fill = "white", border.colour = NA, label.padding = unit(0.12, "lines")) +   # no border, as intended
  geom_vline(xintercept = peak$t, color = "grey30", linewidth = 0.5) +
  # above the connection line and right of the 4CP line
  annotate("text", x = peak$t[1] + 3600 * 3, y = cap + 2, label = "67.13 MW connection", hjust = 0, vjust = 0, size = 2.2, color = "grey20") +
  scale_fill_manual(values = c("grey35", "grey70"), name = NULL) +
  scale_x_datetime(date_breaks = "1 day", date_labels = "%a %d", limits = xl, expand = xe) +
  coord_cartesian(ylim = c(0, 78)) +
  labs(x = NULL, y = "Site draw (MW)", subtitle = "(b) Dispatch: S21 XP at its ceiling, S19j Pro making room, both off in the window") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), legend.position = "top", legend.text = element_text(size = 7), legend.key.size = unit(3.5, "mm"),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(2, 8, 2, 4))
p <- pa / pb + plot_layout(heights = c(1, 1.25))
ggsave("book/images/ch9_dispatch_week.png", p, width = 124, height = 118, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/ch9_dispatch_week.pdf", p, width = 124, height = 118, units = "mm", bg = "white")
cat(sprintf("week %s to %s: price max $%.0f, min $%.0f; S19j strike ~$%.0f, S21 ~$%.0f; window intervals %d; site mean %.1f MW\n",
            min(as.Date(w$t)), max(as.Date(w$t)), max(w$price), min(w$price), mean(w$strike19), mean(w$strike21), sum(w$window), mean(w$mw19 + w$mw21)))
cat("Wrote book/images/ch9_dispatch_week.png and .pdf\n")
