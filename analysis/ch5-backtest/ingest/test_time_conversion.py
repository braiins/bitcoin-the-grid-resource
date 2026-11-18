#!/usr/bin/env python3
"""Regression tests for ERCOT CPT->UTC conversion.

Guards the 2026-08 DST bug: `cpt_to_utc` used to derive the UTC offset from
ERCOT's DSTFlag/repeatHourFlag column, which marks the *duplicated* fall-back
hour rather than "DST is in effect". It is 'N' all summer, so every CDT row
was stamped UTC-6 instead of UTC-5, one hour late for ~8 months a year. That
silently misaligned rtm15/dam against rtm5 (which was always correct, since it
used the tz database).

Run: python3 analysis/ch5-backtest/ingest/test_time_conversion.py
"""

import sys
from pathlib import Path

import sqlite3

sys.path.insert(0, str(Path(__file__).parent))
from ercot_ingest import (_upsert_spp_rows, cpt_hour_ending_to_utc, cpt_to_utc,
                          init_db, sced_to_utc)

# 2025 US DST: CDT from Mar 9 to Nov 2. CST = UTC-6, CDT = UTC-5.
HOUR_CASES = [
    ("2025-01-15",  1, 1, "2025-01-15T06:00:00Z", "CST midnight"),
    ("2025-01-15", 15, 1, "2025-01-15T20:00:00Z", "CST 14:00"),
    ("2025-07-15",  1, 1, "2025-07-15T05:00:00Z", "CDT midnight"),
    ("2025-07-15", 15, 1, "2025-07-15T19:00:00Z", "CDT 14:00"),
    ("2025-07-15", 15, 3, "2025-07-15T19:30:00Z", "CDT 14:30, interval 3"),
    ("2025-03-08", 15, 1, "2025-03-08T20:00:00Z", "day before spring forward"),
    ("2025-03-10", 15, 1, "2025-03-10T19:00:00Z", "day after spring forward"),
    ("2025-11-01", 15, 1, "2025-11-01T19:00:00Z", "day before fall back"),
    ("2025-11-03", 15, 1, "2025-11-03T20:00:00Z", "day after fall back"),
    # winter/summer boundaries of a second year, to catch a hardcoded year
    ("2026-01-15", 15, 1, "2026-01-15T20:00:00Z", "CST 2026"),
    ("2026-06-15", 15, 1, "2026-06-15T19:00:00Z", "CDT 2026"),
]

EQUIV_HOUR_ENDING = [("2025-07-15", "15:00", 15), ("2025-01-15", "01:00", 1),
                     ("2025-11-03", "24:00", 24), ("2026-06-15", "20:00", 20)]

# the 15-min path must land on the same instant as the 5-min path
EQUIV_SCED = [("2025-07-15", 15, "2025-07-15 14:00:00"),
              ("2025-01-15", 15, "2025-01-15 14:00:00"),
              ("2025-11-01",  9, "2025-11-01 08:00:00")]


def main():
    fails = []
    for d, h, i, exp, note in HOUR_CASES:
        got = cpt_to_utc(d, h, i)
        if got != exp:
            fails.append(f"cpt_to_utc({d}, h{h}, i{i}) = {got}, expected {exp} [{note}]")

    # The ambiguous fall-back hour: 01:00 CPT on 2025-11-02 happens twice.
    first, repeat = cpt_to_utc("2025-11-02", 2, 1, False), cpt_to_utc("2025-11-02", 2, 1, True)
    if (first, repeat) != ("2025-11-02T06:00:00Z", "2025-11-02T07:00:00Z"):
        fails.append(f"fall-back ambiguous hour: first={first} repeat={repeat}")

    for d, he, h in EQUIV_HOUR_ENDING:
        a, b = cpt_hour_ending_to_utc(d, he), cpt_to_utc(d, h)
        if a != b:
            fails.append(f"hourEnding {d} {he} = {a} != hour {h} = {b}")

    for d, h, sced in EQUIV_SCED:
        a, b = cpt_to_utc(d, h), sced_to_utc(sced)
        if a != b:
            fails.append(f"rtm15 {d} h{h} = {a} != rtm5 {sced} = {b}")

    # The regression itself: a summer row must NOT be UTC-6.
    if cpt_to_utc("2025-07-15", 1, 1) == "2025-07-15T06:00:00Z":
        fails.append("summer row stamped UTC-6; the DST bug is back")

    # The repeated hour through the hour-ending path (the DAM layout).
    he = (cpt_hour_ending_to_utc("2025-11-02", "02:00", False),
          cpt_hour_ending_to_utc("2025-11-02", "02:00", True))
    if he != ("2025-11-02T06:00:00Z", "2025-11-02T07:00:00Z"):
        fails.append(f"fall-back hour ending 02:00: {he}")

    # The spring-forward gap does not exist and must not be invented.
    try:
        got = cpt_to_utc("2025-03-09", 3, 2)
        fails.append(f"spring-forward 02:15 CPT converted to {got}; should raise")
    except ValueError:
        pass

    # End to end through the row parser, the path the bug actually lived on:
    # an API row for a CDT afternoon carries DSTFlag=False.
    con = sqlite3.connect(":memory:")
    init_db(con)
    fields = ["deliveryDate", "deliveryHour", "deliveryInterval",
              "settlementPoint", "settlementPointType", "settlementPointPrice",
              "DSTFlag"]
    rows = [["2025-07-15", 15, 1, "LZ_WEST", "LZ", 42.0, False],
            ["2025-11-02", 2, 1, "LZ_WEST", "LZ", 40.0, False],
            ["2025-11-02", 2, 1, "LZ_WEST", "LZ", 41.0, True]]
    _upsert_spp_rows(con, rows, fields, "rtm15")
    got = con.execute("SELECT interval_start, price FROM ercot_spp "
                      "ORDER BY interval_start").fetchall()
    want = [("2025-07-15T19:00:00Z", 42.0), ("2025-11-02T06:00:00Z", 40.0),
            ("2025-11-02T07:00:00Z", 41.0)]
    if got != want:
        fails.append(f"_upsert_spp_rows stored {got}, expected {want}")

    n = len(HOUR_CASES) + 1 + len(EQUIV_HOUR_ENDING) + len(EQUIV_SCED) + 4
    if fails:
        print(f"FAILED {len(fails)}/{n}:")
        for f in fails:
            print(f"  - {f}")
        return 1
    print(f"ok: {n} time-conversion checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
