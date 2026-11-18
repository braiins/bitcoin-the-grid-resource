#!/usr/bin/env python3
"""Drop-in replacement for papo_sim.Miner backed by measured fleet telemetry.

The study engine models each machine as a linear J(p) curve fitted to two
points. The chapter's figures use the 2026-Q2 Braiins OS fleet telemetry table
instead, which is a measured curve rather than a fit. This module builds a
Miner-compatible object from that table so the backtest can be re-run on the
same curves the figures draw.

The modulation floor is Braiins OS's default minimum power target for the
model, or the measured curve's best-efficiency point (the power at which
power_w / hashrate_ths is lowest, derived here from the table) where that sits
higher: modulation_floor() below, the one place the floor is set. On the
2026-Q2 snapshot that is 2,774 W for the S21 XP (its default minimum; its best
point, 2,200 W, is lower) and 1,200 W for the S19j Pro (its best point; its
default minimum, 944 W, is lower, and running below the best point is
dominated: less hashrate and worse J/TH). The author's choice (2026-09-26) is
to model what Braiins OS allows by default, not the fleet's best point: until
then the S21 XP's floor was its 2,200 W best point. The defaults are the
Braiins Academy's Technical Resources page, table "Default Power Limits"
(bib entry braiinsacademytechres, read 2026-09-26), which
analysis/checks/ch5_vfloor.py part 3 transcribes in full. The engine used to
inherit the study's parametric floors (1,630 W and 2,760 W) instead.
The default power and the power ceiling still come from the engine's miner
definitions in papo_sim.py (3,068/3,420 W and 3,645/3,990 W).

Two consequences of using a measured curve:
  * J(p) is not monotonic. The S19j Pro's best efficiency sits at 1,200 W and
    gets worse in both directions, where the fit assumes the best point is the
    floor.
  * optimal_power can no longer use the fit's closed form, because that solves
    a quadratic that only exists for a linear J. It is a scan over the measured
    range instead, at 10 W resolution: the floor, then every multiple of 10 W
    above it, then the ceiling itself when that is off the 10 W grid
    (scan_powers; the ceiling was added 2026-10-03), so a floor off the grid,
    like the S21 XP's 2,774 W, does not shift the grid off the measured
    points, and a ceiling off it is still reachable.
"""
import bisect
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
TELEMETRY = os.path.join(HERE, "..", "data", "miner_efficiency_telemetry_2026q2.csv")

# Which telemetry model name belongs to which engine key.
MODEL_FOR = {"S21XP": "S21 XP", "S19jPro": "S19j Pro"}

# Braiins OS's default minimum power target (W) per telemetry model: Braiins
# Academy, Technical Resources, table "Default Power Limits" (Min Power), read
# 2026-09-26, bib entry braiinsacademytechres; the S19J Pro's is the same for
# every performance variant, and the S21 XP's row is its only variant.
# Chapter 9's engine holds its own copy, analysis/checks/ch9_tuning.R
# CH9_BOS_MIN_W; analysis/checks/ch5_vfloor.py part 3 asserts both against its
# transcription of the Academy table.
BOS_DEFAULT_MIN_W = {"S21 XP": 2774, "S19j Pro": 944}


def _load_table(path=TELEMETRY):
    by_model = {}
    with open(path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            by_model.setdefault(row["model"], []).append(
                (float(row["power_w"]), float(row["hashrate_ths"]))
            )
    for m in by_model:
        by_model[m].sort()
    return by_model


class TelemetryMiner:
    """Miner whose hashrate comes from the measured curve, linearly interpolated."""

    def __init__(self, name, p_min, p_def, p_max, points):
        self.name = name
        self.p_min, self.p_def, self.p_max = p_min, p_def, p_max
        self._p = [p for p, _ in points]
        self._h = [h for _, h in points]
        self._opt_cache = {}
        self._be_cache = {}
        if not (self._p[0] <= p_min and p_max <= self._p[-1]):
            raise ValueError(
                f"{name}: engine range {p_min}-{p_max} W is outside the measured "
                f"range {self._p[0]:.0f}-{self._p[-1]:.0f} W"
            )

    def scan_powers(self):
        """The optimizer's 10 W scan: the floor, then every multiple of 10 W
        above it, up to the ceiling, then the ceiling itself if the grid
        stopped short of it. On a floor that is itself a multiple of 10 W
        (1,200 W) this is the plain scan from the floor; on 2,774 W it runs
        2,774, 2,780, 2,790 W, so the measured points and the 3,990 W ceiling
        stay on the grid.

        The ceiling is appended when it is off the 10 W grid (fixed
        2026-10-03). The engine's own ceilings, 3,990 and 3,420 W, are on the
        grid, so nothing the engine's miners compute changes; but a variant
        with its ceiling held at stock power (baselines_study.py's 'full
        loop, ceiling at stock', 3,645 / 3,068 W) could never run at stock
        before the fix, and stopped at 3,640 / 3,060 W."""
        out = [self.p_min]
        p = (int(self.p_min) // 10 + 1) * 10
        while p <= self.p_max:
            out.append(float(p))
            p += 10
        if out[-1] < self.p_max:
            out.append(float(self.p_max))
        return out

    def hashrate(self, p):
        """TH/s at power p, linearly interpolated between measured points."""
        if p <= self._p[0]:
            return self._h[0]
        if p >= self._p[-1]:
            return self._h[-1]
        i = bisect.bisect_right(self._p, p) - 1
        p0, p1 = self._p[i], self._p[i + 1]
        h0, h1 = self._h[i], self._h[i + 1]
        return h0 + (h1 - h0) * (p - p0) / (p1 - p0)

    def _coeffs(self, hp, price, sec):
        return hp / 1000.0 * (sec / 86400.0), price / 1e6 * (sec / 3600.0)

    def profit(self, p, price, hp, sec):
        if p <= 0:
            return 0.0
        A, B = self._coeffs(hp, price, sec)
        return A * self.hashrate(p) - B * p

    def optimal_power(self, price, hp, sec):
        """Profit-optimal power in [p_min, p_max], by scan at 10 W resolution.

        The optimum depends only on the hashprice-to-price ratio, not on the
        two separately and not on the interval length, so results are cached on
        that ratio rounded to four figures. Without it the scan runs a hundred
        times per interval over hundreds of thousands of intervals.
        """
        if price <= 0:
            return self.p_max
        key = round(hp / price, 6)
        hit = self._opt_cache.get(key)
        if hit is not None:
            return hit
        best_p, best_v = self.p_min, None
        for p in self.scan_powers():
            v = self.profit(p, price, hp, sec)
            if best_v is None or v > best_v:
                best_p, best_v = p, v
        self._opt_cache[key] = best_p
        return best_p

    def breakeven_best(self, hp):
        """$/MWh above which no power level in range makes money.

        The fit puts the most efficient point at the floor, so it evaluates the
        floor. A measured curve can have its best point anywhere, so this takes
        the best J over the engine's range: on the S21 XP, whose floor is its
        2,774 W default minimum, that is 3,200 W, not the floor.
        """
        hit = self._be_cache.get(hp)
        if hit is not None:
            return hit
        best = None
        for p in self.scan_powers():
            rev_day = hp * self.hashrate(p) / 1000.0
            mwh_day = p * 24 / 1e6
            v = rev_day / mwh_day
            if best is None or v > best:
                best = v
        self._be_cache[hp] = best
        return best


def best_efficiency_power(points):
    """Power (W) of the measured point with the lowest J/TH."""
    return min(points, key=lambda ph: ph[0] / ph[1])[0]


def modulation_floor(model, points):
    """The modulation floor (W): Braiins OS's default minimum power target, or
    the best-efficiency point where that is higher, since below the best point
    a machine delivers less hashrate at worse J/TH. The one place the chapter
    5 kit sets the floor."""
    return float(max(BOS_DEFAULT_MIN_W[model], best_efficiency_power(points)))


def build(parametric_miners):
    """Return {key: TelemetryMiner}: floor from modulation_floor, default and
    ceiling from the engine's miner definitions."""
    table = _load_table()
    out = {}
    for key, m in parametric_miners.items():
        model = MODEL_FOR.get(key)
        if model is None or model not in table:
            raise KeyError(f"no telemetry rows for engine miner {key!r}")
        floor = modulation_floor(model, table[model])
        out[key] = TelemetryMiner(m.name, floor, m.p_def, m.p_max, table[model])
    return out


if __name__ == "__main__":
    import sys
    sys.path.insert(0, HERE)
    from papo_sim import PARAMETRIC_MINERS

    tel = build(PARAMETRIC_MINERS)
    print("floor / default / ceiling (W): telemetry engine vs the study's fit")
    for key, m in PARAMETRIC_MINERS.items():
        t = tel[key]
        print(f"  {m.name:<18} telemetry {t.p_min:>5.0f} / {t.p_def:.0f} / {t.p_max:.0f}"
              f"   fit {m.p_min:>5.0f} / {m.p_def:.0f} / {m.p_max:.0f}")
    print(f"\n{'machine':<18}{'power':>7}{'J/TH fit':>10}{'J/TH telem':>12}{'diff':>8}")
    for key, m in PARAMETRIC_MINERS.items():
        t = tel[key]
        for p in (t.p_min, m.p_min, m.p_def, m.p_max):
            jf = p / m.hashrate(p)
            jt = p / t.hashrate(p)
            print(f"{m.name:<18}{p:>7.0f}{jf:>10.2f}{jt:>12.2f}{jt - jf:>+8.2f}")
