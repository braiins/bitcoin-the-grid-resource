# fig_ch7_as_history.R, Chapter 7: five ancillary products, five years
# Output: book/images/as_price_history.png (+ .pdf). Run from the repo root:
#   Rscript analysis/figures/fig_ch7_as_history.R
#
# Monthly mean DAM market clearing price for capacity (MCPC, USD per MW per
# hour of standby) for each ERCOT ancillary service, 2021 to mid-2026, on a
# log scale, one small panel per product. Event lines: Winter Storm Uri
# (2021-02), ECRS launch (2023-06-10, visible as the series' first point),
# and RTC+B go-live (2025-12-05). Data: analysis/data/ercot_dam_as_mcpc.csv.gz
# (ERCOT's own MIS report 13091, NP4-181-ER, via
# analysis/data/fetch_ercot_as_mcpc_history.py).
# Console prints the values quoted in the chapter text.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
suppressMessages(library(ggplot2))

z <- read.csv("analysis/data/ercot_dam_as_mcpc.csv.gz")
z$month <- as.Date(paste0(substr(z$deliveryDate, 1, 7), "-01"))

products <- c(regup = "Reg-Up", regdn = "Reg-Down", rrs = "RRS",
              ecrs = "ECRS", nspin = "Non-Spin")
m <- do.call(rbind, lapply(names(products), function(p) {
  v <- tapply(z[[p]], z$month, mean, na.rm = TRUE)
  data.frame(product = products[[p]], month = as.Date(names(v)),
             mcpc = as.numeric(v))
}))
m <- m[is.finite(m$mcpc), ]
m$product <- factor(m$product, levels = products)

events <- data.frame(
  date = as.Date(c("2021-02-15", "2023-06-10", "2025-12-05")),
  label = c("Uri", "ECRS launch", "RTC+B")
)

ink <- "#3a3a3a"
p <- ggplot(m, aes(month, pmax(mcpc, 0.1))) +
  geom_vline(data = events, aes(xintercept = date), color = "grey62",
             linewidth = 0.3, linetype = "dotted") +
  geom_line(color = ink, linewidth = 0.45) +
  geom_text(data = data.frame(product = factor("Reg-Up", levels = products),
                              events),
            aes(x = date, y = 4200, label = label), inherit.aes = FALSE,
            size = 1.9, color = "grey45", hjust = -0.06, vjust = 1) +
  facet_wrap(~product, ncol = 1, strip.position = "right") +
  scale_y_log10(breaks = c(0.1, 10, 1000),
                labels = c("0.1", "10", "1,000")) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y",
               expand = expansion(mult = c(0.01, 0.02))) +
  labs(x = NULL, y = "Monthly mean DAM clearing price (USD/MW per hour, log)") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        strip.text.y.right = element_text(angle = 0, size = 7, hjust = 0),
        plot.margin = margin(6, 8, 2, 4))

ggsave("book/images/as_price_history.png", p,
       width = 124, height = 128, units = "mm", dpi = 300, bg = "white")
ggsave("book/images/as_price_history.pdf", p,
       width = 124, height = 128, units = "mm", bg = "white")

# console: numbers for the text
z$year <- substr(z$deliveryDate, 1, 4)
uri <- z$deliveryDate >= "2021-02-14" & z$deliveryDate <= "2021-02-20"
for (pp in names(products)) {
  cat(sprintf("%-6s 2021 total $%.0f, Uri week $%.0f (%.0f%%), max $%.2f\n",
              toupper(pp), sum(z[[pp]][z$year == "2021"], na.rm = TRUE),
              sum(z[[pp]][uri], na.rm = TRUE),
              100 * sum(z[[pp]][uri], na.rm = TRUE) /
                sum(z[[pp]][z$year == "2021"], na.rm = TRUE),
              max(z[[pp]], na.rm = TRUE)))
}
cat(sprintf("ECRS 2023 (from launch): mean $%.2f over %d h; 2024 mean $%.2f; 2025 mean $%.2f\n",
            mean(z$ecrs[z$year == "2023"], na.rm = TRUE),
            sum(!is.na(z$ecrs[z$year == "2023"])),
            mean(z$ecrs[z$year == "2024"], na.rm = TRUE),
            mean(z$ecrs[z$year == "2025"], na.rm = TRUE)))
cat("Wrote book/images/as_price_history.png and .pdf\n")

# console (used by chapter 8): what a two-hour ancillary buyout would have
# cost on the official 4CP afternoons. For each official 4CP date in
# analysis/data/ercot_official_4cp_2018_2025.csv within this cache, sum the
# DAM clearing price of each product over two hours that hold the official
# interval, and report the most expensive product. The two hours are hour
# endings 17 and 18 (4 to 6 p.m., the summer window) whenever the interval
# falls in them. ERCOT labels an interval by its END (read through
# analysis/checks/official_4cp.R), so 19 of the 20 do; the exception is
# 2024-09-20, labelled 16:00, whose interval 15:45-16:00 sits in HE16, and
# there the two hours are HE16-17. RT MCPCs did not exist before RTC+B, so
# the DAM price is the available proxy.
source("analysis/checks/official_4cp.R")
off <- read_official_4cp()
off <- off[off$date >= min(z$deliveryDate), ]
off$block <- ifelse(off$he %in% 17:18, "HE17-18", sprintf("HE%d-%d", off$he, off$he + 1))
buy <- sapply(seq_len(nrow(off)), function(i) {
  hrs <- if (off$he[i] %in% 17:18) 17:18 else off$he[i] + 0:1
  s <- z[z$deliveryDate == off$date[i] & z$hourEnding %in% hrs, ]
  stopifnot(nrow(s) == 2)
  max(colSums(s[, c("regup", "regdn", "rrs", "nspin", "ecrs")], na.rm = TRUE))
})
cat(sprintf("\n4CP afternoons %s-%s (n=%d): two-hour buyout at the priciest product's DAM MCPC: median $%.0f/MW, max $%.0f/MW (%s); under $160: %d days; over $300: %d days (%s)\n",
            min(off$year), max(off$year), nrow(off), median(buy), max(buy),
            off$date[which.max(buy)], sum(buy < 160), sum(buy > 300),
            paste(off$date[buy > 300], collapse = ", ")))
print(data.frame(date = off$date, label = off$interval_ending_cpt, interval = paste0(off$interval_start_cpt, "-", off$interval_ending_cpt),
                 hours = off$block, buyout_2h_usd_per_mw = round(buy)), row.names = FALSE)
