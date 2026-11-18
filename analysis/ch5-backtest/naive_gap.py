#!/usr/bin/env python3
"""What the full loop earns over a naive design, per year per thousand machines.

Chapter 5's report card closes with a dollar figure for the gap the full loop
closes over a naive design. This driver defines the naive design and prints
that figure from the same engine, prices and windows as mixed_basis_study.py.

THE NAIVE DESIGN is the weakest of Figure 5.5's four configurations (the top
row of that plot), "decide-15 S14" in mixed_basis.csv: the obvious first
build. It reads one five-minute print per 15-minute settlement interval (the
slow feed of mixed_basis_study.coarsen), re-applies the profit-optimal power
target at most once every 30 minutes, has the same backstop, and has no price
deadband.

THE FULL LOOP is "decide-5 +deadband10": the five-minute prints, the same
30-minute hold, a price deadband of 10 percent of default power, the backstop.

Two more designs are scored for context, not as the naive baseline:
  decide-5 S14            the plain hold on the fast feed (the fast feed alone)
  decide-5 every print    retargeting on every five-minute print, no hold and
                          no deadband: the unconstrained reference whose target
                          moves chapter 5 counts ("hold5" in sweep_results.csv,
                          which scores it on the prints instead of the
                          settlement price)

Everything is settled on the 15-minute settlement point price at LZ_WEST, on
the paired five-minute intervals of each window. Dollars per year per thousand
machines = (full-loop uplift - design uplift) per machine over the window,
x 365 / window days, x 1,000; dollars per MW-year of stock draw divide the
same yearly gap per machine by the machine's stock power in MW (3.645 and
3.068), the unit chapters 6 to 10 use. The window's days are the engine's own
(last paired interval - first) / 86,400, the same span its per-day counts use.

Each window also prints the hashprice the engine ran on: the mean of the kit's
frozen daily series (hashprice_daily.csv, USD/PH/day, each interval at its UTC
day's value) over the paired intervals, set beside the book's own Braiins
Insights series (../data/hashprice_daily.csv, USD/TH/day) on the same days.

Output: output/trend_study/naive_gap.csv. The rows it shares with
mixed_basis.csv are checked against that file to the cent, so the two cannot
drift apart silently. Needs ../data/prices.db (build_prices_db.py). Pure stdlib.
"""

import csv
import os
from datetime import datetime, timezone

from mixed_basis_study import OUTDIR, coarsen
from papo_sim import (MINERS, check_breakevens, hp_for_times, load_hashprice,
                      load_mixed_basis, make_signal, simulate)

ZONE = "LZ_WEST"
WINDOWS = (("TUNE-2024", "2024-01-01", "2025-01-01"),
           ("TEST-2025-26", "2025-01-01", "2026-06-24"))
NAIVE = "decide-15 S14"
FULL = "decide-5 +deadband10"
# (name, feed, hold_s, deadband)
DESIGNS = (
    (NAIVE, "slow", 1800, None),
    ("decide-5 S14", "fast", 1800, None),
    ("decide-5 every print", "fast", 300, None),
    (FULL, "fast", 1800, 0.10),
)
FIELDS = ["window", "zone", "miner", "variant", "uplift", "pct_of_s1",
          "changes_day", "stops_day", "full_minus_variant", "full_minus_variant_pct",
          "usd_per_year_per_1000", "usd_per_mw_year", "days", "n_paired",
          "first_utc", "last_utc"]
BOOK_HASHPRICE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data",
                              "hashprice_daily.csv")


def hashprice_line(times, hps, hp_by_date):
    """The kit's hashprice over the paired intervals, against the book's series."""
    with open(BOOK_HASHPRICE) as f:
        book = {r["date"]: 1000.0 * float(r["usd_th_day"]) for r in csv.DictReader(f)}
    day = lambda t: datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%d")
    days = sorted({day(t) for t in times})
    book_iv = [book[day(t)] for t in times]
    kit_mean, book_mean = sum(hps) / len(hps), sum(book_iv) / len(book_iv)
    missing = [d for d in days if d not in hp_by_date]
    diffs = [(abs(hp_by_date[d] - book[d]), d) for d in days if d in hp_by_date]
    worst = max(diffs)
    print(f"  hashprice: kit series ${kit_mean:.2f}/PH/day (${kit_mean / 1000:.4f}/TH/day) "
          f"over the paired intervals; the book's Braiins Insights series on the same "
          f"intervals ${book_mean:.2f} (${book_mean / 1000:.4f}/TH/day); "
          f"{sum(1 for x, _ in diffs if x > 1.0)} of {len(diffs)} days more than $1/PH/day "
          f"apart, largest ${worst[0]:.2f} on {worst[1]}; days absent from the kit "
          f"series, carried from the day before: {', '.join(missing) or 'none'}")


def mixed_basis_rows():
    path = os.path.join(OUTDIR, "mixed_basis.csv")
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return {(r["window"], r["zone"], r["miner"], r["variant"]): r
                for r in csv.DictReader(f)}


def run(label, t0, t1, hp_by_date, writer, ref):
    times, decide, settle, _ = load_mixed_basis(t0, t1, ZONE)
    slow = coarsen(times, decide, settle)
    days = (times[-1] - times[0]) / 86400.0
    iso = lambda t: datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    first, last = iso(times[0]), iso(times[-1])
    print(f"\n=== {label}  {ZONE}: {len(times):,} paired 5-min intervals, "
          f"{days:.1f} days, {first} .. {last} ===")
    hps = hp_for_times(times, hp_by_date)
    hashprice_line(times, hps, hp_by_date)
    for mkey in ("S21XP", "S19jPro"):
        m = MINERS[mkey]
        s0 = simulate(times, decide, hps, m, signal=None, sec=300,
                      settle=settle)["profit"]
        s1 = simulate(times, decide, hps, m, signal="S1", sec=300,
                      settle=settle)["profit"] - s0
        res = {}
        for name, feed, hold_s, db in DESIGNS:
            dec = slow if feed == "slow" else decide
            res[name] = simulate(times, dec, hps, m, sec=300, settle=settle,
                                 hold_s=hold_s, deadband=db,
                                 signal=make_signal("persist", sec=300))
        full = res[FULL]["profit"] - s0
        print(f"  {mkey}: oracle uplift ${s1:,.2f} per machine")
        for name, *_ in DESIGNS:
            r = res[name]
            up = r["profit"] - s0
            gap = full - up
            per_k = gap * 365.0 / days * 1000.0
            per_mw = gap * 365.0 / days / (m.p_def / 1e6)
            chk = ref.get((label, ZONE, mkey, name))
            if chk is not None:
                assert abs(round(up, 2) - float(chk["uplift"])) < 0.006, (name, up, chk["uplift"])
                assert abs(round(r["changes_per_day"], 1) - float(chk["changes_day"])) < 0.05
            writer.writerow(dict(
                window=label, zone=ZONE, miner=mkey, variant=name,
                uplift=round(up, 2), pct_of_s1=round(100 * up / s1, 4),
                changes_day=round(r["changes_per_day"], 1),
                stops_day=round(r["stops_per_day"], 2),
                full_minus_variant=round(gap, 2),
                full_minus_variant_pct=round(100 * gap / abs(up), 4),
                usd_per_year_per_1000=round(per_k, 0), usd_per_mw_year=round(per_mw, 0),
                days=round(days, 3),
                n_paired=len(times), first_utc=first, last_utc=last))
            print(f"    {name:22s} uplift ${up:8.2f}  {100*up/s1:6.2f}% of oracle  "
                  f"chg/d {r['changes_per_day']:5.1f}  full loop over it "
                  f"${gap:+7.2f}/machine = ${per_k:+8,.0f}/yr per 1,000 = ${per_mw:+6,.0f}/MW-yr"
                  + ("   [= mixed_basis.csv]" if chk is not None else ""))
        # on the fast feed: what the plain hold gives up against retargeting on
        # every print, and how much of it the price deadband wins back
        hold, every = res["decide-5 S14"], res["decide-5 every print"]
        given_up = every["profit"] - hold["profit"]
        won_back = res[FULL]["profit"] - hold["profit"]
        print(f"    fast feed: the plain hold makes {hold['changes_per_day']:.1f} target moves "
              f"a day against every-print's {every['changes_per_day']:.1f} "
              f"({100*hold['changes_per_day']/every['changes_per_day']:.0f}%) and gives up "
              f"${given_up:.2f}/machine; the price deadband wins back "
              f"{100*won_back/given_up:.1f}% of it at "
              f"{100*res[FULL]['changes_per_day']/every['changes_per_day']:.0f}% of every-print's moves")


def main():
    check_breakevens()
    hp_by_date = load_hashprice()
    ref = mixed_basis_rows()
    if not ref:
        print("note: mixed_basis.csv not found, skipping the cross-check")
    os.makedirs(OUTDIR, exist_ok=True)
    out = os.path.join(OUTDIR, "naive_gap.csv")
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for label, t0, t1 in WINDOWS:
            run(label, t0, t1, hp_by_date, w, ref)
    print(f"\nnaive design = {NAIVE} (15-minute feed, plain 30-minute hold); "
          f"full loop = {FULL}")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
