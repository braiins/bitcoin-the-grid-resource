#!/usr/bin/env python3
"""Run this FIRST. Verifies everything a long measurement run depends on.

Exit code 0 = safe to start polling. Non-zero = fix what it reports first.
"""
from __future__ import annotations

import email.utils
import sys
import time
from datetime import datetime, timezone

from datetime import timedelta

from common import (CT, Session, ERCOTError, boundary_5min, egress, load_env,
                    now_ct, rows_of, _request)

FAIL, WARN = [], []


def check(label, ok, detail="", fatal=True):
    mark = "PASS" if ok else ("FAIL" if fatal else "WARN")
    print(f"  [{mark}] {label}" + (f" -- {detail}" if detail else ""))
    if not ok:
        (FAIL if fatal else WARN).append(label)
    return ok


def main() -> int:
    print("=" * 74)
    print("ERCOT API readability poller -- preflight")
    print("=" * 74)

    print("\n1. Runtime")
    v = sys.version_info
    check(f"Python {v.major}.{v.minor}.{v.micro}", v >= (3, 9),
          "need 3.9+ for zoneinfo")
    try:
        _ = now_ct()
        check("America/Chicago tzdata available", True, f"CT now = {now_ct():%Y-%m-%d %H:%M:%S}")
    except Exception as e:
        check("America/Chicago tzdata available", False, str(e))

    print("\n2. Clock accuracy  (a wrong local clock silently corrupts every latency number)")
    try:
        st, hdrs, _ = _request("https://api.ercot.com/api/public-reports", timeout=20)
        server = email.utils.parsedate_to_datetime(hdrs["Date"])
        skew = (datetime.now(timezone.utc) - server).total_seconds()
        check(f"clock skew vs ERCOT = {skew:+.1f}s", abs(skew) <= 5,
              "must be within 5s; enable NTP if this fails", fatal=abs(skew) > 15)
    except Exception as e:
        check("clock skew measurable", False, str(e), fatal=False)

    print("\n3. Egress  (ERCOT rejects non-US IP addresses)")
    g = egress()
    if "error" in g:
        check("egress geolocation", False, g["error"], fatal=False)
    else:
        check(f"egress {g['ip']} / {g.get('country')} / {g.get('city')}",
              g.get("country") == "US",
              "must be US -- connect the US VPN before starting" if g.get("country") != "US"
              else g.get("org", ""))

    print("\n4. Credentials and auth")
    try:
        cfg = load_env()
        check("credentials present", True, "from .env / environment")
    except ERCOTError as e:
        check("credentials present", False, str(e).splitlines()[0])
        print("\n" + "=" * 74)
        print("PREFLIGHT FAILED -- cannot continue without credentials.")
        return 1
    s = Session(cfg, "direct")
    try:
        t0 = time.time()
        s.token()
        check("B2C token mint", True, f"{time.time()-t0:.2f}s  (Microsoft-hosted; works from any country)")
    except ERCOTError as e:
        check("B2C token mint", False, str(e)[:160])

    print("\n5. Endpoint reachability  (200 here means the geo-filter let us through)")
    n = now_ct()
    st, j, rtt, note = s.get("/np6-788-cd/lmp_node_zone_hub", {
        "size": 5, "SCEDTimestampFrom": (boundary_5min(n).replace(
            minute=0, second=0)).isoformat()})
    ok = st == 200 and j is not None
    detail = f"{rtt:.2f}s"
    if ok:
        cols, data = rows_of(j)
        if data:
            newest = max(r[cols.index("SCEDTimestamp")] for r in data)
            age = (n - datetime.fromisoformat(newest)).total_seconds()
            detail += f", newest SCED {newest} ({age:.0f}s old)"
    check(f"NP6-788-CD queryable  HTTP {st}", ok, detail or note)

    today = n.date().isoformat()
    st2, j2, rtt2, note2 = s.get("/np6-905-cd/spp_node_zone_hub", {
        "size": 5, "deliveryDateFrom": today, "deliveryDateTo": today,
        "settlementPoint": "HB_NORTH"})
    check(f"NP6-905-CD queryable  HTTP {st2}", st2 == 200 and j2 is not None,
          f"{rtt2:.2f}s" or note2)

    st3, j3, rtt3, note3 = s.get("/archive/NP6-788-CD", {"size": 2})
    check(f"archive listing      HTTP {st3}", st3 == 200 and j3 is not None,
          f"{rtt3:.2f}s" or note3, fatal=False)

    print("\n6. Query-shape guards  (these cost real seconds in a 5-minute loop)")
    slow = {"settlementPoint": "HB_NORTH", "size": 100}
    _, j4, rtt_slow, _ = s.get("/np6-788-cd/lmp_node_zone_hub", slow)
    tot_slow = j4.get("_meta", {}).get("totalRecords") if j4 else "?"
    check("settlementPoint filter WITHOUT a time bound is slow", rtt_slow > 3,
          f"{rtt_slow:.1f}s over {tot_slow} matching rows -- never ship this shape", fatal=False)

    since10 = (n - timedelta(minutes=10)).isoformat(timespec="seconds")
    _, j5, rtt_ok, _ = s.get("/np6-788-cd/lmp_node_zone_hub",
                             {"size": 2500, "SCEDTimestampFrom": since10})
    meta = j5.get("_meta", {}) if j5 else {}
    pages = meta.get("totalPages", 0)
    pts = 0
    if j5:
        c5, d5 = rows_of(j5)
        pts = len({r[c5.index("settlementPoint")] for r in d5}) if d5 else 0
    check("recommended shape: no point filter + 10-min bound + size=2500",
          pages == 1,
          f"{rtt_ok:.2f}s, {meta.get('totalRecords')} rows, {pts} settlement points, "
          f"totalPages={pages}" + ("" if pages == 1 else "  -- RAISE size, this would paginate"),
          fatal=False)

    print("\n" + "=" * 74)
    if FAIL:
        print(f"PREFLIGHT FAILED -- {len(FAIL)} blocking issue(s): {', '.join(FAIL)}")
        return 1
    print("PREFLIGHT PASSED" + (f" ({len(WARN)} warning(s): {', '.join(WARN)})" if WARN else ""))
    print("\nStart the run with:   python3 poll.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
