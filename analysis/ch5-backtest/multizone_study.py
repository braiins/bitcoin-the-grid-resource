#!/usr/bin/env python3
"""Multi-zone reactive-PAPO study across ERCOT load zones.

Runs the two questions from the LZ_WEST trend study on every load zone:

  Q1  Does a forward-looking (trend) decision price beat persistence?
  Q2  Does a deadband override on the 30-min hold add uplift?

Default market is `rtm15`, the 15-minute **settlement point price**
(SCED LMP + RTORPA/RTORDPA adders), which is the price a site actually
settles against and the only RT series available for all load zones. The
5-min `rtm5` series (bare SCED LMP) exists for LZ_WEST only until the
multi-zone NP6-788-CD backfill is run.

Tune window vs test window are reported separately so the deadband choice
is never read off the same data it is scored on.

Pure stdlib. Writes analysis/output/trend_study/multizone_<market>.csv.
"""

import argparse
import csv
import os

from papo_sim import (MINERS, SEC_PER_MARKET, check_breakevens, hp_for_times,
                      load_hashprice, load_prices, make_signal, simulate)

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "output", "trend_study")

# Zones Javi named: Megawatts hydro DC (Houston), client sites (South),
# most miners (West), growing (North). The remaining four are run too when
# --all-zones is passed.
CORE_ZONES = ["LZ_WEST", "LZ_HOUSTON", "LZ_NORTH", "LZ_SOUTH"]
EXTRA_ZONES = ["LZ_AEN", "LZ_CPS", "LZ_LCRA", "LZ_RAYBN"]

# Representative trend variants (the full 68-variant sweep on LZ_WEST showed
# these bracket the family; no need to re-run all of them per zone).
TREND_VARIANTS = [
    ("slope-end W15 g15", "slope-end", {"W": 15, "g": 15}),
    ("slope-end W30 g15", "slope-end", {"W": 30, "g": 15}),
    ("slope-ols W30 g5", "slope-ols", {"W": 30, "g": 5}),
    ("slope-ols W60 g5", "slope-ols", {"W": 60, "g": 5}),
    ("ewma hl15", "ewma", {"W": 15}),
    ("quant W30 q75", "quant", {"W": 30, "q": 0.75}),
    ("bias +$10", "bias", {"b": 10}),
]

DEADBANDS = [0.10, 0.15, 0.25, 0.40]


def run_zone(zone, market, t0, t1, hp_by_date, writer, window_label):
    sec = SEC_PER_MARKET[market]
    times, prices = load_prices(t0, t1, zone, market)
    if len(times) < 1000:
        print(f"  {zone}: only {len(times)} intervals in window, skipped")
        return
    days = (times[-1] - times[0]) / 86400.0
    print(f"\n  -- {zone} ({market}, {len(times)} intervals, {days:.0f} days) --")

    # widest signal window is 60 min; keep a little margin
    hist_span = max(13 * sec, 75 * 60)

    for mkey in ("S21XP", "S19jPro"):
        m = MINERS[mkey]
        hps = hp_for_times(times, hp_by_date)
        s0 = simulate(times, prices, hps, m, signal=None, sec=sec)["profit"]
        s1 = simulate(times, prices, hps, m, signal="S1", sec=sec)
        ceil = s1["profit"] - s0
        if ceil <= 0:
            print(f"     {mkey}: no curtailment headroom in window, skipped")
            continue

        base = simulate(times, prices, hps, m, sec=sec, hist_span_s=hist_span,
                        signal=make_signal("persist", sec=sec))
        base_up = base["profit"] - s0

        def emit(variant, r):
            up = r["profit"] - s0
            d = up - base_up
            writer.writerow(dict(
                window=window_label, market=market, zone=zone, miner=mkey,
                variant=variant, uplift=round(up, 2),
                pct_of_s1=round(100 * up / ceil, 2),
                delta_vs_s14=round(d, 2),
                delta_pct=round(100 * d / abs(base_up), 2) if base_up else 0.0,
                off_pct=round(r["off_pct"], 2),
                changes_day=round(r["changes_per_day"], 1),
                stops_day=round(r["stops_per_day"], 2),
                stops=round(r["stops_per_day"] * r["days"]),
                s1_uplift=round(ceil, 2), s0_profit=round(s0, 2)))
            return up, d

        emit("persist (S14)", base)
        print(f"     {mkey}: S14 {100*base_up/ceil:5.1f}% of S1 "
              f"(S1 uplift ${ceil:,.0f}), {base['changes_per_day']:.1f} chg/d, "
              f"{base['stops_per_day']:.2f} stops/d")

        for name, kind, kw in TREND_VARIANTS:
            r = simulate(times, prices, hps, m, sec=sec, hist_span_s=hist_span,
                         signal=make_signal(kind, sec=sec, **kw))
            _, d = emit(name, r)
            print(f"        {name:20s} d{100*d/abs(base_up):+6.2f}%")

        for db in DEADBANDS:
            r = simulate(times, prices, hps, m, sec=sec, hist_span_s=hist_span,
                         signal=make_signal("persist", sec=sec), deadband=db)
            _, d = emit(f"persist +deadband{int(db*100)}", r)
            print(f"        deadband {int(db*100):>2d}%          "
                  f"d{100*d/abs(base_up):+6.2f}%  chg/d {r['changes_per_day']:5.1f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--market", default="rtm15", choices=["rtm5", "rtm15"])
    ap.add_argument("--all-zones", action="store_true")
    ap.add_argument("--zones", nargs="*", default=None)
    args = ap.parse_args()

    check_breakevens()
    zones = args.zones or (CORE_ZONES + EXTRA_ZONES if args.all_zones else CORE_ZONES)
    hp_by_date = load_hashprice()
    os.makedirs(OUTDIR, exist_ok=True)
    out = os.path.join(OUTDIR, f"multizone_{args.market}.csv")

    # Same windows as the other drivers and as chapter 5 ("January 2025 through
    # June 2026"). The test window used to run to 2026-07-23, which only
    # mattered once the settlement series stopped ending in April 2026.
    windows = [("TUNE-2024", "2024-01-01", "2025-01-01"),
               ("TEST-2025-26", "2025-01-01", "2026-06-24")]

    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=[
            "window", "market", "zone", "miner", "variant", "uplift",
            "pct_of_s1", "delta_vs_s14", "delta_pct", "off_pct",
            "changes_day", "stops_day", "stops", "s1_uplift", "s0_profit"])
        w.writeheader()
        for label, t0, t1 in windows:
            print(f"\n=== {label}: {t0} .. {t1} ({args.market}) ===")
            for z in zones:
                run_zone(z, args.market, t0, t1, hp_by_date, w, label)
    print(f"\nwrote {out}")
    summarize(out)


def summarize(path):
    """The claims chapter 5 makes from this run, recomputed from the CSV."""
    rows = list(csv.DictReader(open(path, newline="")))
    base = {(r["window"], r["zone"], r["miner"]): r for r in rows
            if r["variant"] == "persist (S14)"}
    print("\n=== summary (zone x fleet cells) ===")
    stops = [float(r["stops_day"]) for r in base.values()]
    print(f"backstop pauses per day, plain hold, all cells and windows: "
          f"{min(stops):.2f} to {max(stops):.2f}")
    for window in sorted({k[0] for k in base}, reverse=True):
        cells = [k for k in base if k[0] == window]
        print(f"{window}: {len(cells)} cells")
        for db in DEADBANDS:
            v = [r for r in rows if r["window"] == window
                 and r["variant"] == f"persist +deadband{int(db * 100)}"]
            pos = sum(float(r["delta_vs_s14"]) > 0 for r in v)
            dstop = [int(r["stops"]) - int(base[(window, r["zone"], r["miner"])]["stops"])
                     for r in v]
            print(f"  deadband {int(db * 100):>2d}%: uplift above the plain hold in "
                  f"{pos}/{len(v)} cells; change in backstop pause COUNT "
                  f"{min(dstop):+d} to {max(dstop):+d}")
        trend = [r for r in rows if r["window"] == window
                 and r["variant"] not in ("persist (S14)",)
                 and not r["variant"].startswith("persist +deadband")]
        best = {}
        for r in trend:
            k = (r["zone"], r["miner"])
            if k not in best or float(r["delta_pct"]) > float(best[k]["delta_pct"]):
                best[k] = r
        won = [r for r in best.values() if float(r["delta_vs_s14"]) > 0]
        top = max(best.values(), key=lambda r: float(r["delta_pct"]))
        wins = sorted({r["variant"] for r in trend if float(r["delta_vs_s14"]) > 0})
        print(f"  trend signals ({len({r['variant'] for r in trend})} variants): "
              f"some variant beats persistence in {len(won)}/{len(best)} cells; "
              f"best {float(top['delta_pct']):+.2f}% of the hold's uplift "
              f"({top['variant']}, {top['zone']} {top['miner']}); "
              f"winning variants: {', '.join(wins) or 'none'}")


if __name__ == "__main__":
    main()
