# ch10_subsidy_arithmetic.R -- Chapter 10: the halving schedule against any
# price path, and the fee share of the security budget. Run from the repo root:
#   Rscript analysis/checks/ch10_subsidy_arithmetic.R
#
# Inputs (all committed, all public):
#   analysis/data/bitcoin_security_budget_daily.csv  miner revenue, fees, coins
#       (blockchain.info charts, fetch_bitcoin_security_budget.py)
#   world GDP 2025, current US$: 118.35 trillion (World Bank, NY.GDP.MKTP.CD)
#   above-ground gold, end-Q2 2026: 222,600 t, US$29.0 trillion (World Gold Council)
# The block subsidy is protocol arithmetic: 50 BTC at the genesis block, halved
# every 210,000 blocks; block 840,000 (April 20, 2024) started the 3.125 BTC
# epoch. Later dates assume 10-minute blocks: 210,000 blocks = 1,458 days.
suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
GDP_WORLD <- 118.35e12; GOLD_STOCK_USD <- 29.0e12; GOLD_T <- 222600
d <- read.csv("analysis/data/bitcoin_security_budget_daily.csv", stringsAsFactors = FALSE)
d$year <- substr(d$date, 1, 4)
ref_price <- tail(d$btc_usd[!is.na(d$btc_usd) & d$btc_usd != ""], 1); ref_date <- tail(d$date, 1)
coins_now <- tail(as.numeric(d$total_bitcoins[d$total_bitcoins != ""]), 1)

cat("=== The security budget so far (blockchain.info, USD) ===\n")
cat(sprintf("%-6s %12s %10s %9s %14s\n", "year", "revenue $bn", "fees $bn", "fee share", "coins, year end"))
ann <- aggregate(cbind(rev = d$miners_revenue_usd, fees = d$fees_usd), by = list(year = d$year), FUN = sum)
ann$days <- as.numeric(table(d$year)[ann$year])
last_coins <- sapply(ann$year, function(y) { v <- d$total_bitcoins[d$year == y]; v <- as.numeric(v[v != ""]); tail(v, 1) })
for (k in seq_len(nrow(ann))) cat(sprintf("%-6s %12.2f %10.3f %8.2f%% %14s\n", paste0(ann$year[k], if (ann$days[k] < 360) "*" else ""),
                                          ann$rev[k] / 1e9, ann$fees[k] / 1e9, 100 * ann$fees[k] / ann$rev[k], format(round(last_coins[k]), big.mark = ",")))
cat(sprintf("* partial year. Coins in circulation on %s: %s of 21,000,000 (%.1f%%). Reference price on that day: $%s.\n\n",
            ref_date, format(round(coins_now), big.mark = ","), 100 * coins_now / 21e6, format(round(ref_price), big.mark = ",")))
sub25 <- ann$rev[ann$year == "2025"] - ann$fees[ann$year == "2025"]
cat(sprintf("2025 security budget $%.2f bn, of which subsidy $%.2f bn (%.1f%%) and fees $%.2f bn (%.1f%%)\n\n",
            ann$rev[ann$year == "2025"] / 1e9, sub25 / 1e9, 100 * sub25 / ann$rev[ann$year == "2025"],
            ann$fees[ann$year == "2025"] / 1e9, 100 * ann$fees[ann$year == "2025"] / ann$rev[ann$year == "2025"]))

cat("=== The halving schedule against a price path ===\n")
epochs <- data.frame(epoch = 4:10, subsidy = 50 / 2^(4:10))
epochs$start <- as.Date("2024-04-20") + (epochs$epoch - 4) * 1458
epochs$btc_year <- epochs$subsidy * 52560                        # 144 blocks x 365 days
epochs$usd_year_ref <- epochs$btc_year * ref_price               # at today's price
# the price that would hold the USD subsidy at its 2025 level: doubles every epoch
epochs$price_const <- sub25 / epochs$btc_year
epochs$cap_const <- epochs$price_const * 21e6
epochs$cap_over_gdp <- epochs$cap_const / GDP_WORLD
epochs$cap_over_gold <- epochs$cap_const / GOLD_STOCK_USD
# fees needed to hold the 2025 budget if the price stays where it is
epochs$fees_needed <- pmax(ann$rev[ann$year == "2025"] - epochs$usd_year_ref, 0)
cat(sprintf("%-6s %-10s %8s %10s %12s | %14s %12s %8s %8s | %12s\n", "epoch", "from", "BTC/blk", "BTC/yr", "$bn/yr today", "price for 2025 $", "cap $tn", "x GDP", "x gold", "fees $bn/yr*"))
for (k in seq_len(nrow(epochs))) with(epochs[k, ], cat(sprintf("%-6d %-10s %8.4f %10s %12.2f | %14s %12.1f %8.2f %8.2f | %12.2f\n",
  epoch, format(start, "%Y-%m"), subsidy, format(round(btc_year), big.mark = ","), usd_year_ref / 1e9,
  format(round(price_const), big.mark = ","), cap_const / 1e12, cap_over_gdp, cap_over_gold, fees_needed / 1e9)))
cat(sprintf("* fees that would hold the 2025 security budget ($%.2f bn) with the price fixed at $%s; 2025 fees were $%.2f bn.\n",
            ann$rev[ann$year == "2025"] / 1e9, format(round(ref_price), big.mark = ","), ann$fees[ann$year == "2025"] / 1e9))
cat(sprintf("World GDP 2025 $%.1f tn (World Bank); all gold ever mined %s t = $%.1f tn (WGC, end-Q2 2026); bitcoin at $%s x 21M coins = $%.2f tn.\n",
            GDP_WORLD / 1e12, format(GOLD_T, big.mark = ","), GOLD_STOCK_USD / 1e12, format(round(ref_price), big.mark = ","), ref_price * 21e6 / 1e12))
# what the price actually did across the last two halvings
px <- function(day) { v <- d$btc_usd[d$date == day]; as.numeric(v) }
cat(sprintf("\nPrice at the 2020 halving (2020-05-11) $%s; at the 2024 halving (2024-04-20) $%s (x%.1f); on %s $%s (x%.2f since 2024).\n",
            format(round(px("2020-05-11")), big.mark = ","), format(round(px("2024-04-20")), big.mark = ","), px("2024-04-20") / px("2020-05-11"),
            ref_date, format(round(ref_price), big.mark = ","), ref_price / px("2024-04-20")))
cat(sprintf("Subsidy revenue by epoch year (USD bn): 2021 %.1f, 2022 %.1f, 2023 %.1f (6.25 BTC); 2025 %.1f (3.125 BTC).\n",
            (ann$rev - ann$fees)[ann$year == "2021"] / 1e9, (ann$rev - ann$fees)[ann$year == "2022"] / 1e9, (ann$rev - ann$fees)[ann$year == "2023"] / 1e9, sub25 / 1e9))
# what holders pay today, and the network's megawatt ceiling
p25 <- mean(as.numeric(d$btc_usd[d$year == "2025" & d$btc_usd != ""]))
cap25 <- p25 * as.numeric(last_coins["2025"])
cat(sprintf("\nIssuance of %s BTC a year is %.2f%% of the %s coins outstanding; the 2025 budget of $%.2f bn was %.2f%% of the network's market value at the 2025 mean price ($%s x %s coins = $%.2f tn).\n",
            format(round(epochs$btc_year[1]), big.mark = ","), 100 * epochs$btc_year[1] / coins_now, format(round(coins_now), big.mark = ","),
            ann$rev[ann$year == "2025"] / 1e9, 100 * ann$rev[ann$year == "2025"] / cap25, format(round(p25), big.mark = ","), format(round(as.numeric(last_coins["2025"])), big.mark = ","), cap25 / 1e12))
# Holders pay the subsidy through dilution; fees are paid by whoever transacts.
# So a holder's share is taken on the subsidy alone, valued as it was paid out
# (miners' revenue less fees, each day at that day's price), and, as a second
# convention, on 2025's coins valued at the year's mean price.
iss25 <- as.numeric(last_coins["2025"]) - as.numeric(last_coins["2024"])
cat(sprintf("Dilution: one percent of the supply paid about $%.0f million for security in 2025, 1%% of the $%.2f bn subsidy as paid out ($%.0f million on the %s coins issued in 2025 at the $%s mean price); the $%.2f bn of fees were paid by transactors, not holders. The schedule halves the coins issued every four years; their dollar value follows the price.\n",
            0.01 * sub25 / 1e6, sub25 / 1e9, 0.01 * iss25 * p25 / 1e6, format(round(iss25), big.mark = ","), format(round(p25), big.mark = ","), ann$fees[ann$year == "2025"] / 1e9))
# The table's basis, disclosed in its caption (ENERGY-019, 2026-09-26). The
# table's year is 52,560 ten-minute blocks and its dollars are the revenue
# series' 2025 subsidy. 2025 itself ran more blocks than that, as hashrate grew,
# and the revenue series runs above the coins issued each day times that day's
# price. Both push the table's prices up; this block measures by how much and
# checks that no crossing moves epoch. Nothing here changes the written CSVs.
tbn <- suppressWarnings(as.numeric(d$total_bitcoins)); iss_day <- c(NA, diff(tbn)); in25 <- d$year == "2025"
sub25_supply <- sum(iss_day[in25] * as.numeric(d$btc_usd[in25]))   # coins issued each day x that day's price
p_table <- sub25 / (3.125 * 52560); p_own <- sub25_supply / iss25   # current epoch: table basis vs 2025's own coins and prices
cat(sprintf("Block basis of the halving table: its year is 52,560 ten-minute blocks; 2025 ran %s blocks (%s coins issued / 3.125 BTC), %.1f%% more. The revenue series' 2025 subsidy, $%.2f bn, is %.1f%% above the coins issued each day times that day's price, $%.2f bn. On 2025's own coins and prices the current epoch's price to hold 2025's dollars is $%s, %.1f%% below the table's $%s; every later epoch's price moves with it.\n",
            format(round(iss25 / 3.125), big.mark = ","), format(round(iss25), big.mark = ","), 100 * (iss25 / 3.125 / 52560 - 1),
            sub25 / 1e9, 100 * (sub25 / sub25_supply - 1), sub25_supply / 1e9, format(round(p_own), big.mark = ","), 100 * (1 - p_own / p_table), format(round(p_table), big.mark = ",")))
ep_b <- 4:14; st_b <- as.Date("2024-04-20") + (ep_b - 4) * 1458
cap_own <- p_own * (3.125 / (50 / 2^ep_b)) * 21e6
gdp_b <- GDP_WORLD * (1 + (118.35 / 107.35)^(1 / 2) - 1)^(as.numeric(st_b - as.Date("2025-07-01")) / 365.25)
first_b <- function(r) min(which(r >= 1))
k_gold <- first_b(cap_own / GOLD_STOCK_USD); k_gdp <- first_b(cap_own / GDP_WORLD); k_grow <- first_b(cap_own / gdp_b)
cat(sprintf("On that basis the crossings: gold from %s (%.2f x), 2025 world output from %s (%.2f x), growing world output from %s (%.2f x); the table's are 2040, 2048 and 2056.\n",
            format(st_b[k_gold], "%Y"), cap_own[k_gold] / GOLD_STOCK_USD, format(st_b[k_gdp], "%Y"), cap_own[k_gdp] / GDP_WORLD,
            format(st_b[k_grow], "%Y"), cap_own[k_grow] / gdp_b[k_grow]))
bud_own <- sub25_supply + ann$fees[ann$year == "2025"]
cat(sprintf("The fees column has the same revenue basis: the 2025 budget on coins issued x price is $%.2f bn, $%.2f bn below the revenue series' $%.2f bn, and every fee needed in the table falls by that amount (current epoch $%.2f bn instead of $%.2f bn).\n",
            bud_own / 1e9, (ann$rev[ann$year == "2025"] - bud_own) / 1e9, ann$rev[ann$year == "2025"] / 1e9,
            max(bud_own - epochs$usd_year_ref[1], 0) / 1e9, epochs$fees_needed[1] / 1e9))
POWER <- 42.18   # LZ_WEST 2025 mean, the book's anchor
cat(sprintf("Megawatt ceiling: a network paid $%.2f bn a year cannot run more than revenue / 8,760 h / $%.2f per MWh = %s MW at that power price if it spent everything on power; at the chapter's reference price of $%s (%s) the subsidy alone supports %s MW now, %s MW from 2028, %s MW from 2032.\n",
            ann$rev[ann$year == "2025"] / 1e9, POWER, format(round(ann$rev[ann$year == "2025"] / 8760 / POWER), big.mark = ","),
            format(round(ref_price), big.mark = ","), ref_date,
            format(round(epochs$usd_year_ref[1] / 8760 / POWER), big.mark = ","), format(round(epochs$usd_year_ref[2] / 8760 / POWER), big.mark = ","), format(round(epochs$usd_year_ref[3] / 8760 / POWER), big.mark = ",")))
# The ceiling for the same period as the load (DATA-017, 2026-09-26). Chapter 1's
# network power is an August 2026 figure (930 EH/s, 7 days to 2026-08-21), so the
# ceiling it is set against must be August's too: the subsidy at chapter 1's
# anchor price plus August's fee share, run for a year. Until 2026-09-26 the
# chapter divided August's power by the 2025 ceiling above, which is why it
# printed "roughly half". The network's draw is on chapter 1's range, at the
# machines and at the meter (CBECI's best-guess PUE 1.10); a power bill is read
# at the meter.
px <- read.csv("analysis/data/btc_price_daily.csv", stringsAsFactors = FALSE)
btc_aug <- mean(px$usd[as.Date(px$date) >= as.Date("2026-08-15") & as.Date(px$date) <= as.Date("2026-08-21")])
fee_aug <- mean(d$fee_share[substr(d$date, 1, 7) == "2026-08"])   # the cache lacks 2026-08-17 to 23
rev_aug <- 450 * btc_aug / (1 - fee_aug) * 365
ceil_aug <- rev_aug / 8760 / POWER; ceil_25 <- ann$rev[ann$year == "2025"] / 8760 / POWER
NET_EHS <- 930; BAND <- c(18, 21.5, 26); PUE <- 1.10               # chapter 1: range and the author's estimate
mw_mach <- NET_EHS * BAND; mw_meter <- mw_mach * PUE
cat(sprintf("Matched periods (at chapter 1's August price, not the chapter's reference price): August 2026 pays at $%.2f bn a year (450 BTC x $%s / (1 - %.2f%% fees) x 365), a ceiling of %s MW at $%.2f; the network drew %s MW at its machines on chapter 1's range (18 / 21.5 / 26 J/TH), %s MW at the meter (PUE %.2f): %s of August's ceiling at the meter (%s at the machines); against the 2025 ceiling of %s MW, a different period, the meter draw would be %s.\n",
            rev_aug / 1e9, format(round(btc_aug), big.mark = ","), 100 * fee_aug, format(round(ceil_aug), big.mark = ","), POWER,
            paste(format(round(mw_mach), big.mark = ","), collapse = " / "), paste(format(round(mw_meter), big.mark = ","), collapse = " / "), PUE,
            paste(sprintf("%.1f%%", 100 * mw_meter / ceil_aug), collapse = " / "), paste(sprintf("%.1f%%", 100 * mw_mach / ceil_aug), collapse = " / "),
            format(round(ceil_25), big.mark = ","), paste(sprintf("%.1f%%", 100 * mw_meter / ceil_25), collapse = " / ")))
# the crossing with a growing world economy (checked over a longer horizon than the table)
g <- (118.35 / 107.35)^(1 / 2) - 1                                # World Bank 2023 -> 2025 nominal growth per year
long <- data.frame(epoch = 4:14); long$start <- as.Date("2024-04-20") + (long$epoch - 4) * 1458
long$cap_const <- sub25 / (50 / 2^long$epoch * 52560) * 21e6
long$gdp_grown <- GDP_WORLD * (1 + g)^(as.numeric(long$start - as.Date("2025-07-01")) / 365.25)
long$ratio <- long$cap_const / long$gdp_grown
k <- min(which(long$ratio >= 1))
cat(sprintf("With world output growing %.1f%% a year (World Bank 2023-2025), the constant-subsidy path's value of 21M coins first exceeds world output in the epoch from %s (%.2f x; %.2f x in the epoch before), against %s at fixed 2025 output; per epoch the dollar subsidy on a price growing only with output would fall by a factor of %.2f (0.5 x 1.05^4).\n",
            100 * g, format(long$start[k], "%Y"), long$ratio[k], long$ratio[k - 1], format(epochs$start[min(which(epochs$cap_over_gdp >= 1))], "%Y"), 0.5 * (1 + g)^4))
epochs$gdp_grown <- long$gdp_grown[match(epochs$epoch, long$epoch)]; epochs$cap_over_gdp_grown <- long$ratio[match(epochs$epoch, long$epoch)]
write.csv(epochs, "analysis/data/ch10_subsidy_schedule.csv", row.names = FALSE)
write.csv(ann, "analysis/data/ch10_security_budget_annual.csv", row.names = FALSE)
cat("\nwrote analysis/data/ch10_subsidy_schedule.csv and ch10_security_budget_annual.csv\n")
