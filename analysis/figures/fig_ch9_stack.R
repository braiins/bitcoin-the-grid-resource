# fig_ch9_stack.R -- Chapter 9: what the flexibility stack was worth to the
# reference site, from analysis/data/ch9_optimal_stack.csv (written by
# analysis/checks/ch9_optimal_stack.R). Run from the repo root:
#   Rscript analysis/figures/fig_ch9_stack.R
# Output: book/images/ch9_stack.png (+ .pdf).
#   (a) 2025 as a waterfall: the never-pausing grid site's margin after power
#       and grid charges (EXEC-020: the ledger is a margin, not a profit), then each
#       layer added in the order the chapter stacks them, to the planned site
#       (in 2025 the planned site and the hindsight ceiling are the same stack)
#   (b) 2021-2025: the value of flexibility as a share of the never-pausing
#       site's margin, for the PLANNED site (annual switches set in advance:
#       reserves on the previous year's ledger, the window by the June rule),
#       split by layer; the hindsight ceiling (the best annual choice in hindsight) is marked beside
#       each bar as the ceiling, the way the loop is graded against its oracle
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages({ library(ggplot2); library(patchwork) })
r <- read.csv("analysis/data/ch9_optimal_stack.csv", stringsAsFactors = FALSE)

# (a) the 2025 waterfall, in $ millions
y25 <- r[r$year == 2025, ]
stopifnot(y25$plan_alloc == "flex", y25$plan_fourcp)            # the waterfall is the price-only stack with the window
steps <- data.frame(
  step = c("never pause", "strike", "power target", "summer window", "charges saved", "planned site"),
  value = c(y25$never_total, y25$strike_gain, y25$tuning_gain, y25$fourcp_net,
            y25$plan_total - (y25$never_total + y25$strike_gain + y25$tuning_gain + y25$fourcp_net),
            y25$plan_total) / 1e6)
steps$step <- factor(steps$step, levels = steps$step)
ends <- cumsum(steps$value[1:5])
steps$end <- c(ends, steps$value[6])
steps$start <- c(0, ends[1:4], 0)
steps$kind <- c("total", "gain", "gain", "gain", "gain", "total")
pa <- ggplot(steps) +
  geom_rect(aes(xmin = as.numeric(step) - 0.4, xmax = as.numeric(step) + 0.4,
                ymin = ifelse(kind == "total", 0, start), ymax = end,
                fill = kind), color = "grey30", linewidth = 0.25) +
  geom_text(aes(x = as.numeric(step), y = end + 0.9,
                label = ifelse(kind == "total", sprintf("$%.1fM", value), sprintf("+$%.2fM", value))),
            size = 2.4, color = "grey20") +
  scale_x_continuous(breaks = 1:6, labels = c("never\npause", "strike", "power\ntarget", "summer\nwindow", "charges\nsaved", "planned\nsite")) +
  scale_fill_manual(values = c(total = "grey35", gain = "grey75"), guide = "none") +
  coord_cartesian(ylim = c(38, 52)) +
  labs(x = NULL, y = "Margin after power and\ngrid charges (USD millions)",
       subtitle = "(a) 2025: the layers added in order, LZ_WEST real-time index") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
        axis.text.x = element_text(size = 7),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(4, 8, 2, 4))

# (b) five years, as a share of the never-pausing margin, decomposed along the
# planned path: strike / power target / window / charges saved where the
# planned site ran the price-only stack, reserves / window where it had
# committed both fleets to a reserve award on the previous year's winner
comp <- do.call(rbind, lapply(seq_len(nrow(r)), function(i) {
  x <- r[i, ]
  if (x$plan_alloc == "flex") {
    v <- c(strike = x$strike_gain, `power target` = x$tuning_gain, `summer window` = if (x$plan_fourcp) x$fourcp_net else 0, reserves = 0)
    v["charges saved"] <- x$plan_flex - sum(v)
  } else if (x$plan_alloc == "both") {
    # both fleets held at stock on the award: the only other change is the window
    v <- c(strike = 0, `power target` = 0, `summer window` = x$plan_flex - x$plan_asrev, reserves = x$plan_asrev, `charges saved` = 0)
    if (!x$plan_fourcp) stopifnot(abs(v[["summer window"]]) < 1)
  } else stop(sprintf("%d: a one-fleet reserve allocation in the planned path; decompose it before plotting", x$year))
  data.frame(year = x$year, layer = names(v), value = as.numeric(v) / x$never_total * 100)
}))
comp$layer <- factor(comp$layer, levels = c("strike", "power target", "summer window", "charges saved", "reserves"))
tot <- aggregate(value ~ year, comp, sum)
lab <- r[, c("year", "plan_alloc", "plan_product", "plan_fourcp")]
lab$txt <- ifelse(lab$plan_alloc == "flex", "strike, target", sprintf("reserves (%s)", lab$plan_product))
lab$txt <- paste0(lab$txt, ifelse(lab$plan_fourcp, ",\nwindow", ""))
hind <- data.frame(year = r$year, value = 100 * r$hind_flex / r$never_total,
                   same = abs(r$hind_flex - r$plan_flex) < 1, series = "hindsight ceiling")
hind$bar <- tot$value[match(hind$year, tot$year)]
pb <- ggplot(comp, aes(factor(year), value, fill = layer)) +
  geom_col(width = 0.6, color = "grey30", linewidth = 0.2) +
  geom_text(data = merge(tot, lab), aes(factor(year), value + 2.5, label = sprintf("%.1f%%", value)),
            inherit.aes = FALSE, size = 2.5, color = "grey20") +
  geom_point(data = hind, aes(as.numeric(factor(year)) + 0.42, value, shape = series), inherit.aes = FALSE,
             size = 1.9, color = "grey15", fill = "white", stroke = 0.45) +
  geom_segment(data = hind[!hind$same, ], aes(x = as.numeric(factor(year)) + 0.42, xend = as.numeric(factor(year)) + 0.42,
                                              y = bar, yend = value),
               inherit.aes = FALSE, color = "grey45", linewidth = 0.3, linetype = "22") +
  geom_text(data = hind, aes(as.numeric(factor(year)) + 0.42, value + 3.2, label = sprintf("%.1f%%", value)),   # every diamond labelled, 2025 included where it equals the bar
            inherit.aes = FALSE, size = 2.2, color = "grey35", hjust = 0.5) +
  geom_text(data = merge(tot, lab), aes(factor(year), -5.5, label = txt),
            inherit.aes = FALSE, size = 2.1, color = "grey35", lineheight = 0.85) +
  scale_fill_manual(values = c(strike = "grey25", `power target` = "grey50", `summer window` = "grey72",
                               `charges saved` = "grey90", reserves = "white"), name = NULL, drop = FALSE) +
  scale_shape_manual(values = c(`hindsight ceiling` = 23), name = NULL) +
  scale_y_continuous(breaks = seq(0, 60, 10)) + coord_cartesian(ylim = c(-8, 58), clip = "off") +
  guides(fill = guide_legend(order = 1, nrow = 2), shape = guide_legend(order = 2)) +
  labs(x = NULL, y = "Flexibility as a share of the\nnever-pausing margin (%)",
       subtitle = "(b) 2021 to 2025: what the planned stack added, and the hindsight ceiling beside it") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
        legend.position = "top", legend.text = element_text(size = 7),
        legend.key.size = unit(3.5, "mm"),
        plot.subtitle = element_text(size = 8, color = "grey20"),
        plot.margin = margin(2, 8, 2, 4))
p_all <- pa / pb + plot_layout(heights = c(1, 1.35))
ggsave("book/images/ch9_stack.png", p_all, width = 124, height = 132, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/ch9_stack.pdf", p_all, width = 124, height = 132, units = "mm", bg = "white")
cat("2025 waterfall ($M):\n"); print(steps[, c("step", "value")], row.names = FALSE)
cat("\nplanned flexibility share of never-pausing margin by year (%), and the hindsight ceiling:\n")
print(merge(merge(tot, lab)[, c("year", "value", "txt")], setNames(hind[, c("year", "value")], c("year", "hindsight"))), row.names = FALSE)
cat("Wrote book/images/ch9_stack.png and .pdf\n")
