#!/usr/bin/env python3
"""Follow-up runs for the trend study: fade-the-move variants (mean-reversion
correction, negative extrapolation gain) and a latency/hold gap decomposition.

Writes (overwrites) analysis/ch5-backtest/output/trend_study/followup.csv.
"""

import csv
import os

from reactive_papo_trend import (MINERS, OUTDIR, hp_for_times, load_hashprice,
                                 load_prices, make_signal, simulate)

WINDOWS = [("TUNE-2024", "2024-01-01", "2025-01-01"),
           ("TEST-2025-26", "2025-01-01", "2026-06-24")]

EXTRA = [
    ("fade-end W15 g-5", "slope-end", {"W": 15, "g": -5}),
    ("fade-end W15 g-10", "slope-end", {"W": 15, "g": -10}),
    ("fade-end W30 g-5", "slope-end", {"W": 30, "g": -5}),
    ("fade-end W30 g-10", "slope-end", {"W": 30, "g": -10}),
    ("fade-ols W15 g-5", "slope-ols", {"W": 15, "g": -5}),
    ("fade-ols W30 g-10", "slope-ols", {"W": 30, "g": -10}),
    ("fade-asym W15 up0 dn-10", "slope-asym", {"W": 15, "g_up": 0, "g_dn": -10}),
    ("fade-asym W15 up15 dn-10", "slope-asym", {"W": 15, "g_up": 15, "g_dn": -10}),
]

# (label, hold_s, delay, deadband)
DECOMP = [
    ("persist hold30 delay1 (S14)", 1800, 1, None),
    ("persist hold30 delay0", 1800, 0, None),
    ("persist hold5 delay1", 300, 1, None),
    ("persist hold5 delay0", 300, 0, None),
    ("persist hold30 delay2 (stress)", 1800, 2, None),
    ("persist hold30+db10", 1800, 1, 0.10),
    ("persist hold30+db15", 1800, 1, 0.15),
    ("persist hold30+db25", 1800, 1, 0.25),
    ("persist hold30+db40", 1800, 1, 0.40),
    ("persist hold60+db25", 3600, 1, 0.25),
]


def main():
    hp_by_date = load_hashprice()
    out = os.path.join(OUTDIR, "followup.csv")
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["window", "miner", "variant", "uplift",
                                          "pct_of_s1", "delta_vs_s14", "delta_pct",
                                          "off_pct", "changes_day", "stops_day"])
        w.writeheader()
        for label, t0, t1 in WINDOWS:
            times, prices = load_prices(t0, t1)
            for mkey, m in MINERS.items():
                hps = hp_for_times(times, hp_by_date)
                s0 = simulate(times, prices, hps, m, signal=None)["profit"]
                s1 = simulate(times, prices, hps, m, signal="S1")["profit"] - s0
                base = None
                rows = []
                for name, hold_s, delay, dband in DECOMP:
                    sig = make_signal("persist")
                    r = simulate(times, prices, hps, m, signal=sig,
                                 hold_s=hold_s, delay=delay, deadband=dband)
                    up = r["profit"] - s0
                    if delay == 1 and hold_s == 1800 and dband is None:
                        base = up
                    rows.append((name, up, r))
                for name, kind, kw in EXTRA:
                    sig = make_signal(kind, **kw)
                    r = simulate(times, prices, hps, m, signal=sig)
                    rows.append((name, r["profit"] - s0, r))
                print(f"\n== {label} / {m.name} ==  S1 uplift ${s1:,.0f}")
                for name, up, r in rows:
                    d = up - base
                    w.writerow(dict(window=label, miner=mkey, variant=name,
                                    uplift=round(up),
                                    pct_of_s1=round(100 * up / s1, 2),
                                    delta_vs_s14=round(d),
                                    delta_pct=round(100 * d / abs(base), 2),
                                    off_pct=round(r["off_pct"], 2),
                                    changes_day=round(r["changes_per_day"], 1),
                                    stops_day=round(r["stops_per_day"], 2)))
                    print(f"  {name:32s} ${up:>7,.0f}  {100*up/s1:5.1f}%S1  "
                          f"d{100*d/abs(base):+6.2f}%  off {r['off_pct']:5.2f}%  "
                          f"chg/d {r['changes_per_day']:5.1f}")
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
