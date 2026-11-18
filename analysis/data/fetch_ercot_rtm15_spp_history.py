#!/usr/bin/env python3
"""fetch_ercot_rtm15_spp_history.py -- ERCOT settlement point prices for the
eight load zones, 2021 to date, real-time AND day-ahead, straight from ERCOT's
own public archive. Run from the repo root:

    python3 analysis/data/fetch_ercot_rtm15_spp_history.py
    python3 analysis/data/fetch_ercot_rtm15_spp_history.py --hubs

Outputs (all stamped in Central PREVAILING time, ISO-8601, no offset):
    analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz
        settlement_point, interval_start, dst_repeated_flag, price
    analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz
        settlement_point, hour_start, dst_repeated_flag, price
    analysis/data/ercot_rtm15_spp_hubs_2021on.csv.gz      (--hubs only)
        settlement_point, interval_start, dst_repeated_flag, price

--hubs writes ONLY the third file and leaves the two load-zone files alone:
the same real-time report (13061) also carries the trading hubs, and chapter 6
measures basis, a load zone's price against the hub a block settles at, on
HB_NORTH and HB_WEST. The hub file is pinned to end where the committed
load-zone file ends (HUB_END below), so the two join interval for interval;
move HUB_END when the load-zone file is refetched.

Sources: ERCOT Market Information System reports "Historical RTM Load Zone and
Hub Prices" (reportTypeId 13061) and "Historical DAM Load Zone and Hub Prices"
(13060), one ZIP per calendar year, each containing a workbook with twelve
monthly sheets. No account, no API key, no credentials: these are public files.
The document list is queried live rather than hard-coding document ids, so the
script keeps working as ERCOT reposts the current year.

The workbook's native shape is Delivery Date + Delivery Hour (1-24,
hour-ENDING) + Delivery Interval (1-4). Interval i of hour h begins at
(h-1) hours + (i-1) * 15 minutes, so hour 1 interval 1 starts at 00:00.
The Repeated Hour Flag marks the second pass through the duplicated hour on
the autumn daylight-saving change; it is carried through rather than resolved.

CAREFUL: ERCOT lists every load zone TWICE, under Settlement Point Type "LZ"
and again under "LZEW" (energy weighted). They are not the same series -- in
August 2023 they agreed in only 61% of intervals and differed by up to $7.98 --
and a load settles at the plain "LZ" price, so that is the one kept here.
Taking both silently doubles the row count and quietly mixes two definitions.
"""

import csv
import gzip
import io
import json
import os
import re
import sys
import urllib.request
import zipfile
from datetime import datetime, timedelta

import openpyxl

FIRST_YEAR = 2021
LIST_URL = "https://www.ercot.com/misapp/servlets/IceDocListJsonWS?reportTypeId={}"
DOWNLOAD_URL = "https://www.ercot.com/misdownload/servlets/mirDownload?doclookupId={}"
MARKETS = {
    # key: (reportTypeId, filename stem in the archive, output path, time column)
    "rtm15": (13061, "RTMLZHBSPP",
              "analysis/data/ercot_rtm15_spp_loadzones_2021on.csv.gz", "interval_start"),
    "dam": (13060, "DAMLZHBSPP",
            "analysis/data/ercot_dam_spp_loadzones_2021on.csv.gz", "hour_start"),
}
# --hubs: the two hubs chapter 6's basis check reads, and the last interval of
# the committed load-zone file (ercot_rtm15_spp_loadzones_2021on.csv.gz),
# fetched 2026-09 with the 2026 archive then ending 2026-08-29.
HUB_POINTS = ("HB_NORTH", "HB_WEST")
HUB_OUT = "analysis/data/ercot_rtm15_spp_hubs_2021on.csv.gz"
HUB_END = "2026-08-29T23:45:00"
UA = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 "
        "(KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    )
}


def open_gz_text(path):
    """Open path for writing text through gzip with the header's timestamp
    fixed at zero. gzip.open(path, "wt") stamps the current time into the
    header, so an unchanged rerun used to leave the committed file modified
    in git with identical contents; this writes the same bytes every time."""
    return io.TextIOWrapper(gzip.GzipFile(filename=path, mode="wb", mtime=0),
                            encoding="utf-8", newline="")


def get(url, timeout=600):
    for attempt in range(1, 6):
        try:
            with urllib.request.urlopen(
                urllib.request.Request(url, headers=UA), timeout=timeout
            ) as r:
                return r.read()
        except Exception as exc:  # transient network / ERCOT throttling
            print(f"    attempt {attempt} failed ({exc}); retrying", file=sys.stderr)
    raise SystemExit(f"gave up on {url}")


def year_documents(report_type_id, stem):
    """Map calendar year -> document id, newest posting wins."""
    payload = json.loads(get(LIST_URL.format(report_type_id), timeout=120))
    docs = payload["ListDocsByRptTypeRes"]["DocumentList"]
    found = {}
    for entry in docs:
        doc = entry["Document"]
        name = doc.get("ConstructedName", "")
        match = re.search(stem + r"_(\d{4})\.zip$", name)
        if not match:
            continue
        year = int(match.group(1))
        if year < FIRST_YEAR:
            continue
        published = doc.get("PublishDate", "")
        if year not in found or published > found[year][1]:
            found[year] = (doc["DocID"], published)
    return {y: v[0] for y, v in sorted(found.items())}


def rows_for_year(year, doc_id, market, hubs=False):
    print(f"  {year}: downloading document {doc_id}")
    blob = get(DOWNLOAD_URL.format(doc_id))
    archive = zipfile.ZipFile(io.BytesIO(blob))
    inner = [n for n in archive.namelist() if n.lower().endswith((".xlsx", ".xls"))]
    if not inner:
        raise SystemExit(f"{year}: no workbook inside the archive")
    print(f"    {len(blob) / 1e6:.1f} MB zip -> {inner[0]}")
    book = openpyxl.load_workbook(io.BytesIO(archive.read(inner[0])), read_only=True)
    out = []
    for sheet_name in book.sheetnames:
        sheet = book[sheet_name]
        header = None
        for row in sheet.iter_rows(values_only=True):
            if header is None:
                header = [str(c).strip() if c is not None else "" for c in row]
                idx = {name: i for i, name in enumerate(header)}
                continue
            # the two reports name the column differently
            name_col = "Settlement Point Name" if "Settlement Point Name" in idx else "Settlement Point"
            point = row[idx[name_col]]
            if hubs:
                # a hub is listed once; the uniqueness check in main_hubs()
                # stops the run if that ever changes
                if not point or str(point) not in HUB_POINTS:
                    continue
                if "Settlement Point Type" in idx:
                    hub_types.add((str(point), str(row[idx["Settlement Point Type"]]).strip()))
            else:
                if not point or not str(point).startswith("LZ_"):
                    continue
                # real-time lists every zone twice; keep the plain load-zone price
                if "Settlement Point Type" in idx:
                    if str(row[idx["Settlement Point Type"]]).strip() != "LZ":
                        continue
            date_cell = row[idx["Delivery Date"]]
            if isinstance(date_cell, datetime):
                day = date_cell
            else:
                day = datetime.strptime(str(date_cell).strip(), "%m/%d/%Y")
            if market == "rtm15":
                hour = int(row[idx["Delivery Hour"]])
                interval = int(row[idx["Delivery Interval"]])
                start = day + timedelta(hours=hour - 1, minutes=15 * (interval - 1))
            else:
                # day-ahead: "Hour Ending" runs 01:00 .. 24:00
                hour = int(str(row[idx["Hour Ending"]]).split(":")[0])
                start = day + timedelta(hours=hour - 1)
            out.append(
                (
                    str(point),
                    start.strftime("%Y-%m-%dT%H:%M:%S"),
                    str(row[idx["Repeated Hour Flag"]]).strip(),
                    float(row[idx["Settlement Point Price"]]),
                )
            )
        print(f"    {sheet_name}: {len(out):,} {'hub' if hubs else 'load-zone'} rows so far")
    book.close()
    return out


hub_types = set()


def main_hubs():
    """Real-time hub prices (13061), HB_NORTH and HB_WEST, 2021 to HUB_END."""
    report_type_id, stem, _, time_col = MARKETS["rtm15"]
    print(f"\n=== rtm15 hubs {', '.join(HUB_POINTS)} (report {report_type_id}) ===")
    docs = year_documents(report_type_id, stem)
    if not docs:
        raise SystemExit(f"no {stem} archives found in the ERCOT document list")
    rows = []
    for year, doc_id in docs.items():
        if str(year) > HUB_END[:4]:
            continue
        rows.extend(rows_for_year(year, doc_id, "rtm15", hubs=True))
    rows = [r for r in rows if r[1] <= HUB_END]
    keys = [(r[0], r[1], r[2]) for r in rows]
    if len(set(keys)) != len(keys):
        raise SystemExit("a hub appears twice in one interval; check Settlement Point Type")
    print("Settlement Point Type seen:", sorted(hub_types))
    rows.sort(key=lambda r: (r[0], r[1], r[2]))
    with open_gz_text(HUB_OUT) as fh:
        writer = csv.writer(fh)
        writer.writerow(["settlement_point", time_col, "dst_repeated_flag", "price"])
        writer.writerows(rows)
    for hub in HUB_POINTS:
        n = sum(1 for r in rows if r[0] == hub)
        print(f"  {hub}: {n:,} intervals")
    print(f"Wrote {HUB_OUT}: {len(rows):,} rows, {rows[0][1][:10]} to {rows[-1][1][:10]}")


def main():
    if not os.path.isdir("analysis/data"):
        raise SystemExit("run me from the repo root")
    if "--hubs" in sys.argv[1:]:
        main_hubs()
        return
    for market, (report_type_id, stem, out_path, time_col) in MARKETS.items():
        print(f"\n=== {market} (report {report_type_id}) ===")
        docs = year_documents(report_type_id, stem)
        if not docs:
            raise SystemExit(f"no {stem} archives found in the ERCOT document list")
        print(f"Years from {FIRST_YEAR}: {', '.join(str(y) for y in docs)}")
        all_rows = []
        for year, doc_id in docs.items():
            all_rows.extend(rows_for_year(year, doc_id, market))
        all_rows.sort(key=lambda r: (r[0], r[1], r[2]))
        with open_gz_text(out_path) as fh:
            writer = csv.writer(fh)
            writer.writerow(["settlement_point", time_col, "dst_repeated_flag", "price"])
            writer.writerows(all_rows)
        points = sorted({r[0] for r in all_rows})
        print(
            f"Wrote {out_path}: {len(all_rows):,} rows, "
            f"{len(points)} load zones, {all_rows[0][1][:10]} to {all_rows[-1][1][:10]}"
        )


if __name__ == "__main__":
    main()
