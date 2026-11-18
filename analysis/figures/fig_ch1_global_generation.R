# fig_ch1_global_generation.R, Chapter 1: global electricity generation
# Output: book/images/global_generation.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch1_global_generation.R
#
# Actuals 1990-2023: Statista (statista.com/statistics/270281, which
# republishes the Energy Institute Statistical Review series). 2024 and 2025
# actuals: Energy Institute Statistical Review of World Energy (2025 edition:
# 2024 = 31,255.9 TWh; 2026 edition: 2025 = 32,202 TWh). Note the small
# vintage seam: the 2026 edition revised 2024 upward (~31,345), but we plot
# the as-published 2024 value, which is also what Statista shows.
# 2026 is projected from a linear model on 2016-2025.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
library(ggplot2)
library(scales)

year <- c(1990:2023)
energy <- c(11961, 12222, 12279, 12336, 12924, 13382, 13797, 14129, 14511, 14926,
            15565, 15800, 16358, 16936, 17737, 18465, 19167, 20060, 20437, 20279,
            21591, 22279, 22834, 23469, 24076, 24315, 24984, 25738, 26783, 27147,
            27033, 28548, 29188, 29925)
year <- c(year, 2024, 2025)
energy <- c(energy, 31256, 32202)  # EI Statistical Review 2025 / 2026 editions
actuals <- data.frame(year, energy)

model <- lm(energy ~ year, data = subset(actuals, year >= 2016))
proj <- data.frame(year = 2026)
proj$energy <- predict(model, newdata = proj)

ink <- "#3a3a3a"

p <- ggplot(actuals, aes(x = year, y = energy)) +
  geom_line(color = ink, linewidth = 0.5) +
  geom_line(data = rbind(actuals[nrow(actuals), ], proj),
            color = "grey55", linetype = "dashed", linewidth = 0.5) +
  geom_point(data = proj, shape = 21, color = "grey40", fill = "white",
             stroke = 0.6, size = 1.8) +
  # filled dot marks the 2025 actual (hollow = projection)
  geom_point(data = subset(actuals, year == 2025), shape = 21, color = ink,
             fill = ink, stroke = 0.6, size = 1.8) +
  # 2025 label sits up and left of its point, clear of the line
  geom_text(data = transform(subset(actuals, year == 2025), year = 2023.5, energy = 31950),
            aes(label = paste0(comma(actuals$energy[actuals$year == 2025]), " (2025)")),
            hjust = 1, vjust = 0.5, size = 2.3, color = "grey40") +
  # the projected value is printed, matching the 2025 label
  geom_text(data = proj, aes(label = paste0(comma(round(energy)), " (2026, projected)")),
            vjust = -1.2, hjust = 0.85, size = 2.3, color = "grey40") +
  scale_y_continuous(labels = comma, limits = c(10000, 34500)) +
  scale_x_continuous(breaks = seq(1990, 2026, 6)) +
  labs(x = NULL, y = "Global electricity generation (TWh)") +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.minor = element_blank(),
    plot.margin = margin(6, 8, 4, 4)
  )

ggsave("book/images/global_generation.png", p,
       width = 124, height = 78, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/global_generation.pdf", p,
       width = 124, height = 78, units = "mm", bg = "white")
cat("2026 projection:", round(proj$energy), "TWh\n")
cat("Wrote book/images/global_generation.png and .pdf\n")
