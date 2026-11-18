#!/usr/bin/env python3
"""build_polls_csv.py -- reduce the poller's raw JSONL to the committed CSV.

    python3 analysis/data/ercot_api_readability/build_polls_csv.py [--datadir DIR]

Reads poll-YYYY-MM-DD.jsonl (default: data/ next to this file, where poll.py
writes) and writes analysis/data/ercot_api_readability_polls.csv.gz, one row per
poll. It keeps only what the readability analysis needs: the poll time and, for
each of the two reports, the HTTP status and the newest interval the API
returned. Prices, the archive-listing columns and the egress checks (which carry
the measuring machine's IP address) are dropped.

Columns
  t        poll start, Central prevailing time (America/Chicago), to the second
  a_http   NP6-788-CD (five-minute LMP) status; empty if no response at all
  a_sced   newest SCED time stamp returned (Central), empty if none
  b_http   NP6-905-CD (15-minute settlement point price) status
  b_end    end of the newest 15-minute interval returned (Central), empty if none

Pure stdlib.
"""
import argparse
import csv
import glob
import gzip
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "ercot_api_readability_polls.csv.gz")
COLS = ["t", "a_http", "a_sced", "b_http", "b_end"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--datadir", default=os.path.join(HERE, "data"))
    a = ap.parse_args()
    files = sorted(glob.glob(os.path.join(a.datadir, "poll-*.jsonl")))
    if not files:
        raise SystemExit(f"no poll-*.jsonl in {a.datadir}")
    n = 0
    with gzip.open(OUT, "wt", newline="", encoding="utf-8", compresslevel=9) as g:
        w = csv.writer(g)
        w.writerow(COLS)
        for f in files:
            for line in open(f, encoding="utf-8"):
                r = json.loads(line)
                w.writerow([r.get(c, "") if r.get(c) is not None else "" for c in COLS])
                n += 1
    print(f"wrote {os.path.normpath(OUT)}: {n} polls from {len(files)} day files")


if __name__ == "__main__":
    main()
