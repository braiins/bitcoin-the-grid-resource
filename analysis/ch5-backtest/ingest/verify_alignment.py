#!/usr/bin/env python3
"""Data-quality check: are ERCOT rtm5 and rtm15 stamped on the same timeline?

The 15-min settlement point price is (approximately) the average of the three
5-min SCED prints inside its interval, so pairing them is a sharp test of
timestamp correctness. For each zone and calendar month this reports the
whole-hour shift that best aligns the two series. A correctly-ingested DB
answers **0 h everywhere**. The residual will not be zero (rtm15 carries the
RTORPA/RTORDPA adders that rtm5 lacks), so only a non-zero shift proves a
timestamp bug; the residual just guards against gross mispairing.

A non-zero shift means a CPT->UTC conversion bug (see the DST note in
ingest/ercot_ingest.py: deriving the offset from ERCOT's DSTFlag instead of
the tz database stamps every CDT row one hour late).

A whole-hour test cannot see a 5- or 10-minute slip, and the loop decides on
one series and is billed on the other, so the script also runs a SUB-INTERVAL
lag test: slide the five-minute series by -15..+15 minutes in five-minute steps
and score how well the three prints inside each settlement interval track that
interval's settlement point price. Correct stamping puts the minimum at zero
lag by a wide margin (on the committed LZ_WEST data the median gap is about
four cents at zero lag and ten to twenty times that one step either side).

Also checks the diurnal profile: in CDT, ERCOT's evening ramp peaks ~01-03Z
and the solar trough sits ~14-16Z. A series whose peak lands outside that
window, or that disagrees with its counterpart, is misaligned even if it is
internally self-consistent.

Usage (from the repo root):
  python3 analysis/ch5-backtest/ingest/verify_alignment.py
  python3 analysis/ch5-backtest/ingest/verify_alignment.py --db /path/to/other.db --detail
"""

import argparse
import os
import sqlite3
import statistics
from collections import defaultdict
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
# ingest/ -> ch5-backtest/ -> analysis/, where data/prices.db lives. (This used
# to be one ".." short and pointed at a non-existent ch5-backtest/data/.)
DEFAULT_DB = os.path.normpath(os.path.join(HERE, "..", "..", "data", "prices.db"))
FMT = "%Y-%m-%dT%H:%M:%SZ"
SHIFTS_H = (-2, -1, 0, 1, 2)
# $/MWh. The residual is NOT expected to reach zero: rtm15 is the settlement
# point price (SCED LMP + RTORPA/RTORDPA adders) while rtm5 is the bare SCED
# LMP, so months containing adder events legitimately diverge by a few dollars.
# Only a non-zero *shift* proves a timestamp bug; the residual is a guard
# against gross mispairing.
RESIDUAL_OK = 5.0


def _load(con, market, zone):
    return {int(datetime.strptime(s, FMT).replace(tzinfo=timezone.utc).timestamp()): p
            for s, p in con.execute(
                "SELECT interval_start, price FROM ercot_spp WHERE market=? "
                "AND settlement_point=?", (market, zone))}


def check_zone(con, zone, detail=False):
    p5, p15 = _load(con, "rtm5", zone), _load(con, "rtm15", zone)
    if len(p5) < 1000 or len(p15) < 1000:
        return None

    # mean of the three 5-min prints in each complete 15-min bucket
    buckets = defaultdict(list)
    for t, v in p5.items():
        buckets[t - (t % 900)].append(v)
    mean3 = {b: sum(v) / 3 for b, v in buckets.items() if len(v) == 3}

    by_month = defaultdict(list)
    for b, m in mean3.items():
        by_month[datetime.fromtimestamp(b, timezone.utc).strftime("%Y-%m")].append((b, m))

    rows = []
    for mo, items in sorted(by_month.items()):
        best = None
        for sh in SHIFTS_H:
            pairs = [(m, p15[b + sh * 3600]) for b, m in items if b + sh * 3600 in p15]
            if len(pairs) < 50:
                continue
            err = statistics.mean([abs(x - y) for x, y in pairs])
            if best is None or err < best[1]:
                best = (sh, err, len(pairs))
        if best:
            rows.append((mo, *best))
    return rows


LAGS_MIN = (-15, -10, -5, 0, 5, 10, 15)


def lag_check(con, zone, t0=None, t1=None):
    """Score rtm5 against rtm15 at sub-interval lags.

    For lag L minutes, settlement interval [b, b+15) is paired with the mean of
    the five-minute prints stamped b+L, b+L+5, b+L+10. Returns
    [(lag, n, mean |diff|, median |diff|, share within $0.05)] per lag.
    """
    p5, p15 = _load(con, "rtm5", zone), _load(con, "rtm15", zone)
    lo = min(p5) if t0 is None else t0
    hi = max(p5) if t1 is None else t1
    out = []
    for lag in LAGS_MIN:
        off = lag * 60
        diffs = []
        for b, spp in p15.items():
            if not (lo <= b < hi):
                continue
            ks = (b + off, b + off + 300, b + off + 600)
            if all(k in p5 for k in ks):
                diffs.append(abs(sum(p5[k] for k in ks) / 3 - spp))
        if diffs:
            out.append((lag, len(diffs), statistics.mean(diffs),
                        statistics.median(diffs),
                        sum(d <= 0.05 for d in diffs) / len(diffs)))
    return out


def diurnal(con, market, zone, month):
    h = defaultdict(list)
    for s, p in con.execute(
            "SELECT interval_start, price FROM ercot_spp WHERE market=? AND "
            "settlement_point=? AND interval_start>=? AND interval_start<?",
            (market, zone, f"{month}-01", f"{month}-32")):
        h[int(s[11:13])].append(p)
    if not h:
        return None
    avg = {k: sum(v) / len(v) for k, v in h.items()}
    return max(avg, key=avg.get), min(avg, key=avg.get)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--detail", action="store_true",
                    help="list every month, not just the offenders")
    args = ap.parse_args()

    if not os.path.exists(args.db):
        raise SystemExit(f"no database at {os.path.abspath(args.db)}; build it with "
                         "python3 analysis/ch5-backtest/build_prices_db.py")
    con = sqlite3.connect(f"file:{os.path.abspath(args.db)}?mode=ro", uri=True)
    zones = [r[0] for r in con.execute(
        "SELECT DISTINCT settlement_point FROM ercot_spp WHERE market='rtm5' "
        "ORDER BY settlement_point")]
    if not zones:
        raise SystemExit("no rtm5 zones in this DB, nothing to pair")

    print(f"DB: {os.path.abspath(args.db)}")
    bad_total = 0
    for z in zones:
        rows = check_zone(con, z, args.detail)
        if not rows:
            print(f"\n{z}: insufficient overlap, skipped")
            continue
        offenders = [r for r in rows if r[1] != 0 or r[2] > RESIDUAL_OK]
        bad_total += len(offenders)
        shifts = sorted({r[1] for r in rows})
        med = statistics.median([r[2] for r in rows])
        status = "OK" if not offenders else f"{len(offenders)} SUSPECT MONTH(S)"
        print(f"\n{z}: {len(rows)} months paired, shifts {shifts} h, "
              f"median residual ${med:.2f}/MWh ({status})")
        for mo, sh, err, n in (rows if args.detail else offenders):
            flag = "  <-- " if (sh != 0 or err > RESIDUAL_OK) else "      "
            print(f"  {flag}{mo}  shift {sh:+d}h  residual ${err:7.3f}  n={n}")

    # sub-interval lag test: the prints the loop decides on vs what it is billed
    rtcb = int(datetime(2025, 12, 5, 6, tzinfo=timezone.utc).timestamp())
    for z in zones:
        for label, a, b in (("whole overlap", None, None),
                            ("before RTC+B (to 2025-12-05)", None, rtcb),
                            ("after RTC+B", rtcb, None)):
            rows = lag_check(con, z, a, b)
            if not rows:
                continue
            print(f"\n{z} rtm5 vs rtm15 at sub-interval lags, {label}:")
            print("   lag   intervals   mean |diff|   median |diff|   within $0.05")
            for lag, n, mean_d, med_d, share in rows:
                print(f"  {lag:+4d}m  {n:>9,}   ${mean_d:10.3f}   ${med_d:12.3f}   "
                      f"{100 * share:9.1f}%")
            best = min(rows, key=lambda r: r[2])[0]
            ok = best == 0
            if not ok:
                bad_total += 1
            print(f"  best lag {best:+d} min [{'ok' if ok else 'MISALIGNED'}]")

    # diurnal cross-check on a CDT month
    # In CDT the evening ramp peaks ~01-03Z and the solar trough sits ~14-16Z;
    # the sharper test is that both series agree with each other per zone.
    print("\ndiurnal check (July 2025, CDT: peak 01-03Z, trough 14-16Z, "
          "and rtm5 must agree with rtm15):")
    for z in zones:
        d5, d15 = diurnal(con, "rtm5", z, "2025-07"), diurnal(con, "rtm15", z, "2025-07")
        if not (d5 and d15):
            continue
        plausible = all(1 <= d[0] <= 3 and 14 <= d[1] <= 16 for d in (d5, d15))
        agree = d5 == d15
        ok = "ok" if (plausible and agree) else ("DISAGREE" if not agree else "implausible")
        if not (plausible and agree):
            bad_total += 1
        print(f"  {z:11s} rtm5 peak {d5[0]:02d}Z trough {d5[1]:02d}Z | "
              f"rtm15 peak {d15[0]:02d}Z trough {d15[1]:02d}Z  [{ok}]")
    con.close()

    print(f"\n{'PASS: all months aligned at 0h' if not bad_total else f'{bad_total} suspect month(s) to investigate'}")
    return 1 if bad_total else 0


if __name__ == "__main__":
    raise SystemExit(main())
