#!/usr/bin/env python3
"""ch5_posting_latency.py -- how late does the loop see each five-minute price?
Chapter 5, Rule 1 ("one timing fact shapes everything here"). Run from the repo
root:

    python3 analysis/checks/ch5_posting_latency.py

Reads the committed snapshot written by
analysis/data/fetch_ercot_np6788_posting.py from ERCOT's public MIS listing of
report NP6-788-CD (reportTypeId 12300), no credentials:

  ercot_np6788_posting_census.csv   every SCED run the listing held: the SCED
      time stamp from the file name and ERCOT's PublishDate.

It measures when ERCOT POSTS each price, not when a reader outside ERCOT can
read it. A live probe of the listing that used to be read here timed a CDN
cache in front of the listing, not ERCOT, and was withdrawn on 2026-09-25 (see
the fetcher's docstring); nothing here measures readability.

Definitions.
  boundary   the five-minute clock boundary at or before the SCED time stamp.
             Protocol 6.3.2(2) has ERCOT post each price "with the time stamp
             the prices are effective", and the repo's own alignment test
             (analysis/ch5-backtest/ingest/verify_alignment.py) finds the three
             prints stamped b, b+5, b+10 averaging to the settlement price of
             [b, b+15) at zero lag. So the boundary is where the interval the
             price belongs to STARTS: a print is in force before anyone can
             read it.
  on-cycle   the first SCED run in each five-minute window. Later runs in the
             same window are ERCOT's off-cycle reruns, reported separately.
  SCED time stamps are Central prevailing time; each is put on UTC with the
  offset of its own PublishDate (published 2 to 12 s after the stamp), so the
  autumn repeated hour needs no guessing.
Percentiles: p50 is the median; p95 is nearest-rank (the ceil(0.95 n)-th
smallest value).

Pure stdlib.
"""
import csv
import math
import os
import statistics
from collections import defaultdict
from datetime import datetime, timedelta, timezone

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CENSUS = os.path.join(ROOT, "analysis", "data", "ercot_np6788_posting_census.csv")


def p95(xs):
    s = sorted(xs)
    return s[math.ceil(0.95 * len(s)) - 1]


def summary(label, xs, unit="s"):
    print(f"  {label:<46} n={len(xs):>5}  median {statistics.median(xs):6.1f} {unit}  "
          f"p95 {p95(xs):6.1f} {unit}  min {min(xs):6.1f}  max {max(xs):6.1f}")


def stamp_utc(sced_cpt, publish_date):
    """SCED stamp (naive Central) -> aware UTC, via the PublishDate's offset."""
    published = datetime.fromisoformat(publish_date)
    local = datetime.strptime(sced_cpt, "%Y-%m-%dT%H:%M:%S")
    stamp = local.replace(tzinfo=published.tzinfo)
    lag = (published - stamp).total_seconds()
    if not 0 <= lag <= 600:  # a run straddling a DST change: the other offset
        for hours in (-1, 1):
            alt = stamp + timedelta(hours=hours)
            if 0 <= (published - alt).total_seconds() <= 600:
                stamp = alt
                break
        else:
            raise SystemExit(f"cannot place {sced_cpt} against {publish_date}")
    return stamp.astimezone(timezone.utc), published.astimezone(timezone.utc)


def floor5(t):
    return t.replace(second=0, microsecond=0) - timedelta(minutes=t.minute % 5)



def main():
    with open(CENSUS, newline="") as fh:
        census = list(csv.DictReader(fh))
    runs = []
    for row in census:
        stamp, published = stamp_utc(row["sced_timestamp_cpt"], row["publish_date"])
        runs.append((floor5(stamp), stamp, published))
    by_window = defaultdict(list)
    for r in runs:
        by_window[r[0]].append(r)
    on, off = [], []
    for window, rs in by_window.items():
        rs.sort(key=lambda r: r[1])
        on.append(rs[0])
        off.extend(rs[1:])
    windows = sorted(by_window)
    expected = int((windows[-1] - windows[0]).total_seconds() // 300) + 1
    central = [w.astimezone(datetime.fromisoformat(census[0]["publish_date"]).tzinfo) for w in (windows[0], windows[-1])]

    print("NP6-788 posting census (ERCOT MIS listing, reportTypeId 12300)")
    print(f"  {len(census):,} SCED runs, {len(windows):,} five-minute windows "
          f"({expected - len(windows)} missing), {windows[0]:%Y-%m-%d %H:%M} to {windows[-1]:%Y-%m-%d %H:%M} UTC "
          f"({central[0]:%Y-%m-%d %H:%M} to {central[1]:%Y-%m-%d %H:%M} Central), "
          f"{(windows[-1] - windows[0]).total_seconds() / 86400:.1f} days")
    print(f"  on-cycle runs {len(on):,}; off-cycle reruns {len(off)} in {sum(len(v) > 1 for v in by_window.values())} windows")
    summary("on-cycle: SCED stamp after the boundary", [(s - b).total_seconds() for b, s, p in on])
    summary("on-cycle: posted after the SCED stamp", [(p - s).total_seconds() for b, s, p in on])
    posted = [(p - b).total_seconds() for b, s, p in on]
    summary("on-cycle: POSTED after the boundary", posted)
    print(f"  share of on-cycle runs posted within 30 s of the boundary: "
          f"{sum(x <= 30 for x in posted) / len(posted):.1%}")
    if off:
        summary("off-cycle: SCED stamp after the boundary", [(s - b).total_seconds() for b, s, p in off])


if __name__ == "__main__":
    main()
