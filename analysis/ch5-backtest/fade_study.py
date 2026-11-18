#!/usr/bin/env python3
"""Fade the move: does betting on reversion beat persistence on every basis?

trend_followup.py tests eight "fade the move" decision signals, the decision
price moved AGAINST the recent slope (a negative extrapolation gain), at
LZ_WEST, deciding and billing on the five-minute prints. Fading is the family
that would exploit the reversion chapter 5 describes (a big five-minute leap
upward usually falls straight back). This driver scores the same eight signals,
imported from trend_followup.EXTRA so they cannot drift, on three bases:

  rtm5    LZ_WEST, decide and bill on the five-minute prints: followup.csv's
          basis, re-run here as a cross-check (the eight rows must match it)
  mixed   LZ_WEST, decide on the five-minute print, bill on the 15-minute
          settlement point price: the basis of Figure 5.5 (load_mixed_basis)
  rtm15   all eight load zones, decide and bill on the 15-minute settlement
          point price: the basis of multizone_study.py

plus two probes that fade rises only (the reversion is one-sided: after a
five-minute rise of $100 or more the next print falls back 69% of the time,
after a fall of that size it keeps falling 71% of the time;
analysis/checks/ch5_price_autocorrelation.py). The first probe is the mirror of
the committed "fade-asym W15 up0 dn-10"; the second is its 30-minute twin,
which stays defined on the 15-minute basis. Probes are family=probe and are
kept out of the counts over the eight.

Everything else is the plain hold of the other drivers: 30-minute hold,
decisions one interval stale (delay 1), backstop on, no price deadband. Only
the decision price differs from persistence. Windows as the other drivers:
TUNE-2024 (in sample) and TEST-2025-26 (out of sample).

On the 15-minute series a 15-minute OLS window holds two prices, and the
engine falls back to the last price when it has fewer than three, so the
three W15 OLS-based signals (fade-ols W15 g-5, both fade-asym W15, and the
W15 probe) ARE persistence there. They are written with degenerate=1, checked
to equal persistence to the cent, and left out of the counts.

Money is dollars per machine over the window (uplift = strategy profit minus
always-on-at-stock-power profit, S0). delta_pct is the percent change in that
uplift against persistence, the measure chapter 5 prints ("of the plain hold's
gain").

Pure stdlib; runs the (basis, zone, window) cells in parallel.
Writes output/trend_study/fade_study.csv and prints the summary.

    python3 analysis/ch5-backtest/build_prices_db.py      # once
    cd analysis/ch5-backtest && python3 fade_study.py      # --jobs N (default half the cores)
    python3 fade_study.py --summary-only                   # re-print from the CSV
"""

import argparse
import csv
import os
from multiprocessing import Pool

from papo_sim import (MINERS, SEC_PER_MARKET, check_breakevens, hp_for_times,
                      load_hashprice, load_mixed_basis, load_prices,
                      make_signal, simulate)
from trend_followup import EXTRA

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "output", "trend_study")
OUT = os.path.join(OUTDIR, "fade_study.csv")

WINDOWS = [("TUNE-2024", "2024-01-01", "2025-01-01"),
           ("TEST-2025-26", "2025-01-01", "2026-06-24")]
ZONES = ["LZ_WEST", "LZ_HOUSTON", "LZ_NORTH", "LZ_SOUTH",
         "LZ_AEN", "LZ_CPS", "LZ_LCRA", "LZ_RAYBN"]

PROBES = [
    ("fade-rises W15 up-10 dn0", "slope-asym", {"W": 15, "g_up": -10, "g_dn": 0}),
    ("fade-rises W30 up-10 dn0", "slope-asym", {"W": 30, "g_up": -10, "g_dn": 0}),
]
VARIANTS = [(n, k, kw, "followup") for n, k, kw in EXTRA] + \
           [(n, k, kw, "probe") for n, k, kw in PROBES]

FIELDS = ["basis", "window", "zone", "miner", "variant", "family", "degenerate",
          "uplift", "pct_of_s1", "delta_vs_s14", "delta_pct", "off_pct",
          "changes_day", "stops_day", "s1_uplift", "n_intervals"]


def degenerate(kind, kw, sec):
    """True when the signal cannot differ from persistence at this cadence:
    an OLS window of W minutes holds W*60/sec + 1 prices, and the engine needs
    three."""
    return kind in ("slope-ols", "slope-asym") and kw["W"] * 60 // sec + 1 < 3


def run_cell(task):
    basis, zone, window, t0, t1 = task
    hp_by_date = load_hashprice()
    if basis == "mixed":
        times, decide, settle, _ = load_mixed_basis(t0, t1, zone, verbose=False)
        sec, hist_span = 300, None
    else:
        market = "rtm5" if basis == "rtm5" else "rtm15"
        sec = SEC_PER_MARKET[market]
        times, decide = load_prices(t0, t1, zone, market)
        settle = None
        # multizone_study.py's history span on the 15-minute series; the
        # five-minute drivers keep the engine default (13 intervals)
        hist_span = max(13 * sec, 75 * 60) if market == "rtm15" else None
    rows = []
    for mkey in ("S21XP", "S19jPro"):
        m = MINERS[mkey]
        hps = hp_for_times(times, hp_by_date)
        kw_sim = dict(sec=sec, settle=settle)
        s0 = simulate(times, decide, hps, m, signal=None, **kw_sim)["profit"]
        s1 = simulate(times, decide, hps, m, signal="S1", **kw_sim)["profit"] - s0
        if s1 <= 0:
            continue
        base = simulate(times, decide, hps, m, hist_span_s=hist_span,
                        signal=make_signal("persist", sec=sec), **kw_sim)
        base_up = base["profit"] - s0

        def row(variant, family, deg, r):
            up = r["profit"] - s0
            d = up - base_up
            return dict(basis=basis, window=window, zone=zone, miner=mkey,
                        variant=variant, family=family, degenerate=int(deg),
                        uplift=round(up, 2), pct_of_s1=round(100 * up / s1, 2),
                        delta_vs_s14=round(d, 2),
                        delta_pct=round(100 * d / abs(base_up), 2),
                        off_pct=round(r["off_pct"], 2),
                        changes_day=round(r["changes_per_day"], 1),
                        stops_day=round(r["stops_per_day"], 2),
                        s1_uplift=round(s1, 2), n_intervals=len(times))

        rows.append(row("persist (S14)", "baseline", False, base))
        for name, kind, kw, family in VARIANTS:
            r = simulate(times, decide, hps, m, hist_span_s=hist_span,
                         signal=make_signal(kind, sec=sec, **kw), **kw_sim)
            rows.append(row(name, family, degenerate(kind, kw, sec), r))
    print(f"  done {basis:5s} {window:12s} {zone}", flush=True)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    ap.add_argument("--summary-only", action="store_true",
                    help="re-print the summary from the committed CSV")
    args = ap.parse_args()
    if args.summary_only:
        summarize(OUT)
        return

    check_breakevens()
    tasks = []
    for window, t0, t1 in WINDOWS:
        tasks.append(("rtm5", "LZ_WEST", window, t0, t1))
        tasks.append(("mixed", "LZ_WEST", window, t0, t1))
        tasks += [("rtm15", z, window, t0, t1) for z in ZONES]
    with Pool(args.jobs) as pool:
        results = pool.map(run_cell, tasks, chunksize=1)
    os.makedirs(OUTDIR, exist_ok=True)
    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for rows in results:
            w.writerows(rows)
    print(f"\nwrote {OUT}")
    summarize(OUT)


def _cross_check(rows):
    """The baselines must be the other drivers' baselines, and the rtm5 fades
    must be followup.csv's rows."""
    def load(name):
        p = os.path.join(OUTDIR, name)
        return list(csv.DictReader(open(p, newline=""))) if os.path.exists(p) else []

    fu = {(r["window"], r["miner"], r["variant"]): r for r in load("followup.csv")}
    mb = {(r["window"], r["zone"], r["miner"]): r for r in load("mixed_basis.csv")
          if r["variant"] == "decide-5 S14"}
    mz = {(r["window"], r["zone"], r["miner"]): r for r in load("multizone_rtm15.csv")
          if r["variant"] == "persist (S14)"}
    bad, n = [], 0
    for r in rows:
        if r["basis"] == "rtm5":
            key = (r["window"], r["miner"],
                   "persist hold30 delay1 (S14)" if r["family"] == "baseline"
                   else r["variant"])
            ref = fu.get(key)
            if ref is not None:
                n += 1
                if (round(float(r["uplift"])) != int(ref["uplift"])
                        or abs(float(r["delta_pct"]) - float(ref["delta_pct"])) > 0.005):
                    bad.append(("followup.csv", key, r["uplift"], ref["uplift"]))
        elif r["family"] == "baseline":
            ref = (mb if r["basis"] == "mixed" else mz).get(
                (r["window"], r["zone"], r["miner"]))
            if ref is not None:
                n += 1
                if abs(float(r["uplift"]) - float(ref["uplift"])) > 0.005:
                    bad.append((r["basis"], r["zone"], r["uplift"], ref["uplift"]))
    print(f"cross-check against followup.csv, mixed_basis.csv, multizone_rtm15.csv: "
          f"{n} rows compared, {len(bad)} mismatches")
    for b in bad:
        print("  MISMATCH", b)


def _rank(r):
    """Order by share of the hold's gain, then by dollars (breaks 0.00% ties)."""
    return (float(r["delta_pct"]), float(r["delta_vs_s14"]))


def _ahead(r):
    """Beat persistence: counted on the dollar delta, stored to the cent, which
    is finer than delta_pct at two decimals (0.01% of a ~$550 gain is ~$0.05)."""
    return float(r["delta_vs_s14"]) > 0


def summarize(path):
    rows = list(csv.DictReader(open(path, newline="")))
    _cross_check(rows)
    deg = [r for r in rows if r["degenerate"] == "1"]
    moved = [r for r in deg if abs(float(r["delta_vs_s14"])) > 0.005]
    print(f"degenerate rows (identical to persistence by construction): {len(deg)}, "
          f"of which differ from it by more than a cent: {len(moved)}")

    label = {"rtm5": "LZ_WEST, decide and bill on five-minute prints",
             "mixed": "LZ_WEST, decide on the print, bill on the settlement price",
             "rtm15": "8 load zones, decide and bill on the 15-minute settlement price"}
    for family, title in (("followup", "the eight fade variants"),
                          ("probe", "probes that fade rises only")):
        print(f"\n=== {title} against persistence (plain 30-min hold) ===")
        for basis in ("rtm5", "mixed", "rtm15"):
            print(f"basis {basis}: {label[basis]}")
            for window, _, _ in WINDOWS:
                v = [r for r in rows if r["basis"] == basis and r["window"] == window
                     and r["family"] == family and r["degenerate"] == "0"]
                if not v:
                    continue
                if basis != "rtm15":
                    for miner in ("S21XP", "S19jPro"):
                        vm = [r for r in v if r["miner"] == miner]
                        won = sorted((r for r in vm if _ahead(r)), key=_rank, reverse=True)
                        best = max(vm, key=_rank)
                        worst = min(vm, key=_rank)
                        print(f"  {window:12s} {miner:7s} beat persistence {len(won)}/{len(vm)}; "
                              f"best {best['variant']} {float(best['delta_pct']):+.2f}% "
                              f"(${float(best['delta_vs_s14']):+.2f}/machine); worst "
                              f"{worst['variant']} {float(worst['delta_pct']):+.2f}% "
                              f"(${float(worst['delta_vs_s14']):+.2f})"
                              + (f"; winners: " + ", ".join(
                                  f"{r['variant']} {float(r['delta_pct']):+.2f}% "
                                  f"(${float(r['delta_vs_s14']):+.2f})" for r in won)
                                 if won else ""))
                    continue
                names = sorted({r["variant"] for r in v})
                cells = sorted({(r["zone"], r["miner"]) for r in v})
                best = {}
                for r in v:
                    k = (r["zone"], r["miner"])
                    if k not in best or _rank(r) > _rank(best[k]):
                        best[k] = r
                won = [r for r in best.values() if _ahead(r)]
                top = max(v, key=_rank)
                print(f"  {window:12s} {len(names)} defined variants x {len(cells)} cells: "
                      f"some fade beats persistence in {len(won)}/{len(cells)} cells; "
                      f"best {float(top['delta_pct']):+.2f}% (${float(top['delta_vs_s14']):+.2f}"
                      f"/machine; {top['variant']}, {top['zone']} {top['miner']})")
                for n in names:
                    vn = [r for r in v if r["variant"] == n]
                    wins = sum(_ahead(r) for r in vn)
                    ds = [float(r["delta_pct"]) for r in vn]
                    dd = [float(r["delta_vs_s14"]) for r in vn]
                    print(f"      {n:26s} wins {wins:2d}/{len(vn)}  "
                          f"range {min(ds):+6.2f}% to {max(ds):+6.2f}%  "
                          f"(${min(dd):+.2f} to ${max(dd):+.2f})")


if __name__ == "__main__":
    main()
