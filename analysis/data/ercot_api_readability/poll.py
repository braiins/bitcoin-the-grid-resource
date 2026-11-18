#!/usr/bin/env python3
"""Long-running ERCOT API readability poller (chapter 5's readability figures).

Needs a free ERCOT API Explorer account (.env, see .env.example) and a
connection from inside the United States; ERCOT refuses other countries. Run
preflight.py first. No printed number depends on running this: its output for
2026-09-25..10-05 is committed, reduced by build_polls_csv.py, as
analysis/data/ercot_api_readability_polls.csv.gz.

Records, for every poll, the newest interval readable from each report, so the
analyzer can bracket each interval's arrival between two consecutive polls.
Resolution equals the poll period (default 20s).

  python3 poll.py                    # run until Ctrl-C
  python3 poll.py --days 7           # run for 7 days then stop
  python3 poll.py --period 15        # tighter resolution (watch the rate limit)
  python3 poll.py --no-archive       # skip the archive listing (2 requests/poll)

Safe to stop and restart: output is appended, one file per Central-time day.
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from datetime import datetime, timedelta

from common import (CT, ROOT, Session, boundary_5min, egress, iv_end_905,
                    load_env, now_ct, rows_of)

SP = "HB_NORTH"          # one settlement point is enough; latency is point-independent
STOP = False


def _sigterm(*_):
    global STOP
    STOP = True
    print("\n[poller] stop requested, finishing current poll...", flush=True)


def outfile(outdir: str, ct: datetime) -> str:
    return os.path.join(outdir, f"poll-{ct:%Y-%m-%d}.jsonl")


def poll_once(s: Session, want_archive: bool) -> dict:
    n = now_ct()
    rec = {"t": n.isoformat(timespec="seconds")}

    # --- NP6-788-CD, 5-minute SCED LMP. Always time-bounded: unbounded scans 200k+ rows.
    st, j, rtt, note = s.get("/np6-788-cd/lmp_node_zone_hub", {
        "settlementPoint": SP, "size": 100,
        "SCEDTimestampFrom": (n - timedelta(minutes=40)).isoformat(timespec="seconds")})
    rec["a_http"], rec["a_rtt"] = st, round(rtt, 3)
    if note:
        rec["a_note"] = note[:160]
    if st == 200 and j:
        cols, data = rows_of(j)
        if data:
            i = cols.index("SCEDTimestamp")
            best = max(data, key=lambda r: r[i])
            rec["a_sced"] = best[i]
            rec["a_lmp"] = best[cols.index("LMP")]

    # --- NP6-905-CD, 15-minute settlement SPP. Bounded to today (+ yesterday near midnight).
    today = n.date()
    params = {"settlementPoint": SP, "size": 400,
              "deliveryDateFrom": (today - timedelta(days=1)).isoformat()
              if n.hour == 0 else today.isoformat(),
              "deliveryDateTo": today.isoformat()}
    st, j, rtt, note = s.get("/np6-905-cd/spp_node_zone_hub", params)
    rec["b_http"], rec["b_rtt"] = st, round(rtt, 3)
    if note:
        rec["b_note"] = note[:160]
    if st == 200 and j:
        cols, data = rows_of(j)
        if data:
            di, hi, ii = (cols.index("deliveryDate"), cols.index("deliveryHour"),
                          cols.index("deliveryInterval"))
            best = max(data, key=lambda r: (r[di], r[hi], r[ii]))
            rec["b_iv"] = f"{best[di]} HE{best[hi]} iv{best[ii]}"
            rec["b_end"] = iv_end_905(best[di], best[hi], best[ii]).isoformat(timespec="seconds")
            rec["b_spp"] = best[cols.index("settlementPointPrice")]
            rec["b_maxiv"] = max(r[ii] for r in data)   # 4 => still 15-min settlement

    # --- archive listing: carries postDatetime, so we can split ERCOT-posting from
    #     MIS-to-API visibility. Optional; costs one request per poll.
    if want_archive:
        st, j, rtt, note = s.get("/archive/NP6-788-CD", {"size": 2})
        rec["c_http"], rec["c_rtt"] = st, round(rtt, 3)
        if st == 200 and j:
            arch = j.get("archives", [])
            if arch:
                newest = max(arch, key=lambda a: a["postDatetime"])
                rec["c_doc"] = newest["friendlyName"]
                rec["c_post"] = newest["postDatetime"]
    return rec


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=float, default=None, help="stop after N days")
    ap.add_argument("--period", type=int, default=20, help="seconds between polls")
    ap.add_argument("--outdir", default=os.path.join(ROOT, "data"))
    ap.add_argument("--no-archive", action="store_true")
    a = ap.parse_args()

    signal.signal(signal.SIGTERM, _sigterm)
    signal.signal(signal.SIGINT, _sigterm)
    os.makedirs(a.outdir, exist_ok=True)

    s = Session(load_env())
    want_archive = not a.no_archive
    per_poll = 3 if want_archive else 2
    print(f"[poller] period={a.period}s requests/poll={per_poll} "
          f"({60 // a.period * per_poll}/min vs 30/min limit)")
    print(f"[poller] writing to {a.outdir}/poll-YYYY-MM-DD.jsonl  (Central time days)")

    g = egress()
    print(f"[poller] egress {g.get('ip')} {g.get('country')} {g.get('city')} {g.get('org','')}")
    if g.get("country") not in (None, "US"):
        print("[poller] REFUSING TO START: egress is not US, every call will 403. "
              "Connect the US VPN and re-run preflight.py.")
        return 1

    deadline = time.time() + a.days * 86400 if a.days else None
    n_polls = 0
    t_start = time.time()

    while not STOP and (deadline is None or time.time() < deadline):
        t_loop = time.time()
        try:
            rec = poll_once(s, want_archive)
        except Exception as e:                       # never let one bad poll kill the run
            rec = {"t": now_ct().isoformat(timespec="seconds"),
                   "fatal": f"{type(e).__name__}: {e}"}
        n_polls += 1

        # every ~15 min: re-check egress, so a VPN flip mid-run is visible in the data
        if n_polls % max(1, (900 // a.period)) == 0:
            rec["egress"] = egress()
            rec["counters"] = dict(s.counters)

        with open(outfile(a.outdir, now_ct()), "a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\n")

        if n_polls % max(1, (3600 // a.period)) == 0:
            hrs = (time.time() - t_start) / 3600
            print(f"[poller] {n_polls} polls / {hrs:.1f}h  newest 788={rec.get('a_sced','-')} "
                  f"905={rec.get('b_iv','-')}  counters={s.counters}", flush=True)

        time.sleep(max(0, a.period - (time.time() - t_loop)))

    print(f"[poller] stopped after {n_polls} polls / "
          f"{(time.time()-t_start)/3600:.2f}h. counters={s.counters}")
    print("[poller] then: python3 build_polls_csv.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
