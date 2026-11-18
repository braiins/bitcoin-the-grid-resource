# Chapter 5 backtest replication kit

The control-loop numbers printed in chapter 5 (the oracle-capture ladder of
Figure 5.5, the price deadband and its dial, the feed-latency cost, the full
loop's gain over a naive design, the baselines that give capture its scale,
the trend-signal sweep and the fades, the multizone validation, the optimizer
check, and the anatomy of capture behind section 5.6's explanations) come from
this directory. It
began as Braiins' internal reactive price-response study; the engine, the
study drivers, the frozen hashprice input and the ERCOT prices they run on
are all here, and the chapter's numbers are this kit's output, not the
study's.

The Rule 1 timing numbers (chapter 5: ERCOT posts each five-minute print a
median 22 s after its boundary) come from ERCOT's public MIS listing of
NP6-788, not from this kit: `../data/fetch_ercot_np6788_posting.py` snapshots
it into `../data/ercot_np6788_posting_census.csv`, and
`../checks/ch5_posting_latency.py` reads it. When a posted print becomes
readable outside ERCOT is not measured anywhere in the repository.

## Inputs (all committed)

| series | file | source | stamped |
|---|---|---|---|
| rtm15, 15-min settlement point prices, 8 load zones, 2021 on | `../data/ercot_rtm15_spp_loadzones_2021on.csv.gz` | ERCOT MIS report 13061 | Central prevailing time + repeated-hour flag |
| dam, hourly day-ahead settlement point prices, 8 load zones, 2021 on | `../data/ercot_dam_spp_loadzones_2021on.csv.gz` | ERCOT MIS report 13060 | Central prevailing time + repeated-hour flag |
| rtm5, 5-min prices, LZ_WEST, 2023-12-11 to 2026-06-22 Central | `../data/ercot_spp_rtm5_lzwest.csv.gz` | ERCOT NP6-788 | UTC |
| miner curves | `../data/miner_efficiency_telemetry_2026q2.csv` | Braiins OS fleet telemetry, 2026-Q2 | n/a |
| hashprice (USD/PH/day) | `hashprice_daily.csv` | the study's frozen input, reconstructed from public chain data (see below) | daily, UTC date |

The two MIS files are built credential-free by
`../data/fetch_ercot_rtm15_spp_history.py`. `build_prices_db.py` converts both
to UTC through the tz database (`db.cpt_local_to_utc`) and refuses to load two
rows onto the same instant.

**Superseded:** until 2026-09 the kit loaded
`../data/ercot_spp_dam_rtm15_8zones.csv.gz`, a legacy ingest cache that stamps
Central time as a fixed UTC-6 (every daylight-time interval an hour late),
drops the spring-forward intervals, ends 2026-04-21, and carries a corrupted
row (LZ_WEST rtm15 2025-06-30T21:30:00Z = $1,629.89; ERCOT's archive has
$34.17). That row sat in the out-of-sample window and was billed three times
by the ladder. Nothing in the kit reads that file any more.

## Run it

```
python3 analysis/ch5-backtest/build_prices_db.py   # prices.db, ~230 MB, ~20 s (gitignored)
python3 analysis/ch5-backtest/ingest/test_time_conversion.py   # CPT->UTC regression tests
python3 analysis/ch5-backtest/ingest/verify_alignment.py       # rtm5 vs rtm15 alignment
cd analysis/ch5-backtest
python3 mixed_basis_study.py      # the ladder (Figure 5.5), deadband dial, latency  (~80 s)
python3 naive_gap.py              # the full loop's gain over the naive design, $/yr per 1,000 (~1 min)
python3 baselines_study.py        # doing nothing and pausing alone against the oracle; residual draw (~1.5 min)
python3 capture_anatomy.py        # where capture comes from: pauses, shortfall, information vs friction, move cost, re-tune (~2.5 min)
python3 trend_followup.py         # fade-the-move variants, hold/latency decomposition (~4 min)
python3 fade_study.py             # the same fades on the settlement basis, 8 zones (parallel, --jobs N; --summary-only re-prints)
python3 optimizer_bruteforce_check.py   # the optimizer against exhaustive search, and the targets the loop applies (~4 min)
python3 multizone_study.py --all-zones   # all 8 zones on the settlement price    (~8 min)
python3 reactive_papo_trend.py    # the full 68-variant decision-signal sweep  (~17 min)
```

No external dependencies beyond the Python standard library (the ingester,
which extends the series from ERCOT's API, needs `requests` and
`python-dotenv`). Outputs land in `output/trend_study/`; the original study's
result CSVs are kept in `results/` (`*_original_study.csv`) for comparison and
are NOT the book's source.

## Files

| File | What it is | Writes |
|---|---|---|
| `build_prices_db.py` | builds the price database from the three committed ERCOT files (2,250,452 rows, 227 MB, 20.3 s on 2026-09-25) | `../data/prices.db` (gitignored) |
| `db.py` | the database schema and the one Central-to-UTC conversion | nothing (library) |
| `papo_sim.py` | the engine: miner physics, decision signals, simulator, data loaders | nothing (every driver imports it) |
| `telemetry_miner.py` | the 2026-Q2 telemetry curves (`../data/miner_efficiency_telemetry_2026q2.csv`) as the engine's miners: floors, ceilings, breakevens (`TelemetryMiner.breakeven_best`) | nothing (`papo_sim.py` imports it) |
| `hashprice_daily.csv` | the study's frozen hashprice input, USD/PH/day | (input) |
| `mixed_basis_study.py` | the capture ladder of Figure 5.5, the deadband dial, feed latency | `output/trend_study/mixed_basis.csv` |
| `naive_gap.py` | the full loop's gain over the naive design (`decide-15 S14`) and over retargeting on every print; asserts its shared rows equal `mixed_basis.csv` to the cent, so run it after that driver | `output/trend_study/naive_gap.csv` |
| `baselines_study.py` | the baselines for capture: never pausing at stock power, the stock-power oracle (chapter 6's strike rule, checked against `fig_ch6_strike.R` over calendar 2025), the backstop alone at stock power, on/off at every print, the full loop with its ceiling or its floor held at stock, the power ceiling with only the loop's backstop (`simulate(fixed_power=...)`, tripping at the best-point breakeven or at the ceiling point's own); then the full loop's sensitivity to a paused machine's residual draw (`simulate(paused_draw=...)`); asserts its S0, S1 and full-loop rows equal `mixed_basis.csv` to the cent, so run it after that driver | `output/trend_study/baselines.csv` |
| `capture_anatomy.py` | the full loop's capture taken apart: the oracle's pauses against the loop's (RECON), the target from the last print against the oracle's (SAME-TARGET), the shortfall by type and price band (SHORTFALL), information against friction (INFO), the cost of a power-target move (MOVES), the previous day's hashprice (HASHPRICE), the backstop re-tuned on 2024 alone (RETUNE), and before and after RTC+B (RTCB); asserts its S0, oracle-gain, full-loop, plain-hold and naive-design figures equal `mixed_basis.csv` to the cent, so run it after that driver | `output/trend_study/capture_anatomy.csv` |
| `trend_followup.py` | single-basis hold, latency and deadband decomposition, and the eight fades | `output/trend_study/followup.csv` |
| `fade_study.py` | the same eight fades (imported from `trend_followup.py`) on the settlement basis, 8 zones | `output/trend_study/fade_study.csv` |
| `optimizer_bruteforce_check.py` | the engine's power-target optimizer against exhaustive search, on 250,214 real prices; each curve's hull points and the targets the loop applies | `output/trend_study/optimizer_bruteforce.csv` |
| `multizone_study.py` | 8 zones x 2 fleets on the 15-minute settlement price | `output/trend_study/multizone_rtm15.csv` |
| `reactive_papo_trend.py` | the 68-variant decision-signal sweep: 67 signals against persistence | `output/trend_study/sweep_results.csv` |
| `ingest/ercot_ingest.py`, `ingest/ercot_auth.py` | the ingester that extends the series from ERCOT's API; needs a free ERCOT API Explorer account (credentials from a local `.env.local`, never printed) and a US-reachable network. Not on the path to any printed number | `../data/prices.db` |
| `ingest/test_time_conversion.py`, `ingest/verify_alignment.py` | the data tests (below) | nothing |
| `results/*_original_study.csv`, `results/sweep_repro_log.txt` | the original study's tables and its sweep reproduction log | kept for comparison only |

## What the chapter prints, and where it comes from

All from `output/trend_study/mixed_basis.csv` unless stated; window
TEST-2025-26 (2025-01-01 to 2026-06-22 Central, 154,975 paired five-minute
intervals), zone LZ_WEST, decisions on the five-minute prints, billing on the
15-minute settlement point price. TEST-2025-26 is out of sample for the price
deadband's width, the one setting chosen on 2024; the backstop's constants
were fitted on prices that overlap it, and the loop's design itself comes
from a Braiins report backtested on prices that cover it (see "Provenance of
the constants" below), so the kit calls it "out of sample" in that sense
only.

- **Capture** (`pct_of_s1`) is the share of the oracle's GAIN over running at
  stock power without pausing (S0): (strategy - S0) / (oracle - S0). Figure 5.5,
  S21 XP / S19j Pro: 15-min feed, plain hold 97.2 / 92.9; 5-min feed, plain
  hold 97.6 / 93.8; 15-min feed + deadband 97.5 / 94.5; full loop 98.1 / 96.2.
  In 2024, the window the price deadband's width was chosen on, the full loop
  is 95.1 / 92.8.
- **Price deadband** (`vs_basis_s14`): what the 10% deadband adds to the plain
  hold's gain over stock power on the same feed, +0.47% (S21 XP) and +2.56%
  (S19j Pro), at 2.4 and 26.3 target moves a day against the hold's 1.6 and
  13.4. The 25% deadband keeps 23% and 82% of that gain (console "dial" line),
  at +0.0 and +6.0 moves a day above the hold.
- **Feed latency** (`vs_full_loop`, rows `delay2`, `delay3`): each extra five
  minutes costs the full loop 0.8% (S21 XP) and 1.7% (S19j Pro) of its gain.
- `figures/fig_ch5_oracle_benchmark.R` READS this file, so Figure 5.5 cannot
  drift from the study.
- **Naive-design gap** (`naive_gap.py`, `naive_gap.csv`): the naive design is
  the weakest of Figure 5.5's four configurations, one print per 15-minute
  interval under a plain 30-minute hold (`decide-15 S14`). Out of sample the
  full loop earns $3,158 (S21 XP) and $8,469 (S19j Pro) a year more per 1,000
  machines (`usd_per_year_per_1000`: uplift difference x 365 / 538.2 days x
  1,000); over the plain hold on the fast feed alone, $1,750 and $5,984. Retargeting
  on every print (`decide-5 every print`, hold 5 min, no deadband) earns
  $27 and $164 a year per 1,000 more than the full loop, at 2.8 and 32.0
  target moves a day against 2.4 and 26.3; the price deadband wins back 98.5%
  and 97.3% of what the plain hold gives up against it (console). The rows it
  shares with `mixed_basis.csv` are asserted equal to the cent.
  `usd_per_mw_year` divides the same yearly gap per machine by stock power in
  MW: $866 (S21 XP, 3.645 MW) and $2,760 (S19j Pro, 3.068 MW) a year per MW of
  stock draw. Its console also prints the hashprice the window ran on (see
  "The hashprice input" below).
- **Baselines** (`baselines_study.py`, `baselines.csv`): never pausing at stock
  power (S0) earns 90.1% (S21 XP) and 74.8% (S19j Pro) of the oracle's profit
  (`pct_of_s1_profit`); capture is graded on the rest. Pausing alone, the
  backstop on a stock-only machine (floor = ceiling = stock power), captures
  22.30% and 65.32% of the oracle's gain at 0.18 and 0.69 pauses a day; the
  oracle held at stock power, a free pause with foresight, 24.28% and 72.52%;
  on/off at every print with no hold, 23.39% and 70.40% at 1.3 and 8.1
  switches a day. The full loop with its ceiling held at stock captures 22.65%
  and 75.30% (2024 14.16% and 53.73%; 22.02% and 74.92%, 2024 13.45% and 52.97%,
  before the 2026-10-03 `scan_powers` fix, when the scan could not reach stock
  power), with its floor raised to stock 97.52% and 86.27%: on the S21 XP
  nearly all of the loop's gain beyond pausing is running above stock power.
  With no price-following at all ("ceiling + backstop": every machine fixed at
  the power ceiling, 3,990 / 3,420 W, and paused only by the loop's own
  backstop at the curve's best-point breakeven), the fleets capture 97.61% and
  77.36% (2024 94.93% and 82.70%); with the backstop at the ceiling point's own
  breakeven instead, 97.62% and 83.13% (2024 94.87% and 84.60%). On the S21 XP
  that is within half a point of the full loop's 98.07%; on the S19j Pro the
  price-following is worth 13 to 19 points.
  Over calendar 2025 the stock oracle is worth $17,636 and $48,945 per MW-year
  of stock draw, within 2.5% (asserted) of chapter 6's fixed-strike $17,280
  and $49,116. Residual draw: each 1% of stock power billed through every
  pause takes 0.43% (S21 XP) and 1.10% (S19j Pro) off the full loop's gain
  over S0 out of sample (0.29% and 0.81% in 2024); the kit has no measurement
  of that draw, and every other number books a paused interval at zero.
- **Optimizer check** (`optimizer_bruteforce_check.py`,
  `optimizer_bruteforce.csv`): the engine's power-target optimizer against an
  exhaustive search over the measured operating points between each curve's
  floor and ceiling, plus the interpolated ends of the range (the 3,420 and
  3,990 W ceilings and the S21 XP's 2,774 W floor), on 250,214 real prices
  (2024-01-01 to 2026-06-24 UTC: 124,745 LZ_WEST NP6-788 prints and 125,469
  MIS 13061 settlement point prices over 8 zones; a seeded sample of 100,000
  positive prices per series plus every one of the 50,214 prices at or below
  zero, so the sample over-weights them). Same power target in 500,428 of
  500,428 choices over both fleets, largest shortfall $0.00 per
  machine-hour; a deliberately broken 50 W scan fails the same comparison.
  It prints each curve's upper concave hull, the only points any price can
  select: 2,774, 3,200, 3,400 and 3,990 W on the S21 XP; 1,200, 1,400, 1,600,
  1,800, 2,000, 2,600, 3,400 and 3,420 W on the S19j Pro. Its last pass runs
  the loop through every configuration `mixed_basis_study.py` scores (20 runs
  per fleet, LZ_WEST, both windows) and counts the intervals at each applied
  target: all 4 and all 8 hull points, no other target, and stock power only
  in the 26 intervals per fleet before each run's first move. Chapter 5
  prints this as "each is tuned once and every later visit reuses its saved
  profile".
- **Capture anatomy** (`capture_anatomy.py`, `capture_anatomy.csv`; each
  console line carries its block tag, and the CSV holds every number the
  console prints, to four decimals): the full loop's capture taken apart,
  S21 XP / S19j Pro, out of sample, with 2024 in parentheses. The console
  rounds each part of a sum on its own, so a printed sum of parts can miss
  its printed total by 0.01 (noted below where it does).
  - RECON: the oracle pauses in 1.89% / 8.66% of five-minute steps, and those
    steps hold 24.26% / 69.36% of its gain, the pause class (2024 18.71% /
    55.23%). The full loop is also paused in 78.53% / 67.29% of them by count
    (2024 67.20% / 60.10%), yet recovers 96.34% / 97.19% of the pause class's
    gain in dollars (2024 91.66% / 94.33%): 95.45% / 88.57% by being paused,
    the rest, net, by running below stock power through those steps, mostly
    at the floor (floor +0.58% / +6.47%, other targets below stock +0.39% /
    +2.17%, stock power and above -0.10% / -0.02%; 2024 +0.53% / +5.73%,
    +0.39% / +2.28%, -0.50% / -0.26%). Of 155 / 798 oracle pause episodes,
    those longer than 3 h are 14.2% / 10.9% of the episodes and hold 83.6% /
    79.3% of the pause class's gain, recovered at 99.4% / 99.3%; episodes of
    1 h or less are 69.0% / 71.8% of the episodes but 6.3% / 8.6% of the
    gain, recovered at 61.6% / 84.2%. In 2024 episodes over 3 h hold only
    33.0% / 42.6% of the pause class's gain and 1 to 3 h ones 49.8% / 39.4%,
    recovered at 96.9% / 98.0%. Of 178 / 1,179 spike events (runs of
    15-minute settlement intervals above the day's stock breakeven), single
    intervals are 43.8% / 40.0% of the count and 2.3% / 1.3% of the value.
  - SAME-TARGET: the target computed from print i-1 with no friction equals
    the oracle's target on step i in 98.85% / 88.37% of steps, a pause
    counting as a target (2024 98.79% / 89.96%); over the oracle's running
    steps only, 99.02% / 88.32%. The steps at or below the stock S19j Pro's
    breakeven are 86.06% of the window's steps (93.21% in 2024), hold 71.63% /
    25.77% of the oracle's gain and 16.37% / 38.28% of the full loop's
    shortfall; the loop is paused in 47 / 511 of them.
  - SHORTFALL: of 1.93 / 3.75 capture points, ran through an oracle pause
    0.89 / 1.95, paused while the oracle ran 0.91 / 0.73, running on a
    different target 0.13 / 1.07 (2024: of 4.89 / 7.20, 1.56 / 3.13, 3.13 /
    2.11 and 0.20 / 1.95; the S19j Pro's three parts round to 7.19, the CSV
    has 3.1287, 2.1147 and 1.9547 of 7.198). By the settlement point price
    over the day's best-point breakeven: at or below 0.9x 50.8% / 43.1% of
    the shortfall, 0.9 to 1.1x 9.1% / 12.1%, 1.1 to 3x 36.7% / 43.2%, above
    3x 3.3% / 1.6%.
  - INFO: a frictionless causal loop (decides on print i-1, retargets every
    print, pauses for free; no hold, no price deadband, no backstop, no
    runtimes) captures 99.03% / 97.81%, and 99.29% / 98.51% deciding on the
    current print. Of the 1.93 / 3.75 shortfall, information is 0.97 / 2.19
    (basis, no print reveals the settlement price, 0.71 / 1.49; latency 0.27
    / 0.70; the S21 XP's two parts round to 0.98, the CSV has 0.7074 and
    0.2663 of 0.9738) and friction, the loop's own rules, 0.96 / 1.56 (2024:
    information 2.48 / 5.58, friction 2.41 / 1.62). The split is sequential,
    basis first, then latency, friction as what remains: one way to
    attribute the shortfall, not the only one.
  - MOVES: charging each physical move (2.59 / 26.85 a day: 2.42 / 26.34
    moves the hold or the price deadband allows plus 0.17 / 0.51 resumes,
    each resume setting a target) in lost hashing costs 0.0345 / 0.1882
    capture points per second (2024 0.0356 / 0.2000); at 30 s a move the
    full loop captures 97.03 / 90.60, and it falls to 90% at 233.6 / 33.2 s
    (2024 143.5 / 14.0 s). It stops beating the plain hold on the five-minute
    feed at 43.1 / 26.3 s a move and the naive design at 55.2 / 33.4 s (2024
    62.1 / 29.5 s and 1.1 / 33.9 s). On the saved-profile model, where only
    the first visit to each of the 4 / 8 targets costs, 600 s per first
    visit gives 97.99 / 96.18 and 10,800 s gives 97.17 / 95.39 (2024 95.00 /
    92.65 and 93.32 / 90.44).
  - HASHPRICE: deciding on the previous UTC day's hashprice, 98.04 / 96.13
    (2024 95.10 / 92.53) against 98.07 / 96.25 on the same day's.
  - RETUNE: re-tuning `K_TRIP`, `RESTART_BAND` and `DWELL_S` on 2024 alone
    (18 settings, best 2024 capture of the full loop) picks K_TRIP $20/MW,
    band 5%, dwell 15 min on the S21 XP (2024 95.66 against the printed
    setting's 95.11, which ranks 6 of 18 there), which captures 97.86 out of
    sample (-0.21 points against the printed setting's 98.07), and the
    printed setting itself on the S19j Pro (96.25, +0.00). Over all 18
    settings the out-of-sample capture runs -0.86 to +0.05 and -1.16 to
    +0.29 points around the printed setting's. The CSV files the pick and
    the printed setting's 2024 rank under TUNE-2024, the window the pick is
    made on.
  - RTCB: out of sample before ERCOT's RTC+B go-live (2025-12-05 06:00 UTC)
    97.62 / 94.74, after it 98.86 / 98.04 (338 and 200 days; the earlier
    part holds 63.9% / 54.2% of the oracle's gain).

History of the headline, full loop out of sample: the S21 XP was at 92.3 on
the study's parametric curves; 97.6 (S21 XP) / 94.8 (S19j Pro) on the
telemetry curves with the parametric floors and the legacy price cache
(2026-08-27 to 2026-09); 98.2 / 96.2 on MIS 13061 settlement prices and the
telemetry's own best-efficiency floors (2026-09-25). Moving only the prices
(MIS 13061, old floors) gives 98.1 / 95.7, matching an external review's
rebuild; moving the floors then gives 98.2 / 96.2. The price data carries most
of the change. 98.1 / 96.2 now (98.07 / 96.25), since the S21 XP's floor
became Braiins OS's default minimum power target, 2,774 W (2026-09-26); the
S19j Pro's numbers do not move.

## The engine

- `papo_sim.py` is the study engine: miner physics, the decision signals, the
  simulator and the data loaders. `reactive_papo_trend.py` (the sweep) and
  `trend_followup.py` used to carry their own copy of it with the parametric
  curves hard-wired; since 2026-09 they import it, so every driver runs the
  same machines.
- The engine runs the **2026-Q2 fleet telemetry curves**
  (`../data/miner_efficiency_telemetry_2026q2.csv`), the same ones the
  chapter's figures draw, via `telemetry_miner.py`. The **modulation floor**
  is set in one place, `telemetry_miner.modulation_floor`: Braiins OS's
  default minimum power target (`BOS_DEFAULT_MIN_W`, from the Braiins Academy's
  Technical Resources page, table "Default Power Limits", read 2026-09-26), or
  the curve's best-efficiency point, derived from the table, where that is
  higher: 1,200 W (S19j Pro, its best point; its default, 944 W, is lower, and
  below the best point a machine is dominated) and 2,774 W (S21 XP, its
  default; its best point is 2,200 W), as chapter 5 prints. Modelling what
  Braiins OS allows by default is the author's choice (2026-09-26); until then
  the S21 XP's floor was its 2,200 W best point. The optimizer scans the floor
  and then every multiple of 10 W above it (`scan_powers`), so the off-grid
  2,774 W floor does not shift the scan off the measured points; since
  2026-10-03 it also appends the ceiling when that is off the 10 W grid.
  Default power and ceiling are 3,068 / 3,420 W and 3,645 / 3,990 W.
- **The `scan_powers` fix (2026-10-03).** The scan used to stop at the last
  multiple of 10 W below the ceiling, so a miner whose ceiling is off the grid
  could never reach it. The engine's own ceilings, 3,990 and 3,420 W, are on
  the grid, so no engine miner changes; the one variant affected is
  `baselines_study.py`'s "full loop, ceiling at stock" (ceiling 3,645 /
  3,068 W), which stopped at 3,640 / 3,060 W. Every driver whose output the
  book cites was re-run after the fix (`mixed_basis_study.py`, `naive_gap.py`,
  `baselines_study.py`, `multizone_study.py --all-zones`,
  `optimizer_bruteforce_check.py`), and again after the `simulate()` options
  below were added, together with `trend_followup.py`, `fade_study.py` and
  `reactive_papo_trend.py`: `mixed_basis.csv`, `naive_gap.csv`,
  `multizone_rtm15.csv`, `optimizer_bruteforce.csv`, `followup.csv`,
  `fade_study.csv` and `sweep_results.csv` came out byte-identical. In
  `baselines.csv` only the four "full loop, ceiling at stock" rows moved
  (capture 22.02 / 74.92 to 22.65 / 75.30 out of sample, 13.45 / 52.97 to
  14.16 / 53.73 in 2024, S21 XP / S19j Pro), and the "ceiling + backstop"
  rows were added. The trend, fade and sweep drivers only ever build the
  engine's miners, whose scan does not change.
- `PAPO_PARAMETRIC=1` restores the study's original two-point linear fit, with
  its original floors (1,630 W and 2,760 W), for comparison.
- A power target move is free in `simulate()` by default: once the hold or
  the price deadband allows it, the new target applies within the interval at
  full curve efficiency, and `changes` only counts it. `simulate(targets=Counter())`
  counts the intervals spent at each applied target and changes nothing else;
  the loop only ever sets stock power (its starting value), a result of
  `optimal_power`, or, when `fixed_power` is given, that fixed target and
  nothing else (`baselines_study.py`, the only driver that passes it, passes
  the power ceiling, itself a hull point). The firmware's settling period on
  a target with no saved tuning profile is not modeled in any printed number
  except `capture_anatomy.py`'s MOVES block, so every other gain the kit
  prints comes before any cost of the moves (chapter 5 says so).
- `simulate(move_loss_s=x)` charges every physical power-target change the
  loop makes (a move the hold or the price deadband allows, and the target
  set at each backstop resume) x seconds of lost hashing while the power is
  still billed at the new target; `simulate(first_visit_s=y)` is the
  saved-profile model: y seconds of zero hashing at full draw the first time
  in a run the loop applies each distinct target, later visits free (the
  starting target counts as already tuned). Lost hashing is a blackout window
  laid over the five-minute grid; a new charge extends an open window, never
  shortens it. The result always carries `moves`, `moves_per_day` (physical
  changes: `changes` plus resumes), `resumes` and `first_visits`; the first
  three are counted on every run, `first_visits` only when `move_loss_s` or
  `first_visit_s` is above 0 (it is 0 otherwise).
- `simulate(hps_decide=series)` lets the loop decide (its power target and
  the backstop's breakeven) on a second hashprice series while revenue stays
  at `hps`; `capture_anatomy.py` passes the previous UTC day's value.
- `simulate(fixed_power=p)` runs a fixed-target strategy on the same curve:
  the loop starts at p, never moves it, and resumes to it after every pause.
  Its backstop trips at `backstop_be(hp)`, by default the miner's best-point
  breakeven (the loop's own backstop); `papo_sim.point_breakeven(miner, p)`
  gives the fixed point's own breakeven instead.
- `simulate(k_trip=, restart_band=, dwell_s=)` override the backstop
  constants for one run (`capture_anatomy.py` RETUNE), and
  `simulate(trace=[])` collects each interval's booked profit and applied
  power target (0.0 while paused).
- Every one of these options defaults to the behavior every committed number
  was computed with, and S0 and S1 ignore them all.
- `check_breakevens()` pins breakevens at $44.31/PH/day and the floors for each
  model: telemetry 148/144 (S21 XP) and 77/65 (S19j Pro) $/MWh at best point /
  stock, floors 2,774 and 1,200 W. The best point is the best J/TH over the
  engine's range, 3,200 W on the S21 XP, not its floor. On the 2,200 W
  best-point floor the S21 XP's was 149; with the old parametric floors the
  telemetry best-point breakevens were 148 and 76.
- `db.py` owns the database schema and the one Central-to-UTC conversion.
- `hashprice_daily.csv` here is the study's frozen input (USD/PH/day),
  distinct from `../data/hashprice_daily.csv` (the book's stitched
  Braiins Insights series, USD/TH/day). See "The hashprice input" below.
- `simulate(paused_draw=r)` charges a machine the loop has paused r times its
  stock power at the settlement price of each paused interval. The default,
  0, books a paused interval at zero, as every printed number does;
  `baselines_study.py` alone sets it, for the residual-draw sensitivity.

## Provenance of the constants

The full loop's settings did not all come from the same place, and only one
was chosen on the 2024 window:

- the price deadband's width, 10% of stock power, was chosen on TUNE-2024
  (`mixed_basis_study.py`, `multizone_study.py`); TEST-2025-26 is out of sample
  for it;
- the backstop's constants, `K_TRIP` ($10/MW), `RESTART_BAND` (10%) and
  `DWELL_S` (15 minutes), come from an earlier Braiins backstop study whose
  grid search ran on LZ_WEST five-minute prints from 2023-12-11 to
  2026-06-23, a span that overlaps TEST-2025-26; the runtimes and the cycle
  budget came with them. The note above `K_TRIP` in `papo_sim.py` records
  this;
- the loop's design itself, persistence (deciding on the last print) every
  five minutes under a 30-minute hold (`simulate(hold_s=1800)`, the kit's
  `decide-5 S14`), comes from the Braiins report that defined S14, whose
  backtest ran, by its own account, on LZ_WEST five-minute prices from
  January 2025 to August 2026, a span that covers TEST-2025-26; the reactive
  price-response study this kit began as took S14 as its baseline and added
  the price deadband. The same note in `papo_sim.py` records this.

`capture_anatomy.py` RETUNE measures the exposure of the backstop's
constants: it re-tunes the three on TUNE-2024 alone and prints the
TEST-2025-26 capture of the pick next to the printed setting's (see "Capture
anatomy" above). Nothing in the kit re-selects the loop's design on
TUNE-2024 alone, so its exposure is not measured as a number.

## The hashprice input

`hashprice_daily.csv` came with the original study. Its own documentation
describes it as realized daily hashprice in USD/PH/day reconstructed from
public chain data, expected block revenue over the hashrate implied by
difficulty, and says it matched the series of the report that study checked
to about 1% (mean 44.34 against 44.31 $/PH/day over that report's window). The
script that built it did not survive, so the file is kept frozen, and
`naive_gap.py` prints, for each window, its mean over the paired intervals
beside the book's own Braiins Insights series (`../data/hashprice_daily.csv`)
on the same intervals:

- out of sample (TEST-2025-26), $45.41 against $45.46 per PH per day
  ($0.0454 and $0.0455 per TH per day); 51 of 536 days differ by more than
  $1, and none by more than $3.77 (2025-07-12). The file lacks 2025-11-13 to
  15, which the engine carries from the day before;
- in 2024 (TUNE-2024), $64.49 against $64.01; 160 of 366 days differ by
  more than $1, the largest by $85.63 on 2024-04-20, the day of the fourth
  halving, which the file puts at $176.25 and the Braiins Insights series at
  $90.62.

The hashprice chapter 5 prints for the out-of-sample window, about $0.045
per TH per day, is the same on either series; the 2024 figures
rest on this file.

## Data tests

- `ingest/test_time_conversion.py` guards the DST bug the study documented:
  ERCOT's DSTFlag marks the repeated autumn hour, not "daylight time is in
  effect", and reading it the second way stamps every CDT row an hour late.
  The ingester carried that bug until 2026-09 (and could not be imported: its
  `db` module was missing); both are fixed and the test runs the row parser end
  to end.
- `ingest/verify_alignment.py` pairs rtm5 with rtm15 month by month at whole-
  hour shifts, then slides the five-minute series by -15..+15 minutes to show
  the three prints inside each settlement interval track that interval's
  settlement at zero lag. It used to point at a non-existent
  `ch5-backtest/data/prices.db`.

## Other checks that use the same data

- `../checks/ch5_price_autocorrelation.py`: the autocorrelation of price
  changes chapter 5 quotes (LZ_WEST five-minute prints), with the 15-minute
  settlement series of all eight zones for contrast.
- `../checks/ch5_adder_example.py`: chapter 5's example of an interval billed
  far above its prints (2025-01-13, before RTC+B).
- `../checks/ch5_oracle_check.R`: a simulator-free check on how rarely
  foresight pays (86.5% of 2025's five-minute intervals below the stock S19j
  Pro's breakeven). Its capture ratios are for a pause-only oracle at stock
  power, not Figure 5.5's; `baselines_study.py` gives the pause-only baselines
  against Figure 5.5's oracle.
- `../checks/ch5_stakes.py`: chapter 5's cost-to-revenue multiple for a
  $1,600 hour, and how often LZ_WEST prices at or above $1,600.
- `../checks/ch5_posting_latency.py`: when ERCOT posts each five-minute
  print, from the NP6-788 listing census.
- `../checks/ch5_vfloor.py`: what the fleet telemetry the kit runs on shows
  below each machine's best-efficiency point (1,200 and 2,200 W), against a
  Braiins OS chip-autotuning engineer's modelled curves and Braiins OS's
  default power limits, and the modulation floor `telemetry_miner.py` takes
  from them: 1,200 W on the S19j Pro (its best point; its default minimum,
  944 W, is lower) and 2,774 W on the S21 XP (its default minimum; its best
  point, 2,200 W, is lower). Part 3 checks `BOS_DEFAULT_MIN_W` against its
  transcription of the Academy table.

## The claims that came from the original study, re-run 2026-09-26

On the rebuilt database and the current floors (the S21 XP's at Braiins OS's
default minimum, 2,774 W, since 2026-09-26; the S19j Pro's rows do not move); both drivers print these as a
summary at the end of their run. The original study's tables in `results/`
are kept for comparison only.

- **Multizone** (`multizone_study.py --all-zones`, `multizone_rtm15.csv`, 8
  zones x 2 fleets on the 15-minute settlement price, windows aligned with the
  other drivers: TUNE 2024, TEST 2025-01-01 to 2026-06-23 UTC). Plain-hold
  backstop pauses 0.12 to 0.53 a day (the study printed 0.15 to 0.50). The
  10, 15 and 25% deadbands beat the plain hold in 16/16 cells in both windows;
  the 40% deadband in 8/16, because on the S21 XP it equals the plain hold
  exactly: 40% of 3,645 W is 1,458 W, more than the 1,216 W from the S21 XP's
  2,774 W floor to its 3,990 W ceiling, so it cannot fire (16/16 at all four
  widths on the earlier 2,200 W floor). Every width changes the backstop pause
  COUNT by exactly 0 in every cell (the CSV now carries the integer count,
  `stops`). Trend signals: out of sample the two gentlest OLS slopes (W30 g5,
  W60 g5) edge past persistence in 10 of 16 cells (8 of 16 on the earlier
  floor), by at most +0.12% of the hold's uplift; the other five
  representative signals lose in all 16. The study's "0/16 cells positive"
  does not reproduce, and did not in its own table either (10/16 there).
- **68-variant sweep** (`reactive_papo_trend.py`, `sweep_results.csv`, LZ_WEST
  five-minute prints, single basis, 30-minute hold). Out of sample: S19j Pro
  0 of 67 signals beat persistence; S21 XP 3 of 67 on `delta_pct` (ewma hl10
  +0.16%, quant W15 q60 +0.13%, ewma hl15 +0.10% of the hold's uplift, $1 per
  machine over 538 days, whole dollars; 5 of 67, best +0.29%, on the earlier
  2,200 W floor); no slope extrapolation beats it on either fleet. In sample
  (2024) 6 and 9 smoothing or quantile variants do (S19j Pro, S21 XP; this
  README said 5 for the S19j Pro, which the committed CSV did not show).
- **Follow-up** (`trend_followup.py`, `followup.csv`): single-basis hold,
  latency and deadband decomposition plus eight "fade the move" variants.
  Re-run 2026-09-26 on the 2,774 W floor: the S19j Pro's rows are unchanged.
  Six fade every move; the two fade-asym variants fade falls only (up0 dn-10)
  or fade falls while extrapolating rises (up15 dn-10). Out of sample some
  fades edge past persistence at LZ_WEST (best fade-end W15 g-5 +0.15%, $0.81
  per machine, S21 XP; fade-end W30 g-5 +0.15%, $0.50, S19j Pro; the S21 XP's
  best was +0.32%, $1.71, on the earlier floor); both fade-asym variants lose
  on both fleets.
- **Fade study** (`fade_study.py`, `fade_study.csv`): the same eight fades
  on the settlement basis. Deciding on the print and billing on the
  settlement point price changes little (+0.15% / +0.15%); on the 15-minute
  settlement point price in all 8 zones they come out ahead in 0 of 16 cells
  out of sample (best -$0.02; 1 of 16, by $0.02, on the earlier floor). At 15
  minutes the W15 OLS-based signals equal persistence and fade-ols W30 g-10
  equals fade-end W30 g-10, so four distinct signals are scored there. Two
  probes fade rises only (best +0.31%, S21 XP; both lose on the S19j Pro). Chapter 5 prints one sentence from this and
  `followup.csv`.

Braiins' own material, published here for the first time, like the
telemetry curves.
