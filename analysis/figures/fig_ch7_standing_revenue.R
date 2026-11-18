# fig_ch7_standing_revenue.R, Chapter 7: what standing by paid, per year
# Output: book/images/as_standing_revenue.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch7_standing_revenue.R
#
# Annual DAM standing revenue per product: the sum of hourly clearing prices
# over the year, i.e. what one megawatt earned by holding the award through
# every hour (before any energy consequences). Log scale; 2026 is the
# year-to-date total annualized to 8,760 hours and drawn as an open marker.
# Data: analysis/data/ercot_dam_as_mcpc.csv.gz (ERCOT MIS report 13091, via
# analysis/data/fetch_ercot_as_mcpc_history.py). Console prints the values
# quoted in the chapter text.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages(library(ggplot2))

z <- read.csv("analysis/data/ercot_dam_as_mcpc.csv.gz")
z$year <- as.integer(substr(z$deliveryDate, 1, 4))

products <- c(regup = "Reg-Up", regdn = "Reg-Down", rrs = "RRS",
              ecrs = "ECRS", nspin = "Non-Spin")
a <- do.call(rbind, lapply(names(products), function(p) {
  tot <- tapply(z[[p]], z$year, sum, na.rm = TRUE)
  hrs <- tapply(!is.na(z[[p]]), z$year, sum)
  data.frame(product = products[[p]], year = as.integer(names(tot)),
             revenue = as.numeric(tot), hours = as.numeric(hrs))
}))
a <- a[a$revenue > 0, ]
cur <- max(a$year)
a$annualized <- a$revenue * ifelse(a$year == cur, 8760 / a$hours, 1)
a$product <- factor(a$product, levels = products)

ink <- "#3a3a3a"
# left-hand labels, manually spread on the log axis so they never collide
lab <- a[a$year == 2021 | (a$product == "ECRS" & a$year == 2023), ]
# each 2021 label sits level with its own dot. The old spread
# (1.45 / 0.62 / 1.0 / 1.15) put Reg-Up above RRS although RRS is the higher
# dot (2021: RRS $2.74M, Reg-Up $2.14M), and the two labels collided.
lab$y <- lab$annualized * c(1.0, 1.0, 1.0, 1.0, 0.95)[match(
  lab$product, c("Reg-Up", "Reg-Down", "RRS", "Non-Spin", "ECRS"))]
p <- ggplot(a, aes(year, annualized, group = product)) +
  geom_line(color = "grey60", linewidth = 0.4) +
  geom_point(aes(shape = year == cur), color = ink, size = 1.7,
             fill = "white", show.legend = FALSE) +
  geom_text(data = lab, aes(x = year - 0.12, y = y,
                            label = as.character(product)),
            size = 2.3, color = ink, hjust = 1, fontface = "bold") +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 21)) +
  scale_y_log10(breaks = c(1e4, 1e5, 1e6),
                labels = c("10k", "100k", "1M")) +
  scale_x_continuous(breaks = 2021:cur,
                     limits = c(2020.3, cur + 0.15)) +
  labs(x = NULL, y = "DAM standing revenue (USD/MW-yr, log)") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        plot.margin = margin(6, 10, 2, 4))

ggsave("book/images/as_standing_revenue.png", p,
       width = 124, height = 92, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/as_standing_revenue.pdf", p,
       width = 124, height = 92, units = "mm", bg = "white")

# console: numbers for the text
w <- reshape(a[, c("product", "year", "revenue")], direction = "wide",
             idvar = "product", timevar = "year")
print(w, row.names = FALSE)
stack21 <- sum(a$revenue[a$year == 2021])
stack25 <- sum(a$revenue[a$year == 2025])
cat(sprintf("stack 2021 (4 products): $%.0f/MW-yr; stack 2025 (5 products): $%.0f/MW-yr; ratio %.0fx\n",
            stack21, stack25, stack21 / stack25))
cat(sprintf("RRS 2021 $%.0f -> 2025 $%.0f: %.0fx decline\n",
            a$revenue[a$product == "RRS" & a$year == 2021],
            a$revenue[a$product == "RRS" & a$year == 2025],
            a$revenue[a$product == "RRS" & a$year == 2021] /
              a$revenue[a$product == "RRS" & a$year == 2025]))
cat("Wrote book/images/as_standing_revenue.png and .pdf\n")
