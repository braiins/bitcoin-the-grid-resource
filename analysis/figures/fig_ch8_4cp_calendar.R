# fig_ch8_4cp_calendar.R, Chapter 8: when the peaks land
# Output: book/images/fourcp_calendar.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch8_4cp_calendar.R
#
# (a) A summer calendar strip per year: the four monthly peak-demand
#     intervals reconstructed from public 15-minute system demand
#     (analysis/data/ercot_monthly_peak_intervals_reconstructed.csv, built
#     by analysis/checks/ch8_4cp_peaks.R), with the official ERCOT 4CP
#     dates for 2018-2025 (analysis/data/ercot_official_4cp_2018_2025.csv)
#     drawn as rings where they fall on a different day.
# (b) Time of day of every monthly peak, January 2019 to the last complete
#     month of the series (the y-axis label and the console print the span),
#     split into the four 4CP months and the other eight months (the 12CP
#     question): summer peaks cluster around 5 p.m.; winter peaks around
#     7:30 a.m.
# Complete months only: ch8_4cp_peaks.R writes a month only when every day
# of it is in the checked series (analysis/checks/ch8_demand.R), because a
# month's peak is not known until the month is over. A summer still in
# progress at the data edge therefore shows only its complete months (the
# console's "summer peaks" count says how many dots there are in all).
invisible(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")))
suppressMessages({ library(ggplot2); library(patchwork); library(ggrepel) })

pk <- read.csv("analysis/data/ercot_monthly_peak_intervals_reconstructed.csv")
stopifnot(all(pk$n_intervals >= 28 * 96))   # no partial month can slip in
source("analysis/checks/official_4cp.R")   # official dates only are drawn here
off <- read_official_4cp()
pk$date <- as.Date(pk$date); off$date <- as.Date(off$date)
span <- sprintf("%s to %s", format(min(pk$date), "%b %Y"), format(max(pk$date), "%b %Y"))

# (a) summer strip
s <- pk[pk$month %in% 6:9, ]
s$doy <- as.integer(format(s$date, "%j")) - as.integer(format(as.Date(paste0(s$year, "-06-01")), "%j"))
o <- off[off$year %in% unique(s$year), ]  # years present in both series
o$doy <- as.integer(format(o$date, "%j")) - as.integer(format(as.Date(paste0(o$year, "-06-01")), "%j"))
key <- paste(s$year, s$month); okey <- paste(o$year, o$month)
o$differs <- o$date != s$date[match(okey, key)]
odiff <- o[o$differs, ]

lab <- rbind(
  data.frame(doy = s$doy, year = s$year, label = s$time_ending, ps = 3.2,
             ny = ifelse(s$month %in% c(6, 8), 0.36, -0.36)),
  data.frame(doy = odiff$doy, year = odiff$year, label = "", ps = 4.6, ny = 0))
month_starts <- cumsum(c(0, 30, 31, 31))  # Jun 1, Jul 1, Aug 1, Sep 1 offsets
ink <- "#3a3a3a"
pa <- ggplot(s, aes(doy, factor(year))) +
  geom_vline(xintercept = month_starts[-1] - 0.5, color = "grey80", linewidth = 0.3) +
  geom_point(aes(size = mw), color = ink, alpha = 0.9) +
  geom_point(data = odiff, aes(doy, factor(year)), inherit.aes = FALSE,
             shape = 21, size = 4.2, color = "grey45", stroke = 0.7) +
  # Adjacent years can peak on neighboring dates. Repel labels horizontally
  # while keeping each above/below its own year's row; fix the seed and
  # iteration budget so reruns do not depend on machine timing.
  # labels get a white backing so month dividers pass behind
  # them, and the official-4CP rings are added as label-less obstacles so
  # labels are pushed clear of them as well as of the dots.
  geom_label_repel(data = lab, aes(doy, factor(year), label = label, point.size = ps),
                   inherit.aes = FALSE, nudge_y = lab$ny,
                   direction = "x", seed = 8, max.time = Inf, max.iter = 10000,
                   max.overlaps = Inf, box.padding = 0.08, point.padding = 0.05,
                   label.padding = unit(0.6, "pt"), label.size = NA, label.r = unit(0, "pt"),
                   fill = "white", min.segment.length = unit(2.2, "mm"), segment.size = 0.25,
                   segment.color = "grey55",
                   size = 1.8, color = "grey35") +
  scale_continuous_identity(aesthetics = "point.size") +
  scale_x_continuous(breaks = month_starts + 15,
                     labels = c("June", "July", "August", "September"),
                     limits = c(-1, 122), expand = expansion(mult = 0)) +
  scale_size_continuous(range = c(1.2, 3.6), guide = "none") +
  labs(x = NULL, y = NULL,
       subtitle = paste0("(a) The four monthly peak intervals of each summer\n",
                         "(dot size: MW; time labels: interval end; rings: the official 4CP fell on a different day)")) +
  theme_minimal(base_size = 9) +
  theme(panel.grid = element_blank(),
        plot.subtitle = element_text(size = 7.5, color = "grey20"),
        axis.text.y = element_text(size = 8),
        plot.margin = margin(4, 8, 2, 4))

# (b) time of day
pk$hour <- as.integer(substr(pk$time_ending, 1, 2)) + as.integer(substr(pk$time_ending, 4, 5)) / 60
pk$group <- ifelse(pk$month %in% 6:9, "June to September (the 4CP months)",
                   "October to May (the eight months 12CP would add)")
pk$group <- factor(pk$group, levels = c("June to September (the 4CP months)",
                                        "October to May (the eight months 12CP would add)"))
pb <- ggplot(pk, aes(hour, fill = group)) +
  # stacked, summer at the base: overlapping bars ("identity") read as a stack
  # and hid most of the summer count at 5 p.m. (22 summer + 15 other)
  geom_histogram(binwidth = 0.5, boundary = 0, color = "white", linewidth = 0.2,
                 position = position_stack(reverse = TRUE)) +
  scale_fill_manual(values = c("#3a3a3a", "grey70"), name = NULL) +
  scale_x_continuous(breaks = seq(6, 22, 2),
                     labels = c("6 am", "8 am", "10 am", "noon", "2 pm", "4 pm", "6 pm", "8 pm", "10 pm"),
                     limits = c(6, 22.5)) +
  labs(x = "Time of day the monthly peak interval ended (Central)",
       y = paste0("Monthly peaks, ", span),
       subtitle = "(b) When monthly peaks happen: summer at 5 p.m., winter at breakfast") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), legend.position = "top",
        legend.text = element_text(size = 7), legend.key.size = unit(3, "mm"),
        plot.subtitle = element_text(size = 7.5, color = "grey20"),
        plot.margin = margin(2, 8, 2, 4))

p <- pa / pb + plot_layout(heights = c(1.15, 1))
ggsave("book/images/fourcp_calendar.png", p, width = 124, height = 128, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/fourcp_calendar.pdf", p, width = 124, height = 128, units = "mm", bg = "white")

# console
cat(sprintf("official vs reconstructed dates (years in both series): %d of %d match; differ in: %s\n",
            sum(!o$differs), nrow(o),
            paste(format(odiff$date, "%Y-%m"), collapse = ", ")))
summ <- pk[pk$month %in% 6:9, ]
cat(sprintf("complete months %s; summer peaks: %d; between 4 and 6 pm: %.0f%%; weekend: %.0f%%\n",
            span, nrow(summ), 100 * mean(summ$hour >= 16 & summ$hour <= 18),
            100 * mean(summ$wday %in% c("Saturday", "Sunday"))))
win <- pk[!(pk$month %in% 6:9), ]
cat(sprintf("non-summer peaks: %d; before 10 am: %.0f%%; after 4 pm: %.0f%%\n",
            nrow(win), 100 * mean(win$hour <= 10), 100 * mean(win$hour >= 16)))
cat("Wrote book/images/fourcp_calendar.png and .pdf\n")
