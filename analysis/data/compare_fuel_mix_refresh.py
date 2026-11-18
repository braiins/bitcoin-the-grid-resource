#!/usr/bin/env python3
"""compare_fuel_mix_refresh.py -- hold a refreshed fuel-mix history against the
committed one before it replaces it. Run from the repo root:

    python3 analysis/data/compare_fuel_mix_refresh.py NEW.csv.gz
        [--old analysis/data/ercot_fuel_mix_15min_2019on.csv.gz] [--edge YYYY-MM-DD]

NEW is a rebuild written by fetch_ercot_fuel_mix.py --history --out NEW. The
step is part of the runbook "Refreshing the fuel-mix series" in
analysis/data/README.md. Standard library only.

Three parts of the series, split at the edge (default: the first day the
committed file still carries at INITIAL settlement, the earliest row a
refresh may legitimately revise):

  before the edge   every row must be the same text in both files, or the
                    run exits 1: those months were FINAL and must not move;
  edge to old end   the months ERCOT revises from INITIAL to FINAL: per month
                    the settlement types before and after, how many rows
                    changed, the MW revision (min, mean, max), and the
                    monthly peak before and after, with its label;
  after old end     the months the refresh adds: rows, settlement type, peak.

MW is the chapter 8 demand proxy of analysis/checks/ch8_demand.R: four times
the interval's summed fuel MWh, WSL included. A peak's label is the interval's
END in Central prevailing time, 24:00 at midnight, as the workbook and
ch8_4cp_peaks.R print it. For each peak the run also prints the runner-up
interval (any day) and the best interval on another day, with the margins, so
a label that a small revision could flip is visible before it is printed.
"""

import argparse
import csv
import gzip
import sys
from collections import defaultdict
from datetime import datetime, timedelta

COMMITTED = "analysis/data/ercot_fuel_mix_15min_2019on.csv.gz"


def read(path):
    with gzip.open(path, "rt", encoding="utf-8", newline="") as fh:
        lines = fh.read().splitlines()
    header = lines[0]
    rows = {}
    for line in lines[1:]:
        r = next(csv.reader([line]))
        rows[(r[0], r[1])] = (line, r[2], 4 * sum(float(x) for x in r[3:]))
    return header, rows


def label(start):
    end = datetime.fromisoformat(start) + timedelta(minutes=15)
    return "24:00" if end.strftime("%H:%M") == "00:00" else end.strftime("%H:%M")


def peak_line(rows, keys):
    ks = sorted(keys, key=lambda k: -rows[k][2])
    top, second = ks[0], ks[1]
    other_day = next(k for k in ks if k[0][:10] != top[0][:10])
    mw = rows[top][2]
    return (f"{top[0][:10]} ending {label(top[0])} {mw:,.0f} MW; runner-up "
            f"{second[0][:10]} ending {label(second[0])} ({mw - rows[second][2]:,.0f} MW behind); "
            f"best other day {other_day[0][:10]} ending {label(other_day[0])} "
            f"({mw - rows[other_day][2]:,.0f} MW behind)"), (top[0][:10], label(top[0]))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("new")
    p.add_argument("--old", default=COMMITTED)
    p.add_argument("--edge", help="first day a refresh may revise (default: first INITIAL day of --old)")
    a = p.parse_args()

    old_h, old = read(a.old)
    new_h, new = read(a.new)
    print(f"old {a.old}: {len(old):,} rows, {min(old)[0][:10]} to {max(old)[0][:10]}")
    print(f"new {a.new}: {len(new):,} rows, {min(new)[0][:10]} to {max(new)[0][:10]}")
    with open(a.old, "rb") as f1, open(a.new, "rb") as f2:
        if f1.read() == f2.read():
            print("the two files are byte-identical: nothing to refresh")
            return 0
    bad = 0
    if old_h != new_h:
        print(f"HEADER DIFFERS:\n  old {old_h}\n  new {new_h}")
        bad += 1

    initial = sorted(k[0][:10] for k, v in old.items() if v[1] != "FINAL")
    old_end = max(old)[0][:10]
    edge = a.edge or (initial[0] if initial else
                      (datetime.fromisoformat(old_end) + timedelta(days=1)).strftime("%Y-%m-%d"))
    print(f"edge {edge}: rows before it must not change\n")

    # 1. before the edge
    before = [k for k in old if k[0][:10] < edge]
    missing = [k for k in before if k not in new]
    changed = [k for k in before if k in new and new[k][0] != old[k][0]]
    extra = [k for k in new if k[0][:10] < edge and k not in old]
    print(f"before {edge}: {len(before):,} committed rows; identical {len(before) - len(missing) - len(changed):,}, "
          f"changed {len(changed)}, missing from new {len(missing)}, new rows {len(extra)}")
    for k in (changed + missing + extra)[:10]:
        print(f"  DIFFERS {k[0]} {k[1]}\n    old {old.get(k, ('(none)',))[0]}\n    new {new.get(k, ('(none)',))[0]}")
    bad += len(changed) + len(missing) + len(extra)

    # 2. edge to the old end: the months ERCOT revises
    by_month = defaultdict(list)
    for k in old:
        if k[0][:10] >= edge:
            by_month[k[0][:7]].append(k)
    print(f"\n{edge} to {old_end}: revisions")
    for m in sorted(by_month):
        ks = by_month[m]
        gone = [k for k in ks if k not in new]
        if gone:
            print(f"  {m}: {len(gone)} committed rows MISSING from new")
            bad += len(gone)
            continue
        types_old = sorted({old[k][1] for k in ks})
        types_new = sorted({new[k][1] for k in ks})
        diffs = [new[k][2] - old[k][2] for k in ks]
        nchg = sum(new[k][0] != old[k][0] for k in ks)
        line_o, lab_o = peak_line(old, ks)
        line_n, lab_n = peak_line(new, ks)
        print(f"  {m}: {len(ks)} rows, settlement {'/'.join(types_old)} -> {'/'.join(types_new)}; "
              f"rows changed {nchg}; MW revision min {min(diffs):+.1f}, mean {sum(diffs) / len(diffs):+.1f}, "
              f"max {max(diffs):+.1f}")
        print(f"    peak before: {line_o}")
        print(f"    peak after:  {line_n}")
        print(f"    peak label {'UNCHANGED' if lab_o == lab_n else 'CHANGED'}")

    # 3. months the refresh adds
    added = defaultdict(list)
    for k in new:
        if k[0][:10] > old_end:
            added[k[0][:7]].append(k)
    print(f"\nafter {old_end}: {len(added)} month(s) added")
    for m in sorted(added):
        ks = added[m]
        line, _ = peak_line(new, ks)
        print(f"  {m}: {len(ks)} rows, settlement {'/'.join(sorted({new[k][1] for k in ks}))}; peak {line}")

    print(f"\n{'FAIL' if bad else 'OK'}: {bad} problem row(s) at or before the edge")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
