#!/usr/bin/env python3
"""Reactive PAPO (S14) + trend-aware decision signals: LZ_WEST backtest.

Replicates the colleague's S14 ("reactive PAPO": re-optimise every 5 min on the
previous RT print, move the applied power target at most once per 30 min, full
stops only via the L2 integral backstop) and tests whether a forward-looking
decision price improves it:

  signal families
    persist     P_dec = last print (S14 baseline)
    slope-end   P_dec = last + g * endpoint-slope(window W)   [g = minutes]
    slope-ols   P_dec = last + g * OLS-slope(window W)
    slope-asym  asymmetric gain: g_up when slope>0 else g_dn
    ewma        P_dec = EWMA(prints, half-life W)
    quant       P_dec = q-quantile of prints in last W minutes
    bias        P_dec = last + b  [$ constant]

  hold-rule variants (orthogonal)
    hold=1800s baseline; deadband override lets the target move early when the
    ideal target diverges from the applied one by > frac of default power.

Economics: the engine's miners (papo_sim.MINERS): the 2026-Q2 fleet telemetry
curves with the modulation floor of telemetry_miner.modulation_floor (Braiins
OS's default minimum power target, or the best-efficiency point where that is
higher: 2,774 W S21 XP, 1,200 W S19j Pro), the same machines chapter 5 draws (PAPO_PARAMETRIC=1 restores the study's original
linear fit through two published points per miner). Daily hashprice from
hashprice_daily.csv. Settlement on realized 5-min prints (single basis; the
mixed decide-5 / settle-15 basis is mixed_basis_study.py); decisions only ever
see the previous print (delay=1) or older.

Until 2026-09 this file carried its own copy of the engine with the linear fit
hard-wired, so the sweep and trend_followup.py (which imports from here) ran on
different machines from the rest of the kit. The copy is gone: the physics,
signals and simulator now come from papo_sim.py, which was extracted from this
file and reproduces it exactly at sec=300.

Pure stdlib. Outputs CSV to analysis/ch5-backtest/output/trend_study/.
"""

import argparse
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "output", "trend_study")

# The engine: miner physics, signals, simulator, data loaders. Re-exported
# because trend_followup.py imports them from this module.
from papo_sim import (MINER_MODEL, MINERS, check_breakevens,  # noqa: E402,F401
                      hp_for_times, load_hashprice, load_prices, make_signal,
                      simulate)


# ------------------------------------------------------------------ sweep ---

def variant_list(full=True):
    v = [("persist", "persist", {})]
    for W in (10, 15, 20, 30, 60):
        for g in (5, 10, 15, 30):
            v.append((f"slope-end W{W} g{g}", "slope-end", {"W": W, "g": g}))
            v.append((f"slope-ols W{W} g{g}", "slope-ols", {"W": W, "g": g}))
    for W in (15, 30):
        for gu, gd in ((15, 5), (30, 10), (30, 0), (15, 0)):
            v.append((f"slope-asym W{W} up{gu} dn{gd}", "slope-asym",
                      {"W": W, "g_up": gu, "g_dn": gd}))
    for W in (10, 15, 30):
        v.append((f"ewma hl{W}", "ewma", {"W": W}))
    for W in (15, 30, 60):
        for q in (0.6, 0.75, 0.9, 1.0):
            v.append((f"quant W{W} q{int(q*100)}", "quant", {"W": W, "q": q}))
    for b in (5, 10, 20, 40):
        v.append((f"bias +${b}", "bias", {"b": b}))
    return v


def run_window(label, t0, t1, miners, hp_by_date, variants, hold_variants,
               writer, hp_constant=None):
    times, prices = load_prices(t0, t1)
    print(f"\n== {label}: {t0} .. {t1}  ({len(times)} intervals, "
          f"{(times[-1]-times[0])/86400:.0f} days) ==")
    for mkey in miners:
        m = MINERS[mkey]
        hps = hp_for_times(times, hp_by_date, hp_constant)
        s0 = simulate(times, prices, hps, m, signal=None)
        s1 = simulate(times, prices, hps, m, signal="S1")
        ceil = s1["profit"] - s0["profit"]
        print(f"\n-- {m.name} --  S0 profit ${s0['profit']:,.0f}   "
              f"S1 uplift ${ceil:,.0f} (curtail {s1['off_pct']:.2f}%)")
        base_uplift = None
        for name, kind, kw in variants:
            sig = make_signal(kind, **kw)
            holds = hold_variants if name == "persist" else hold_variants[:1]
            for hname, hold_s, dband in holds:
                r = simulate(times, prices, hps, m, signal=sig,
                             hold_s=hold_s, deadband=dband)
                up = r["profit"] - s0["profit"]
                if name == "persist" and hname == "hold30":
                    base_uplift = up
                d_vs_s14 = (up - base_uplift) if base_uplift is not None else 0.0
                row = dict(window=label, miner=mkey, variant=name, hold=hname,
                           uplift=round(up), pct_of_s1=round(100 * up / ceil, 2),
                           delta_vs_s14=round(d_vs_s14),
                           delta_pct=round(100 * d_vs_s14 / abs(base_uplift), 2)
                           if base_uplift else 0.0,
                           off_pct=round(r["off_pct"], 2),
                           changes_day=round(r["changes_per_day"], 1),
                           stops_day=round(r["stops_per_day"], 2))
                writer.writerow(row)
                if hname == "hold30" or name == "persist":
                    print(f"  {name:26s} {hname:14s} uplift ${up:>9,.0f}  "
                          f"{row['pct_of_s1']:5.1f}%S1  d${d_vs_s14:>7,.0f} "
                          f"({row['delta_pct']:+.2f}%)  off {row['off_pct']:4.2f}%  "
                          f"chg/d {row['changes_day']:4.1f}  stop/d {row['stops_day']:.2f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true", help="baseline sanity only")
    ap.add_argument("--miners", nargs="*", default=["S21XP", "S19jPro"])
    ap.add_argument("--hp-constant", type=float, default=None)
    args = ap.parse_args()

    # economics sanity: breakevens and floors expected for the miner model
    check_breakevens()
    print(f"breakeven sanity ({MINER_MODEL}): OK")

    os.makedirs(OUTDIR, exist_ok=True)
    hp_by_date = load_hashprice()

    variants = [("persist", "persist", {})] if args.quick else variant_list()
    hold_variants = [("hold30", 1800, None)]
    if not args.quick:
        hold_variants += [("hold30+db25", 1800, 0.25), ("hold15", 900, None),
                          ("hold5", 300, None)]

    out_csv = os.path.join(OUTDIR, "sweep_results.csv")
    with open(out_csv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "window", "miner", "variant", "hold", "uplift", "pct_of_s1",
            "delta_vs_s14", "delta_pct", "off_pct", "changes_day", "stops_day"])
        writer.writeheader()
        run_window("TUNE-2024", "2024-01-01", "2025-01-01",
                   args.miners, hp_by_date, variants, hold_variants, writer,
                   args.hp_constant)
        run_window("TEST-2025-26", "2025-01-01", "2026-06-24",
                   args.miners, hp_by_date, variants, hold_variants, writer,
                   args.hp_constant)
    print(f"\nwrote {out_csv}")
    summarize(out_csv)


def summarize(path):
    """How many decision signals beat persistence, per window and machine.

    Only the signal variants at the baseline 30-minute hold are compared: the
    hold and deadband rows of `persist` are a different question.
    """
    rows = list(csv.DictReader(open(path, newline="")))
    print("\n=== summary: decision signals against persistence (hold30) ===")
    for window in ("TUNE-2024", "TEST-2025-26"):
        for miner in sorted({r["miner"] for r in rows}):
            v = [r for r in rows if r["window"] == window and r["miner"] == miner
                 and r["hold"] == "hold30" and r["variant"] != "persist"]
            if not v:
                continue
            # delta_vs_s14 is stored in whole dollars, so testing it dropped every
            # variant that won by under $0.50; the percentage is not rounded that way.
            won = sorted((r for r in v if float(r["delta_pct"]) > 0),
                         key=lambda r: -float(r["delta_pct"]))
            best = max(v, key=lambda r: float(r["delta_pct"]))
            print(f"  {window:13s} {miner:8s} {len(v)} signals; beat persistence: "
                  f"{len(won)}; best {best['variant']} {float(best['delta_pct']):+.2f}%"
                  + (f"; winners: {', '.join(r['variant'] + ' ' + r['delta_pct'] + '%' for r in won)}"
                     if won else ""))


if __name__ == "__main__":
    main()
