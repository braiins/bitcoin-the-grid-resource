#!/usr/bin/env python3
"""fetch_ercot_np6788_posting.py -- when does ERCOT post each five-minute price?
Credential-free. Run from the repo root.

Report: NP6-788-CD "LMPs by Resource Nodes, Load Zones and Trading Hubs"
(MIS reportTypeId 12300), one small zip per SCED run. Its public document
listing (the same IceDocListJsonWS endpoint fetch_ercot_rtm15_spp_history.py
reads) gives, for every file it still holds, two times:

  * the SCED time stamp, in the file name (LMPSROSNODENP6788_YYYYMMDD_HHMMSS),
    Central prevailing time. Protocol 6.3.2(2) has ERCOT post these prices
    "with the time stamp the prices are effective", so this is the moment the
    price takes force;
  * PublishDate, with its UTC offset, the moment ERCOT posted the file.

The listing is a rolling window of about five days, so one run captures about
1,500 SCED runs.

  python3 analysis/data/fetch_ercot_np6788_posting.py
      Read the listing once and merge every csv-format document into
      analysis/data/ercot_np6788_posting_census.csv (keyed on DocID, so rerunning
      it every few days grows the census instead of replacing it).
      Columns: doc_id, friendly_name, sced_timestamp_cpt, publish_date,
      fetched_utc.

What this does NOT measure: when a posted file becomes readable to someone
outside ERCOT. An earlier version had a --probe mode that polled the bare
listing URL live and timed when each new file first appeared in it. That URL
is answered from a CDN cache (cache-control max-age=60), so the probe timed
the cache, not ERCOT; ERCOT's own report page asks for the listing with a
cache-busting query, which goes past that cache. The probe mode and its
snapshot were withdrawn on 2026-09-25 and nothing in the book rests on them.
Readability is not measured anywhere in this repository.

The reading of the census is analysis/checks/ch5_posting_latency.py.
"""

import argparse
import csv
import json
import os
import re
import sys
import time
import urllib.request
from datetime import datetime, timezone

REPORT_TYPE_ID = 12300
LIST_URL = f"https://www.ercot.com/misapp/servlets/IceDocListJsonWS?reportTypeId={REPORT_TYPE_ID}"
CENSUS = "analysis/data/ercot_np6788_posting_census.csv"
CENSUS_COLS = ["doc_id", "friendly_name", "sced_timestamp_cpt", "publish_date", "fetched_utc"]
NAME = re.compile(r"^LMPSROSNODENP6788_(\d{8})_(\d{6})_csv$")
UA = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 "
        "(KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    )
}


def utc_iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")[:-4] + "Z"


def get_listing(timeout=60):
    """One listing request. Returns (sent, headers_at, csv_docs, http_date)."""
    sent = time.time()
    with urllib.request.urlopen(urllib.request.Request(LIST_URL, headers=UA), timeout=timeout) as r:
        headers_at = time.time()
        http_date = r.headers.get("Date", "")
        body = r.read()
    docs = []
    for entry in json.loads(body)["ListDocsByRptTypeRes"]["DocumentList"]:
        doc = entry["Document"]
        m = NAME.match(doc.get("FriendlyName", ""))
        if not m:  # the xml twin of every file, and anything unexpected
            continue
        stamp = datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S")
        docs.append({
            "doc_id": doc["DocID"],
            "friendly_name": doc["FriendlyName"],
            "sced_timestamp_cpt": stamp.strftime("%Y-%m-%dT%H:%M:%S"),
            "publish_date": doc["PublishDate"],
        })
    return sent, headers_at, docs, http_date


def read_rows(path):
    if not os.path.exists(path):
        return {}
    with open(path, newline="") as fh:
        return {row["doc_id"]: row for row in csv.DictReader(fh)}


def write_rows(path, cols, rows):
    ordered = sorted(rows.values(), key=lambda r: (r["publish_date"][:19], r["doc_id"]))
    with open(path, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=cols)
        writer.writeheader()
        writer.writerows(ordered)
    return ordered


def census():
    for attempt in range(1, 6):
        try:
            _, headers_at, docs, _ = get_listing(timeout=120)
            break
        except Exception as exc:  # transient network / ERCOT throttling
            print(f"  listing attempt {attempt} failed ({exc})", file=sys.stderr)
            time.sleep(10)
    else:
        raise SystemExit("gave up on the listing")
    rows = read_rows(CENSUS)
    before = len(rows)
    fetched = utc_iso(headers_at)
    for d in docs:
        if d["doc_id"] not in rows:
            rows[d["doc_id"]] = dict(d, fetched_utc=fetched)
    ordered = write_rows(CENSUS, CENSUS_COLS, rows)
    print(f"Listing holds {len(docs):,} csv documents, "
          f"{min(d['sced_timestamp_cpt'] for d in docs)} to {max(d['sced_timestamp_cpt'] for d in docs)} Central")
    print(f"Wrote {CENSUS}: {len(ordered):,} documents ({len(ordered) - before:,} new), "
          f"{ordered[0]['sced_timestamp_cpt']} to {ordered[-1]['sced_timestamp_cpt']} Central")


def main():
    if not os.path.isdir("analysis/data"):
        raise SystemExit("run me from the repo root")
    argparse.ArgumentParser(description=__doc__.split("\n")[0]).parse_args()
    census()


if __name__ == "__main__":
    main()
