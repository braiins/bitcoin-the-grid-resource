#!/usr/bin/env python3
"""ch5_api_readability.py -- when can a reader outside ERCOT read each price?
Chapter 5, beside ch5_posting_latency.py. Run from the repo root:

    python3 analysis/checks/ch5_api_readability.py

ch5_posting_latency.py measures when ERCOT POSTS each five-minute price. This
script measures when the price can actually be READ through ERCOT's public API,
which is later. It reads the committed poll log

  analysis/data/ercot_api_readability_polls.csv.gz

written by analysis/data/ercot_api_readability/poll.py (needs a free ERCOT API
Explorer account and a US connection) and reduced by build_polls_csv.py in the
same folder: one poll every 20 s from 2026-09-25 02:11 to 2026-10-05 02:11
Central, each asking both reports for the newest interval they hold.

Definitions.
  arrival    an interval's first appearance in a successful poll. It is
             bracketed between that poll and the previous SUCCESSFUL poll of
             the same report, and timed at the bracket's midpoint (so to about
             +-10 s at the 20 s period). A failed poll (no response, or an HTTP
             error) is not an observation: it neither opens nor closes a
             bracket. Brackets wider than 60 s are dropped, and so is the first
             interval after the start (no bracket).
  NP6-788    five-minute LMP. Timed from the five-minute boundary at or before
             its SCED time stamp, as ch5_posting_latency.py does. Only the first
             SCED run of each five-minute window counts (on-cycle); ERCOT's
             later reruns in the same window are skipped.
  NP6-905    15-minute settlement point price, timed from the end of its
             interval (the moment the interval settles).
  windows    "full" is the whole log. "clean" leaves out 2026-09-30 to
             2026-10-02, when the measuring connection failed: on those days all
             three requests of a poll failed together (every poll of
             2026-10-01), which is the measuring side, not ERCOT. With failed
             polls handled as above the two windows should agree closely; both
             are printed, and the book prints the full window.
Percentiles: p50 is the median; p95 is nearest-rank (the ceil(0.95 n)-th
smallest value), as in ch5_posting_latency.py.

Pure stdlib.
"""
import csv
import gzip
import math
import os
import statistics
from collections import defaultdict
from datetime import date, datetime, timedelta

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
POLLS = os.path.join(ROOT, "analysis", "data", "ercot_api_readability_polls.csv.gz")
MAX_BRACKET = 60.0
OUTAGE = (date(2026, 9, 30), date(2026, 10, 2))


def p95(xs):
    s = sorted(xs)
    return s[math.ceil(0.95 * len(s)) - 1]


def boundary5(ts):
    return ts.replace(minute=ts.minute // 5 * 5, second=0, microsecond=0)


def arrivals(rows, http_col, val_col, close_of, window_of=None):
    """[(close, latency_s)] for each new value, and a count of what was dropped."""
    out, dropped = [], defaultdict(int)
    seen, seen_window, prev_ok = set(), set(), None
    for r in rows:
        v = r[val_col]
        if r[http_col] != "200" or not v:
            continue                                   # failed poll: not an observation
        t = datetime.fromisoformat(r["t"])
        if v not in seen:
            seen.add(v)
            close = close_of(v)
            w = window_of(v) if window_of else v
            if w in seen_window:
                dropped["off-cycle rerun"] += 1
            elif prev_ok is None:
                dropped["no bracket (first)"] += 1
            elif (t - prev_ok).total_seconds() > MAX_BRACKET:
                dropped["bracket > 60 s"] += 1
            else:
                lat = ((t - close).total_seconds() + (prev_ok - close).total_seconds()) / 2
                if lat < 0:
                    dropped["negative"] += 1
                else:
                    out.append((close, lat))
            seen_window.add(w)
        prev_ok = t
    return out, dict(dropped)


def line(label, xs):
    n = len(xs)
    over = sum(x > 300 for x in xs)
    print(f"  {label:<34} n={n:>5}  median {statistics.median(xs):6.1f} s  "
          f"p95 {p95(xs):6.1f} s  max {max(xs):6.1f} s  >5 min {over:>4} ({100 * over / n:4.1f}%)")


def main():
    with gzip.open(POLLS, "rt", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    t0, t1 = rows[0]["t"], rows[-1]["t"]
    print(f"polls: {len(rows)}, {t0} .. {t1} Central")
    for col, name in (("a_http", "NP6-788"), ("b_http", "NP6-905")):
        bad = sum(r[col] != "200" for r in rows)
        bad_out = sum(r[col] != "200" for r in rows
                      if OUTAGE[0] <= datetime.fromisoformat(r["t"]).date() <= OUTAGE[1])
        print(f"  {name} polls without a 200: {bad}, of them {bad_out} on "
              f"{OUTAGE[0]}..{OUTAGE[1]}")

    a, da = arrivals(rows, "a_http", "a_sced",
                     lambda v: boundary5(datetime.fromisoformat(v)),
                     lambda v: boundary5(datetime.fromisoformat(v)))
    b, db = arrivals(rows, "b_http", "b_end", lambda v: datetime.fromisoformat(v))
    print(f"  dropped NP6-788: {da}")
    print(f"  dropped NP6-905: {db}")

    def clean(xs):
        return [x for x in xs if not OUTAGE[0] <= x[0].date() <= OUTAGE[1]]

    print("\nNP6-788 five-minute price, readable after its five-minute boundary")
    line("full window", [l for _, l in a])
    line("clean window (outage days out)", [l for _, l in clean(a)])
    print("\nNP6-905 15-minute settlement price, readable after its interval ends")
    line("full window", [l for _, l in b])
    line("clean window (outage days out)", [l for _, l in clean(b)])

    print("\nNP6-788 by hour of day (Central, hour the interval starts), full window")
    by = defaultdict(list)
    for c, l in a:
        by[c.hour].append(l)
    for h in range(24):
        xs = by[h]
        print(f"  {h:02d}:00  n={len(xs):>4}  median {statistics.median(xs):6.1f} s  p95 {p95(xs):6.1f} s")
    eve = [l for c, l in a if 18 <= c.hour < 22]
    rest = [l for c, l in a if not 18 <= c.hour < 22]
    line("18:00-22:00", eve)
    line("other hours", rest)

    xs = [l for _, l in a]
    print(f"\nreadable within one five-minute interval of its boundary: "
          f"{sum(x <= 300 for x in xs)} of {len(xs)} = {100 * sum(x <= 300 for x in xs) / len(xs):.1f}%")


if __name__ == "__main__":
    main()
