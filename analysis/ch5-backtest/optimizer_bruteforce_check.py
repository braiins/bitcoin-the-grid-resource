#!/usr/bin/env python3
"""Check the engine's power-target optimizer against exhaustive search.

Chapter 5 says the optimizer that picks each interval's power target was
checked against brute-force search, negative prices included. This script is
that check, on the engine the chapter's backtests run and on real ERCOT prices.

What is tested
--------------
papo_sim's default engine (telemetry_miner.TelemetryMiner) picks the
profit-optimal power target inside [modulation floor, power ceiling] by
scanning the floor and every multiple of 10 W above it (TelemetryMiner.
scan_powers; the S21 XP's floor, 2,774 W, is off the 10 W grid) and caching
the answer on the rounded hashprice-to-price ratio. That is exactly the call simulate() makes, for the
loop's target and for the oracle alike, and it is called here the same way,
cache included.

The reference is an independent exhaustive search. The engine interpolates
hashrate linearly between the measured points of
../data/miner_efficiency_telemetry_2026q2.csv, so profit
    A * H(p) - B * p        (A from hashprice, B from price)
is piecewise linear in p and its maximum over the range sits on one of the
curve's operating points: a measured point inside the range, or an end of the
range (the power ceiling, 3,420 W and 3,990 W, falls between measured points
and is interpolated). The search evaluates every one of those points, with
hashrate read from the CSV here, not through the engine. Both choices are
scored by this script's own profit formula, so the comparison is the engine's
CHOICE against the best choice.

Three more passes keep the check honest:
  * a 1 W search over the whole range on a sub-sample must find nothing better
    than the operating points (confirms the vertex argument numerically);
  * a deliberately broken optimizer (the same scan at 50 W steps, which steps
    over the power ceiling) goes through the identical comparison and must
    FAIL it, so a clean result means something;
  * the closed-form optimizer of the study's linear-efficiency fit
    (papo_sim.PARAMETRIC_MINERS, the one Figure 5.2 draws) against a 1 W grid.

It also prints the points on each curve's upper concave hull. Only those can
ever be profit-optimal, whatever the price, and if all of them sit on the
engine's scan grid the scan lands on the exact optimum rather than near it.
The last pass runs the loop itself, every configuration mixed_basis_study.py
scores (both feeds, the plain hold, the three price deadbands, the two extra
latencies) at LZ_WEST in both windows, and counts the intervals it spends at
each applied target (papo_sim.simulate's `targets`). Chapter 5 prints the
result: apart from stock power, held from the start of a run until the
loop's first move, the loop applies only hull points, so each target it
uses needs one tuning run and every later visit reuses the saved profile.

Prices
------
A seeded sample of real prices from prices.db over the two backtest windows
together (2024-01-01 to 2026-06-24 UTC): the NP6-788 five-minute prints at
LZ_WEST, which are what the loop decides on, and the MIS 13061 15-minute
settlement point prices of all eight load zones, which are what the oracle and
the multizone study optimize against. Every interval with a zero or negative
price is included on top of the random sample. Each price is paired with its
day's hashprice from hashprice_daily.csv (a missing day carries the previous
day's value, as the simulator does).

The oracle also has the pause: it runs at the optimum or pauses, whichever pays
more. The check counts intervals where the engine's run-or-pause call differs
from the exhaustive one (pause = profit 0).

Run after build_prices_db.py:
    python3 analysis/ch5-backtest/optimizer_bruteforce_check.py      (~4 min)
Writes output/trend_study/optimizer_bruteforce.csv and prints a summary.
Pure stdlib.
"""

import bisect
import collections
import csv
import os
import random
import sqlite3
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from papo_sim import (DB, MINER_MODEL, MINERS, PARAMETRIC_MINERS,  # noqa: E402
                      check_breakevens, hp_for_times, load_hashprice,
                      load_mixed_basis, make_signal, simulate)
from telemetry_miner import MODEL_FOR, TELEMETRY  # noqa: E402
from mixed_basis_study import DEADBANDS, LATENCY_DELAYS, coarsen  # noqa: E402

OUT = os.path.join(HERE, "output", "trend_study", "optimizer_bruteforce.csv")
T0, T1 = "2024-01-01T00:00:00Z", "2026-06-24T00:00:00Z"
SEED = 20260925
N_SAMPLE = 100_000       # random positive-price intervals per series ...
                         # ... plus every interval priced at or below zero
N_GRID = 2_000           # sub-sample that also gets the 1 W search
N_GRID_NONPOS = 500      # closed-form pass: prices <= 0 on top of N_GRID
MUTANT_STEP_W = 50       # the broken optimizer's scan step
SERIES = [("rtm5 LZ_WEST", "rtm5", ["LZ_WEST"], 300),
          ("rtm15 all 8 zones", "rtm15", None, 900)]


# ------------------------------------------------ independent profit model ---

def load_curve(model):
    """(powers, hashrates) of one model's measured points, sorted by power."""
    pts = []
    with open(TELEMETRY, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            if row["model"] == model:
                pts.append((float(row["power_w"]), float(row["hashrate_ths"])))
    pts.sort()
    return [p for p, _ in pts], [h for _, h in pts]


def interp(curve, p):
    """Hashrate at p by linear interpolation between measured points."""
    ps, hs = curve
    if not ps[0] <= p <= ps[-1]:
        raise ValueError(f"{p} W outside the measured curve")
    i = min(bisect.bisect_right(ps, p), len(ps) - 1)
    return hs[i - 1] + (hs[i] - hs[i - 1]) * (p - ps[i - 1]) / (ps[i] - ps[i - 1])


def profit(h_ths, p_w, price, hp, sec):
    """$ per machine over one interval: hashprice revenue minus energy cost."""
    revenue = hp / 1000.0 * h_ths * sec / 86400.0      # hp in $/PH/day
    cost = price * p_w / 1e6 * sec / 3600.0            # price in $/MWh
    return revenue - cost


def upper_hull(points):
    """Points of the upper concave hull of [(p, h)], left to right."""
    hull = []
    for pt in points:
        while len(hull) >= 2:
            (x1, y1), (x2, y2) = hull[-2], hull[-1]
            if (y2 - y1) * (pt[0] - x1) <= (pt[1] - y1) * (x2 - x1):
                hull.pop()           # hull[-1] lies on or below the chord
            else:
                break
        hull.append(pt)
    return hull


def hull_points(mkey):
    """Powers (W) of the hull points of one fleet's curve inside its range."""
    m = MINERS[mkey]
    curve = load_curve(MODEL_FOR[mkey])
    pts = [(p, interp(curve, p)) for p in sorted(
        {m.p_min, m.p_max} | {p for p in curve[0] if m.p_min <= p <= m.p_max})]
    return [p for p, _ in upper_hull(pts)]


# ------------------------------------------------- targets the loop applies ---

LOOP_WINDOWS = [("TUNE-2024", "2024-01-01", "2025-01-01"),
                ("TEST-2025-26", "2025-01-01", "2026-06-24")]


def loop_targets(hp_by_date):
    """Count the intervals the loop runs at each applied target, per fleet,
    over every configuration mixed_basis_study.py scores at LZ_WEST."""
    counts = {mkey: collections.Counter() for mkey in ("S21XP", "S19jPro")}
    runs = 0
    for label, t0, t1 in LOOP_WINDOWS:
        times, decide, settle, _ = load_mixed_basis(t0, t1, "LZ_WEST",
                                                    verbose=False)
        slow = coarsen(times, decide, settle)
        hps = hp_for_times(times, hp_by_date)
        configs = [(dec, db, 1) for dec in (slow, decide)
                   for db in [None] + DEADBANDS]
        configs += [(decide, 0.10, d) for d in LATENCY_DELAYS]
        for mkey in counts:
            for dec, db, delay in configs:
                simulate(times, dec, hps, MINERS[mkey], sec=300, settle=settle,
                         deadband=db, delay=delay,
                         signal=make_signal("persist", sec=300),
                         targets=counts[mkey])
                runs += 1
    return counts, runs // len(counts)


# ------------------------------------------------------------------ prices ---

def load_series(market, zones):
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    sql = ("SELECT interval_start, settlement_point, price FROM ercot_spp "
           "WHERE market=? AND interval_start>=? AND interval_start<?")
    args = [market, T0, T1]
    if zones:
        sql += " AND settlement_point IN (%s)" % ",".join("?" * len(zones))
        args += zones
    rows = con.execute(sql + " ORDER BY settlement_point, interval_start",
                       args).fetchall()
    con.close()
    return rows


def sample(rows, rng):
    nonpos = [r for r in rows if r[2] <= 0]
    pos = [r for r in rows if r[2] > 0]
    return nonpos + rng.sample(pos, min(N_SAMPLE, len(pos))), len(nonpos)


def hashprice_for(rows, hp_by_date):
    dates = sorted(hp_by_date)
    out = []
    for ts, _, _ in rows:
        d = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc).strftime("%Y-%m-%d")
        if d not in hp_by_date:
            i = bisect.bisect_left(dates, d)
            d = dates[max(i - 1, 0)]
        out.append(hp_by_date[d])
    return out


# ------------------------------------------------------------------ checks ---

def mutant_optimizer(m, step):
    """The engine's scan with a coarser step and no shortcut for prices at or
    below zero, so it cannot reach an optimum, the ceiling included, that is
    off its grid."""
    def opt(price, hp, sec):
        best_p, best_v, p = m.p_min, None, m.p_min
        while p <= m.p_max:
            v = m.profit(p, price, hp, sec)
            if best_v is None or v > best_v:
                best_p, best_v = p, v
            p += step
        return best_p
    return opt


def compare(label, sec, rows, hps, n_nonpos, mkey, optimizer, name, grid_idx=()):
    """One optimizer's choices against the operating-point search."""
    m = MINERS[mkey]
    curve = load_curve(MODEL_FOR[mkey])
    cands = sorted({m.p_min, m.p_max} |
                   {p for p in curve[0] if m.p_min <= p <= m.p_max})
    cand_h = [(p, interp(curve, p)) for p in cands]
    hours = sec / 3600.0
    grid_set = set(grid_idx)

    worst, worst_price = 0.0, None     # shortfall, $ per machine-hour
    above = 0.0                        # optimizer above the search: must be 0
    tot_short = tot_oracle = 0.0
    same = pause_diff = nonpos_diff = 0
    grid_excess = 0.0

    for i, ((ts, zone, price), hp) in enumerate(zip(rows, hps)):
        p_opt = optimizer(price, hp, sec)
        v_opt = profit(interp(curve, p_opt), p_opt, price, hp, sec)
        p_bf, v_bf = max(((p, profit(h, p, price, hp, sec)) for p, h in cand_h),
                         key=lambda x: x[1])
        short = v_bf - v_opt
        if short / hours > worst:
            worst, worst_price = short / hours, price
        above = max(above, -short)
        tot_short += short
        tot_oracle += max(v_bf, 0.0)
        same += p_opt == p_bf
        if (v_opt > 0) != (v_bf > 0):
            pause_diff += 1
        if price <= 0 and (p_opt != m.p_max or p_bf != m.p_max):
            nonpos_diff += 1
        if i in grid_set:
            p = m.p_min
            while p <= m.p_max:
                grid_excess = max(grid_excess,
                                  profit(interp(curve, p), p, price, hp, sec) - v_bf)
                p += 1
    row = dict(
        optimizer=name, series=label, miner=mkey,
        n_prices=len(rows), n_nonpositive=n_nonpos,
        min_price=min(r[2] for r in rows), max_price=max(r[2] for r in rows),
        reference=f"{len(cands)} operating points {cands[0]:.0f}-{cands[-1]:.0f} W",
        same_power_target=same,
        max_shortfall_usd_per_machine_hour=f"{worst:.3e}",
        max_shortfall_at_price=worst_price,
        total_shortfall_pct_of_oracle_profit=f"{100 * tot_short / tot_oracle:.3e}",
        optimizer_above_search_usd=f"{above:.1e}",
        run_or_pause_disagreements=pause_diff,
        nonpositive_price_mismatches=nonpos_diff,
    )
    if grid_idx:
        row.update(grid_1w_checked=len(grid_idx),
                   grid_1w_best_above_points_usd=f"{grid_excess:.1e}")
    return row


def check_parametric(label, sec, rows, hps, n_nonpos, mkey, rng):
    """The study's closed form against a 1 W search on its own fitted curve."""
    m = PARAMETRIC_MINERS[mkey]
    hours = sec / 3600.0
    idx = sorted(rng.sample(range(n_nonpos), min(N_GRID_NONPOS, n_nonpos)) +
                 rng.sample(range(n_nonpos, len(rows)),
                            min(N_GRID, len(rows) - n_nonpos)))
    grid_above = cf_above = 0.0        # $ per machine-hour, each direction
    gap_w = 0.0
    nonpos_diff = 0
    for i in idx:
        (ts, zone, price), hp = rows[i], hps[i]
        p_cf = m.optimal_power(price, hp, sec)
        v_cf = profit(m.hashrate(p_cf), p_cf, price, hp, sec)
        best, p = None, m.p_min
        while p <= m.p_max:
            v = profit(m.hashrate(p), p, price, hp, sec)
            if best is None or v > best[1]:
                best = (p, v)
            p += 1
        grid_above = max(grid_above, (best[1] - v_cf) / hours)
        cf_above = max(cf_above, (v_cf - best[1]) / hours)
        gap_w = max(gap_w, abs(p_cf - best[0]))
        if price <= 0 and p_cf != m.p_max:
            nonpos_diff += 1
    return dict(
        optimizer="parametric fit, closed form", series=label, miner=mkey,
        n_prices=len(idx), n_nonpositive=sum(rows[i][2] <= 0 for i in idx),
        min_price=min(rows[i][2] for i in idx),
        max_price=max(rows[i][2] for i in idx),
        reference=f"1 W grid {m.p_min}-{m.p_max} W",
        max_shortfall_usd_per_machine_hour=f"{grid_above:.3e}",
        closed_form_above_grid_usd_per_machine_hour=f"{cf_above:.3e}",
        max_power_gap_w=round(gap_w, 2),
        nonpositive_price_mismatches=nonpos_diff,
    )


def main():
    if MINER_MODEL != "2026-Q2 fleet telemetry":
        raise SystemExit("run without PAPO_PARAMETRIC: this checks the telemetry engine")
    check_breakevens()

    print("operating points that any price can select (upper concave hull), "
          "and whether each sits on the engine's scan grid (the floor, then every 10 W):")
    for mkey in ("S21XP", "S19jPro"):
        m = MINERS[mkey]
        hull = hull_points(mkey)
        grid = set(m.scan_powers())
        off = [p for p in hull if p not in grid]
        print(f"  {mkey:8s} {', '.join(f'{p:.0f}' for p in hull)} W; "
              f"off the grid: {', '.join(f'{p:.0f}' for p in off) or 'none'}")

    rng = random.Random(SEED)
    hp_by_date = load_hashprice()
    results = []
    for label, market, zones, sec in SERIES:
        rows, n_nonpos = sample(load_series(market, zones), rng)
        hps = hashprice_for(rows, hp_by_date)
        print(f"\n{label}: {len(rows):,} prices ({n_nonpos:,} at or below zero), "
              f"${min(r[2] for r in rows):,.2f} to ${max(r[2] for r in rows):,.2f}/MWh")
        for mkey in ("S21XP", "S19jPro"):
            m = MINERS[mkey]
            grid_idx = rng.sample(range(len(rows)), min(N_GRID, len(rows)))
            for name, opt, gi in (
                    ("engine, 10 W scan", m.optimal_power, grid_idx),
                    (f"broken on purpose, {MUTANT_STEP_W} W scan",
                     mutant_optimizer(m, MUTANT_STEP_W), ())):
                r = compare(label, sec, rows, hps, n_nonpos, mkey, opt, name, gi)
                results.append(r)
                print(f"  {mkey:8s} {name:28s} same target {r['same_power_target']:>7,}"
                      f"/{r['n_prices']:,}; max shortfall "
                      f"${float(r['max_shortfall_usd_per_machine_hour']):.2e}"
                      f"/machine-hour; run/pause diff {r['run_or_pause_disagreements']}; "
                      f"price<=0 mismatches {r['nonpositive_price_mismatches']}"
                      + (f"; 1 W grid above points "
                         f"${r['grid_1w_best_above_points_usd']}" if gi else ""))
            q = check_parametric(label, sec, rows, hps, n_nonpos, mkey, rng)
            results.append(q)
            print(f"  {mkey:8s} {'closed form (parametric fit)':28s} on {q['n_prices']:,}: "
                  f"1 W grid above it by at most "
                  f"${float(q['max_shortfall_usd_per_machine_hour']):.2e}/machine-hour, "
                  f"it above the grid by at most "
                  f"${float(q['closed_form_above_grid_usd_per_machine_hour']):.2e}; "
                  f"max power gap {q['max_power_gap_w']} W; "
                  f"price<=0 mismatches {q['nonpositive_price_mismatches']}")

    fields = []
    for r in results:
        fields += [k for k in r if k not in fields]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(results)

    def pick(prefix):
        return [r for r in results if r["optimizer"].startswith(prefix)]

    eng, mut, par = pick("engine"), pick("broken"), pick("parametric")
    n = sum(r["n_prices"] for r in eng) // 2
    neg = sum(r["n_nonpositive"] for r in eng) // 2
    fmax = lambda rs, k: max(float(r[k]) for r in rs)
    isum = lambda rs, k: sum(int(r[k]) for r in rs)
    print(f"\n=== summary ===\nengine optimizer, {n:,} real prices "
          f"({neg:,} at or below zero) x 2 fleets = {2 * n:,} choices:")
    print(f"  same power target as the exhaustive search: "
          f"{isum(eng, 'same_power_target'):,} of {2 * n:,}")
    print(f"  largest shortfall: ${fmax(eng, 'max_shortfall_usd_per_machine_hour'):.2e} "
          f"per machine-hour; run-or-pause disagreements "
          f"{isum(eng, 'run_or_pause_disagreements')}; price<=0 mismatches "
          f"{isum(eng, 'nonpositive_price_mismatches')}")
    print(f"  engine above the search (would mean the search missed a point): "
          f"${fmax(eng, 'optimizer_above_search_usd'):.1e}; 1 W grid above the "
          f"operating points: ${fmax(eng, 'grid_1w_best_above_points_usd'):.1e}")
    print(f"broken optimizer ({MUTANT_STEP_W} W scan), same comparison: "
          f"{2 * n - isum(mut, 'same_power_target'):,} different targets, largest "
          f"shortfall ${fmax(mut, 'max_shortfall_usd_per_machine_hour'):.2e} per "
          f"machine-hour, price<=0 mismatches "
          f"{isum(mut, 'nonpositive_price_mismatches'):,} (must be nonzero)")
    print(f"closed-form optimizer (parametric fit), {sum(r['n_prices'] for r in par) // 2:,}"
          f" prices x 2 fleets: a 1 W grid beats it by at most "
          f"${fmax(par, 'max_shortfall_usd_per_machine_hour'):.2e} per machine-hour; "
          f"price<=0 mismatches {isum(par, 'nonpositive_price_mismatches')}")

    counts, runs = loop_targets(hp_by_date)
    print(f"\ntargets the loop applies: {runs} runs per fleet, every configuration of "
          f"mixed_basis_study.py at LZ_WEST, {', '.join(w for w, _, _ in LOOP_WINDOWS)}; "
          f"intervals at each target, paused intervals not counted")
    for mkey, c in counts.items():
        # Stock power (3,645 and 3,068 W) is off the optimizer's scan grid
        # (the floor, then every multiple of 10 W), so the optimizer can never
        # return it: every interval counted there is the starting value, before
        # the run's first move.
        m = MINERS[mkey]
        assert m.p_def not in set(m.scan_powers()), "stock power on the scan grid"
        hull = set(hull_points(mkey))
        others = {p: n for p, n in c.items() if p not in hull and p != m.p_def}
        used = sorted(p for p in c if p in hull)
        print(f"  {mkey:8s} hull points applied: {len(used)} of {len(hull)} "
              f"({', '.join(f'{p:.0f} W {c[p]:,}' for p in used)}); stock power "
              f"{m.p_def:.0f} W {c.get(m.p_def, 0):,} intervals, before the first "
              f"move of each run; any other target: {len(others)}")
        if others:
            raise SystemExit(f"{mkey}: the loop applied targets off the hull: {others}")
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
