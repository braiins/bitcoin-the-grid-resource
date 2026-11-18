#!/usr/bin/env python3
"""Reactive PAPO simulation core: interval-length and market/zone agnostic.

Extracted from reactive_papo_trend.py so the same engine can run on ERCOT
5-min SCED LMPs (market='rtm5', bare LMP) and 15-min settlement point prices
(market='rtm15', SCED LMP + RTORPA/RTORDPA adders) across any load zone. The
15-min series is the settlement-relevant one.

All interval-dependent quantities derive from `sec` (interval length in
seconds); sec=300 reproduces the original 5-min study exactly.
"""

import csv
import math
import os
import sqlite3
from collections import deque
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "..", "data", "prices.db")
HASHPRICE_CSV = os.path.join(HERE, "hashprice_daily.csv")

# L2 integral backstop constants (an earlier Braiins backstop study; identical
# to S12/S14).
# Provenance (audited 2026-10-03): K_TRIP, RESTART_BAND and DWELL_S come from
# an earlier Braiins backstop study whose grid search ran on LZ_WEST
# five-minute prints from 2023-12-11 to 2026-06-23, a span that overlaps this
# kit's TEST-2025-26 window. They were NOT chosen on TUNE-2024: the only
# setting chosen on TUNE-2024 is the price deadband's width (10% of stock
# power), so the TEST window is out of sample for that width alone.
# capture_anatomy.py RETUNE measures the exposure: it re-tunes these three on
# TUNE-2024 only and prints the TEST capture of the pick next to the printed
# setting's. The runtimes and the cycle budget come with them from the same
# study. simulate(k_trip=, restart_band=, dwell_s=) overrides them per run.
# The loop's design itself (persistence: decide on the last print, every five
# minutes; the 30-minute hold, simulate(hold_s=1800)) comes from the Braiins
# report that defined S14, whose backtest ran, by its own account, on LZ_WEST
# five-minute prices from January 2025 to August 2026, a span that covers
# TEST-2025-26; the reactive price-response study this kit began as took S14
# as its baseline. Nothing in the kit re-selects that design on TUNE-2024
# alone. README.md, "Provenance of the constants", has all three sources.
K_TRIP = 10.0                # $/MW accumulated excess above best-eff breakeven
RESTART_BAND = 0.10          # restart requires price <= BE*(1-band) ...
DWELL_S = 15 * 60            # ... held for 15 min
MIN_DOWN_S = 30 * 60
MIN_UP_S = 30 * 60
MAX_CYCLES_DAY = 8

SEC_PER_MARKET = {"rtm5": 300, "rtm15": 900}


class Miner:
    """Linear J(p) power model:  J = J_best + c*(p - p_min);  H(p) = p/J(p)."""

    def __init__(self, name, p_min, p_def, p_max, j_best, j_def):
        self.name = name
        self.p_min, self.p_def, self.p_max = p_min, p_def, p_max
        c = (j_def - j_best) / (p_def - p_min)
        self.a = j_best - c * p_min          # J(p) = a + b*p
        self.b = c
        assert self.a > 0

    def hashrate(self, p):                   # TH/s
        return p / (self.a + self.b * p)

    def _coeffs(self, hp, price, sec):
        """(A, B) such that profit = A*H(p) - B*p over one interval."""
        A = hp / 1000.0 * (sec / 86400.0)    # $ per TH/s over the interval
        B = price / 1e6 * (sec / 3600.0)     # $ per W over the interval
        return A, B

    def profit(self, p, price, hp, sec):
        """$ over one interval at power p (W), price ($/MWh), hp ($/PH/day)."""
        if p <= 0:
            return 0.0
        A, B = self._coeffs(hp, price, sec)
        return A * self.hashrate(p) - B * p

    def optimal_power(self, price, hp, sec):
        """Profit-optimal p in [p_min, p_max] (modulation floor; no OFF here).

        H is concave in p, so d/dp [A*H(p) - B*p] = 0 gives
        p* = (sqrt(A*a/B) - a)/b, clamped to the physical range."""
        if price <= 0:
            return self.p_max
        A, B = self._coeffs(hp, price, sec)
        p = (math.sqrt(A * self.a / B) - self.a) / self.b
        return min(self.p_max, max(self.p_min, p))

    def breakeven_best(self, hp):
        """$/MWh above which even the max-efficiency point loses money."""
        rev_day = hp * self.hashrate(self.p_min) / 1000.0
        mwh_day = self.p_min * 24 / 1e6
        return rev_day / mwh_day


# The original study fitted each machine's J(p) to two points and ran the linear
# model below. The chapter's figures draw the 2026-Q2 Braiins OS fleet telemetry
# instead, and the two disagree where it matters: the fit puts the S21 XP at
# 10.93 J/TH at its 2,760 W floor, where the fleet measures 12.68. The engine now
# runs on the measured curves so the backtest and the figures describe the same
# machines. Its modulation floor is set in telemetry_miner.modulation_floor:
# Braiins OS's default minimum power target, or the telemetry's best-efficiency
# point where that is higher, 2,774 W (S21 XP, the default) and 1,200 W
# (S19j Pro, the best point) since 2026-09-26. The first two numbers of each
# entry below (floor 2,760 / 1,630 W) are therefore the ORIGINAL STUDY'S floors
# and only apply under PAPO_PARAMETRIC=1; default power and ceiling apply to
# both.
# Set PAPO_PARAMETRIC=1 to run the original fitted curves for comparison.
PARAMETRIC_MINERS = {
    "S21XP": Miner("Antminer S21 XP", 2760, 3645, 3990, 10.93, 12.82),
    "S19jPro": Miner("Antminer S19j Pro", 1630, 3068, 3420, 23.81, 28.53),
}

if os.environ.get("PAPO_PARAMETRIC") == "1":
    MINERS = PARAMETRIC_MINERS
    MINER_MODEL = "parametric fit"
else:
    from telemetry_miner import build as _build_telemetry
    MINERS = _build_telemetry(PARAMETRIC_MINERS)
    MINER_MODEL = "2026-Q2 fleet telemetry"


def load_prices(t0, t1, zone="LZ_WEST", market="rtm5", db=DB):
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    rows = con.execute(
        "SELECT interval_start, price FROM ercot_spp "
        "WHERE market=? AND settlement_point=? "
        "AND interval_start >= ? AND interval_start < ? ORDER BY interval_start",
        (market, zone, t0, t1),
    ).fetchall()
    con.close()
    times, prices = [], []
    for ts, p in rows:
        dt = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        times.append(int(dt.timestamp()))
        prices.append(p)
    return times, prices


def load_mixed_basis(t0, t1, zone="LZ_WEST", db=DB, verbose=True):
    """Pair the 5-min decision series with the 15-min settlement series.

    Returns (times, decide, settle, report) on the 5-min grid, where
    `settle[i]` is the settlement point price of the 15-min interval that
    5-min print i falls inside.

    The offset between the two series is calibrated rather than assumed. This
    began as a workaround for a CPT->UTC bug that stamped rtm15 an hour late
    during CDT (fixed 2026-08; see ingest/ercot_ingest.py and the note in
    MIXED_BASIS.md) and is kept as a standing safety net, since a silent
    one-hour misalignment is invisible in aggregate statistics. On correctly
    ingested data every month calibrates to 0 h. The offset is
    **calibrated per calendar month** by choosing the whole-hour shift that
    minimises |mean(3 SCED prints) - SPP|, and the residual is reported so a
    bad pairing is visible instead of silent. Months whose residual stays
    high are dropped rather than silently mis-paired.
    """
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    q = lambda mkt: con.execute(
        "SELECT interval_start, price FROM ercot_spp WHERE market=? AND settlement_point=? "
        "AND interval_start>=? AND interval_start<? ORDER BY interval_start",
        (mkt, zone, t0, t1)).fetchall()
    rows5, rows15 = q("rtm5"), q("rtm15")
    con.close()
    if not rows5 or not rows15:
        raise SystemExit(f"{zone}: need both rtm5 and rtm15 (have "
                         f"{len(rows5)} / {len(rows15)} rows)")

    to_ts = lambda s: int(datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
                          .replace(tzinfo=timezone.utc).timestamp())
    p5 = {to_ts(s): v for s, v in rows5}
    p15 = {to_ts(s): v for s, v in rows15}
    month = lambda t: datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m")

    # group 5-min prints into their own 15-min bucket (true timeline)
    buckets = {}
    for t, v in p5.items():
        buckets.setdefault(t - (t % 900), []).append(v)

    by_month = {}
    for b, vs in buckets.items():
        if len(vs) == 3:
            by_month.setdefault(month(b), []).append((b, sum(vs) / 3))

    offsets, report = {}, []
    for mo, items in sorted(by_month.items()):
        best = None
        for shift_h in (-2, -1, 0, 1, 2):
            off = shift_h * 3600
            pairs = [(a, p15[b + off]) for b, a in items if b + off in p15]
            if len(pairs) < 50:
                continue
            err = sum(abs(x - y) for x, y in pairs) / len(pairs)
            if best is None or err < best[1]:
                best = (off, err, len(pairs))
        if best is None:
            continue
        offsets[mo] = best[0]
        report.append((mo, best[0] // 3600, best[1], best[2]))

    if not offsets:
        raise SystemExit(f"{zone}: could not calibrate rtm5/rtm15 alignment")

    # residual sanity: a correctly paired month sits near $1; flag the rest
    BAD = 5.0
    bad = [r for r in report if r[2] > BAD]
    if verbose:
        shifts = sorted({r[1] for r in report})
        print(f"  [{zone}] rtm15 offset vs rtm5 by month: {shifts} h "
              f"(median residual ${sorted(r[2] for r in report)[len(report)//2]:.2f}/MWh)")
        if bad:
            print(f"  [{zone}] dropping {len(bad)} month(s) with residual > ${BAD}: "
                  f"{', '.join(r[0] for r in bad)}")

    dropped = {r[0] for r in bad}
    times, decide, settle = [], [], []
    for t in sorted(p5):
        mo = month(t - (t % 900))
        if mo in dropped or mo not in offsets:
            continue
        key = (t - (t % 900)) + offsets[mo]
        if key not in p15:
            continue
        times.append(t)
        decide.append(p5[t])
        settle.append(p15[key])
    return times, decide, settle, report


def load_hashprice(path=HASHPRICE_CSV):
    hp = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            hp[row["date"]] = float(row["hashprice_usd_per_ph_day"])
    return hp


def hp_for_times(times, hp_by_date, constant=None):
    """Per-interval hashprice; missing dates carry the last known value."""
    out, last = [], None
    first = next(iter(hp_by_date.values()))
    for t in times:
        if constant is not None:
            out.append(constant)
            continue
        d = datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%d")
        last = hp_by_date.get(d, last)
        out.append(last if last is not None else first)
    return out


# ---------------------------------------------------------------- signals ---

def make_signal(kind, sec=300, **kw):
    """Returns f(hist, t_prev) -> decision price. `hist` is a deque of
    (t, price) ending at the previous print (never the current one)."""
    W = kw.get("W", 15) * 60

    if kind == "persist":
        return lambda hist, tp: hist[-1][1]

    if kind == "slope-end":
        g = kw["g"]  # minutes of extrapolation

        def f(hist, tp):
            last = hist[-1][1]
            tgt = tp - W
            best = None
            for t, p in hist:
                if abs(t - tgt) <= sec / 2:
                    best = (t, p)
                    break
            if best is None or best[0] == tp:
                return last
            slope = (last - best[1]) / ((tp - best[0]) / 60.0)   # $/min
            return last + g * slope
        return f

    if kind in ("slope-ols", "slope-asym"):
        g_up = kw.get("g_up", kw.get("g", 15))
        g_dn = kw.get("g_dn", kw.get("g", 15))

        def f(hist, tp):
            last = hist[-1][1]
            pts = [(t, p) for t, p in hist if t >= tp - W]
            if len(pts) < 3:
                return last
            n = len(pts)
            mt = sum(t for t, _ in pts) / n
            mp = sum(p for _, p in pts) / n
            sxx = sum((t - mt) ** 2 for t, _ in pts)
            if sxx == 0:
                return last
            slope = sum((t - mt) * (p - mp) for t, p in pts) / sxx * 60.0  # $/min
            g = g_up if slope > 0 else g_dn
            return last + g * slope
        return f

    if kind == "ewma":
        # Normalized truncated EWMA (weights (1-alpha)^age, renormalized).
        # Seeding at hist[0] instead would give the oldest retained print an
        # outsized weight and echo spikes a full buffer-length later.
        alpha = 1 - 0.5 ** (float(sec) / W)   # per-interval, half-life W

        def f(hist, tp):
            num = den = 0.0
            wgt = 1.0
            for _, p in reversed(hist):
                num += wgt * p
                den += wgt
                wgt *= 1 - alpha
            return num / den
        return f

    if kind == "quant":
        q = kw["q"]

        def f(hist, tp):
            pts = sorted(p for t, p in hist if t >= tp - W)
            if not pts:
                return hist[-1][1]
            i = q * (len(pts) - 1)
            lo = int(math.floor(i))
            hi = min(lo + 1, len(pts) - 1)
            return pts[lo] + (pts[hi] - pts[lo]) * (i - lo)
        return f

    if kind == "bias":
        b = kw["b"]
        return lambda hist, tp: hist[-1][1] + b

    raise ValueError(kind)


# ------------------------------------------------------------- simulation ---

def point_breakeven(miner, p):
    """f(hp) -> $/MWh at which power p earns exactly nothing on hashprice hp.

    With p = miner.p_def it is the stock breakeven; with the fixed target of a
    fixed-target strategy (simulate(fixed_power=p)) it is that point's own
    breakeven, the alternative to the loop's own best-point backstop."""
    return lambda hp: hp * miner.hashrate(p) / 1000.0 / (p * 24 / 1e6)


def simulate(times, prices, hps, miner, signal=None, hold_s=1800,
             deadband=None, delay=1, backstop=True, sec=300, hist_span_s=None,
             settle=None, targets=None, paused_draw=0.0, hps_decide=None,
             move_loss_s=0.0, first_visit_s=0.0, fixed_power=None,
             backstop_be=None, k_trip=None, restart_band=None, dwell_s=None,
             trace=None):
    """Run one strategy. Returns metrics dict.

    signal=None   -> S0 (always default power, never stops)
    signal='S1'   -> perfect foresight, free pause, no hold, no backstop
    else          -> reactive PAPO with the given decision-price function

    `prices` is the DECISION series (what the loop sees, one interval
    stale). `settle` is the SETTLEMENT series billed for the same intervals;
    when None it defaults to `prices` (single-basis mode, as in the original
    study). Mixed basis (decide on 5-min SCED, settle on the 15-min SPP
    broadcast across its three 5-min sub-intervals) is what a real ERCOT
    site experiences: the price is 15-min granular but consumption is not.

    hist_span_s bounds the retained price history; it must exceed the largest
    signal window in use (default: 13 intervals, as in the 5-min study).

    targets, if given (a collections.Counter), counts the intervals the causal
    loop runs at each applied power target; paused intervals are not counted,
    and S0 and S1 ignore it. It changes nothing else. The loop sets its target
    only to stock power (the starting value, held until the first move), to a
    result of miner.optimal_power, or, when fixed_power is given, to that
    fixed target and nothing else (baselines_study.py, the only driver that
    passes it, passes the power ceiling, itself a hull point);
    optimizer_bruteforce_check.py uses this to print which targets the loop
    applies.

    paused_draw is the share of stock power (miner.p_def) a machine the causal
    loop has paused still draws, billed at the settlement price of each paused
    interval. The default, 0.0, books a paused interval at zero, as every
    printed number assumes, and leaves every result unchanged. S0 never pauses
    and S1 ignores it: the oracle's pause is free by definition.
    baselines_study.py uses it for the sensitivity chapter 5 does not measure.

    The options below were added 2026-10-03 for capture_anatomy.py and
    baselines_study.py. Each defaults to the behavior every committed number
    was computed with, and S0 and S1 ignore all of them.

    hps_decide, if given, is a second hashprice series (same length as hps)
    that the causal loop DECIDES on: the power target it computes and the
    backstop's breakeven. Revenue is still booked at hps. Passing the previous
    UTC day's hashprice removes the engine's one look-ahead, the same day's
    realized hashprice (capture_anatomy.py HASHPRICE).

    move_loss_s charges a power-target move: the machine hashes nothing for
    that many seconds after every physical change of power target the causal
    loop makes while its power is still billed at the new target. A physical
    change is a move the hold or the price deadband allows (the moves
    `changes` counts) or the target set at a backstop resume. first_visit_s is
    the saved-profile model: the first time in a run that the loop applies a
    distinct target, the machine hashes nothing for that many seconds at full
    draw (the larger of the two applies); later visits to that target cost
    only move_loss_s. The starting target (stock power, or fixed_power) counts
    as already tuned. Lost hashing is a blackout window [t, t + seconds) laid
    over the interval grid: each running interval loses the share of its
    revenue that falls inside the window, and a new charge while a window is
    open extends it, never shortens it. Both default to 0.0, a free move, as
    every other printed number assumes. The returned dict always carries
    `moves` and `moves_per_day` (physical changes: `changes` plus resumes),
    `resumes` and `first_visits`; the first three are counted on every run,
    but `first_visits` only when move_loss_s or first_visit_s is above 0, and
    is 0 otherwise.

    fixed_power, if given, runs a fixed-target strategy on the same curve:
    the causal loop starts at that power target, never moves it, and resumes
    to it after every backstop pause (hold, price deadband and signal are
    then irrelevant). backstop_be, if given, replaces the backstop's breakeven:
    a function of the day's decision hashprice returning $/MWh. The default
    is miner.breakeven_best, the best-point breakeven of the miner passed in,
    so simulate(miner, fixed_power=miner.p_max) is the ceiling with the loop's
    own backstop, and backstop_be=point_breakeven(miner, miner.p_max) trips
    it at the ceiling point's own breakeven instead (baselines_study.py).

    k_trip, restart_band and dwell_s override the backstop constants K_TRIP,
    RESTART_BAND and DWELL_S for one run (capture_anatomy.py RETUNE); None
    takes the module constants.

    trace, if given (a list), receives one (profit, power) tuple per interval
    of the causal path: the interval's booked profit and the applied power
    target, 0.0 while paused. S0 and S1 ignore it.
    """
    if settle is None:
        settle = prices
    if hps_decide is None:
        hps_decide = hps
    if backstop_be is None:
        backstop_be = miner.breakeven_best
    k_trip = K_TRIP if k_trip is None else k_trip
    restart_band = RESTART_BAND if restart_band is None else restart_band
    dwell_s = DWELL_S if dwell_s is None else dwell_s
    n = len(times)
    if hist_span_s is None:
        hist_span_s = 13 * sec
    dt_h = sec / 3600.0
    profit = 0.0
    hist = deque()                      # (t, price) available prints
    applied = miner.p_def if fixed_power is None else fixed_power
    t_last_change = -10**12
    changes = 0
    resumes = 0
    off_intervals = 0

    # backstop state
    running = True
    area = 0.0
    calm_since = None
    t_stop = -10**12
    t_start = -10**12
    stops = 0
    cycles_today = 0
    cur_day = None

    be_cache_day, be_val = None, None

    # actuation cost state (inactive at the defaults)
    charge_moves = move_loss_s > 0 or first_visit_s > 0
    blackout_until = -10**12
    visited = {applied}
    first_visits = 0

    def charge(t, p):
        """Open or extend the blackout window for a physical move to p at t."""
        nonlocal blackout_until, first_visits
        loss = move_loss_s
        if p not in visited:
            visited.add(p)
            first_visits += 1
            loss = max(loss, first_visit_s)
        if loss > 0:
            blackout_until = max(blackout_until, t + loss)

    for i in range(n):
        t, price, hp = times[i], prices[i], hps[i]
        sp = settle[i]          # billed price for this interval

        if signal is None:                       # S0
            profit += miner.profit(miner.p_def, sp, hp, sec)
            continue

        if signal == "S1":                       # perfect foresight ceiling
            p = miner.optimal_power(sp, hp, sec)
            pr = miner.profit(p, sp, hp, sec)
            if pr < 0:
                pr = 0.0
                off_intervals += 1
            profit += pr
            continue

        hpd = hps_decide[i]

        # ---- causal path: decisions use prints up to index i-delay ----
        if i >= delay:
            hist.append((times[i - delay], prices[i - delay]))
            while hist and hist[0][0] < t - hist_span_s:
                hist.popleft()

        if not hist:                             # warm-up: run at default
            if targets is not None:
                targets[applied] += 1
            pr = miner.profit(applied, sp, hp, sec)
            profit += pr
            if trace is not None:
                trace.append((pr, applied))
            continue

        t_prev, p_prev = hist[-1]

        day = datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%d")
        if day != cur_day:
            cur_day = day
            cycles_today = 0
        if day != be_cache_day:
            be_cache_day = day
            be_val = backstop_be(hpd)

        if backstop:
            if running:
                if p_prev >= be_val:
                    area += (p_prev - be_val) * dt_h
                else:
                    area = 0.0
                if (area >= k_trip and cycles_today < MAX_CYCLES_DAY
                        and t - t_start >= MIN_UP_S):
                    running = False
                    stops += 1
                    cycles_today += 1
                    t_stop = t
                    calm_since = None
                    area = 0.0
            else:
                if p_prev <= be_val * (1 - restart_band):
                    if calm_since is None:
                        calm_since = t_prev
                else:
                    calm_since = None
                if (calm_since is not None and t_prev - calm_since >= dwell_s - sec
                        and t - t_stop >= MIN_DOWN_S):
                    running = True
                    t_start = t
                    if fixed_power is None:
                        applied = miner.optimal_power(signal(hist, t_prev), hpd, sec)
                    t_last_change = t
                    resumes += 1
                    if charge_moves:
                        charge(t, applied)

        if not running:
            off_intervals += 1
            if paused_draw:
                profit -= paused_draw * miner.p_def / 1e6 * dt_h * sp
                if trace is not None:
                    trace.append((-paused_draw * miner.p_def / 1e6 * dt_h * sp, 0.0))
            elif trace is not None:
                trace.append((0.0, 0.0))
            continue

        if fixed_power is None:
            ideal = miner.optimal_power(signal(hist, t_prev), hpd, sec)
            if abs(ideal - applied) > 1.0:
                allowed = (t - t_last_change) >= hold_s
                if not allowed and deadband is not None:
                    allowed = abs(ideal - applied) > deadband * miner.p_def
                if allowed:
                    applied = ideal
                    t_last_change = t
                    changes += 1
                    if charge_moves:
                        charge(t, applied)

        if targets is not None:
            targets[applied] += 1
        pr = miner.profit(applied, sp, hp, sec)
        if blackout_until > t:               # lost hashing, power still billed
            pr -= miner.profit(applied, 0.0, hp, sec) * min(blackout_until - t, sec) / sec
        profit += pr
        if trace is not None:
            trace.append((pr, applied))

    days = (times[-1] - times[0]) / 86400.0
    return {
        "profit": profit,
        "off_pct": 100.0 * off_intervals / n,
        "changes_per_day": changes / days,
        "stops_per_day": stops / days,
        "days": days,
        "moves": changes + resumes,
        "moves_per_day": (changes + resumes) / days,
        "resumes": resumes,
        "first_visits": first_visits,
    }


# Expected breakevens ($/MWh) at the report's $44.31/PH/day, per miner model,
# and the modulation floor (W) each model clamps at. The default-power figures
# are the same either way, because the two curves agree at default power. The
# best-point figures are not: the fitted curve's optimistic floor efficiency buys
# the S21 XP about 20 $/MWh of headroom the fleet does not measure, which is the
# whole reason this engine moved to telemetry.
# Moved with the floor: telemetry best-point breakevens were 148 (S21 XP) and
# 76 (S19j Pro) when the engine clamped at the fit's 2,760 / 1,630 W floors;
# 149 and 77 at the telemetry's best-efficiency floors (2,200 / 1,200 W,
# 2026-09 to 2026-09-26); 148 and 77 now, with the S21 XP floored at its
# 2,774 W default minimum, where the best J/TH in range is at 3,200 W
# (148.38 $/MWh). The floors are pinned here too, so a silent revert fails
# loudly.
EXPECTED_BREAKEVENS = {
    "parametric fit": (("S21XP", 169, 144, 2760), ("S19jPro", 78, 65, 1630)),
    "2026-Q2 fleet telemetry": (("S21XP", 148, 144, 2774), ("S19jPro", 77, 65, 1200)),
}


def check_breakevens():
    """Economics sanity: reproduce the breakevens and floors expected for the
    miner model. Tolerance is 0.75 $/MWh. That catches the S19j Pro's 2026-09
    floor move (+1.7 $/MWh) but not the S21 XP's (+0.55, then -0.55 on
    2026-09-26), which sits inside it, so the floors themselves are pinned in
    EXPECTED_BREAKEVENS as well."""
    for mkey, be_best, be_def, floor in EXPECTED_BREAKEVENS[MINER_MODEL]:
        m = MINERS[mkey]
        be = m.breakeven_best(44.31)
        rev_day = 44.31 * m.hashrate(m.p_def) / 1000.0
        be_d = rev_day / (m.p_def * 24 / 1e6)
        assert abs(be - be_best) < 0.75 and abs(be_d - be_def) < 0.75, (mkey, be, be_d)
        assert m.p_min == floor, (mkey, m.p_min, floor)
    return True
