#!/usr/bin/env python3
"""Two baselines for chapter 5's capture: doing nothing, and pausing alone.

Chapter 5 grades the loop by capture, the share of the oracle's gain over
running every machine at stock power without ever pausing (S0) that a strategy
earns. This driver prints the scale of that number from the same engine,
prices, windows and billing as mixed_basis_study.py: LZ_WEST, decisions on the
five-minute prints one interval late, billing on the 15-minute settlement point
price, each day's own hashprice. It answers the operator's question "do I need
the curve, or just a contactor?" in Figure 5.5's own units.

The variants, per window and fleet:
  S0                          every machine at stock power, never paused
  S1                          Figure 5.5's oracle: foresight, a free pause, and
                              the profit-optimal power target in every interval
  S1 at stock                 the same oracle on a stock-only machine (floor =
                              ceiling = stock power): a free pause with
                              foresight and no target to move, which is
                              chapter 6's strike rule on each day's hashprice
  backstop alone at stock     the full loop's backstop, with its own constants,
                              on the stock-only machine: pausing alone
  on/off every print at stock pause whenever the last print seen is above the
                              day's stock breakeven, run otherwise; no hold, no
                              minimum runtime, no cycle budget
  full loop, ceiling at stock the full loop, never above stock power (stock
                              power itself is on the optimizer's scan since the
                              2026-10-03 telemetry_miner.scan_powers fix; before
                              it the scan stopped at 3,640 / 3,060 W)
  full loop, floor at stock   the full loop, never below stock power
  full loop, no backstop      the full loop's power-target rule alone, never
                              paused
  ceiling + backstop          no price-following: every machine fixed at the
                              engine's power ceiling (3,990 / 3,420 W), paused
                              and resumed only by the full loop's own backstop,
                              which trips at the curve's best-point breakeven
                              (papo_sim.simulate(fixed_power=...))
  ceiling + backstop (own breakeven)
                              the same, with the backstop tripping at the
                              ceiling point's own breakeven instead
                              (papo_sim.point_breakeven)
  full loop                   decide-5 +deadband10, as in mixed_basis.csv

Two further blocks follow in the console:
  CAL-2025       the stock oracle over calendar 2025, in dollars per MW-year of
                 stock draw, against chapter 6's fixed-strike figures
                 (analysis/figures/fig_ch6_strike.R console, 1 MW paused above a
                 fixed strike on 2025's settlement prices); asserted within
                 2.5 percent, so the two chapters cannot drift apart
  residual draw  the full loop's gain over S0 when a paused machine still draws
                 a share of its stock power, billed at the settlement price
                 (papo_sim.simulate(paused_draw=...)); every printed number
                 books a paused interval at zero, and the repository holds no
                 measurement of that draw

Money is dollars per machine over the window unless stated.
usd_per_year_per_1000 = uplift x 365 / window days x 1,000 and
usd_per_mw_year = uplift x 365 / window days / stock power in MW, on the
engine's own days, (last paired interval - first) / 86,400, as naive_gap.py.
pct_of_s1_profit is the variant's profit as a percent of the oracle's; the S0
row is what doing nothing already earns.

Output: output/trend_study/baselines.csv. The S0, S1 and full-loop rows are
checked against mixed_basis.csv to the cent. Needs ../data/prices.db
(build_prices_db.py); run it after mixed_basis_study.py. Pure stdlib, about
two minutes.
"""

import csv
import os
from datetime import datetime, timezone

from mixed_basis_study import OUTDIR
from papo_sim import (MINERS, check_breakevens, hp_for_times, load_hashprice,
                      load_mixed_basis, make_signal, point_breakeven, simulate)
from telemetry_miner import TelemetryMiner

ZONE = "LZ_WEST"
WINDOWS = (("TUNE-2024", "2024-01-01", "2025-01-01"),
           ("TEST-2025-26", "2025-01-01", "2026-06-24"))
FULL = "full loop"
# fig_ch6_strike.R console, calendar 2025, $ per MW-year: pausing above a fixed
# strike at the machine's breakeven on 2025's mean hashprice (chapter 6)
CH6_STRIKE_2025 = {"S21XP": 17280.0, "S19jPro": 49116.0}
CH6_TOL = 0.025
RESIDUALS = (0.01, 0.02, 0.05)
FIELDS = ["window", "zone", "miner", "variant", "profit", "uplift", "pct_of_s1",
          "pct_of_s1_profit", "stops_day", "changes_day", "switches_day",
          "off_pct", "usd_per_year_per_1000", "usd_per_mw_year", "days",
          "n_paired", "first_utc", "last_utc"]


def variant_miner(m, p_min=None, p_max=None):
    """The same measured curve with a different floor or ceiling."""
    pts = list(zip(m._p, m._h))
    return TelemetryMiner(m.name, m.p_def if p_min is None else p_min, m.p_def,
                          m.p_def if p_max is None else p_max, pts)


def stock_breakeven(m, hp):
    """$/MWh at which stock power earns exactly nothing on the day's hashprice."""
    return hp * m.hashrate(m.p_def) / 1000.0 / (m.p_def * 24 / 1e6)


def onoff_every_print(times, decide, settle, hps, m, sec=300, delay=1):
    """Pause whenever the last print seen is above the day's stock breakeven,
    run at stock power otherwise; no hold, no minimum runtime, no cycle budget."""
    profit, switches, off, running = 0.0, 0, 0, True
    for i in range(len(times)):
        hp = hps[i]
        want = decide[i - delay] < stock_breakeven(m, hp) if i >= delay else True
        if want != running:
            switches += 1
            running = want
        if running:
            profit += m.profit(m.p_def, settle[i], hp, sec)
        else:
            off += 1
    days = (times[-1] - times[0]) / 86400.0
    return {"profit": profit, "off_pct": 100.0 * off / len(times),
            "changes_per_day": 0.0, "stops_per_day": None,
            "switches_per_day": switches / days, "days": days}


def mixed_basis_rows():
    path = os.path.join(OUTDIR, "mixed_basis.csv")
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return {(r["window"], r["zone"], r["miner"], r["variant"]): r
                for r in csv.DictReader(f)}


def run(label, t0, t1, hp_by_date, writer, ref):
    times, decide, settle, _ = load_mixed_basis(t0, t1, ZONE, verbose=False)
    days = (times[-1] - times[0]) / 86400.0
    iso = lambda t: datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    first, last = iso(times[0]), iso(times[-1])
    hps = hp_for_times(times, hp_by_date)
    print(f"\n=== {label}  {ZONE}: {len(times):,} paired 5-min intervals, "
          f"{days:.1f} days, {first} .. {last}; mean hashprice "
          f"${sum(hps) / len(hps):.2f}/PH/day ===")
    persist = lambda: make_signal("persist", sec=300)
    out = {}
    for mkey in ("S21XP", "S19jPro"):
        m = MINERS[mkey]
        stock = variant_miner(m)
        kw = dict(sec=300, settle=settle)
        s0 = simulate(times, decide, hps, m, signal=None, **kw)
        s1 = simulate(times, decide, hps, m, signal="S1", **kw)
        res = {
            "S0": s0,
            "S1": s1,
            "S1 at stock": simulate(times, decide, hps, stock, signal="S1", **kw),
            "backstop alone at stock": simulate(times, decide, hps, stock,
                                                signal=persist(), **kw),
            "on/off every print at stock": onoff_every_print(times, decide, settle, hps, m),
            "full loop, ceiling at stock": simulate(
                times, decide, hps, variant_miner(m, p_min=m.p_min), deadband=0.10,
                signal=persist(), **kw),
            "full loop, floor at stock": simulate(
                times, decide, hps, variant_miner(m, p_max=m.p_max), deadband=0.10,
                signal=persist(), **kw),
            "full loop, no backstop": simulate(times, decide, hps, m, deadband=0.10,
                                               backstop=False, signal=persist(), **kw),
            "ceiling + backstop": simulate(times, decide, hps, m, fixed_power=m.p_max,
                                           signal=persist(), **kw),
            "ceiling + backstop (own breakeven)": simulate(
                times, decide, hps, m, fixed_power=m.p_max,
                backstop_be=point_breakeven(m, m.p_max), signal=persist(), **kw),
            FULL: simulate(times, decide, hps, m, deadband=0.10, signal=persist(), **kw),
        }
        for name in ("S1", "S1 at stock"):      # the oracle's pause is free and uncounted
            res[name]["stops_per_day"] = None
        P0, P1 = s0["profit"], s1["profit"]
        gain = P1 - P0
        mw = m.p_def / 1e6
        print(f"  {mkey}: S0 ${P0:,.2f}, S1 ${P1:,.2f}, oracle gain ${gain:,.2f} per machine; "
              f"S0 earns {100 * P0 / P1:.1f}% of the oracle's profit")
        for name, r in res.items():
            up = r["profit"] - P0
            per_k = up * 365.0 / days * 1000.0
            per_mw = up * 365.0 / days / mw
            stops = r.get("stops_per_day")
            sw = r.get("switches_per_day")
            writer.writerow(dict(
                window=label, zone=ZONE, miner=mkey, variant=name,
                profit=round(r["profit"], 2), uplift=round(up, 2),
                pct_of_s1=round(100 * up / gain, 4),
                pct_of_s1_profit=round(100 * r["profit"] / P1, 4),
                stops_day="" if stops is None else round(stops, 2),
                changes_day=round(r.get("changes_per_day", 0.0), 1),
                switches_day="" if sw is None else round(sw, 1),
                off_pct=round(r.get("off_pct", 0.0), 2),
                usd_per_year_per_1000=round(per_k, 0), usd_per_mw_year=round(per_mw, 0),
                days=round(days, 3), n_paired=len(times), first_utc=first, last_utc=last))
            extra = ""
            if stops is not None:
                extra += f"  stops/d {stops:.2f}"
            if sw is not None:
                extra += f"  switches/d {sw:.1f}"
            print(f"    {name:34s} capture {100 * up / gain:6.2f}%  "
                  f"{100 * r['profit'] / P1:5.1f}% of S1 profit  gain ${up:8.2f}  "
                  f"${per_mw:>9,.0f}/MW-yr  chg/d {r.get('changes_per_day', 0.0):5.1f}"
                  f"  off {r.get('off_pct', 0.0):5.2f}%{extra}")
        # the rows mixed_basis.csv also holds, to the cent
        chk = ref.get((label, ZONE, mkey, "decide-5 +deadband10"))
        if chk is not None:
            assert abs(round(P0, 2) - float(chk["s0_profit"])) < 0.006, (mkey, P0, chk["s0_profit"])
            assert abs(round(gain, 2) - float(chk["s1_uplift"])) < 0.006, (mkey, gain, chk["s1_uplift"])
            full_up = res[FULL]["profit"] - P0
            assert abs(round(full_up, 2) - float(chk["uplift"])) < 0.006, (mkey, full_up, chk["uplift"])
            assert abs(round(res[FULL]["changes_per_day"], 1) - float(chk["changes_day"])) < 0.05
            print("    [S0, S1 and full loop = mixed_basis.csv]")
        out[mkey] = (times, decide, settle, hps, res)
    return out


def cal2025_stock_oracle(hp_by_date):
    """Chapter 5's stock oracle over calendar 2025 against chapter 6's strike."""
    times, decide, settle, _ = load_mixed_basis("2025-01-01", "2026-01-01", ZONE, verbose=False)
    days = (times[-1] - times[0]) / 86400.0
    hps = hp_for_times(times, hp_by_date)
    print(f"\n=== CAL-2025  {ZONE}: {len(times):,} paired intervals, {days:.1f} days: "
          f"the stock oracle (S1 at stock) against chapter 6's 2025 strike ===")
    for mkey in ("S21XP", "S19jPro"):
        m = MINERS[mkey]
        s0 = simulate(times, decide, hps, m, signal=None, sec=300, settle=settle)["profit"]
        s1s = simulate(times, decide, hps, variant_miner(m), signal="S1", sec=300,
                       settle=settle)["profit"]
        per_mw = (s1s - s0) * 365.0 / days / (m.p_def / 1e6)
        ch6 = CH6_STRIKE_2025[mkey]
        print(f"  {mkey}: stock oracle ${per_mw:,.0f} per MW-year of stock draw; "
              f"chapter 6's fixed strike ${ch6:,.0f} ({100 * (per_mw / ch6 - 1):+.1f}%)")
        assert abs(per_mw / ch6 - 1) < CH6_TOL, (mkey, per_mw, ch6)


def residual_block(label, runs):
    print(f"\n=== {label}: the full loop's gain over S0 when a paused machine still "
          f"draws a share of its stock power, billed at the settlement price ===")
    for mkey, (times, decide, settle, hps, res) in runs.items():
        m = MINERS[mkey]
        P0 = res["S0"]["profit"]
        up0 = res[FULL]["profit"] - P0
        parts = []
        for r in RESIDUALS:
            up = simulate(times, decide, hps, m, sec=300, settle=settle, deadband=0.10,
                          signal=make_signal("persist", sec=300),
                          paused_draw=r)["profit"] - P0
            parts.append(f"{100 * r:.0f}%: {100 * (up - up0) / up0:+.2f}%")
        print(f"  {mkey}: full loop gain ${up0:.2f} per machine, paused "
              f"{res[FULL]['off_pct']:.2f}% of intervals; change in that gain per share "
              f"of stock draw: " + ", ".join(parts))


def main():
    check_breakevens()
    hp_by_date = load_hashprice()
    ref = mixed_basis_rows()
    if not ref:
        print("note: mixed_basis.csv not found, skipping the cross-check")
    os.makedirs(OUTDIR, exist_ok=True)
    out = os.path.join(OUTDIR, "baselines.csv")
    runs = {}
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for label, t0, t1 in WINDOWS:
            runs[label] = run(label, t0, t1, hp_by_date, w, ref)
    cal2025_stock_oracle(hp_by_date)
    for label, _, _ in WINDOWS:
        residual_block(label, runs[label])
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
