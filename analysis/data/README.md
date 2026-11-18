# Data caches

Every number computed for the book is reproducible from this directory plus
the scripts in `analysis/figures/` and `analysis/checks/`. Every file in this
directory has a row below giving its origin, its license posture, and how to
rebuild it. Numbers that come from cited external sources (ERCOT documents,
the market monitor's reports, Braiins' internal backtest studies) are
citations, not computations, and live in the bibliography instead.

## Fetchers

Nine scripts go out to a public source and write into this directory. Eight
need no credentials of any kind; the ninth is noted.

| Script | Writes | Source |
|---|---|---|
| `fetch_ercot_rtm15_spp_history.py` | `ercot_rtm15_spp_loadzones_2021on.csv.gz`, `ercot_dam_spp_loadzones_2021on.csv.gz`; with `--hubs`, only `ercot_rtm15_spp_hubs_2021on.csv.gz` | ERCOT's own public MIS archive, reportTypeIds 13061 (RTM 15-minute SPP) and 13060 (DAM SPP), all eight load zones, 2021 to date; `--hubs` reads 13061's HB_NORTH and HB_WEST rows instead, pinned to end where the load-zone file ends. No account, no key. |
| `fetch_lz_west_ercot.py` | LZ_WEST SPP series, standalone | ERCOT Public API. **One of the two scripts here that need credentials** (an ERCOT API Explorer account, read from a local `.env`, never printed; the other is the readability poller below). It is a second path to data the script above fetches anonymously; prefer that one. |
| `fetch_ercot_fuel_mix.py` | `ercot_fuel_mix_15min_2025.csv.gz`; `ercot_fuel_mix_15min_2019on.csv.gz` with `--history` (to the month end given by `--through`, or else to the last month the newest workbook covers completely; `--out` writes elsewhere) | ERCOT's own Fuel Mix Report, current annual workbooks plus the historical ZIP linked from ercot.com/gridinfo/generation. No account, no key. Requires Python openpyxl. Extending the history is the runbook at the end of this file, with `compare_fuel_mix_refresh.py`. |
| `fetch_ercot_native_load.R` | `ercot_native_load_hourly_2019on.csv.gz` | ERCOT's own Hourly Load Data Archives (ercot.com/gridinfo/load/load_hist), one Native_Load_YYYY.zip per year, ERCOT total only. No account, no key. |
| `fetch_ercot_as_mcpc_history.py` | `ercot_dam_as_mcpc.csv.gz` | ERCOT's own public MIS archive, reportTypeId 13091 (NP4-181-ER, Historical DAM Clearing Prices for Capacity), one DAMASMCPC_YYYY.zip per year: DAM ancillary-service clearing prices (RegUp, RegDown, RRS, Non-Spin, ECRS from its 2023-06-10 launch), pinned to end 2026-08-22. No account, no key. The archive is fetched without credentials. |
| `fetch_hashprice_history.py` | `hashprice_daily_2021on.csv` | blockchain.info public charts (no key, no account); hashprice derived from miner revenue and network hashrate. |
| `fetch_bitcoin_security_budget.py` | `bitcoin_security_budget_daily.csv` | blockchain.info public charts: daily miner revenue split into subsidy and fees. |
| `fetch_ercot_np6788_posting.py` | `ercot_np6788_posting_census.csv` | ERCOT's public MIS document listing for NP6-788-CD (reportTypeId 12300), no account, no key. Reads the SCED time stamp and PublishDate of every file in the rolling five-day listing and merges them by DocID, so a rerun extends the census. It measures when ERCOT posts each print, not when a reader can read it. |
| `fetch_ercot_ers_procurement.py` | `ercot_ers_procurement.csv` | ERCOT's public MIS listing for NP3-144-M, ERS Procurement Results (reportTypeId 11465), one .docx per service type and Standard Contract Term, from December 2024 on; the newest posting of each report is kept. No account, no key. Every row is reconciled to ERCOT's projected cost, and the run stops if two services clear at different prices in one Time Period. |
| `ercot_api_readability/poll.py` (+ `build_polls_csv.py`) | `ercot_api_readability_polls.csv.gz` | ERCOT Public API (`/np6-788-cd/lmp_node_zone_hub` and `/np6-905-cd/spp_node_zone_hub`, HB_NORTH), polled every 20 s. Needs an ERCOT API Explorer account (`.env` next to the script, see `.env.example`) and a US connection; run `preflight.py` first. `build_polls_csv.py` reduces the raw daily JSONL to the committed CSV: poll time, HTTP status and newest interval per report; no prices and no egress checks (they carry the measuring machine's IP address). |

## Market data caches

Rows marked "public" under ERCOT are ERCOT's own files. ERCOT's Website Terms
of Use (ercot.com/help/terms, sec. 5, read 2026-09-27) allow raw data from the
public portions of its site to be used, reproduced and redistributed in
compilations, charts and analyses.

| File | Contents | Source and license | Rebuild |
|---|---|---|---|
| `ercot_rtm15_spp_loadzones_2021on.csv.gz` | ERCOT 15-minute real-time settlement point prices, eight load zones, 2021 to date. The book's reference power price; the $42.18 anchor is the LZ_WEST 2025 mean of this file. | ERCOT MIS, public | `fetch_ercot_rtm15_spp_history.py` |
| `ercot_dam_spp_loadzones_2021on.csv.gz` | ERCOT hourly day-ahead settlement point prices, eight load zones, 2021 to date | ERCOT MIS, public | same script |
| `ercot_rtm15_spp_hubs_2021on.csv.gz` | ERCOT 15-minute real-time settlement point prices at the North and West trading hubs (HB_NORTH, HB_WEST; Settlement Point Type HU), 2021-01-01 to 2026-08-29, the last interval of the load-zone file above, so the two join interval for interval (198,428 intervals each). Chapter 6's basis, a load zone against the hub a block settles at (`../checks/ch6_basis.R`) | ERCOT MIS, public | `fetch_ercot_rtm15_spp_history.py --hubs` (fetched 2026-09-27; move `HUB_END` in the script when the load-zone file is refetched) |
| `ercot_spp_rtm5_lzwest.csv.gz` | ERCOT 5-minute real-time prices (NP6-788), LZ_WEST, 2023-12-11 to 2026-06-22 Central, stamped in UTC. Verified against MIS 13061: the three prints inside each settlement interval track that interval's settlement price at zero lag (`../ch5-backtest/ingest/verify_alignment.py`) | ERCOT public API, ingested via `../ch5-backtest/ingest/` | extend with the ingester (free ERCOT API Explorer account, US-reachable network) |
| `ercot_spp_dam_rtm15_8zones.csv.gz` | **SUPERSEDED; do not use.** Legacy ingest cache of DAM and RTM 15-minute prices, eight load zones, Dec 2023 to 2026-04-21. Stamps Central time as a fixed UTC-6 (every daylight-time interval an hour late), drops the spring-forward intervals, and carries at least one corrupted row: LZ_WEST rtm15 `2025-06-30T21:30:00Z` = $1,629.89, where ERCOT's settlement archive (MIS 13061) has $34.17 for that interval (15:30 CDT) | ERCOT public API (NP4-190, NP6-905), ingested by the pre-2026-09 ingester, which carried the DST bug | none. Kept only so `../checks/sell_vs_mine.R` can document the offset; nothing that prints a number reads it. The chapter 5 kit stopped loading it in 2026-09 |
| `ercot_dam_as_mcpc.csv.gz` | DAM ancillary-service clearing prices, all products, 2021-01-01 to 2026-08-22 | ERCOT MIS report 13091 (NP4-181-ER), public | `fetch_ercot_as_mcpc_history.py` |
| `ercot_fuel_mix_15min_2019on.csv.gz` | Complete 15-minute generation by fuel, 2019-01-01 to 2026-09-30: 271,676 intervals. Same units and timestamp schema as the 2025 file below. `ch8_demand.R` sums all fuel MWh, including negative WSL, and multiplies by four for a MW demand proxy. Net DC-tie imports are omitted; the 2019-2021 workbook Summary notes include WSL adjustments in `Other`, so the separate `WSL` field is padded with zero without changing the total. From 2022 WSL is separate. The zero does not mean no charging. Every interval matches the Central calendar; no gap-fill. FINAL through July 2026; August-September 2026 INITIAL, as the workbook reports. A settlement reconstruction, not a live feed | ERCOT Fuel Mix Report, [current workbooks](https://www.ercot.com/gridinfo/generation) and [2007-2024 ZIP](https://www.ercot.com/files/docs/2021/03/10/FuelMixReport_PreviousYears.zip), retrieved 2026-11-01 | `fetch_ercot_fuel_mix.py --history --through 2026-09-30` |
| `ercot_fuel_mix_15min_2025.csv.gz` | ERCOT-wide generation by fuel, 15-minute intervals, calendar 2025, every interval at FINAL settlement: MWh produced in the interval by Biomass, Coal, Gas, Gas-CC, Hydro, Nuclear, Other, Solar and Wind, plus WSL (battery charging, negative). Stamped in Central prevailing time with the same `dst_repeated_flag` as the settlement price archive, so the two join interval for interval (35,040 rows each in 2025). The fetcher checks every row against the workbook's own daily totals and prints each fuel's year beside the workbook's Summary sheet (the six fuels it lists). Chapter 6 uses the Wind and Solar columns to price its behind-the-meter bargaining band on the hours ERCOT's wind and solar fleets produced, and the Wind column for how much of a wind-backed mine's energy the farm covers (`../checks/ch6_btm_ledger.R`) | ERCOT, public | `fetch_ercot_fuel_mix.py` (single-year mode; `--history` with the `--through` of the row above rebuilds the chapter 8 history, including the multi-year ZIP) |
| `ercot_native_load_hourly_2019on.csv.gz` | ERCOT hourly Native Load, ERCOT total, 2019 to the last posted month, with each hour's UTC start. Retained as a separate source snapshot; chapter 8 no longer uses it for gap-fill | ERCOT, public | `fetch_ercot_native_load.R` |
| `ercot_official_4cp_2018_2025.csv` | The thirty-two official ERCOT 4CP intervals, 2018-2025, with each year's average 4CP demand. `interval_ending_cpt` is ERCOT's label, copied verbatim, and it marks the END of the fifteen-minute settlement interval (Central prevailing time): the interval labelled 17:00 ran 16:45-17:00. ERCOT's 2003-2006 filing workbooks and 2007 preliminary workbooks (in the 1996-2020 archive) and its 2016 report to the PUCT (Docket 46604 Item 13) say "interval ending" in words; Protocols §10.9.1(2)(h) and §10.9.2(1)(h) divide each hour into settlement intervals by their ending times; AEP Texas (Docket 58315 Item 53) reads the 2024 labels the same way. The 2022-2025 NP9-83-M workbooks print the bare label and do not say. Never read the file directly: `../checks/official_4cp.R` derives `interval_start_cpt` (label minus 15 minutes), the hour ending and the date-plus-start key that the price and demand series join on, and `../checks/ch8_4cp_peaks.R` prints the convention check against the demand series (on 27 of the 28 official days of 2019-2025 the interval ending at the label carried more demand than the one starting at it). Until 2026-09-25 the column was called `interval_start_cpt` and every script read the label as the start | ERCOT NP9-83-M workbooks (2022-2025); PUCT Project 51878 Item 52 (2021); ERCOT's 1996-2020 archive (2018-2020, 2019 as revised). Public filings, transcribed by hand | fixed transcription; the `source` column names the filing per row |
| `ercot_np6788_posting_census.csv` | When ERCOT posted each five-minute price file: 1,597 SCED runs, 2026-09-20 00:00 to 2026-09-25 10:40 Central, SCED time stamp (Central) and PublishDate (with offset). Read by `../checks/ch5_posting_latency.py` (chapter 5, Rule 1: posted a median 22 s after the five-minute boundary). A live probe of the listing, once committed beside it, timed a CDN cache rather than ERCOT and was withdrawn on 2026-09-25 | ERCOT MIS listing, public | `fetch_ercot_np6788_posting.py`; the listing holds about five days, so a rerun adds to the census rather than reproducing it |
| `ercot_api_readability_polls.csv.gz` | When each price became readable through ERCOT's public API: 37,780 polls, one every 20 s, 2026-09-25 02:11 to 2026-10-05 02:11 Central; columns `t` (poll start, Central), `a_http`/`a_sced` (NP6-788 status, newest SCED time stamp), `b_http`/`b_end` (NP6-905 status, end of newest 15-minute interval). 2026-09-30 to 2026-10-02 carry a connection outage on the measuring side (every request of a poll failing together). Read by `../checks/ch5_api_readability.py` |
| `ercot_ers_procurement.csv` | Emergency Response Service procurement results by Standard Contract Term and Time Period, December 2024 to September 2026: service (Non-Weather-Sensitive ERS-30 and ERS-10, Weather-Sensitive ERS-30), ERCOT's own count of each Time Period's hours, MW procured or self-arranged, clearing price ($/MW per hour) and projected cost. The three services clear at the same price in every Time Period; Non-Weather-Sensitive ERS-30 is 99.6% of the MW-hours of the 2025 program year (Dec 2024-Nov 2025), ERS-10 under half a MW in any Time Period and Weather-Sensitive ERS-30 at most 84 MW. Read by `../checks/ch8_ers_blocks.R` (chapter 8), which rebuilds every Time Period's hours from the ERCOT Holiday calendar and stops unless they match | ERCOT MIS, public | `fetch_ercot_ers_procurement.py` (fetched 2026-09-27) |
| `ercot_capacity_additions_2026-07.csv` | ERCOT generator inventory by technology and in-service month, used for the battery build-out and for the wind nameplate chapter 6's wind-coverage check divides by (`../checks/ch6_btm_ledger.R`) | EIA-860M, July 2026; US government work, public domain | refresh from EIA-860M |
| `prices.db` (gitignored, ~230 MB on disk) | SQLite reconstitution, in UTC, of the two MIS files and the five-minute file above (converted through the tz database), used by `../ch5-backtest/` | built locally in about 20 seconds, never committed | `python3 analysis/ch5-backtest/build_prices_db.py` |
| `lz_west_rt_annual_means.csv` | Annual aggregates of the 5-minute real-time series, LZ_WEST | derived | `Rscript analysis/data/build_lz_west_annual_means.R` |
| `lz_west_dam_annual_means.csv` | Annual aggregates of the hourly day-ahead series, LZ_WEST | derived | same script |
| `build_lz_west_annual_means.R` | Builds both annual-means tables from the committed ERCOT exports | n/a (it is the rebuild path) | n/a |
| `compare_fuel_mix_refresh.py` | Holds a rebuilt `ercot_fuel_mix_15min_2019on.csv.gz` against the committed one before it replaces it (the runbook "Refreshing the fuel-mix series" at the end of this file); writes nothing | n/a (a check) | n/a |

## Bitcoin network caches

| File | Contents | Source and license | Rebuild |
|---|---|---|---|
| `hashprice_daily.csv` | Daily hashprice (USD/TH/day), Jan 2024 onward. Chapter 4's landmarks are read out of this file. | Braiins Insights public API (no auth), timeframes stitched to daily | delete and rerun `analysis/figures/fig_ch4_hashprice_cycle.R` |
| `btc_price_daily.csv` | Daily bitcoin price (USD) | same | same |
| `network_hashrate_daily.csv` | Daily network hashrate (EH/s) | same | same |
| `hashprice_daily_2021on.csv` | Daily hashprice back to 2021, with the revenue, hashrate and price it is built from, plus a spliced column: `hashprice_daily.csv` wherever that file has the day (2024-01-01 to 2026-08-24), and before and after it the derived series scaled onto it by a trimmed-mean factor (0.98), so the halving-day fee spike does not set the level. **Ten days are missing** (2025-11-13 to 15, 2026-08-17 to 23), the days blockchain.info did not serve. From 2024 on the spliced column is a copy of `hashprice_daily.csv`, which has those days, so every script that reads it goes through `../checks/ch9_hashprice.R`, which fills them from that file after checking the two agree on every shared day, and stops on any other gap. The one exception is `../checks/ch9_vs_papo.R`, which reproduces an external run on that run's own 362 days | blockchain.info public charts | `fetch_hashprice_history.py` |
| `bitcoin_security_budget_daily.csv` | Daily miner revenue, split into subsidy and fees | same | `fetch_bitcoin_security_budget.py` |
| `braiins_hashrate_difficulty_all.json` | Network hashrate and difficulty, whole history, 104 points to 2026-09-14 | Braiins Insights public API. A committed snapshot on purpose: the endpoint returns a window that always ends at the moment of the request, so a build-time fetch could never be checked against the printed figure | `REFRESH=1 Rscript analysis/figures/fig_ch1_network_hr_diff.R`, which overwrites the snapshot and leaves the change in the diff |

## Mining hardware

| File | Contents | Source and license | Rebuild |
|---|---|---|---|
| `bitmain_flagship_efficiency.csv` | The eight points of chapter 1's efficiency figure: Bitmain's flagship Antminer models, S9 (2016) to S23 XP Hyd (2026), each with the date Bitmain announced or launched it and its rated efficiency on wall at stock settings | Bitmain's own documents, read 2026-09-25: its Help Center specification pages (support.bitmain.com; the HTML pages answer scripted clients with 403, the same articles are served by the Help Center API at `/api/v2/help_center/en-us/articles/<id>.json`), its news posts (served by `www-api.bitmain.com/postDetail`), two posts on its X account and one BITMAIN Shop product page (the S23 XP Hyd, read 2026-10-12). Facts transcribed by hand; every row names its two documents and quotes the fact | fixed transcription; re-read the documents in each row |

## Listed miners

Hand transcriptions of public company documents, so chapter 1 can print what
the part of the fleet that discloses anything actually discloses. No fetcher:
several of the documents live on SEC EDGAR, which refuses scripted clients
without a contact in the User-Agent, and a committed fetcher must not carry
anybody's address. Re-read the documents in each row to refresh.

| File | Contents | Source and license | Rebuild |
|---|---|---|---|
| `listed_miner_fleets_2026.csv` | Fifteen fleets of listed miners, mid-2026: twelve that publish a fleet efficiency (`in_weighted` 1; MARA, Bitdeer, CleanSpark, Riot, American Bitcoin, HIVE, IREN, Cipher, Canaan outside and inside its joint venture, TeraWulf, BitFuFu's self-owned fleet) and three that publish none (Cango, Core Scientific, Keel). Per row: hashrate and its basis and date, operating hashrate where the company gives one, J/TH and its basis and date, a `jth_stale` flag (Riot, HIVE, Cipher: first quarter; IREN: June 2025), the document for each figure with its URL and publication date, a verbatim quote of each figure, the access date and a note. Read by `../checks/ch1_fleet_efficiency.R` (chapter 1: 345.1 EH/s, 16.98 J/TH hashrate-weighted) and cited by chapter 10's Texas range | SEC filings and company releases, read 2026-09-26 (SEC documents in a browser or on the company's IR mirror of the filing); public documents, facts transcribed with their source. Core Scientific's J/TH, used only in the script's sensitivity, is CoinShares' (secondary) and labelled so | fixed transcription; re-read the documents in each row |
| `listed_miner_power_share_2026.csv` | Six listed miners' second-quarter 2026 electricity per bitcoin (net of curtailment credits) and realised revenue per bitcoin, with bitcoin mined: CleanSpark, Riot, MARA (its figure includes third-party hosting fees), IREN, HIVE, Bitdeer. The miners CoinShares covers whose electricity line is not a power bill (American Bitcoin's is a hosting fee, TeraWulf's blends tenant power) or who give no such figure are left out. Riot's and MARA's rows are checked against the companies' own documents | CoinShares, Bitcoin Mining Report Q2 2026, section 5.2 (secondary: a compilation of the companies' filings), read 2026-09-26; a handful of figures with attribution | fixed transcription |

Cambridge's CBECI series and the CCAF 2025 report's data are licensed CC
BY-NC-SA 4.0 and are not in this directory: `../checks/ch1_fleet_efficiency.R`
quotes a handful of their published figures, with the date and attribution,
and reads no CCAF file. The licence is NonCommercial and ShareAlike, so the
book's use of these figures, and of the range chapter 1 derives from them,
awaits written permission from CCAF.

## Braiins material

| File | Contents | Source and license | Rebuild |
|---|---|---|---|
| `miner_efficiency_telemetry_2026q2.csv` | Fleet-average efficiency curves, Antminer S19j Pro (104 TH) and S21 XP (270 TH), 2026-Q2 | Braiins OS fleet telemetry aggregates, not a laboratory measurement. Braiins' own data, published here for the first time | fixed snapshot; these are the curves chapter 5 prints and the curves its backtest now runs on |

## Derived intermediates

Written by an analysis script, read by a figure script, committed so the two
cannot drift apart. Delete any of them and rerun the script in the last
column.

| File | Written by |
|---|---|
| `ch9_optimal_stack.csv` | `analysis/checks/ch9_optimal_stack.R` |
| `ch9_btm_indifference.csv` | same |
| `ch9_dispatch_week_2025.csv` | same |
| `ch9_calculator_data.json` | `analysis/checks/ch9_calculator_export.R`, which also writes it into `analysis/calculator/ch9_calculator.html` (the historical calculator chapter 9 asks you to run on your own mix of its two machines); `node analysis/calculator/check_calculator.mjs` holds the page to `ch9_optimal_stack.csv` |
| `ch10_hashprice_sensitivity.csv` | `analysis/checks/ch10_hashprice_sensitivity.R` |
| `ch10_security_budget_annual.csv` | `analysis/checks/ch10_subsidy_arithmetic.R` |
| `ch10_subsidy_schedule.csv` | same |
| `ercot_fuel_mix_4cp_validation.csv` | `analysis/checks/ch8_4cp_peaks.R` (all official 2019-2025 intervals: proxy MW, official MW, signed gap, daily/monthly maximum flags) |
| `ercot_monthly_peak_intervals_reconstructed.csv` | `analysis/checks/ch8_4cp_peaks.R` (ERCOT's monthly peak intervals reconstructed from the complete generation-based demand proxy, without gap-fill, complete months only, against which the official list is checked) |

## Geodata

| File | Contents | Source and license | Rebuild |
|---|---|---|---|
| `ercot_load_zones.geojson` | Simplified polygons of the four competitive ERCOT load zones | derived from a third-party GIS tracing of ERCOT's published load-zone map; boundaries approximate, no license attached (ERCOT publishes no vector zone geodata) | see header of `analysis/figures/fig_ch3_lz_map.R` |
| `ercot_plants_erco_2026-06.csv` | Grid-connected power plants in ERCOT (name, MW, coordinates) | EIA-860M, June 2026; US government work, public domain | same |
| `texas_outline.geojson` | Texas state boundary | U.S. Census cartographic boundary file (public domain) | same |

## Manuscript trace

The glossary carries no `% src:` comments: each of its numbers restates a
chapter figure that is sourced where the chapter gives it. `glossary_trace.csv`
is the trace instead, and it is a reviewed baseline: every best hit in it was
read by hand. The checker's default run never rewrites it; it regenerates the
rows and fails on any whose value, match kind, best-hit file or best-hit context
differs from the committed row, printing both. After reading those rows, run
the checker with `--update` and commit the file with the edit. Most of that
diff is line-number churn in `hits` and `best_hit` (a line inserted near the top
of a chapter moves hundreds of them); the rows to read are the ones the default
run printed.

| File | Contents | Written by |
|---|---|---|
| `glossary_trace.csv` | One row per number `book/chapters/glossary.tex` prints: `entry`, `glossary_line`, `token` as printed, `value` normalised (`money:3500`, `share:33.33333333`, `W:1220000000`, `/year:2`, `ordinal:4`, `date:2026-07-24`), `hits` (the chapter lines whose prose prints the same value, best first), `best_hit`, `best_context` (the best hit's number as printed with about six words either side, or for an exception its `chapter_text`), and `match_kind`: `contextual` (the best hit shares words or a nearby number with the entry) or `exception` (pinned by `../checks/glossary_trace_exceptions.csv`); `value_only` and `untraced` fail the check, so the committed file has none | `analysis/checks/check_glossary_trace.py --update` |

---

Backtest replication (`analysis/ch5-backtest/`): the internal study behind
chapter 5's control-loop numbers, runnable end to end on the committed
price exports; see its README for replication status.

Checks (`analysis/checks/`):

- `ch1_hashrate_peak.R` reads `network_hashrate_daily.csv` and prints when
  network hashrate peaked and how much of it 2026 gave back, all on 7-day
  means, the estimator of chapter 1's 930 EH/s: peak 1,132.7 EH/s in the week
  to 2025-10-20, 2026 high 1,070.1 EH/s in the week to 2026-03-02, 17.9%
  given back by chapter 1's anchor week (to 2026-08-21) and 20.0% by the
  cache's last week (to 2026-08-24). Daily values (max 1,151.5 EH/s on
  2025-10-18) and the top point of the chapter 1 figure's snapshot,
  `braiins_hashrate_difficulty_all.json` (1,067.6 EH/s on 2025-11-08), print
  beside them for reference.
- `ch1_network_energy.R` turns chapter 1's range, 18 to 26 J/TH at the
  machines, and the author's 21.5 J/TH into power, energy and share of 2025
  generation at the printed 930 EH/s (16.7 to 24.2 GW, 147 to 212 TWh, 0.46
  to 0.66%; 20.0 GW and 175.2 TWh at 21.5), and prints the subsidy-only
  profitability bound.
- `ch1_fleet_efficiency.R` prints what chapter 1 sets beside that range: the
  listed fleets' hashrate-weighted efficiency and coverage from
  `listed_miner_fleets_2026.csv`, and the J/TH the undisclosed rest of the
  network would need for each network average; the band in GW, TWh and share
  of generation, at the machines and at the meter; the share of August 2026
  revenue each average would spend on power on the meter basis at six power
  prices, with the listed miners' own second-quarter share from
  `listed_miner_power_share_2026.csv`, period-matched; and Cambridge's CBECI,
  as figures quoted with their date.
- `ch5_oracle_check.R` reproduces chapter 5's oracle-plausibility numbers
  (86.5% of 2025 LZ_WEST intervals below the stock S19j Pro breakeven;
  a 1-interval-lag persistence rule captures 99.1% of perfect-foresight
  profit, 94.1% of its gain over always-on) from `ercot_spp_rtm5_lzwest.csv.gz`,
  filtered to 2025.
- `ch5_price_autocorrelation.py` computes the lag-1 autocorrelation of price
  changes chapter 5 quotes, on the LZ_WEST five-minute prints and on the
  15-minute settlement prices of all eight zones, with the spike and
  half-year breakdowns.
- `ch5_adder_example.py` finds chapter 5's example of an interval billed far
  above the prints the loop decided on (LZ_WEST, 2025-01-13, before RTC+B),
  from `ercot_rtm15_spp_loadzones_2021on.csv.gz`, `ercot_spp_rtm5_lzwest.csv.gz`
  and `hashprice_daily.csv`.
- `ch5_stakes.py` computes chapter 5's cost-to-revenue multiple for a $1,600
  hour (41,666.7 x hashprice / J/TH on the gap-filled daily hashprice) and
  counts LZ_WEST prints, settlement intervals and clock hours at or above
  $1,600 per year.
- `ch5_posting_latency.py` reads `ercot_np6788_posting_census.csv`: how long
  after each five-minute boundary ERCOT posts the print (median 22 s, p95 28 s
  over 1,569 runs).
- `ch5_api_readability.py` reads `ercot_api_readability_polls.csv.gz`: how long
  after its boundary each print can be read through the public API (median
  172 s, p95 296 s, 95.3% within five minutes, over 2,448 on-cycle prints), and
  the 15-minute settlement price after its interval ends (median 287 s).
- `ch5_vfloor.py` reads `miner_efficiency_telemetry_2026q2.csv` and prints,
  per model, the best-efficiency point, every reading below it and how far the
  curve wobbles above it: the S19j Pro's rise below its 1,200 W best-efficiency
  point (+16.8% at 1,000 W, +24.1% at 800 W) against the S21 XP's one reading
  below its 2,200 W best point, 2,000 W at +1.0%. Its constants transcribe two
  cited sources, which it sets against the telemetry: a Braiins OS
  chip-autotuning engineer's modelled performance curves (bib entry
  `mikus2025vfloor`, a personal communication: the V-floor at about 1,850 to
  1,900 W on the S19j Pro, 1,900 to 1,950 W on the S21 XP, 1,650 W on the S21
  Pro) and Braiins OS's default power limits (`braiinsacademytechres`: minimum
  944 W and 2,774 W). Chapter 5 prints where the two sources agree (at the
  floor) and where they part (below it on the S19j Pro; in watts on the S21 XP).
  Part 3 also prints the modulation floor both backtest engines take from the
  defaults and the telemetry: the default minimum, or the best-efficiency point
  where that is higher (2,774 W on the S21 XP, 1,200 W on the S19j Pro; the
  author's decision of 2026-09-26). It asserts each engine's copy of the
  defaults (`telemetry_miner.py` `BOS_DEFAULT_MIN_W`, `ch9_tuning.R`
  `CH9_BOS_MIN_W`) against its transcription, and chapter 9's floor, recomputed
  as `ch9_floor` takes it, against chapter 5's.
- `ch8_postage_stamp.py` reads no data file: its constants are transcribed
  from the two commission staff transmission charge matrices (Docket 40946
  Item 48 for 2013, Docket 57491 Item 51 for 2025). It prints chapter 8's
  postage-stamp trio for both years, the cost of service divided by the 4CP
  ($30.32 and $67.21; the stamp sits 2.1% and 2.0% above them, the gap the
  2013 matrix's own footnote explains), the stamp times the 4CP, and the
  2013-to-2025 changes (+121% rate, +172% cost, +23% peak).
- `ch8_ers_blocks.R` reads `ercot_ers_procurement.csv` and prints what ERS
  paid block by block in the 2025 program year (Dec 2024-Nov 2025,
  Non-Weather-Sensitive ERS-30): every block of every term $42,840 per MW,
  the blocks a site keeping its afternoons free can sell $17,948, the June to
  September 2025 afternoon block $4,766 (255 h at $18.69), and the MW-weighted
  price ($4.32) beside the monitor's $4.36. It rebuilds each Time Period's
  hours from the ERCOT Holiday calendar and stops unless all 85 rows match, and
  it prints, per block, the share of quarter-hours in which the LZ_WEST price of
  `ercot_rtm15_spp_loadzones_2021on.csv.gz` was above each machine's strike at
  the previous day's hashprice (through `ch9_hashprice.R`).
- `ch8_demand.R` is not run on its own: every chapter 8 demand script
  sources it. It sums ERCOT fuel generation into a MW proxy and requires an
  exact UTC calendar grid, including 92/96/100 intervals per Central day and
  complete months. No gaps are filled. `filled` remains FALSE for compatibility.
  The Fuel Mix Report is a settlement product; threshold-rule counts are
  retrospective proxy tests, not a backtest of a real-time information feed.
  The calendar figure uses ggplot2, patchwork and ggrepel (with a fixed seed
  and iteration budget to keep labels from colliding).
  `analysis/tests/test_fuel_mix.py` tests both DST transitions and rejects
  misplaced intervals even when a day's total count looks right.
- `ercot_fuel_mix_4cp_validation.csv`, written by `ch8_4cp_peaks.R`, records
  each of the 28 official intervals of 2019-2025: proxy MW, official MW,
  signed gap (proxy minus official), and daily/monthly maximum flags.
  Daily maxima match on 24/28; ending beats starting on 27/28, versus the
  retired series' 19/28 and 23/28. Monthly maxima match on 14/28 and dates on
  17/28 (the retired series matched 24/28 dates). The proxy is not an exact
  reconstruction of 4CP: net DC-tie flows and explicit Block Load Transfer
  adjustments are missing. WSL is included throughout, within `Other` before
  2022 and as a separate category thereafter. The signed gaps range from -1,087.20 to +200.42 MW.
  ERCOT's [Approved DC Tie Schedules](https://www.ercot.com/mp/data-products/data-product-details?id=NP3-765-CD)
  is public but starts in 2024 and displays seven days of schedules, not a
  complete actual-flow history for 2019 onward. No suitable credential-free
  full-period interval flow archive was found; flows are not assumed zero
  in the interpretation, only omitted from the proxy calculation.
- `official_4cp.R` is not run on its own either: `read_official_4cp()` is the
  one place `ercot_official_4cp_2018_2025.csv` is read. It keeps ERCOT's
  label (`interval_ending_cpt`) and derives `interval_start_cpt` (label minus
  15 minutes), the hour ending `he`, the decimal start hour `start_h` and the
  date-plus-start `key`, and it stops on a 00:00 label or any label that would
  move the date. All nine readers of the file load it: `ch8_4cp_peaks.R`,
  `ch8_4cp_prices.R`, `ch8_4cp_rules.R`, `ch9_flexibility_stack.R`,
  `ch9_optimal_stack.R`, `ch9_calculator_export.R`,
  `ch10_hashprice_sensitivity.R`, and the figure scripts
  `fig_ch7_as_history.R` and `fig_ch8_4cp_calendar.R`.
- `oncor_distribution.R` is not run on its own either and reads no data: it
  holds the distribution line of chapter 6's ledger (Oncor's Transmission
  Service class, 2025: Distribution System Charge and Rider DCRF per billing
  kW-month on the month's highest quarter-hour with an 80% ratchet, plus the
  customer and metering charges per meter-month) and the functions that bill
  it. `ch6_btm_ledger.R`, `ch9_optimal_stack.R`,
  `ch10_hashprice_sensitivity.R` and `ch9_calculator_export.R` source it; the
  calculator page bills it from the constants and monthly sums the export
  writes.
- `check_glossary_trace.py` checks the manuscript, as `check_citations.py` and
  `check_src_comments.py` do. It finds the numbers the glossary prints (money,
  shares and fractions, quantities with units, rates, counts in digits or words,
  positions, dates, years, clock times; its docstring lists what it leaves out),
  looks for chapter, preface and appendix lines whose prose prints the same
  value, and holds the result against the reviewed `glossary_trace.csv`. It
  exits 1 on a number no chapter prints, on one printed only out of context, on
  any row that differs from the committed map, and on an appendix src comment
  that quotes other totals than the run's. Run it after any change to a chapter
  number or to the glossary; `--update` rewrites the map once the changed rows
  have been read. `glossary_trace_exceptions.csv` beside it (entry, token,
  glossary_text, chapter_ref, chapter_text, reason) pins the restatements the
  matcher cannot see: roundings (the glossary's 9 percent for chapter 9's 8.8),
  counts and positions a chapter gives by naming things in order, complements
  (one third for two-thirds), and real homes the matcher passes over for a
  coincidence. Each row covers one occurrence in the glossary and points at the
  exact chapter line, and the checker fails a row whose line no longer contains
  its `chapter_text`, which catches both a changed number and a shifted line.

## Refreshing the fuel-mix series

`ercot_fuel_mix_15min_2019on.csv.gz` ends at a month end, and chapter 8
follows it there: Figure 8.1 and the lines listed in step 6 move when a month
is added. Figure 8.2 (`fig_ch8_4cp_window.R`, summers pinned to 2019-2025),
the rules table (`ch8_4cp_rules.R`, 2019-2025) and the 12CP haystack
(`ch8_12cp_haystack.R`, October-September years 2020-2025) are pinned and do
not move. ERCOT reposts the current year's workbook once a month with the month
just ended at INITIAL settlement and moves a month to FINAL two months after it
ends (the workbook's Disclaimer sheet), so the September 2026 refresh should
carry FINAL through July and INITIAL August-September. The 2026 workbook was
last reposted on 2026-09-08 with August (the generation page's "Fuel Mix
Report: 2026, Sep 8, 2026"; the file's Last-Modified header, read 2026-10-04);
the reposts in Internet Archive captures of that page, January 2025 to
September 2026, are dated between the 7th and the 10th of the month (October 7
in 2025).

1. Check the posting. On https://www.ercot.com/gridinfo/generation the "Fuel
   Mix Report: 2026" line carries the date of the last repost; a repost dated
   after the month ended should carry it.

2. Fetch into a new, empty cache directory and a scratch output, never over the
   committed file. Keep the output's base name: gzip stores it in the header,
   and the comparison in step 3 is otherwise never byte-identical.

   ```
   S=$(mktemp -d)
   python3 analysis/data/fetch_ercot_fuel_mix.py --history --through 2026-09-30 \
       --cache-dir "$S/cache" --out "$S/ercot_fuel_mix_15min_2019on.csv.gz" > "$S/fetch.log"
   ```

   A reused cache directory hands back the old workbook (the log says "reusing
   cached ... (not refreshed)"). If the month is not complete in the workbook
   the run stops with "calendar mismatch". Without `--through` the run ends at
   the last complete month posted and prints which one it chose.

3. Compare with the committed file.

   ```
   python3 analysis/data/compare_fuel_mix_refresh.py "$S/ercot_fuel_mix_15min_2019on.csv.gz"
   ```

   It must end "OK". Every row before the committed file's first INITIAL day
   (2026-07-01 for the September 2026 refresh) has to be the same text in both
   files; if one is not, the script exits 1, and the refresh stops until the
   revision of a FINAL month is understood. For each revised month it prints the
   settlement types before and after (expect July INITIAL to FINAL), how many
   rows changed, the MW revision, and whether the monthly peak's label changed.
   The July 2026 label is fragile: its peak interval, 2026-07-22 ending 17:30
   (90,903 MW), leads the interval ending 17:00 the same afternoon by 2 MW, and
   July goes FINAL in the October repost, so the label can flip to 17:00. No
   chapter line prints the reconstructed July 2026 label; it shows in Figure
   8.1(a). August's peak (2026-08-20 ending 17:00, 91,455 MW, the 91.5 GW of
   chapter 8) leads the interval ending 16:45 by 21 MW. Keep the log.

4. Install the file and rerun the five chapter 8 demand scripts, saving each
   console first from the committed file and then from the new one. The
   calendar figure reads the CSV the peaks script writes, so keep the order.

   ```
   run() { mkdir -p "$S/$1"; for f in analysis/checks/ch8_4cp_peaks.R analysis/figures/fig_ch8_4cp_calendar.R \
       analysis/figures/fig_ch8_4cp_window.R analysis/checks/ch8_4cp_rules.R analysis/checks/ch8_12cp_haystack.R; do
       Rscript "$f" > "$S/$1/$(basename "$f" .R).log" 2>&1 || echo "FAILED $f"; done; }
   run before
   cp "$S/ercot_fuel_mix_15min_2019on.csv.gz" analysis/data/
   run after
   diff -r "$S/before" "$S/after"
   ```

5. What to check.
   - `fig_ch8_4cp_window.R`, `ch8_4cp_rules.R`, `ch8_12cp_haystack.R`: the
     diff shows only the loader's coverage lines (the date span and the 2026
     settlement row). `book/images/fourcp_window.png` is unchanged; a
     `fourcp_window.pdf` that differs only in its CreationDate and ModDate is
     restored with `git checkout -- book/images/fourcp_window.pdf`.
   - `ch8_4cp_peaks.R`: the new month's row in the monthly peaks; "N complete
     months"; the 2026 line ("(9 months only)" after September) with the
     annual peak, still 91,455 MW on 2026-08-20 unless the new month beats it;
     the annual energy line ("(January to September only)"); the official
     comparisons (17 of 28 dates, 24/28 daily maxima, 27 of 28 ending beats
     starting) unchanged. `git diff` must show `ercot_fuel_mix_4cp_validation.csv`
     unchanged and one row added to `ercot_monthly_peak_intervals_reconstructed.csv`
     (plus any July or August row a FINAL revision moved).
   - Also in `ch8_4cp_peaks.R`, 2026 becomes a complete summer, so these lines
     move and need no book edit (no chapter line quotes them; the book's 30 of
     32, 31 of 32, 29 of 32 and 19 at 17:00 count the official intervals): the
     year list in the summer time-ending heading, the time-ending, hour-ending
     and weekday tables, "Share of summer peaks in HE 17 or HE 18", "Share on a
     weekend day", the new month's near-miss row, "Median per month", and a new
     "2026: hours within 2% of the four monthly peaks" line.
   - `fig_ch8_4cp_calendar.R`: "complete months Jan 2019 to Sep 2026; summer
     peaks: 32". The same line's "between 4 and 6 pm" and "weekend" shares can
     move; no book line quotes them, but if September's peak is outside 4-6
     p.m. or on a weekend, re-read the Figure 8.1 caption's "summer peaks
     cluster at 5~p.m.". Figure 8.1 changes; commit its PNG and PDF.
   - Only a month from October to May moves the non-summer lines ("Non-summer
     peaks in the morning (HE 7-10): 34%; in the evening (HE 17-21): 51%";
     "non-summer peaks: 61"), and then chapter 8's 12CP paragraphs (ch8:176 and
     ch8:181 on 2026-10-04) and their src comments need the same check.

6. Edit the book (line numbers as of 2026-10-04; search for the quoted text).
   - ch8:68, Figure 8.1 caption: "from January 2019 to August 2026" becomes the
     new last month. After September, delete "Only complete months count, so
     2026 shows three summer peaks."
   - ch8:73: "July and August 2026 are still initial settlement" names the
     INITIAL months of the new file, and its src comment's "FINAL through June
     2026, INITIAL July-August 2026" follows.
   - ch8:78: "the highest through August" becomes the new month; "91.5~GW on
     August 20, 2026" changes only if the new month beats it; the src comment's
     "2026 eight complete months only" takes the new count. The same line
     cites `ercot2026factsheet`, a PDF ERCOT overwrites at the same address
     each edition, for the record it calls unofficial until final settlement:
     re-read it and update the record and its read date if a newer edition
     changed it.
   - appendix-methodology.tex:182, src comment: "FINAL through June 2026 and
     INITIAL July-August 2026".
   - This file: the `ercot_fuel_mix_15min_2019on.csv.gz` row (date span,
     interval count, settlement months, retrieval date, the `--through` in the
     Rebuild column).

   Then run the checkers and build as for any manuscript edit, and commit the
   csv.gz, this README, the reconstructed-peaks CSV, Figure 8.1 and the book
   lines together. The official 2026 4CP intervals are a separate update
   (`ercot_official_4cp_2018_2025.csv`).
