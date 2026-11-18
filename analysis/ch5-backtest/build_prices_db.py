#!/usr/bin/env python3
"""Reconstitute analysis/data/prices.db from the committed ERCOT archives.

Run from the repo root:  python3 analysis/ch5-backtest/build_prices_db.py

The database is gitignored; these three files are the committed artifact, and
all three are ERCOT market facts:

  rtm15  analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz
         ERCOT MIS report 13061, 15-minute Real-Time Market settlement point
         prices, eight load zones, 2021 to date. Stamped in Central
         PREVAILING time with ERCOT's repeated-hour flag.
  dam    analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz
         ERCOT MIS report 13060, hourly Day-Ahead Market settlement point
         prices, same zones and stamping.
  rtm5   analysis/data/ercot_spp_rtm5_lzwest.csv.gz
         ERCOT NP6-788 five-minute prices, LZ_WEST, stamped in UTC.
  (both 2021on files are built by analysis/data/fetch_ercot_rtm15_spp_history.py,
  credential-free)

Every row is stored in UTC. The two MIS files are converted through the tz
database (db.cpt_local_to_utc), with the repeated-hour flag resolving the
duplicated autumn hour; no fixed offset is applied anywhere.

This script used to load analysis/data/ercot_spp_dam_rtm15_8zones.csv.gz, a
legacy ingest cache that stamps Central time as a fixed UTC-6 (every
daylight-time interval an hour late), drops the spring-forward intervals, ends
2026-04-21, and carries at least one corrupted row: LZ_WEST rtm15
2025-06-30T21:30:00Z = $1,629.89, where ERCOT's settlement archive has $34.17.
It is kept in the repo as superseded and is read by nothing that prints a
number.

Pure stdlib. Inserts are plain INSERTs, so any two rows landing on the same
UTC instant (the signature of a time-conversion bug) abort the build instead
of silently overwriting each other.
"""
import csv
import gzip
import os
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from db import DB, cpt_local_to_utc, get_conn, init_db  # noqa: E402

DATA = os.path.normpath(os.path.join(HERE, "..", "data"))
RTM15 = os.path.join(DATA, "ercot_rtm15_spp_loadzones_2021on.csv.gz")
DAM = os.path.join(DATA, "ercot_dam_spp_loadzones_2021on.csv.gz")
RTM5 = os.path.join(DATA, "ercot_spp_rtm5_lzwest.csv.gz")


def mis_rows(path, market, time_col):
    """Rows of a MIS 13060/13061 export as (market, zone, utc, price)."""
    with gzip.open(path, "rt", newline="") as f:
        for r in csv.DictReader(f):
            local = datetime.strptime(r[time_col], "%Y-%m-%dT%H:%M:%S")
            utc = cpt_local_to_utc(local, r["dst_repeated_flag"] == "Y")
            yield (market, r["settlement_point"], utc, float(r["price"]))


def utc_rows(path):
    """Rows of the UTC-stamped five-minute export, as stored."""
    with gzip.open(path, "rt", newline="") as f:
        for r in csv.DictReader(f):
            if not r["interval_start"].endswith("Z"):
                raise SystemExit(f"{os.path.basename(path)}: expected UTC stamps, "
                                 f"got {r['interval_start']!r}")
            yield (r["market"], r["settlement_point"], r["interval_start"],
                   float(r["price"]))


def main() -> None:
    if os.path.exists(DB):
        os.remove(DB)
    con = get_conn(DB)
    init_db(con)
    sources = [
        (os.path.basename(RTM15), mis_rows(RTM15, "rtm15", "interval_start")),
        (os.path.basename(DAM), mis_rows(DAM, "dam", "hour_start")),
        (os.path.basename(RTM5), utc_rows(RTM5)),
    ]
    for name, rows in sources:
        rows = list(rows)
        con.executemany("INSERT INTO ercot_spp VALUES (?,?,?,?)", rows)
        con.commit()
        print(f"loaded {len(rows):>9,} rows from {name}")
    print("\nmarket  zones  first interval (UTC)   last interval (UTC)       rows")
    for mkt, nz, t0, t1, n in con.execute(
            "SELECT market, COUNT(DISTINCT settlement_point), MIN(interval_start),"
            " MAX(interval_start), COUNT(*) FROM ercot_spp GROUP BY market "
            "ORDER BY market"):
        print(f"{mkt:<7} {nz:>5}  {t0}   {t1}  {n:>9,}")
    n = con.execute("SELECT COUNT(*) FROM ercot_spp").fetchone()[0]
    con.close()
    print(f"\ndone: {n:,} rows in {DB} ({os.path.getsize(DB) / 1e6:.0f} MB)")


if __name__ == "__main__":
    main()
