#!/usr/bin/env python3
"""ch5_adder_example.py -- chapter 5's example of an interval billed far above
the prints the loop decided on. Run from the repo root:

    python3 analysis/checks/ch5_adder_example.py

Before RTC+B, ERCOT's real-time settlement point price was the interval's
energy price plus two adders, the ORDC reserve adder and the
reliability-deployment adder. The five-minute prints the loop decides on carry
neither, so in a scarcity interval the bill can sit well above every print.
RTC+B (live December 5, 2025) retired the separate ORDC adder by folding
scarcity into the co-optimized price itself; the reliability-deployment adder
remains.

The search, LZ_WEST, over every settlement interval before RTC+B for which all
three five-minute prints exist:
  settlement  ERCOT MIS 13061 (analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz)
  prints      NP6-788 five-minute prices (analysis/data/ercot_spp_rtm5_lzwest.csv.gz)
It ranks intervals by settlement / highest print and by settlement minus mean
print, then picks the example the chapter needs: the interval with the largest
settlement / highest-print ratio in which every print the loop could have
seen, from an hour before the interval to its last print, sat BELOW the
S19j Pro's best-point breakeven while the settlement sat ABOVE it. That is the
case where a loop deciding on prints does not pause and is billed a loss. It
then prints the unbroken run of such intervals the example sits in.

Why not the candidates external reviews proposed: 2024-08-20 20:15 Central
(settled $2,070.26 on prints of $881 to $1,495) was billed above what it
showed, but its prints sat far above every breakeven, so the loop would have
been pausing anyway; 2024-04-16 20:45 Central (settled $304.71 on prints of
$100 to $132) came at the tail of an hour of prints up to $4,998, so the loop
would already have paused; and 2025-01-15 07:30 Central (settled $2,197.00
against a "peak print" of $388.09) pairs the settlement with the prints of the
interval an hour earlier: its own prints were $2,032.56 to $2,073.52 (1.06x),
and every print from 06:55 to 07:45 sat above $1,800, far above every
breakeven. None of the three is a case of hashing through.

Breakevens use chapter 4's identity, breakeven = 41,666.7 x hashprice / (J/TH),
on the day's hashprice from analysis/data/hashprice_daily.csv (USD/TH/day), at
the nameplate stock efficiency (29.5 and 13.5 J/TH) and at the best efficiency
inside the loop's power range, whose breakeven the loop's backstop uses
(analysis/ch5-backtest/telemetry_miner.py TelemetryMiner.breakeven_best): 23.83
J/TH at 1,200 W on the S19j Pro, its modulation floor, and 12.44 J/TH at 3,200 W
on the S21 XP, above its 2,774 W floor (12.40 at 2,200 W until 2026-09-26, when
that best point was the S21 XP's floor), on
analysis/data/miner_efficiency_telemetry_2026q2.csv.

Pure stdlib.
"""
import csv
import gzip
import os
import sys
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "analysis", "ch5-backtest"))
from db import cpt_local_to_utc  # noqa: E402  (tz-database Central -> UTC)

DATA = os.path.join(ROOT, "analysis", "data")
RTM5 = os.path.join(DATA, "ercot_spp_rtm5_lzwest.csv.gz")
RTM15 = os.path.join(DATA, "ercot_rtm15_spp_loadzones_2021on.csv.gz")
HASHPRICE = os.path.join(DATA, "hashprice_daily.csv")
CENTRAL = ZoneInfo("America/Chicago")
FMT = "%Y-%m-%dT%H:%M:%SZ"
K = 41666.7                       # chapter 4: $/MWh per ($/TH/day per J/TH)
NAMEPLATE = {"S19j Pro": 29.5, "S21 XP": 13.5}   # bitmain2021s19jpro, S21 XP spec
RTCB = int(datetime(2025, 12, 5, tzinfo=CENTRAL).timestamp())
epoch = lambda s: int(datetime.strptime(s, FMT).replace(tzinfo=timezone.utc).timestamp())
central = lambda t: datetime.fromtimestamp(t, CENTRAL)


def best_jth():
    """Best J/TH over each engine miner's scan, floor to ceiling: the point
    whose breakeven the loop's backstop uses (TelemetryMiner.breakeven_best)."""
    from papo_sim import MINERS  # noqa: E402  (the kit's telemetry miners)
    from telemetry_miner import MODEL_FOR  # noqa: E402
    return {MODEL_FOR[k]: min(p / m.hashrate(p) for p in m.scan_powers())
            for k, m in MINERS.items()}


def main():
    p5 = {}
    with gzip.open(RTM5, "rt", newline="") as f:
        for r in csv.DictReader(f):
            p5[epoch(r["interval_start"])] = float(r["price"])
    lo, hi = min(p5), max(p5)
    spp = {}
    with gzip.open(RTM15, "rt", newline="") as f:
        for r in csv.DictReader(f):
            if r["settlement_point"] != "LZ_WEST" or r["interval_start"] < "2023-12":
                continue
            local = datetime.strptime(r["interval_start"], "%Y-%m-%dT%H:%M:%S")
            t = epoch(cpt_local_to_utc(local, r["dst_repeated_flag"] == "Y"))
            if lo <= t <= hi:
                spp[t] = float(r["price"])
    hp = {}
    with open(HASHPRICE, newline="") as f:
        for r in csv.DictReader(f):
            hp[r["date"]] = float(r["usd_th_day"])
    jbest = best_jth()

    rows = []
    for b, s in spp.items():
        ks = (b, b + 300, b + 600)
        if all(k in p5 for k in ks):
            pr = [p5[k] for k in ks]
            rows.append((b, s, pr, max(pr), sum(pr) / 3))
    pre = [r for r in rows if r[0] < RTCB]
    post = [r for r in rows if r[0] >= RTCB]

    def show(r):
        b, s, pr, mx, mean = r
        prints = ", ".join(f"${v:,.2f}" for v in pr)
        return (f"{central(b):%Y-%m-%d %H:%M} Central  settled ${s:,.2f}  "
                f"prints {prints}  settlement / highest print {s / mx:.2f}x  "
                f"gap to mean print ${s - mean:,.2f}")

    print(f"LZ_WEST settlement intervals with all three prints: {len(rows):,} "
          f"({len(pre):,} before RTC+B, {len(post):,} after)")
    print("\nbefore RTC+B, largest settlement / highest print (settlement >= $100):")
    for r in sorted((r for r in pre if r[1] >= 100 and r[3] > 0),
                    key=lambda r: -r[1] / r[3])[:6]:
        print("  " + show(r))
    print("\nbefore RTC+B, largest dollar gap between settlement and mean print:")
    for r in sorted(pre, key=lambda r: -(r[1] - r[4]))[:6]:
        print("  " + show(r))

    # the chapter's example: invisible to a loop deciding on prints, billed a loss
    def breakevens(b):
        h = hp.get(central(b).strftime("%Y-%m-%d"))
        if h is None:                       # the series starts 2024-01-01
            return None, None
        return h, {m: (K * h / NAMEPLATE[m], K * h / jbest[m]) for m in NAMEPLATE}

    picks = []
    for r in pre:
        b, s, pr, mx, mean = r
        if s < 100:
            continue
        h, be = breakevens(b)
        if h is None:
            continue
        seen = [p5[t] for t in range(b - 3600, b + 601, 300) if t in p5]
        if max(seen) < be["S19j Pro"][1] < s:
            picks.append((s / mx, r, h, be, max(seen)))
    picks.sort(key=lambda x: -x[0])
    print("\ncandidates (settlement / highest print; S19j Pro best-point breakeven):")
    for x in picks[:8]:
        print(f"  {show(x[1])}  S19j Pro best-point breakeven ${x[3]['S19j Pro'][1]:,.2f}")
    ratio, r, h, be, seen_max = picks[0]
    b, s, pr, mx, mean = r
    print(f"\n{len(picks)} pre-RTC+B intervals were billed above the S19j Pro's "
          f"best-point breakeven while every print from an hour before sat below it.")
    print("CHOSEN EXAMPLE (largest settlement / highest print among them):")
    print("  " + show(r))
    print(f"  highest print from 60 minutes before through the interval: ${seen_max:,.2f}")
    print(f"  hashprice that day: ${h:.4f}/TH/day (analysis/data/hashprice_daily.csv)")
    for m, (stock, best) in be.items():
        verdict = []
        verdict.append("prints below" if seen_max < best else "prints ABOVE")
        verdict.append("bill above" if s > best else "bill below")
        print(f"  {m:<9} breakeven ${stock:,.2f} at nameplate stock, "
              f"${best:,.2f} at best efficiency ({'; '.join(verdict)} the best-point breakeven)")
    print("  prints around it (Central):")
    for t in range(b - 1800, b + 1801, 300):
        if t in p5:
            mark = "  <- in the interval" if b <= t < b + 900 else ""
            print(f"    {central(t):%H:%M}  ${p5[t]:9.2f}{mark}")

    # the episode: the unbroken run of such intervals the chosen one sits in
    qual = {x[1][0]: x for x in picks}
    first = last = b
    while first - 900 in qual:
        first -= 900
    while last + 900 in qual:
        last += 900
    run = [qual[t] for t in range(first, last + 1, 900)]
    worst_print = max(max(x[1][2]) for x in run)
    seen_run = max(p5[t] for t in range(first - 3600, last + 601, 300) if t in p5)
    s21_best = be["S21 XP"][1]
    print(f"\n  EPISODE: {len(run)} consecutive settlement intervals, "
          f"{central(first):%H:%M} to {central(last + 900):%H:%M} Central, each billed "
          f"above the S19j Pro's best-point breakeven (${be['S19j Pro'][1]:,.2f})")
    print(f"    settlements ${min(x[1][1] for x in run):,.2f} to "
          f"${max(x[1][1] for x in run):,.2f}; highest print inside the run "
          f"${worst_print:,.2f}; highest print from an hour before ${seen_run:,.2f}")
    print(f"    billed above the S21 XP's best-point breakeven (${s21_best:,.2f}) in "
          f"{sum(1 for x in run if x[1][1] > s21_best)} of them")
    nxt = next(t for t in range(last + 900, last + 86400, 300)
               if t in p5 and p5[t] > seen_run)
    print(f"    first print above ${seen_run:,.2f} after the run: "
          f"{central(nxt):%Y-%m-%d %H:%M} Central (${p5[nxt]:,.2f})")

    gap = lambda rs: sum(abs(r[1] - r[4]) for r in rs) / len(rs)
    big = lambda rs: sum(1 for r in rs if r[1] > 1.5 * r[3] and r[1] >= 100)
    print(f"\nmean |settlement - mean print|: ${gap(pre):.3f} before RTC+B, "
          f"${gap(post):.3f} after")
    print(f"intervals settled >= $100 and above 1.5x their highest print: "
          f"{big(pre)} before RTC+B, {big(post)} after")

    # the reliability-deployment adder survives RTC+B, so the settlement point
    # price can still sit above every print it was decided on (chapter 5)
    w = max(post, key=lambda r: r[1] - r[3])
    print(f"largest settlement above the highest print after RTC+B: "
          f"{datetime.fromtimestamp(w[0], timezone.utc).astimezone(ZoneInfo('America/Chicago')):%Y-%m-%d %H:%M} Central, "
          f"settled ${w[1]:,.2f} on a highest print of ${w[3]:,.2f}")


if __name__ == "__main__":
    main()
