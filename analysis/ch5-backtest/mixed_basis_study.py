#!/usr/bin/env python3
"""Mixed-basis reactive PAPO: decide on 5-min SCED, settle on the 15-min SPP.

This is the methodologically correct backtest for an ERCOT site. The price a
load pays is the 15-minute settlement point price, but consumption is
continuous: each settlement interval contains three 5-minute SCED runs, so
reacting after the first one changes the MWh billed at that price for the
remaining two-thirds of the interval. Deciding and settling on the same
series, as the earlier studies did, cannot represent that.

Three bases are compared, all settled on the same 15-min SPP so the dollars
are comparable:

  decide-15  the loop sees one five-minute print per 15-min interval, the first,
           and carries it (slow feed; see coarsen). It is NOT the 15-min
           settlement price, which is published only after its interval ends.
  decide-5   the loop sees the 5-min SCED print                (S14 today)
  and for each, S14 with and without the deadband override.

Output columns (output/trend_study/mixed_basis.csv), per window, zone, miner
and variant; money is dollars per machine over the window:
  uplift            strategy profit minus always-on-at-stock-power profit (S0)
  pct_of_s1         uplift as a percent of the oracle's (S1) uplift: the
                    "capture" that chapter 5's Figure 5.5 plots
  vs_decide15_s14   percent change in uplift against the slow-feed plain hold
  vs_basis_s14      percent change in uplift against the plain hold ON THE SAME
                    FEED, i.e. what the deadband adds to the hold it modifies
  vs_full_loop      percent change in uplift against the full loop (decide-5
                    +deadband10); the delay2/delay3 rows are the full loop with
                    one and two extra five-minute intervals of feed latency
  pct_of_s0_profit  percent change in total mining profit against S0
  changes_day, stops_day, off_pct   target moves, backstop pauses, time paused
  n_paired, first_utc, last_utc     the paired 5-minute intervals scored

Zones are limited to those with 5-min data. Pure stdlib.
"""

import argparse
import csv
import os
from datetime import datetime, timezone

from papo_sim import (MINERS, check_breakevens, hp_for_times, load_hashprice,
                      load_mixed_basis, make_signal, simulate)

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "output", "trend_study")
DEADBANDS = [0.10, 0.15, 0.25]
LATENCY_DELAYS = [2, 3]      # intervals; the baseline loop runs at delay=1


def coarsen(times, decide, settle, factor=3):
    """Down-sample the decision series to the settlement cadence.

    The loop only learns a price once per 15-min interval; between
    updates it carries the last one it saw. Settlement is untouched, so the
    two bases are scored on identical dollars.
    """
    out = []
    last = decide[0]
    for i, t in enumerate(times):
        if (t % 900) == 0:
            last = decide[i]
        out.append(last)
    return out


def run(zone, t0, t1, hp_by_date, writer, window):
    times, decide, settle, _ = load_mixed_basis(t0, t1, zone)
    if len(times) < 5000:
        print(f"  {zone}: only {len(times)} paired intervals, skipped")
        return
    days = (times[-1] - times[0]) / 86400.0
    iso = lambda t: datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    first, last = iso(times[0]), iso(times[-1])
    print(f"  -- {zone}: {len(times)} paired 5-min intervals, {days:.0f} days, "
          f"{first} .. {last} --")
    slow = coarsen(times, decide, settle)

    for mkey in ("S21XP", "S19jPro"):
        m = MINERS[mkey]
        hps = hp_for_times(times, hp_by_date)
        s0 = simulate(times, decide, hps, m, signal=None, sec=300,
                      settle=settle)["profit"]
        s1 = simulate(times, decide, hps, m, signal="S1", sec=300,
                      settle=settle)["profit"] - s0
        if s1 <= 0:
            continue

        rows = []
        for basis, dec in (("decide-15", slow), ("decide-5", decide)):
            base = simulate(times, dec, hps, m, sec=300, settle=settle,
                            signal=make_signal("persist", sec=300))
            rows.append((f"{basis} S14", basis, base))
            for db in DEADBANDS:
                r = simulate(times, dec, hps, m, sec=300, settle=settle,
                             deadband=db, signal=make_signal("persist", sec=300))
                rows.append((f"{basis} +deadband{int(db*100)}", basis, r))
        # feed latency: the full loop seeing each print one and two intervals
        # later than the baseline's one-interval lag (delay=1)
        for delay in LATENCY_DELAYS:
            r = simulate(times, decide, hps, m, sec=300, settle=settle,
                         deadband=0.10, delay=delay,
                         signal=make_signal("persist", sec=300))
            rows.append((f"decide-5 +deadband10 delay{delay}", "decide-5", r))

        ref = rows[0][2]["profit"] - s0          # decide-15 S14 is the reference
        hold = {b: r["profit"] - s0 for n, b, r in rows if n.endswith(" S14")}
        full = next(r["profit"] for n, b, r in rows
                    if n == "decide-5 +deadband10") - s0
        print(f"     {mkey}:  S0 profit ${s0:,.0f}   S1 uplift ${s1:,.0f}")
        for name, basis, r in rows:
            up = r["profit"] - s0
            # 4 decimals: the figure rounds these to one, and rounding twice
            # (2 dp here, 1 dp there) turned 97.449 into 97.5
            writer.writerow(dict(
                window=window, zone=zone, miner=mkey, variant=name,
                uplift=round(up, 2), pct_of_s1=round(100 * up / s1, 4),
                vs_decide15_s14=round(100 * (up - ref) / abs(ref), 4),
                vs_basis_s14=round(100 * (up - hold[basis]) / abs(hold[basis]), 4),
                vs_full_loop=round(100 * (up - full) / abs(full), 4),
                pct_of_s0_profit=round(100 * up / s0, 4),
                changes_day=round(r["changes_per_day"], 1),
                stops_day=round(r["stops_per_day"], 2),
                off_pct=round(r["off_pct"], 2), s1_uplift=round(s1, 2),
                s0_profit=round(s0, 2), n_paired=len(times),
                first_utc=first, last_utc=last))
            print(f"        {name:29s} {100*up/s1:5.1f}% of S1   "
                  f"vs decide-15 S14 {100*(up-ref)/abs(ref):+6.2f}%   "
                  f"vs same-feed S14 {100*(up-hold[basis])/abs(hold[basis]):+6.2f}%   "
                  f"vs full loop {100*(up-full)/abs(full):+6.2f}%   "
                  f"chg/d {r['changes_per_day']:5.1f}   "
                  f"stops/d {r['stops_per_day']:.2f}")

        # the dial: how much of the 10% deadband's gain a wider one keeps, and
        # at how many extra target moves a day above the plain hold
        by = {n: r for n, b, r in rows}
        gain = lambda n: by[n]["profit"] - s0 - hold["decide-5"]
        moves = lambda n: by[n]["changes_per_day"] - by["decide-5 S14"]["changes_per_day"]
        for db in (15, 25):
            n = f"decide-5 +deadband{db}"
            print(f"     dial, 5-min feed: deadband{db} keeps "
                  f"{100 * gain(n) / gain('decide-5 +deadband10'):.0f}% of deadband10's "
                  f"gain over the plain hold, at {moves(n):+.1f} moves/day above the "
                  f"hold (deadband10: {moves('decide-5 +deadband10'):+.1f})")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zones", nargs="*", default=["LZ_WEST"])
    args = ap.parse_args()
    check_breakevens()
    hp_by_date = load_hashprice()
    os.makedirs(OUTDIR, exist_ok=True)
    out = os.path.join(OUTDIR, "mixed_basis.csv")
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=[
            "window", "zone", "miner", "variant", "uplift", "pct_of_s1",
            "vs_decide15_s14", "vs_basis_s14", "vs_full_loop", "pct_of_s0_profit",
            "changes_day", "stops_day", "off_pct", "s1_uplift", "s0_profit",
            "n_paired", "first_utc", "last_utc"])
        w.writeheader()
        for label, t0, t1 in (("TUNE-2024", "2024-01-01", "2025-01-01"),
                              ("TEST-2025-26", "2025-01-01", "2026-06-24")):
            print(f"\n=== {label} ===")
            for z in args.zones:
                run(z, t0, t1, hp_by_date, w, label)
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
