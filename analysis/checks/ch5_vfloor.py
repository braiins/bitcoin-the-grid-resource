#!/usr/bin/env python3
"""ch5_vfloor.py -- the V-floor: what the 2026-Q2 fleet telemetry shows below
each machine's best-efficiency point, and how that compares with a Braiins OS
chip-autotuning engineer's modelled performance curves and Braiins OS's default
power limits. It backs chapter 5's
V-floor paragraphs, Figure 5.1's caption and the glossary's V-floor entry. Run
from the repo root:

    python3 analysis/checks/ch5_vfloor.py

Part 1, the fleet telemetry. For each model it prints the best-efficiency point
(as analysis/ch5-backtest/telemetry_miner.py best_efficiency_power derives it;
the loop's modulation floor on the S19j Pro, not on the S21 XP, whose floor is
Braiins OS's default minimum, part 3), every reading below it with its J/TH and
hashrate against the best point, and, for scale, how far the curve wobbles
above the best point: the point-to-point steps that IMPROVE efficiency as power
rises, which a smooth curve would not have. A rise below the best point no
larger than those wobbles is too small to call an upturn from fleet averages
alone.

Part 2, the modelled curves against the fleet. The MODELLED constants below are
transcribed from the book's bib entry mikus2025vfloor: a personal communication
from one Braiins OS chip-autotuning engineer (a Braiins internal chat of
15 October 2025 and the performance-curve CSVs he sent on 15 and 16 October
2025). They are his model, fitted to a year of telemetry, for one machine at a
42 C average hashboard temperature (which he calls the bosminer default for the
model; the Academy's Default Temperatures, 60 C for the S19J Pro and 65 C for
the S21 XP and S21 Pro, are target temperatures, a different quantity), and
they carry the errors of Braiins' own power model. Below its floor a modelled curve is exactly linear
(the hashrate gained per 50 W step stays constant, because only the frequency
changes); the floor is where that gain first drops. Only the steps the
communication quotes are transcribed. The one number derived beyond them is the
S19j Pro line's zero-hashrate intercept: arithmetic on the quoted slope and
point that sizes the draw which does not scale with the clock (chapter 5's
leakage, fans and control board), not a modelled reading at zero hashrate.

Part 3, Braiins OS's default power limits (bib entry braiinsacademytechres,
the Academy's Technical Resources page, table "Default power limits -- Braiins
OS", read 2026-09-26), against the modelled floors and the fleet readings, and
the modulation floor both backtest engines take from them (the default
minimum, or the best-efficiency point where that is higher): chapter 5's kit
through telemetry_miner.modulation_floor, chapter 9's engine through
analysis/checks/ch9_tuning.R ch9_floor. Each engine's copy of the defaults
(telemetry_miner.BOS_DEFAULT_MIN_W, ch9_tuning.R CH9_BOS_MIN_W, read from the
R source) is checked against this transcription, and the two floors against
each other.

Pure stdlib; reads analysis/data/miner_efficiency_telemetry_2026q2.csv.
"""
import csv
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TELEMETRY = os.path.join(ROOT, "analysis", "data", "miner_efficiency_telemetry_2026q2.csv")

# mikus2025vfloor, transcribed. steps: (from W, to W, TH/s gained over the step).
MODELLED = {
    "S19j Pro": {
        "steps": [(1800, 1850, 2.525), (1850, 1900, 2.380), (1900, 1950, 1.293)],
        "floor_w": (1850, 1900), "floor_ths": (74, 76),
        "best": (1900, 25.06),            # best efficiency: 25.06 J/TH at 1,900 W
        "top": (5350, 149),               # hashrate stops growing: the PSU's maximum voltage
    },
    "S21 XP": {
        "steps": [(1800, 1850, 6.685), (1850, 1900, 6.685), (1900, 1950, 6.626),
                  (1950, 2000, 4.902)],
        "floor_w": (1900, 1950), "floor_ths": (178, 178),
    },
    "S21 Pro": {
        # a flat +5.816 TH/s per 50 W up to 1,650 W, then +5.14
        "steps": [(1600, 1650, 5.816), (1650, 1700, 5.14)],
        "floor_w": (1650, 1650), "floor_ths": (122, 122),
    },
}

# braiinsacademytechres, "Default power limits -- Braiins OS" (current miners).
# Min Power, Max Power (W) and Min Hashrate (TH/s); the S19J Pro's are the same for
# every performance variant, 2,478 to 3,068 W; the S21 XP row is its only variant,
# 3,645 W / 270 TH/s; the S21 Pro's are the same for its 3,300, 3,500 and 3,675 W
# variants.
ACADEMY = {
    "S19j Pro": {"min_w": 944, "max_w": 6435, "min_ths": 70.75},
    "S21 XP": {"min_w": 2774, "max_w": 6435, "min_ths": 153.16},
    "S21 Pro": {"min_w": 2316, "max_w": 6435, "min_ths": 109.40},
}


def load():
    by = {}
    with open(TELEMETRY, newline="") as f:
        for r in csv.DictReader(f):
            by.setdefault(r["model"], []).append(
                (int(r["power_w"]), float(r["avg_jth"]), float(r["hashrate_ths"])))
    for pts in by.values():
        pts.sort()
    return by


def interp_ths(pts, p):
    """Fleet hashrate at power p, linear between measured points (as the kit does)."""
    for (p0, _, h0), (p1, _, h1) in zip(pts, pts[1:]):
        if p0 <= p <= p1:
            return h0 + (h1 - h0) * (p - p0) / (p1 - p0)
    raise ValueError(p)


def per50(pts, a, b):
    """Fleet TH/s gained per 50 W between measured points a and b (W)."""
    h = {p: x for p, _, x in pts}
    return (h[b] - h[a]) / (b - a) * 50


def part1(by):
    print("PART 1: the fleet telemetry below and above each best point")
    for model, pts in by.items():
        # best point as telemetry_miner.best_efficiency_power ranks it (power /
        # hashrate); the avg_jth column must agree, or the telemetry is suspect
        i = min(range(len(pts)), key=lambda k: pts[k][0] / pts[k][2])
        if i != min(range(len(pts)), key=lambda k: pts[k][1]):
            print(f"{model}: WARNING power / hashrate and avg_jth disagree on the best point")
        pb, jb, hb = pts[i]
        print(f"{model}: {len(pts)} points, {pts[0][0]:,} to {pts[-1][0]:,} W; "
              f"best {jb:.3f} J/TH at {pb:,} W; range {min(p[1] for p in pts):.2f} "
              f"to {max(p[1] for p in pts):.2f} J/TH")
        for p, j, h in pts[:i]:
            print(f"  below the best point: {p:,} W  {j:.3f} J/TH ({100 * (j / jb - 1):+.2f}%), "
                  f"{h:.1f} TH/s ({100 * (h / hb - 1):+.1f}% hashrate)")
        steps = [(pts[k][0], pts[k + 1][0], 100 * (pts[k + 1][1] / pts[k][1] - 1))
                 for k in range(i, len(pts) - 1)]
        dips = [s for s in steps if s[2] < 0]
        line = f"  above the best point: {len(dips)} of {len(steps)} steps improve"
        if dips:
            a, b, d = min(dips, key=lambda s: s[2])
            line += f", largest {d:.2f}% ({a:,} to {b:,} W)"
        print(line)


def part2(by):
    print("\nPART 2: the modelled curves (mikus2025vfloor) against the fleet")
    for model, m in MODELLED.items():
        lo, hi = m["floor_w"]
        print(f"{model}: modelled V-floor about {lo:,}"
              + (f" to {hi:,}" if hi != lo else "") + f" W, about "
              + (f"{m['floor_ths'][0]} to {m['floor_ths'][1]}" if m["floor_ths"][0] != m["floor_ths"][1]
                 else f"{m['floor_ths'][0]}") + " TH/s; steps "
              + ", ".join(f"{a:,}-{b:,} W +{g:.3f}" for a, b, g in m["steps"]))

    s19 = MODELLED["S19j Pro"]
    f19 = by["S19j Pro"]
    pb, jb = s19["best"]
    h1900 = pb / jb
    h1850 = h1900 - s19["steps"][1][2]
    print(f"\nS19j Pro, the model at its floor: {h1850:.2f} TH/s at 1,850 W "
          f"({1850 / h1850:.2f} J/TH), {h1900:.2f} TH/s at 1,900 W ({jb:.2f} J/TH, its best)")
    for p, hm in ((1850, h1850), (1900, h1900)):
        hf = interp_ths(f19, p)
        print(f"  fleet at {p:,} W (interpolated): {hf:.2f} TH/s, {p / hf:.2f} J/TH, "
              f"{100 * (hf / hm - 1):+.1f}% hashrate against the model")
    h = {p: x for p, _, x in f19}
    j = {p: x for p, x, _ in f19}
    print(f"  fleet at 1,800 W: {h[1800]:.2f} TH/s, {j[1800]:.2f} J/TH; at 2,000 W: "
          f"{h[2000]:.2f} TH/s, {j[2000]:.2f} J/TH")
    print(f"  above the floor, TH/s per 50 W: model 1,900-1,950 W +{s19['steps'][2][2]:.3f}; "
          f"fleet 2,000-2,200 W +{per50(f19, 2000, 2200):.3f}, 1,800-2,000 W +{per50(f19, 1800, 2000):.3f}")
    print(f"  below the floor, TH/s per 50 W: model 1,800-1,850 W +{s19['steps'][0][2]:.3f} (constant "
          f"below the floor); fleet 1,200-1,800 W +{per50(f19, 1200, 1800):.3f} "
          f"({100 * per50(f19, 1200, 1800) / s19['steps'][0][2]:.0f}% of the model's), "
          f"1,000-1,200 W +{per50(f19, 1000, 1200):.3f}, 800-1,000 W +{per50(f19, 800, 1000):.3f}")
    print(f"  fleet J/TH falls from {j[1800]:.2f} at 1,800 W to {j[1200]:.2f} at 1,200 W "
          f"({100 * (j[1200] / j[1800] - 1):+.1f}%), where the model's gets worse below 1,900 W")
    w_per_ths = 50 / s19["steps"][0][2]
    print(f"  the model's line below its floor: +{s19['steps'][0][2]:.3f} TH/s per 50 W is "
          f"{w_per_ths:.2f} W per TH/s; through {h1850:.2f} TH/s at 1,850 W it leaves "
          f"{1850 - w_per_ths * h1850:.1f} W that does not scale with hashrate (the line's "
          f"intercept: arithmetic, not a modelled reading)")

    x21 = MODELLED["S21 XP"]
    f21 = by["S21 XP"]
    h21 = {p: x for p, _, x in f21}
    j21 = {p: x for p, x, _ in f21}
    lo, hi = x21["floor_w"]
    mid = (lo + hi) / 2
    fth = x21["floor_ths"][0]
    print(f"\nS21 XP: fleet best point 2,200 W, {h21[2200]:.2f} TH/s ({j21[2200]:.3f} J/TH), "
          f"{100 * (h21[2200] / fth - 1):+.1f}% against the modelled floor's {fth} TH/s")
    print(f"  power for that hashrate: fleet 2,200 W against the model's {lo:,}-{hi:,} W: "
          f"{100 * (2200 / hi - 1):+.1f}% to {100 * (2200 / lo - 1):+.1f}% "
          f"({100 * (2200 / mid - 1):+.1f}% on the midpoint, {mid:,.0f} W); "
          f"the model at its floor, about {mid / fth:.1f} J/TH")
    print(f"  fleet at 2,000 W: {h21[2000]:.2f} TH/s, {100 * (h21[2000] / fth - 1):+.1f}% against the "
          f"modelled floor's hashrate, {100 * (j21[2000] / j21[2200] - 1):+.2f}% J/TH against 2,200 W")
    print(f"  TH/s per 50 W: model below its floor +{x21['steps'][0][2]:.3f}, above it "
          f"+{x21['steps'][3][2]:.3f}; fleet 2,000-2,200 W +{per50(f21, 2000, 2200):.3f}, "
          f"2,200-2,400 W +{per50(f21, 2200, 2400):.3f}")

    print(f"\nSame power supply (Bitmain lists APW171215a/c, PW380a/b/c for both), different "
          f"floors: S21 XP about {sum(x21['floor_w']) / 2:,.0f} W, S21 Pro about "
          f"{MODELLED['S21 Pro']['floor_w'][0]:,} W")


def part3(by):
    print("\nPART 3: Braiins OS default power limits (braiinsacademytechres)")
    for model, a in ACADEMY.items():
        lo, hi = MODELLED[model]["floor_w"]
        where = "below" if a["min_w"] < lo else ("above" if a["min_w"] > hi else "within")
        line = (f"{model}: default Min Power {a['min_w']:,} W, Max {a['max_w']:,} W, Min Hashrate "
                f"{a['min_ths']:.2f} TH/s; {where} the modelled floor ({lo:,}"
                + (f"-{hi:,}" if hi != lo else "") + " W)")
        if model in by:
            under = [p for p, _, _ in by[model] if p < a["min_w"]]
            line += (f"; fleet readings below the default: {len(under)} of {len(by[model])} "
                     f"({', '.join(f'{p:,}' for p in under) or 'none'} W)")
        print(line)
    # the two engines' floors: chapter 5's kit holds the defaults in
    # analysis/ch5-backtest/telemetry_miner.py BOS_DEFAULT_MIN_W, chapter 9's
    # engine its own copy in analysis/checks/ch9_tuning.R CH9_BOS_MIN_W; both
    # are asserted against this transcription, and chapter 9's floor is
    # recomputed as ch9_floor takes it (the default, or the telemetry's lowest
    # avg_jth where that is higher) and asserted equal to the kit's
    sys.path.insert(0, os.path.join(ROOT, "analysis", "ch5-backtest"))
    import telemetry_miner as tm
    ch9 = ch9_default_mins()
    assert set(ch9) == set(tm.BOS_DEFAULT_MIN_W), (sorted(ch9), sorted(tm.BOS_DEFAULT_MIN_W))
    for model, dmin in tm.BOS_DEFAULT_MIN_W.items():
        assert dmin == ACADEMY[model]["min_w"], (model, dmin, ACADEMY[model]["min_w"])
        assert ch9[model] == ACADEMY[model]["min_w"], (model, ch9[model], ACADEMY[model]["min_w"])
        pts = [(p, h) for p, _, h in by[model]]
        best = tm.best_efficiency_power(pts)
        floor = tm.modulation_floor(model, pts)
        floor9 = max(ch9[model], min(by[model], key=lambda r: r[1])[0])
        assert floor9 == floor, (model, floor9, floor)
        print(f"  modulation floor, {model}: {floor:,.0f} W in both engines "
              "(telemetry_miner.modulation_floor, ch9_tuning.R ch9_floor), the "
              + ("default minimum" if floor == dmin else "best-efficiency point")
              + f" (default {dmin:,} W in both, best point {best:,.0f} W)")


def ch9_default_mins():
    """CH9_BOS_MIN_W as analysis/checks/ch9_tuning.R assigns it: {model: W}."""
    path = os.path.join(ROOT, "analysis", "checks", "ch9_tuning.R")
    with open(path) as f:
        lines = [ln for ln in f if ln.startswith("CH9_BOS_MIN_W <-")]
    assert len(lines) == 1, lines
    found = dict((m, int(w)) for m, w in re.findall(r'"(S19j Pro|S21 XP)" = (\d+)', lines[0]))
    assert len(found) == 2, lines[0]
    return found


def main():
    by = load()
    part1(by)
    part2(by)
    part3(by)


if __name__ == "__main__":
    main()
