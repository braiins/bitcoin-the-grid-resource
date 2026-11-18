#!/usr/bin/env python3
"""ch5_price_autocorrelation.py -- is the real-time price mean-reverting from one
print to the next? Chapter 5's "three facts" section. Run from the repo root:

    python3 analysis/checks/ch5_price_autocorrelation.py

The statistic is the lag-1 autocorrelation of price CHANGES: corr(dp_t, dp_t-1),
where dp_t = p_t - p_t-1 over consecutive intervals (a pair is used only when
all three prints exist, so gaps never masquerade as moves). Negative means a
move tends to be followed by a move the other way.

Two cadences, because they answer different questions:
  * five-minute prints, LZ_WEST (analysis/data/ercot_spp_rtm5_lzwest.csv.gz),
    the series the loop DECIDES on, so the one chapter 5 quotes;
  * 15-minute settlement point prices, all eight load zones (ERCOT MIS 13061,
    analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz), the series a site
    is billed on.
Window: 2024-01-01 through the end of the five-minute file (2026-06-22 Central),
in UTC, applied to both.

Because a Pearson correlation of changes is dominated by the largest moves (a
single up-and-back spike contributes -dp^2), the script also reports how much
of the statistic a handful of spikes carry: the five-minute figure with the
intervals around the largest moves removed, a rank (Spearman) version, and the
figure by half-year.

Pure stdlib.
"""
import csv
import gzip
import math
import os
import sys
from datetime import datetime, timezone

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "analysis", "ch5-backtest"))
from db import cpt_local_to_utc  # noqa: E402  (tz-database Central -> UTC)

RTM5 = os.path.join(ROOT, "analysis", "data", "ercot_spp_rtm5_lzwest.csv.gz")
RTM15 = os.path.join(ROOT, "analysis", "data", "ercot_rtm15_spp_loadzones_2021on.csv.gz")
T0 = "2024-01-01T00:00:00Z"
T1 = "2026-06-23T05:00:00Z"          # end of the five-minute file, exclusive
FMT = "%Y-%m-%dT%H:%M:%SZ"
epoch = lambda s: int(datetime.strptime(s, FMT).replace(tzinfo=timezone.utc).timestamp())


def pearson(x, y):
    n = len(x)
    mx, my = sum(x) / n, sum(y) / n
    sxy = sum((a - mx) * (b - my) for a, b in zip(x, y))
    sxx = sum((a - mx) ** 2 for a in x)
    syy = sum((b - my) ** 2 for b in y)
    return sxy / math.sqrt(sxx * syy)


def ranks(v):
    order = sorted(range(len(v)), key=v.__getitem__)
    r = [0.0] * len(v)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and v[order[j + 1]] == v[order[i]]:
            j += 1
        for k in range(i, j + 1):
            r[order[k]] = (i + j) / 2.0
        i = j + 1
    return r


def change_pairs(series, step):
    """[(t, dp_prev, dp_now)] over runs of consecutive intervals."""
    ts = sorted(series)
    out = []
    for a, b, c in zip(ts, ts[1:], ts[2:]):
        if b - a == step and c - b == step:
            out.append((c, series[b] - series[a], series[c] - series[b]))
    return out


def ac(pairs):
    return pearson([p[1] for p in pairs], [p[2] for p in pairs])


def load_rtm5():
    s = {}
    with gzip.open(RTM5, "rt", newline="") as f:
        for r in csv.DictReader(f):
            if T0 <= r["interval_start"] < T1:
                s[epoch(r["interval_start"])] = float(r["price"])
    return s


def load_rtm15():
    by_zone = {}
    with gzip.open(RTM15, "rt", newline="") as f:
        for r in csv.DictReader(f):
            if r["interval_start"] < "2023-12-31":
                continue
            local = datetime.strptime(r["interval_start"], "%Y-%m-%dT%H:%M:%S")
            u = cpt_local_to_utc(local, r["dst_repeated_flag"] == "Y")
            if T0 <= u < T1:
                by_zone.setdefault(r["settlement_point"], {})[epoch(u)] = float(r["price"])
    return by_zone


def half(t):
    d = datetime.fromtimestamp(t, timezone.utc)
    return f"{d.year}-H{1 if d.month <= 6 else 2}"


def main():
    p5 = load_rtm5()
    pairs5 = change_pairs(p5, 300)
    # Mean reversion is one-sided. After a large RISE the next print usually
    # falls back; after a large FALL it usually keeps falling, because a spike
    # unwinds over several prints. Chapter 5 and the glossary state it that way.
    for label, sel in (("rises of $100 or more", lambda a: a >= 100),
                       ("falls of $100 or more", lambda a: a <= -100)):
        nxt = [b for _, a, b in pairs5 if sel(a)]
        down = sum(1 for b in nxt if b < 0)
        print(f"after {label}: n={len(nxt)}, next print lower {100*down/len(nxt):.0f}% of the time, "
              f"mean next move ${sum(nxt)/len(nxt):+,.2f}")
    print("=== LZ_WEST five-minute prints (the series the loop decides on) ===")
    print(f"window {T0} .. {T1} (UTC), {len(p5):,} prints, {len(pairs5):,} change pairs")
    r_all = ac(pairs5)
    r_rank = pearson(ranks([p[1] for p in pairs5]), ranks([p[2] for p in pairs5]))
    print(f"lag-1 autocorrelation of changes (Pearson):   {r_all:+.3f}")
    print(f"lag-1 autocorrelation of changes (Spearman):  {r_rank:+.3f}")

    # How much do the biggest moves carry? Drop every pair that touches one of
    # the N largest absolute changes, then recompute.
    big = sorted(pairs5, key=lambda p: -abs(p[2]))
    print("\nlargest five-minute moves (UTC stamp of the print after the move):")
    for t, dprev, dnow in big[:10]:
        print(f"  {datetime.fromtimestamp(t, timezone.utc):%Y-%m-%d %H:%M}Z  "
              f"move {dnow:+10.2f}  previous move {dprev:+10.2f}  "
              f"print {p5[t]:9.2f}")
    ups = sorted(pairs5, key=lambda p: -p[2])[:5]
    print("\nthe five largest upward moves, and the move at the next print:")
    for t, _, dnow in ups:
        nxt = p5.get(t + 300)
        after = f"{nxt - p5[t]:+10.2f}" if nxt is not None else "   (no print)"
        print(f"  {datetime.fromtimestamp(t, timezone.utc):%Y-%m-%d %H:%M}Z  "
              f"up {dnow:+9.2f}  then {after}")

    # A pair spans three prints (t-600, t-300, t). Drop every pair that shares a
    # print with one of the N largest moves, so a spike's up-leg and down-leg
    # both leave the sample together.
    def without(moves):
        bad = set()
        for t in moves:
            bad.update((t - 300, t))          # the two prints of that move
        return [p for p in pairs5
                if not ({p[0] - 600, p[0] - 300, p[0]} & bad)]
    for n in (5, 10, 20, 50):
        keep = without([p[0] for p in big[:n]])
        print(f"  without the {n:>2} largest moves:              "
              f"{ac(keep):+.3f}   ({len(pairs5) - len(keep)} pairs dropped)")
    for cap in (1000, 500):
        hot = [t for t, v in p5.items() if v > cap]
        episodes = sum(1 for t in hot if (t - 300) not in p5 or p5[t - 300] <= cap)
        keep = without([t for t in hot] + [t + 300 for t in hot])
        print(f"  without every print above ${cap:,} ({len(hot)} prints, "
              f"{episodes} episodes): {ac(keep):+.3f}   "
              f"({len(pairs5) - len(keep)} pairs dropped)")

    print("\nby half-year (Pearson, Spearman, and prints above $1,000):")
    halves = sorted({half(p[0]) for p in pairs5})
    for h in halves:
        sub = [p for p in pairs5 if half(p[0]) == h]
        rr = pearson(ranks([p[1] for p in sub]), ranks([p[2] for p in sub]))
        hot = [t for t, v in p5.items() if half(t) == h and v > 1000]
        runs = sum(1 for t in hot if p5.get(t - 300, 0) <= 1000)
        big_up = max(p[2] for p in sub)
        print(f"  {h}  n={len(sub):>6,}  {ac(sub):+.3f}  {rr:+.3f}  "
              f"largest one-print rise {big_up:+8.2f}  "
              f"prints above $1,000: {len(hot):>3} in {runs:>2} runs"
              + (f" (mean run {len(hot) / runs:.1f} prints)" if runs else ""))

    print("\n=== 15-minute settlement point prices, eight load zones (billing series) ===")
    zones = load_rtm15()
    for z in sorted(zones):
        pz = change_pairs(zones[z], 900)
        rr = pearson(ranks([p[1] for p in pz]), ranks([p[2] for p in pz]))
        print(f"  {z:<11} n={len(pz):>6,}  Pearson {ac(pz):+.3f}  Spearman {rr:+.3f}")


if __name__ == "__main__":
    main()
