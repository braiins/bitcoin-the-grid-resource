# fig_ch1_asic_efficiency.R, Chapter 1: ASIC miner efficiency over time
# Output: book/images/asic_miner_eff.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch1_asic_efficiency.R
#
# Reversed log scale: efficiency improvement is multiplicative, so on a log
# axis the decade-long ~10x gain reads as a straight climb. Hydro
# (liquid-cooled) models are open points.
#
# Data: analysis/data/bitmain_flagship_efficiency.csv, one row per plotted
# point, every row carrying the manufacturer document its date and its
# efficiency were read from (all read 2026-09-25). Conventions, identical for
# every row:
#   * one manufacturer (Bitmain), a selection of its flagship-tier SHA-256 models;
#   * x = the date Bitmain first announced or launched the model, not the first
#     shipment (where only a month or quarter is documented, mid-period);
#     S21 XP uses its verified specification date, as identified in the caption.
#   * y = Bitmain's rated efficiency on wall at stock settings, normal mode
#     where the machine has several.
# Until 2026-09-25 the figure carried nine hand-typed rows, most never checked
# against a specification sheet: it mixed announcement and shipment dates, and
# three rows were plainly wrong (an "S17" at 40 J/TH in October 2018, a
# "Whatsminer M30S" at 34 J/TH in April 2019, a "Whatsminer M10" at 70 J/TH in
# May 2017). The two MicroBT rows were dropped rather than re-sourced, so the
# line now follows one manufacturer's flagships on one convention.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
library(ggplot2)
library(scales)

miners <- read.csv("analysis/data/bitmain_flagship_efficiency.csv",
                   stringsAsFactors = FALSE)
miners$date  <- as.Date(miners$date_plotted)
miners$hydro <- as.logical(miners$hydro)
miners <- miners[order(miners$date), ]
miners$label <- sprintf("%s\n%s J/TH", miners$model,
                        sub("\\.0$", "", sprintf("%.1f", miners$efficiency_j_th)))

# Label placement is layout, not data: one nudge per point.
place <- data.frame(
  model = c("Antminer S9", "Antminer S17 Pro", "Antminer S19 Pro",
            "Antminer S19 XP", "Antminer S21", "Antminer S21 XP",
            "Antminer S23 Hyd", "Antminer S23 XP Hyd"),
  vjust = c( 1.25, -0.35,  1.25, -0.35, -0.35,  1.25,  0.30, -0.35),
  hjust = c(-0.05,  0.95, -0.06,  0.90,  0.95, -0.06,  1.14,  0.85)
)
miners <- merge(miners, place, by = "model", sort = FALSE)
stopifnot(nrow(miners) == nrow(place))
miners <- miners[order(miners$date), ]

# The printed claim: tenfold in a decade. Check it against the data, so the
# annotation cannot outlive the numbers: the latest flagship within ten years
# of the first must already be ten times as efficient.
first <- miners[1, ]
in_decade <- miners[as.numeric(miners$date - first$date) / 365.25 <= 10, ]
last <- in_decade[nrow(in_decade), ]
gain  <- first$efficiency_j_th / last$efficiency_j_th
years <- as.numeric(last$date - first$date) / 365.25
cat(sprintf("%s (%s, %g J/TH) to %s (%s, %g J/TH): %.1fx in %.1f years\n",
            first$model, format(first$date, "%b %Y"), first$efficiency_j_th,
            last$model, format(last$date, "%b %Y"), last$efficiency_j_th,
            gain, years))
stopifnot(gain >= 10, years <= 10)
for (i in seq_len(nrow(miners)))
  cat(sprintf("  %-20s %s  %5.1f J/TH  %s\n", miners$model[i],
              format(miners$date[i]), miners$efficiency_j_th[i],
              ifelse(miners$hydro[i], "hydro", "air")))

ink <- "#3a3a3a"

p <- ggplot(miners, aes(x = date, y = efficiency_j_th)) +
  geom_line(color = "grey62", linewidth = 0.5) +
  geom_point(data = subset(miners, !hydro), color = ink, size = 1.9) +
  geom_point(data = subset(miners, hydro), shape = 21, color = ink,
             fill = "white", stroke = 0.7, size = 2.2) +
  geom_text(aes(label = label, vjust = vjust, hjust = hjust),
            size = 2.4, lineheight = 0.95, color = ink) +
  annotate("text", x = as.Date("2016-03-01"), y = 13.5,
           label = "a tenfold efficiency gain\nin one decade",
           hjust = 0, size = 2.7, lineheight = 1, fontface = "italic",
           color = "grey45") +
  scale_y_continuous(trans = compose_trans("log10", "reverse"),
                     breaks = c(100, 50, 25, 10),
                     limits = c(130, 6.5)) +
  scale_x_date(breaks = as.Date(sprintf("%d-01-01", seq(2016, 2026, 2))),
               date_labels = "%Y",
               limits = as.Date(c("2015-11-01", "2026-12-31")),
               expand = expansion(mult = c(0.01, 0.01))) +
  labs(x = NULL, y = "Efficiency (J/TH, log scale, reversed)") +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    plot.margin = margin(8, 8, 4, 4)
  )

ggsave("book/images/asic_miner_eff.png", p,
       width = 124, height = 84, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/asic_miner_eff.pdf", p,
       width = 124, height = 84, units = "mm", bg = "white")
cat("Wrote book/images/asic_miner_eff.png and .pdf\n")
