#!/usr/bin/env python3
"""ch5_stakes.py -- chapter 5's "the stakes are wildly asymmetric": what one hour
of hashing at $1,600 per megawatt-hour costs against the revenue it earns, and
how often LZ_WEST actually prices at $1,600. Run from the repo root:

    python3 analysis/checks/ch5_stakes.py

THE RATIO. Chapter 4's identity gives the revenue a megawatt-hour earns,
41,666.7 x hashprice / (J/TH), with hashprice in USD/TH/day. An hour at power P
buys P MWh at the price and earns P x that revenue, so the power cancels and
the hour costs price / revenue-per-MWh times what it earns. The script prints
that multiple at each period's mean hashprice (the basis of chapter 4's $72 and
$157 strikes), and the range of the daily multiples, for:
  * nameplate stock efficiency, 29.5 J/TH (S19j Pro) and 13.5 J/TH (S21 XP),
    the machines chapter 4 prices;
  * the power ceiling, the "full power" of chapter 5: the engine's ceiling
    (papo_sim.py, 3,420 W and 3,990 W) at the efficiency the 2026-Q2 fleet
    telemetry measures there (analysis/data/miner_efficiency_telemetry_2026q2.csv
    through analysis/ch5-backtest/telemetry_miner.py).
Periods: calendar 2025, and 2026 from January 1 to the last day of the
settlement series (the book's "2026 to date").

Hashprice is the gap-filled daily series every ledger runs on, built as
analysis/checks/ch9_hashprice.R builds it: the spliced column of
analysis/data/hashprice_daily_2021on.csv, with its ten missing days taken from
analysis/data/hashprice_daily.csv after checking that the two agree on every
day both carry. The run stops if they disagree or if any day stays missing.
Over 2025 the spliced column is a copy of hashprice_daily.csv, so the 2025 mean
is chapter 4's: 0.0508 (0.050785; chapter 4's comments truncate it to 0.0507).

HOW OFTEN $1,600. Counted on LZ_WEST, by Central calendar year:
  * five-minute prints (NP6-788, analysis/data/ercot_spp_rtm5_lzwest.csv.gz,
    2023-12-11 to 2026-06-22), the series the loop decides on;
  * 15-minute settlement point prices (MIS 13061,
    analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz, 2021 to date), the
    series the site is billed on;
  * clock hours (Central prevailing time) whose four settlement intervals
    average $1,600 or more, which is what "one hour at $1,600" means.
Beside $1,600 it prints the same counts at a ladder of other levels, the
highest hour of each year, and the median of the prints at or above $1,000, so the
example can be judged against the spikes that actually happened.

Pure stdlib, apart from the chapter 5 kit's miner model for the ceiling rows.
"""
import csv
import gzip
import os
import statistics
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "analysis", "ch5-backtest"))
from papo_sim import MINERS, MINER_MODEL  # noqa: E402  (telemetry curves, engine ceiling)

DATA = os.path.join(ROOT, "analysis", "data")
RTM5 = os.path.join(DATA, "ercot_spp_rtm5_lzwest.csv.gz")
RTM15 = os.path.join(DATA, "ercot_rtm15_spp_loadzones_2021on.csv.gz")
SPLICED = os.path.join(DATA, "hashprice_daily_2021on.csv")
BRAIINS = os.path.join(DATA, "hashprice_daily.csv")
CENTRAL = ZoneInfo("America/Chicago")
FMT = "%Y-%m-%dT%H:%M:%SZ"
K = 3.6e9 / 86400                 # 41,666.7: chapter 4, $/MWh per ($/TH/day per J/TH)
PRICE = 1600.0                    # the chapter's example, $/MWh
NAMEPLATE = {"S19j Pro": 29.5, "S21 XP": 13.5}   # bitmain2021s19jpro, bitmain2024s21xp
ENGINE_KEY = {"S19j Pro": "S19jPro", "S21 XP": "S21XP"}
LADDER = (500, 1000, 1600, 2000, 3000, 4000, 4900)


def hashprice_filled():
    """Daily USD/TH/day with no gaps, as ch9_hashprice.R builds it."""
    hp = {}
    with open(SPLICED, newline="") as f:
        for r in csv.DictReader(f):
            if r["date"] in hp:
                raise SystemExit(f"duplicate hashprice date {r['date']}")
            hp[r["date"]] = float(r["usd_th_day_spliced"])
    bk = {}
    with open(BRAIINS, newline="") as f:
        for r in csv.DictReader(f):
            bk[r["date"]] = float(r["usd_th_day"])
    both = sorted(set(hp) & set(bk))
    dev = max(abs(hp[d] - bk[d]) for d in both)
    d0, d1 = date.fromisoformat(min(hp)), date.fromisoformat(max(hp))
    cal = [(d0 + timedelta(days=i)).isoformat() for i in range((d1 - d0).days + 1)]
    miss = [d for d in cal if d not in hp]
    if miss:
        if dev > 1e-6:
            raise SystemExit(f"hashprice fill refused: the two files differ by up to {dev:.3g} "
                             f"on their {len(both)} shared days")
        if any(d not in bk for d in miss):
            raise SystemExit("hashprice gap hashprice_daily.csv cannot fill: "
                             + ", ".join(d for d in miss if d not in bk))
        for d in miss:
            hp[d] = bk[d]
    assert all(d in hp for d in cal)
    print(f"hashprice: {cal[0]} to {cal[-1]}, {len(cal)} calendar days; {len(miss)} missing from "
          f"the spliced series filled from hashprice_daily.csv, which matches it on all "
          f"{len(both)} shared days (largest difference {dev:.1e} $/TH/day)")
    return hp


def ceiling_jth():
    """J/TH at the engine's power ceiling on the measured telemetry curve."""
    out = {}
    for name, key in ENGINE_KEY.items():
        m = MINERS[key]
        out[name] = (m.p_max, m.p_max / m.hashrate(m.p_max))
    return out


def load_prices():
    """LZ_WEST five-minute prints and 15-minute settlements, keyed for counting."""
    p5 = []                                     # (Central datetime, price)
    with gzip.open(RTM5, "rt", newline="") as f:
        for r in csv.DictReader(f):
            t = datetime.strptime(r["interval_start"], FMT).replace(tzinfo=timezone.utc)
            p5.append((t.astimezone(CENTRAL), float(r["price"])))
    p15 = []                                    # (local start string, dst flag, price)
    with gzip.open(RTM15, "rt", newline="") as f:
        for r in csv.DictReader(f):
            if r["settlement_point"] == "LZ_WEST":
                p15.append((r["interval_start"], r["dst_repeated_flag"], float(r["price"])))
    return p5, p15


def main():
    hp = hashprice_filled()
    p5, p15 = load_prices()
    last_settle = max(s for s, _, _ in p15)[:10]
    periods = {"2025": ("2025-01-01", "2025-12-31"),
               "2026 to date": ("2026-01-01", last_settle)}
    ceil = ceiling_jth()

    print(f"\n1. ONE HOUR AT ${PRICE:,.0f}/MWh AGAINST WHAT IT EARNS "
          f"(revenue/MWh = {K:,.1f} x hashprice / J/TH)")
    for label, (a, b) in periods.items():
        days = sorted(d for d in hp if a <= d <= b)
        n_days = (date.fromisoformat(b) - date.fromisoformat(a)).days + 1
        assert len(days) == n_days, f"{label}: {len(days)} hashprice days, calendar has {n_days}"
        hmean = statistics.fmean(hp[d] for d in days)
        print(f"\n  {label} ({a} to {b}, {len(days)} days): mean hashprice ${hmean:.4f}/TH/day "
              f"(daily ${min(hp[d] for d in days):.4f} to ${max(hp[d] for d in days):.4f})")
        rows = [(f"{m} nameplate {e} J/TH", e) for m, e in NAMEPLATE.items()]
        rows += [(f"{m} ceiling {p:,.0f} W, {e:.2f} J/TH", e) for m, (p, e) in ceil.items()]
        for name, e in rows:
            rev = K * hmean / e
            daily = [PRICE * e / (K * hp[d]) for d in days]
            print(f"    {name:<36} earns ${rev:6.2f}/MWh; the hour costs {PRICE / rev:5.2f}x "
                  f"what it earns, loses {(PRICE - rev) / rev:5.2f}x "
                  f"(daily multiples {min(daily):.1f} to {max(daily):.1f})")

    print(f"\n   (ceiling efficiency from the {MINER_MODEL} model the chapter 5 kit runs on)")

    # ------------------------------------------------------------ frequency ---
    print(f"\n2. HOW OFTEN LZ_WEST PRICES AT ${PRICE:,.0f} OR MORE (Central calendar years)")

    by5 = defaultdict(list)
    for t, p in p5:
        by5[t.year].append((t, p))
    print(f"\n  five-minute prints (NP6-788), {p5[0][0]:%Y-%m-%d} to {p5[-1][0]:%Y-%m-%d} Central")
    for y in sorted(by5):
        v = by5[y]
        hi = [t for t, p in v if p >= PRICE]
        days = len({t.date() for t in hi})
        ladder = "  ".join(f">=${L:,}: {sum(1 for _, p in v if p >= L)}" for L in LADDER)
        big = [p for _, p in v if p >= 1000]
        med = f"${statistics.median(big):,.0f}" if big else "n/a"
        print(f"    {y}: {len(v):>7,} prints; >=${PRICE:,.0f}: {len(hi):>3} prints on {days:>2} days; "
              f"max ${max(p for _, p in v):,.2f}; median of prints >=$1,000 {med} (n={len(big)})")
        print(f"          {ladder}")

    by15 = defaultdict(list)
    hours = defaultdict(list)
    for s, flag, p in p15:
        by15[int(s[:4])].append((s, p))
        hours[(s[:13], flag)].append(p)
    print(f"\n  15-minute settlement point prices (MIS 13061), {p15[0][0][:10]} to {last_settle}")
    for y in sorted(by15):
        v = by15[y]
        hi = [s for s, p in v if p >= PRICE]
        ladder = "  ".join(f">=${L:,}: {sum(1 for _, p in v if p >= L)}" for L in LADDER)
        print(f"    {y}: {len(v):>6,} intervals; >=${PRICE:,.0f}: {len(hi):>4} on "
              f"{len({s[:10] for s in hi}):>2} days; max ${max(p for _, p in v):,.2f}")
        print(f"          {ladder}")

    print(f"\n  clock hours whose four settlement intervals average ${PRICE:,.0f} or more")
    hy = defaultdict(list)
    for (h, flag), ps in hours.items():
        if len(ps) == 4:
            hy[int(h[:4])].append((h, sum(ps) / 4))
    for y in sorted(hy):
        v = hy[y]
        hi = sorted((m, h) for h, m in v if m >= PRICE)
        top = max(v, key=lambda x: x[1])
        ladder = "  ".join(f">=${L:,}: {sum(1 for _, m in v if m >= L)}" for L in LADDER)
        print(f"    {y}: {len(v):>5,} full hours; >=${PRICE:,.0f}: {len(hi):>3} on "
              f"{len({h[:10] for _, h in hi}):>2} days; highest hour {top[0]}:00 Central "
              f"averaging ${top[1]:,.2f}")
        print(f"          {ladder}")

    # what the highest hours cost the machines, at the day's hashprice and at
    # the period mean (nameplate efficiency)
    print("\n  the highest hour of 2025 and of 2026 to date, cost against revenue at nameplate:")
    for label, (a, b) in periods.items():
        y = int(a[:4])
        h, m = max(hy[y], key=lambda x: x[1])
        hmean = statistics.fmean(hp[d] for d in hp if a <= d <= b)
        hday = hp[h[:10]]
        day = "; ".join(f"{name} {m * e / (K * hday):.1f}x" for name, e in NAMEPLATE.items())
        mean = "; ".join(f"{name} {m * e / (K * hmean):.1f}x" for name, e in NAMEPLATE.items())
        print(f"    {label}: {h}:00 Central, ${m:,.2f}/MWh; at that day's hashprice "
              f"${hday:.4f}: {day}; at the period mean: {mean}")


if __name__ == "__main__":
    main()
