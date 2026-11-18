# fig_ch2_uri_frequency.R, Chapter 2: ERCOT frequency, Feb 15 2021 (Uri)
# Output: book/images/uri_frequency.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch2_uri_frequency.R
#
# SCHEMATIC reconstruction (replaces a rights-encumbered ResearchGate image).
# Anchor values from the FERC/NERC Staff Report "The February 2021 Cold
# Weather Outages in Texas and the South Central United States" (Nov 2021),
# pp. 133-138 and Figure 73; interpolation between anchors is linear and the
# recovery path after 1:55 a.m. is indicative only. Times CT, Feb 15 2021:
#   1:18  59.932 Hz  (responsive reserves below EEA3 threshold)
#   1:20  59.944 Hz  (EEA3 declared, 1,000 MW load shed ordered)
#   1:45  59.820 Hz  (2,000 MW cumulative)
#   1:50  59.496 Hz  (5,000 MW cumulative)
#   1:51  59.400 Hz  (falls below relay threshold; 9-minute clock starts)
#   1:54  59.304 Hz  (minimum; ERCOT's own deck says 59.302)
#   1:55  59.401 Hz  (recovers above threshold: 4 min 23 s below)
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
library(ggplot2)

tm <- function(h, m) as.POSIXct(sprintf("2021-02-15 %02d:%02d:00", h, m), tz = "UTC")

anchors <- data.frame(
  t = c(tm(1,10), tm(1,18), tm(1,20), tm(1,45), tm(1,50), tm(1,51), tm(1,54), tm(1,55)),
  hz = c(59.95, 59.932, 59.944, 59.820, 59.496, 59.400, 59.304, 59.401)
)
recovery <- data.frame(   # indicative only
  t = c(tm(1,55), tm(2,0), tm(2,10)),
  hz = c(59.401, 59.60, 59.85)
)

shed <- data.frame(
  t = c(tm(1,20), tm(1,50), tm(1,55)),
  hz = c(59.944, 59.496, 59.401),
  label = c("EEA3 declared,\n1,000 MW shed", "5,000 MW\ncumulative", "8,500 MW\ncumulative"),
  # 5,000 MW sits left of and below its point, 8,500 MW right of
  # its point under the 59.4 Hz line, so neither crosses the frequency trace.
  vjust = c(-0.6, 1.0, 1.35),
  hjust = c(0.4, 1.15, -0.12)
)

ink <- "#3a3a3a"

p <- ggplot(anchors, aes(t, hz)) +
  annotate("rect", xmin = tm(1,51), xmax = tm(1,55), ymin = -Inf, ymax = 59.4,
           fill = "grey85", alpha = 0.6) +
  geom_hline(yintercept = 59.4, linetype = "dashed", color = "grey40", linewidth = 0.4) +
  geom_line(color = ink, linewidth = 0.6) +
  geom_line(data = recovery, color = ink, linewidth = 0.6, linetype = "dotted") +
  geom_point(data = anchors[anchors$t >= tm(1,18), ], color = ink, size = 1.4) +
  geom_text(data = shed, aes(label = label, vjust = vjust, hjust = hjust),
            size = 2.2, lineheight = 0.95, color = "grey30") +
  annotate("text", x = tm(1,10), y = 59.415, hjust = 0, vjust = -0.4, size = 2.4,
           color = "grey40",
           label = "59.4 Hz: generators may trip after 9 minutes below") +
  annotate("text", x = tm(1,53), y = 59.304, hjust = 1.08, vjust = 0.4, size = 2.4,
           color = ink, label = "minimum 59.304 Hz, 1:54 a.m.") +
  scale_x_datetime(date_breaks = "10 min", date_labels = "%H:%M",
                   expand = expansion(mult = c(0.02, 0.02))) +
  scale_y_continuous(limits = c(59.25, 60.02),
                     breaks = c(59.3, 59.4, 59.6, 59.8, 60.0)) +
  labs(x = "February 15, 2021 (Central Time)", y = "System frequency (Hz)") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        plot.margin = margin(6, 8, 4, 4))

ggsave("book/images/uri_frequency.png", p,
       width = 124, height = 80, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/uri_frequency.pdf", p,
       width = 124, height = 80, units = "mm", bg = "white")
cat("Wrote book/images/uri_frequency.png and .pdf\n")
