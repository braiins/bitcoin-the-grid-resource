#!/usr/bin/env python3
"""Where the full loop's capture comes from, and what it leaves out.

Chapter 5 prints one number per fleet for the full loop (decide-5 +deadband10
in mixed_basis.csv): capture, the share of the oracle's gain over never
pausing at stock power (S0) that the loop earns. This driver takes that
number apart, on the same engine, prices, windows and billing as
mixed_basis_study.py (LZ_WEST, decisions on the five-minute prints one
interval late, billing on the 15-minute settlement point price, each day's
own hashprice), for both fleets in TUNE-2024 and TEST-2025-26. Every block is
printed under its tag; the book's src comments quote those lines.

  RECON        the oracle's pauses against the loop's. The oracle pauses for
               free in every five-minute step whose best power target loses
               money at the settlement price. By COUNT: the share of those
               steps in which the loop is also paused. By DOLLARS: the share of
               the oracle's gain in those steps (the pause class) that the loop
               earns, split into the part earned by being paused and the part
               earned while running through those steps, the second split again
               by the loop's applied target: the floor, other targets below
               stock power, stock power and above (on these curves a target
               above stock is less efficient than stock and loses more than
               stock does in those steps, so that part comes out negative).
               Oracle pause EPISODES are runs of contiguous oracle-paused steps,
               bucketed <= 1 h, 1-3 h, > 3 h. Spike EVENTS are runs of
               consecutive 15-minute settlement intervals above the day's stock
               breakeven, valued at what stock power loses in them; the single
               interval events are counted and valued.
  SAME-TARGET  the target the loop's rule computes from print i-1 with no
               friction (the profit-optimal power target at that print, or a
               pause where even that loses money at that print) against the
               oracle's target on step i (pause counts as a target), over the
               steps whose previous print is five minutes earlier; then over
               the oracle's running steps only. Then the steps whose settlement
               point price is at or below the day's stock S19j Pro breakeven
               (the chapter's "run-or-pause call not in doubt" class): their
               share of steps, of the oracle's gain, and of the loop's
               shortfall.
  SHORTFALL    100 - capture, in capture points, by type: running through an
               oracle pause, paused while the oracle runs, running on a
               different target than the oracle (the three sum to the
               shortfall); and by the settlement point price relative to the
               day's best-point breakeven (<= 0.9x, 0.9-1.1x, 1.1-3x, > 3x).
  INFO         a frictionless causal loop: it decides on print i - delay,
               retargets every print, pauses for free where the target it
               computes loses money at that print, and has no hold, no price
               deadband, no backstop and no runtimes. Information = 100 -
               frictionless capture at delay 1, split into basis (100 -
               frictionless at delay 0: no print reveals the settlement price)
               and latency (delay 0 - delay 1). Friction = frictionless at
               delay 1 - the full loop: the cost of the loop's own rules.
               The split is sequential (basis first, then latency, friction as
               what remains), one way to attribute the shortfall, not the only
               one.
  MOVES        the full loop, the plain hold on the five-minute feed (decide-5
               S14) and the naive design (decide-15 S14) when every physical
               power-target change costs move_loss_s seconds of hashing with
               the power still billed (papo_sim.simulate(move_loss_s=...);
               a physical change includes the target set at each backstop
               resume): capture at 0, 5, 15, 30, 60 s; the slope in capture
               points per second (exactly linear below 300 s, since the loop
               moves at most once per five-minute step); the cost at which the
               full loop falls to 90 percent; the cost at which it stops
               beating the plain hold and the naive design (each solved on the
               linear slope and checked by a direct run). Then the
               saved-profile model (simulate(first_visit_s=...)): zero hashing
               at full draw for 600 s or 10,800 s the first time in a run the
               loop applies each distinct target, later visits free.
  HASHPRICE    the full loop deciding (target and backstop breakeven) on the
               previous UTC day's hashprice instead of the same day's
               realized value, revenue still at the realized value
               (simulate(hps_decide=...)).
  RETUNE       the backstop constants (papo_sim.K_TRIP, RESTART_BAND, DWELL_S)
               came from an earlier Braiins study whose grid search ran on
               prices that overlap TEST-2025-26 (see the provenance note in
               papo_sim.py). This re-tunes them on TUNE-2024 alone over K_TRIP
               {5, 10, 20} $/MW x RESTART_BAND {0, 0.05, 0.10} x DWELL {15, 30}
               min (18 settings), picks per fleet the best TUNE-2024 capture of
               the full loop, and prints that pick's TEST-2025-26 capture next
               to the printed setting's, with the spread over all 18 settings.
  RTCB         the full loop's TEST-2025-26 capture before and after ERCOT's
               RTC+B go-live, operating day 2025-12-05 (06:00 UTC).

Money is dollars per machine over the window. Capture of a part of the window
is (strategy - S0) / (S1 - S0) summed over that part. The console rounds each
part of a sum on its own (SHORTFALL's three types, INFO's basis and latency),
so the printed parts can miss the printed total by 0.01; the CSV holds them to
four decimals.

Output: output/trend_study/capture_anatomy.csv (window, zone, miner, block,
metric, value), one row for every number the console prints except the
window's first and last timestamps; RETUNE's pick and the printed setting's
rank are filed under TUNE-2024, the window the pick is made on. S0, the oracle
gain, the full loop, the plain hold and the naive design are asserted equal
to mixed_basis.csv to the cent, so run it after mixed_basis_study.py. Needs
../data/prices.db (build_prices_db.py). Pure stdlib, about two and a half
minutes (135 s on an otherwise idle machine, 2026-10-03).
"""

import csv
import os
from datetime import datetime, timezone

from mixed_basis_study import OUTDIR, coarsen
from papo_sim import (DWELL_S, K_TRIP, MINERS, RESTART_BAND, check_breakevens,
                      hp_for_times, load_hashprice, load_mixed_basis,
                      make_signal, simulate)

ZONE = "LZ_WEST"
SEC = 300
WINDOWS = (("TUNE-2024", "2024-01-01", "2025-01-01"),
           ("TEST-2025-26", "2025-01-01", "2026-06-24"))
TUNE, TEST = WINDOWS[0][0], WINDOWS[1][0]
FULL, HOLD, NAIVE = "decide-5 +deadband10", "decide-5 S14", "decide-15 S14"
# (name, feed, deadband); all with the 30-minute hold and the backstop
DESIGNS = ((FULL, "fast", 0.10), (HOLD, "fast", None), (NAIVE, "slow", None))
KEY = {FULL: "full_loop", HOLD: "plain_hold", NAIVE: "naive"}    # CSV metric prefixes
MOVE_COSTS = (0, 5, 15, 30, 60)
FIRST_VISITS = (600, 10800)
EPISODES = (("<=1h", 1, 12), ("1-3h", 13, 36), (">3h", 37, 10**9))
BANDS = (("<=0.9x", None, 0.9), ("0.9-1.1x", 0.9, 1.1), ("1.1-3x", 1.1, 3.0),
         (">3x", 3.0, None))
RETUNE_K = (5.0, 10.0, 20.0)
RETUNE_BAND = (0.0, 0.05, 0.10)
RETUNE_DWELL_MIN = (15, 30)
RTCB = int(datetime(2025, 12, 5, 6, 0, tzinfo=timezone.utc).timestamp())
FIELDS = ["window", "zone", "miner", "block", "metric", "value"]


def persist():
    return make_signal("persist", sec=SEC)


def stock_breakeven(m, hp):
    """$/MWh at which stock power earns exactly nothing on hashprice hp."""
    return hp * m.hashrate(m.p_def) / 1000.0 / (m.p_def * 24 / 1e6)


def oracle_arrays(settle, hps, m):
    """Per step: S0 profit, S1 profit, and whether the oracle pauses, exactly
    as papo_sim.simulate's S0 and S1 paths book them."""
    s0, s1, paused = [], [], []
    for sp, hp in zip(settle, hps):
        s0.append(m.profit(m.p_def, sp, hp, SEC))
        pr = m.profit(m.optimal_power(sp, hp, SEC), sp, hp, SEC)
        paused.append(pr < 0)
        s1.append(0.0 if pr < 0 else pr)
    return s0, s1, paused


def target(m, price, hp):
    """The profit-optimal power target at a price, or 0.0 (pause) where even
    that loses money at that price."""
    p = m.optimal_power(price, hp, SEC)
    return 0.0 if m.profit(p, price, hp, SEC) < 0 else p


def frictionless(times, decide, settle, hps, m, delay):
    """Decide on print i - delay, retarget every step, pause for free; stock
    power in the first `delay` steps, as simulate's warm-up."""
    out = []
    for i in range(len(times)):
        sp, hp = settle[i], hps[i]
        if i < delay:
            out.append(m.profit(m.p_def, sp, hp, SEC))
            continue
        p = target(m, decide[i - delay], hp)
        out.append(m.profit(p, sp, hp, SEC) if p > 0 else 0.0)
    return out


def runs(mask, times, step):
    """(first, last) index of each run of True whose members are `step` s apart."""
    out, start = [], None
    for i, on in enumerate(mask):
        if on and start is None:
            start = i
        if on and not (i + 1 < len(mask) and mask[i + 1] and times[i + 1] - times[i] == step):
            out.append((start, i))
            start = None
    return out


def pct(a, b):
    return 100.0 * a / b if b else float("nan")


class Out:
    """CSV writer: one row for every number the console prints (window
    timestamps aside)."""

    def __init__(self, writer):
        self.w = writer

    def row(self, window, mkey, block, metric, value):
        v = round(value, 4)
        self.w.writerow(dict(window=window, zone=ZONE, miner=mkey, block=block,
                             metric=metric, value=abs(v) if v == 0 else v))  # no -0.0


def mixed_basis_rows():
    path = os.path.join(OUTDIR, "mixed_basis.csv")
    if not os.path.exists(path):
        raise SystemExit("run mixed_basis_study.py first: capture_anatomy.py checks "
                         "its shared rows against mixed_basis.csv")
    with open(path) as f:
        return {(r["window"], r["zone"], r["miner"], r["variant"]): r
                for r in csv.DictReader(f)}


def load(label, t0, t1, hp_by_date):
    times, decide, settle, _ = load_mixed_basis(t0, t1, ZONE, verbose=False)
    hps = hp_for_times(times, hp_by_date)
    # previous UTC day's hashprice, carried over missing days as hp_for_times does
    hps_prev = hp_for_times([t - 86400 for t in times], hp_by_date)
    return dict(times=times, decide=decide, settle=settle, hps=hps, hps_prev=hps_prev,
                slow=coarsen(times, decide, settle))


def window_block(label, d, out, ref):
    times, decide, settle, hps = d["times"], d["decide"], d["settle"], d["hps"]
    n = len(times)
    days = (times[-1] - times[0]) / 86400.0
    iso = lambda t: datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"\n=== {label}  {ZONE}: {n:,} paired 5-min intervals, {days:.1f} days, "
          f"{iso(times[0])} .. {iso(times[-1])} ===")
    feeds = {"fast": decide, "slow": d["slow"]}
    res = {}
    for mkey in ("S21XP", "S19jPro"):
        m = MINERS[mkey]
        s0, s1, opause = oracle_arrays(settle, hps, m)
        S0, S1 = sum(s0), sum(s1)
        e0 = simulate(times, decide, hps, m, signal=None, sec=SEC, settle=settle)["profit"]
        e1 = simulate(times, decide, hps, m, signal="S1", sec=SEC, settle=settle)["profit"]
        assert abs(e0 - S0) < 1e-6 and abs(e1 - S1) < 1e-6, (mkey, e0, S0, e1, S1)
        G = S1 - S0
        cap = lambda P: pct(P - S0, G)
        tr = []
        L = simulate(times, decide, hps, m, sec=SEC, settle=settle, deadband=0.10,
                     signal=persist(), trace=tr)
        lp = [p for p, _ in tr]
        run = [w > 0 for _, w in tr]
        assert len(tr) == n and abs(sum(lp) - L["profit"]) < 1e-6
        capture = cap(L["profit"])

        # the rows mixed_basis.csv holds, to the cent
        chk = ref[(label, ZONE, mkey, FULL)]
        assert abs(round(S0, 2) - float(chk["s0_profit"])) < 0.006, (mkey, S0)
        assert abs(round(G, 2) - float(chk["s1_uplift"])) < 0.006, (mkey, G)
        assert abs(round(L["profit"] - S0, 2) - float(chk["uplift"])) < 0.006
        assert abs(round(L["changes_per_day"], 1) - float(chk["changes_day"])) < 0.05
        print(f"\n  {mkey}: S0 ${S0:,.2f}, oracle gain ${G:,.2f}, full loop gain "
              f"${L['profit'] - S0:,.2f}, capture {capture:.4f}%  [= mixed_basis.csv]")
        out.row(label, mkey, "BASE", "steps", n)
        out.row(label, mkey, "BASE", "days", days)
        out.row(label, mkey, "BASE", "s0_usd", S0)
        out.row(label, mkey, "BASE", "oracle_gain_usd", G)
        out.row(label, mkey, "BASE", "full_loop_gain_usd", L["profit"] - S0)
        out.row(label, mkey, "BASE", "full_loop_capture_pct", capture)
        g = [a - b for a, b in zip(s1, s0)]
        lg = [a - b for a, b in zip(lp, s0)]
        short = [a - b for a, b in zip(s1, lp)]

        # ------------------------------------------------------------ RECON
        P = [i for i in range(n) if opause[i]]
        both = [i for i in P if not run[i]]
        gP = sum(g[i] for i in P)
        lgP = sum(lg[i] for i in P)
        lg_paused = sum(lg[i] for i in both)
        print(f"  {mkey} RECON oracle pauses in {len(P):,} steps ({pct(len(P), n):.2f}% of "
              f"steps), worth {pct(gP, G):.2f}% of the oracle's gain (the pause class)")
        print(f"  {mkey} RECON oracle-pause steps in which the full loop is also paused, "
              f"by count: {pct(len(both), len(P)):.2f}% ({len(both):,} of {len(P):,})")
        print(f"  {mkey} RECON the full loop's recovery of the pause class's gain, in "
              f"dollars: {pct(lgP, gP):.2f}% (of which by being paused "
              f"{pct(lg_paused, gP):.2f}%)")
        # the rest, earned while running through oracle-paused steps, by applied target
        by_tgt = {"floor": 0.0, "below_stock": 0.0, "stock_or_above": 0.0}
        for i in P:
            if run[i]:
                w = tr[i][1]
                k = ("floor" if abs(w - m.p_min) < 0.5 else
                     "below_stock" if w < m.p_def else "stock_or_above")
                by_tgt[k] += lg[i]
        assert abs(lg_paused + sum(by_tgt.values()) - lgP) < 1e-6
        print(f"  {mkey} RECON the rest of that recovery, running through oracle-paused steps, "
              f"by applied target: the floor ({m.p_min:,.0f} W) "
              f"{pct(by_tgt['floor'], gP):+.2f}%, other targets below stock power "
              f"{pct(by_tgt['below_stock'], gP):+.2f}%, stock power and above "
              f"{pct(by_tgt['stock_or_above'], gP):+.2f}%")
        out.row(label, mkey, "RECON", "oracle_pause_steps", len(P))
        out.row(label, mkey, "RECON", "oracle_pause_steps_pct", pct(len(P), n))
        out.row(label, mkey, "RECON", "pause_class_share_of_oracle_gain_pct", pct(gP, G))
        out.row(label, mkey, "RECON", "oracle_pause_steps_loop_paused", len(both))
        out.row(label, mkey, "RECON", "oracle_pause_steps_loop_paused_pct", pct(len(both), len(P)))
        out.row(label, mkey, "RECON", "pause_class_gain_recovered_pct", pct(lgP, gP))
        out.row(label, mkey, "RECON", "pause_class_gain_recovered_by_pausing_pct",
                pct(lg_paused, gP))
        out.row(label, mkey, "RECON", "floor_w", m.p_min)
        for k, v in by_tgt.items():
            out.row(label, mkey, "RECON", f"pause_class_gain_recovered_running_{k}_pct",
                    pct(v, gP))
        eps = runs(opause, times, SEC)
        touched = sum(1 for a, b in eps if any(not run[i] for i in range(a, b + 1)))
        print(f"  {mkey} RECON oracle pause episodes: {len(eps):,}; the full loop pauses in at "
              f"least one step of {pct(touched, len(eps)):.1f}%")
        out.row(label, mkey, "RECON", "oracle_pause_episodes", len(eps))
        out.row(label, mkey, "RECON", "oracle_pause_episodes_loop_pauses_in_pct",
                pct(touched, len(eps)))
        for name, lo, hi in EPISODES:
            sel = [(a, b) for a, b in eps if lo <= b - a + 1 <= hi]
            ge = sum(sum(g[a:b + 1]) for a, b in sel)
            le = sum(sum(lg[a:b + 1]) for a, b in sel)
            print(f"  {mkey} RECON episodes {name:>4}: {pct(len(sel), len(eps)):5.1f}% of episodes "
                  f"({len(sel):,}), {pct(ge, gP):5.1f}% of the pause class's gain, full loop "
                  f"recovers {pct(le, ge):5.1f}%")
            out.row(label, mkey, "RECON", f"episodes_{name}_count", len(sel))
            out.row(label, mkey, "RECON", f"episodes_{name}_share_pct", pct(len(sel), len(eps)))
            out.row(label, mkey, "RECON", f"episodes_{name}_pause_gain_share_pct", pct(ge, gP))
            out.row(label, mkey, "RECON", f"episodes_{name}_loop_recovery_pct", pct(le, ge))
        # spike events: runs of 15-min settlement intervals above the stock breakeven
        first_of = {}
        for i, t in enumerate(times):
            first_of.setdefault(t - t % 900, i)
        buckets = sorted(first_of)
        steps_of = {}
        for i, t in enumerate(times):
            steps_of.setdefault(t - t % 900, []).append(i)
        above = [s0[first_of[b]] < 0 for b in buckets]
        ev = runs(above, buckets, 900)
        vals = [sum(-s0[i] for k in range(a, b + 1) for i in steps_of[buckets[k]]) for a, b in ev]
        single = [a == b for a, b in ev]
        sv = sum(v for v, s in zip(vals, single) if s)
        print(f"  {mkey} RECON spike events (runs of 15-min settlement intervals above the stock "
              f"breakeven): {len(ev):,}; single-interval events {pct(sum(single), len(ev)):.1f}% "
              f"of the count, {pct(sv, sum(vals)):.1f}% of the value")
        out.row(label, mkey, "RECON", "spike_events", len(ev))
        out.row(label, mkey, "RECON", "spike_single_interval_count_pct", pct(sum(single), len(ev)))
        out.row(label, mkey, "RECON", "spike_single_interval_value_pct", pct(sv, sum(vals)))

        # ------------------------------------------------------ SAME-TARGET
        agree = tot = agree_run = tot_run = 0
        for i in range(1, n):
            if times[i] - times[i - 1] != SEC:
                continue
            to = target(m, settle[i], hps[i])
            tp = target(m, decide[i - 1], hps[i])
            tot += 1
            agree += tp == to
            if to > 0:
                tot_run += 1
                agree_run += tp == to
        print(f"  {mkey} SAME-TARGET steps in which the target computed from print i-1 equals "
              f"the oracle's on step i (pause counts as a target): {pct(agree, tot):.2f}%; "
              f"over the oracle's running steps only: {pct(agree_run, tot_run):.2f}%")
        out.row(label, mkey, "SAME-TARGET", "same_target_all_steps_pct", pct(agree, tot))
        out.row(label, mkey, "SAME-TARGET", "same_target_oracle_running_steps_pct",
                pct(agree_run, tot_run))
        mj = MINERS["S19jPro"]
        cls = [i for i in range(n) if settle[i] <= stock_breakeven(mj, hps[i])]
        print(f"  {mkey} SAME-TARGET steps at or below the stock S19j Pro breakeven: "
              f"{pct(len(cls), n):.2f}% of steps, {pct(sum(g[i] for i in cls), G):.2f}% of the "
              f"oracle's gain, {pct(sum(short[i] for i in cls), sum(short)):.2f}% of the full "
              f"loop's shortfall; the loop is paused in {sum(1 for i in cls if not run[i]):,} of them")
        out.row(label, mkey, "SAME-TARGET", "below_stock_s19jpro_be_steps_pct", pct(len(cls), n))
        out.row(label, mkey, "SAME-TARGET", "below_stock_s19jpro_be_oracle_gain_pct",
                pct(sum(g[i] for i in cls), G))
        out.row(label, mkey, "SAME-TARGET", "below_stock_s19jpro_be_shortfall_pct",
                pct(sum(short[i] for i in cls), sum(short)))
        out.row(label, mkey, "SAME-TARGET", "below_stock_s19jpro_be_steps_loop_paused",
                sum(1 for i in cls if not run[i]))

        # -------------------------------------------------------- SHORTFALL
        thru = sum(short[i] for i in range(n) if run[i] and opause[i])
        idle = sum(short[i] for i in range(n) if not run[i] and not opause[i])
        other = sum(short[i] for i in range(n) if run[i] and not opause[i])
        rest = sum(short[i] for i in range(n) if not run[i] and opause[i])
        assert abs(rest) < 1e-9 and abs(pct(thru + idle + other, G) - (100 - capture)) < 1e-6
        print(f"  {mkey} SHORTFALL {100 - capture:.2f} capture points = ran through an oracle "
              f"pause {pct(thru, G):.2f} + paused while the oracle ran {pct(idle, G):.2f} + "
              f"running on a different target {pct(other, G):.2f}")
        out.row(label, mkey, "SHORTFALL", "shortfall_pts", 100 - capture)
        out.row(label, mkey, "SHORTFALL", "ran_through_oracle_pause_pts", pct(thru, G))
        out.row(label, mkey, "SHORTFALL", "paused_while_oracle_ran_pts", pct(idle, G))
        out.row(label, mkey, "SHORTFALL", "different_target_pts", pct(other, G))
        ratio = [settle[i] / m.breakeven_best(hps[i]) for i in range(n)]
        parts = []
        for name, lo, hi in BANDS:
            idx = [i for i in range(n) if (lo is None or ratio[i] > lo)
                   and (hi is None or ratio[i] <= hi)]
            sh = pct(sum(short[i] for i in idx), sum(short))
            parts.append(f"{name} {sh:.1f}% ({pct(len(idx), n):.2f}% of steps)")
            out.row(label, mkey, "SHORTFALL", f"band_{name}_shortfall_pct", sh)
            out.row(label, mkey, "SHORTFALL", f"band_{name}_steps_pct", pct(len(idx), n))
        print(f"  {mkey} SHORTFALL by settlement point price / best-point breakeven: "
              + "; ".join(parts))

        # ------------------------------------------------------------- INFO
        f1 = cap(sum(frictionless(times, decide, settle, hps, m, 1)))
        f0 = cap(sum(frictionless(times, decide, settle, hps, m, 0)))
        print(f"  {mkey} INFO frictionless causal loop: {f1:.2f}% deciding on print i-1, "
              f"{f0:.2f}% on the current print")
        print(f"  {mkey} INFO shortfall {100 - capture:.2f} = information {100 - f1:.2f} "
              f"(basis {100 - f0:.2f} + latency {f0 - f1:.2f}) + friction {f1 - capture:.2f}")
        out.row(label, mkey, "INFO", "frictionless_delay1_pct", f1)
        out.row(label, mkey, "INFO", "frictionless_delay0_pct", f0)
        out.row(label, mkey, "INFO", "information_pts", 100 - f1)
        out.row(label, mkey, "INFO", "basis_pts", 100 - f0)
        out.row(label, mkey, "INFO", "latency_pts", f0 - f1)
        out.row(label, mkey, "INFO", "friction_pts", f1 - capture)

        # ------------------------------------------------------------ MOVES
        mv = {}
        for name, feed, db in DESIGNS:
            for x in MOVE_COSTS:
                mv[(name, x)] = simulate(times, feeds[feed], hps, m, sec=SEC, settle=settle,
                                         deadband=db, signal=persist(), move_loss_s=x)
            r0 = mv[(name, 0)]
            c = ref[(label, ZONE, mkey, name)]
            assert abs(round(r0["profit"] - S0, 2) - float(c["uplift"])) < 0.006, name
            assert abs(round(r0["changes_per_day"], 1) - float(c["changes_day"])) < 0.05, name
            caps = [cap(mv[(name, x)]["profit"]) for x in MOVE_COSTS]
            slope = (caps[0] - caps[-1]) / MOVE_COSTS[-1]
            # linear below 300 s: the 15 s point must sit on the 0-60 s line
            assert abs(caps[MOVE_COSTS.index(15)] - (caps[0] - 15 * slope)) < 1e-6
            print(f"  {mkey} MOVES {name:21s} {r0['moves_per_day']:5.2f} physical moves/day "
                  f"({r0['changes_per_day']:.2f} + {r0['resumes'] / days:.2f} resumes); capture at "
                  + ", ".join(f"{x} s {c_:.2f}" for x, c_ in zip(MOVE_COSTS, caps))
                  + f"; {slope:.4f} pts per second")
            out.row(label, mkey, "MOVES", f"{KEY[name]}_moves_per_day", r0["moves_per_day"])
            out.row(label, mkey, "MOVES", f"{KEY[name]}_changes_per_day", r0["changes_per_day"])
            out.row(label, mkey, "MOVES", f"{KEY[name]}_resumes_per_day", r0["resumes"] / days)
            out.row(label, mkey, "MOVES", f"{KEY[name]}_pts_per_second", slope)
            for x, c_ in zip(MOVE_COSTS, caps):
                out.row(label, mkey, "MOVES", f"{KEY[name]}_capture_at_{x}s_pct", c_)
        spec = {name: (feed, db) for name, feed, db in DESIGNS}
        rate = lambda name: (mv[(name, 0)]["profit"] - mv[(name, 60)]["profit"]) / 60.0
        run_at = lambda name, x: simulate(times, feeds[spec[name][0]], hps, m, sec=SEC,
                                          settle=settle, deadband=spec[name][1],
                                          signal=persist(), move_loss_s=x)
        c0, rf = capture, rate(FULL)
        x90 = (c0 - 90.0) / pct(rf, G) if c0 > 90 else 0.0
        if x90 <= 300:
            chk90 = cap(run_at(FULL, x90)["profit"])
            print(f"  {mkey} MOVES full loop falls to 90% at {x90:.1f} s per move "
                  f"(direct run at that cost: {chk90:.3f}%)")
            out.row(label, mkey, "MOVES", "full_loop_90pct_direct_run_capture_pct", chk90)
        else:
            print(f"  {mkey} MOVES full loop stays above 90% up to 300 s per move "
                  f"(linear estimate {x90:.1f} s, outside the linear range)")
        out.row(label, mkey, "MOVES", "full_loop_90pct_at_s", x90)
        for other in (HOLD, NAIVE):
            ro = rate(other)
            gap = mv[(FULL, 0)]["profit"] - mv[(other, 0)]["profit"]
            if rf > ro and gap > 0:
                xb = gap / (rf - ro)
                if xb <= 300:
                    a = run_at(FULL, xb)["profit"]
                    b = run_at(other, xb)["profit"]
                    note = f"direct run at that cost: {cap(a) - cap(b):+.4f} pts"
                    out.row(label, mkey, "MOVES",
                            f"full_loop_breakeven_vs_{KEY[other]}_direct_run_gap_pts",
                            cap(a) - cap(b))
                else:
                    note = "outside the linear range, not checked"
                print(f"  {mkey} MOVES full loop stops beating {other} at {xb:.1f} s per move "
                      f"({note})")
            else:
                xb = float("inf")
                print(f"  {mkey} MOVES full loop beats {other} at every move cost")
            out.row(label, mkey, "MOVES", f"full_loop_breakeven_vs_{KEY[other]}_s", xb)
        for fv in FIRST_VISITS:
            parts = []
            for name, feed, db in DESIGNS:
                r = simulate(times, feeds[feed], hps, m, sec=SEC, settle=settle, deadband=db,
                             signal=persist(), first_visit_s=fv)
                parts.append(f"{name} {cap(r['profit']):.2f}% ({r['first_visits']} first visits)")
                out.row(label, mkey, "MOVES", f"{KEY[name]}_first_visit_{fv}s_capture_pct", cap(r["profit"]))
                out.row(label, mkey, "MOVES", f"{KEY[name]}_first_visit_{fv}s_count", r["first_visits"])
            print(f"  {mkey} MOVES saved-profile model, {fv:,} s per first visit: "
                  + "; ".join(parts))

        # -------------------------------------------------------- HASHPRICE
        h = simulate(times, decide, hps, m, sec=SEC, settle=settle, deadband=0.10,
                     signal=persist(), hps_decide=d["hps_prev"])
        print(f"  {mkey} HASHPRICE full loop deciding on the previous UTC day's hashprice: "
              f"{cap(h['profit']):.2f}% (same-day: {capture:.2f}%)")
        out.row(label, mkey, "HASHPRICE", "prev_day_hashprice_capture_pct", cap(h["profit"]))

        # ------------------------------------------------------------- RTCB
        if label == TEST:
            for name, sel in (("before", lambda t: t < RTCB), ("after", lambda t: t >= RTCB)):
                idx = [i for i in range(n) if sel(times[i])]
                c_ = pct(sum(lg[i] for i in idx), sum(g[i] for i in idx))
                print(f"  {mkey} RTCB full loop {name} 2025-12-05 06:00 UTC: {c_:.2f}% over "
                      f"{len(idx) * SEC / 86400:.0f} days of steps, "
                      f"{pct(sum(g[i] for i in idx), G):.1f}% of the oracle's gain")
                out.row(label, mkey, "RTCB", f"capture_{name}_pct", c_)
                out.row(label, mkey, "RTCB", f"days_{name}", len(idx) * SEC / 86400)
                out.row(label, mkey, "RTCB", f"oracle_gain_share_{name}_pct",
                        pct(sum(g[i] for i in idx), G))
        res[mkey] = (S0, G, capture)
    return res


def retune(data, base, out):
    """Re-tune the backstop constants on TUNE-2024 only; score the pick on TEST."""
    print(f"\n=== RETUNE: backstop constants re-tuned on {TUNE} only, full loop "
          f"(printed setting K_TRIP {K_TRIP:g} $/MW, RESTART_BAND {RESTART_BAND:g}, "
          f"DWELL {DWELL_S // 60} min) ===")
    grid = [(k, b, dw) for k in RETUNE_K for b in RETUNE_BAND for dw in RETUNE_DWELL_MIN]
    for mkey in ("S21XP", "S19jPro"):
        m = MINERS[mkey]
        scores = {}
        for label in (TUNE, TEST):
            d = data[label]
            S0, G, _ = base[label][mkey]
            for k, b, dw in grid:
                r = simulate(d["times"], d["decide"], d["hps"], m, sec=SEC,
                             settle=d["settle"], deadband=0.10, signal=persist(),
                             k_trip=k, restart_band=b, dwell_s=dw * 60)
                scores[(label, k, b, dw)] = pct(r["profit"] - S0, G)
        printed = (K_TRIP, RESTART_BAND, DWELL_S // 60)
        for label in (TUNE, TEST):
            assert abs(scores[(label,) + printed] - base[label][mkey][2]) < 1e-9
        best = max(grid, key=lambda s: (round(scores[(TUNE,) + s], 9), -grid.index(s)))
        ties = [s for s in grid if abs(scores[(TUNE,) + s] - scores[(TUNE,) + best]) < 1e-9]
        test_all = [scores[(TEST,) + s] - scores[(TEST,) + printed] for s in grid]
        rank = 1 + sum(1 for s in grid if scores[(TUNE,) + s] > scores[(TUNE,) + printed] + 1e-9)
        print(f"  {mkey} RETUNE {TUNE} pick: K_TRIP {best[0]:g} $/MW, RESTART_BAND {best[1]:g}, "
              f"DWELL {best[2]} min: {TUNE} {scores[(TUNE,) + best]:.2f}%, {TEST} "
              f"{scores[(TEST,) + best]:.2f}%; printed setting {TUNE} "
              f"{scores[(TUNE,) + printed]:.2f}% (rank {rank} of {len(grid)}), {TEST} "
              f"{scores[(TEST,) + printed]:.2f}%; pick minus printed on {TEST} "
              f"{scores[(TEST,) + best] - scores[(TEST,) + printed]:+.2f} pts"
              + (f"; {len(ties)} settings tie on {TUNE}" if len(ties) > 1 else ""))
        print(f"  {mkey} RETUNE all {len(grid)} settings on {TEST}, minus the printed setting: "
              f"{min(test_all):+.2f} to {max(test_all):+.2f} pts")
        # the setting space, the pick and the printed setting's rank belong to
        # TUNE-2024, the window the pick is made on; the scores to each window
        out.row(TUNE, mkey, "RETUNE", "settings", len(grid))
        out.row(TUNE, mkey, "RETUNE", "printed_k_trip", K_TRIP)
        out.row(TUNE, mkey, "RETUNE", "printed_restart_band", RESTART_BAND)
        out.row(TUNE, mkey, "RETUNE", "printed_dwell_min", DWELL_S // 60)
        out.row(TUNE, mkey, "RETUNE", "pick_k_trip", best[0])
        out.row(TUNE, mkey, "RETUNE", "pick_restart_band", best[1])
        out.row(TUNE, mkey, "RETUNE", "pick_dwell_min", best[2])
        out.row(TUNE, mkey, "RETUNE", "pick_ties", len(ties))
        out.row(TUNE, mkey, "RETUNE", "pick_capture_pct", scores[(TUNE,) + best])
        out.row(TUNE, mkey, "RETUNE", "printed_capture_pct", scores[(TUNE,) + printed])
        out.row(TUNE, mkey, "RETUNE", "printed_rank", rank)
        out.row(TEST, mkey, "RETUNE", "pick_capture_pct", scores[(TEST,) + best])
        out.row(TEST, mkey, "RETUNE", "printed_capture_pct", scores[(TEST,) + printed])
        out.row(TEST, mkey, "RETUNE", "pick_minus_printed_pts",
                scores[(TEST,) + best] - scores[(TEST,) + printed])
        out.row(TEST, mkey, "RETUNE", "grid_minus_printed_min_pts", min(test_all))
        out.row(TEST, mkey, "RETUNE", "grid_minus_printed_max_pts", max(test_all))


def main():
    check_breakevens()
    ref = mixed_basis_rows()
    hp_by_date = load_hashprice()
    os.makedirs(OUTDIR, exist_ok=True)
    path = os.path.join(OUTDIR, "capture_anatomy.csv")
    data = {label: load(label, t0, t1, hp_by_date) for label, t0, t1 in WINDOWS}
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        out = Out(w)
        base = {label: window_block(label, data[label], out, ref) for label, _, _ in WINDOWS}
        retune(data, base, out)
    print(f"\nwrote {path}")


if __name__ == "__main__":
    main()
