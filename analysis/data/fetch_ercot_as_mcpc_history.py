#!/usr/bin/env python3
"""fetch_ercot_as_mcpc_history.py -- ERCOT day-ahead ancillary-service
clearing prices, 2021 to a pinned end date, straight from ERCOT's own public
archive. Run from the repo root:

    python3 analysis/data/fetch_ercot_as_mcpc_history.py              # to 2026-08-22
    python3 analysis/data/fetch_ercot_as_mcpc_history.py 2026-09-19   # a later end

Output: analysis/data/ercot_dam_as_mcpc.csv.gz, one row per delivery hour,
wide (one column per product), sorted by delivery start:
    deliveryDate       YYYY-MM-DD, Central prevailing time
    hourEnding         1-24, Central prevailing time
    repeatedHourFlag   N, or Y for the SECOND pass through hour ending 02:00
                       on the autumn daylight-saving day
    regdn, regup, rrs, nspin, ecrs
                       market clearing prices for capacity (MCPC), USD per MW
                       per hour of standby; capacity prices, not energy
                       prices. ECRS is empty before the product launched on
                       2023-06-10.
    deliveryStart, deliveryEnd
                       ISO-8601 with the Central offset (-06:00 or -05:00)

Source: ERCOT Market Information System report "Historical DAM Clearing
Prices for Capacity" (NP4-181-ER, reportTypeId 13091), one DAMASMCPC_YYYY.zip
per calendar year, each holding one CSV. No account, no API key, no
credentials: these are public files, and ERCOT's Website Terms of Use (sec. 5,
ercot.com/help/terms) allow raw data from the public site to be reproduced
and redistributed in compilations, charts and analyses. The document list is
queried live rather than hard-coding document ids, so the script keeps
working as ERCOT reposts the current year.

The file's native shape: Delivery Date (MM/DD/YYYY), Hour Ending ("01:00" ..
"24:00"), Repeated Hour Flag, then one column per product. Two quirks: the
REGUP header carries a trailing space ("REGUP "), and the 2021 and 2022 files
have no ECRS column at all; from 2023 the column exists and is blank before
the launch. On the spring-forward day hour ending 03:00 is absent; on the
fall-back day hour ending 02:00 appears twice, flagged N then Y.

END DATE. The committed file ends at 2026-08-22 HE24, the end of the cache the
book was computed on (chapter 7's figure, chapter 9's ledger, chapter 10's
2026 lines). Pass a later date to extend it; the printed numbers were not
computed on the extension.

Repeated autumn hour. On each fall-back day ERCOT lists the repeated hour
twice and flags the second pass; that row is stamped 01:00-06:00 here and the
unflagged first pass 01:00-05:00. No script reads the stamps.

On a rerun the script compares every hour it shares with the file already on
disk and prints how many values differ, so a restatement by ERCOT shows up in
the console before the diff does.
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
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

FIRST_YEAR = 2021
DEFAULT_END = date(2026, 8, 22)
REPORT_TYPE_ID = 13091
STEM = "DAMASMCPC"
OUT = "analysis/data/ercot_dam_as_mcpc.csv.gz"
LIST_URL = "https://www.ercot.com/misapp/servlets/IceDocListJsonWS?reportTypeId={}"
DOWNLOAD_URL = "https://www.ercot.com/misdownload/servlets/mirDownload?doclookupId={}"
PRODUCTS = [("regdn", "REGDN"), ("regup", "REGUP"), ("rrs", "RRS"),
            ("nspin", "NSPIN"), ("ecrs", "ECRS")]
ECRS_LAUNCH = date(2023, 6, 10)
CENTRAL = ZoneInfo("America/Chicago")
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


def get(url, timeout=300):
    for attempt in range(1, 6):
        try:
            with urllib.request.urlopen(
                urllib.request.Request(url, headers=UA), timeout=timeout
            ) as r:
                return r.read()
        except Exception as exc:  # transient network / ERCOT throttling
            print(f"    attempt {attempt} failed ({exc}); retrying", file=sys.stderr)
    raise SystemExit(f"gave up on {url}")


def year_documents():
    """Map calendar year -> document id, newest posting wins."""
    payload = json.loads(get(LIST_URL.format(REPORT_TYPE_ID), timeout=120))
    found = {}
    for entry in payload["ListDocsByRptTypeRes"]["DocumentList"]:
        doc = entry["Document"]
        match = re.search(STEM + r"_(\d{4})\.zip$", doc.get("ConstructedName", ""))
        if not match or int(match.group(1)) < FIRST_YEAR:
            continue
        year, published = int(match.group(1)), doc.get("PublishDate", "")
        if year not in found or published > found[year][1]:
            found[year] = (doc["DocID"], published)
    return {y: v[0] for y, v in sorted(found.items())}


def price(text):
    text = (text or "").strip()
    return float(text) if text else None


def stamps(day, hour_ending, repeated):
    """Delivery start and end with the Central offset. fold=1 picks the
    second pass through the repeated autumn hour."""
    wall = datetime(day.year, day.month, day.day) + timedelta(hours=hour_ending - 1)
    start = wall.replace(tzinfo=CENTRAL, fold=1 if repeated == "Y" else 0)
    utc = start.astimezone(timezone.utc)
    if utc.astimezone(CENTRAL).replace(tzinfo=None) != wall:
        raise SystemExit(f"{day} HE{hour_ending}: wall time does not exist in Central time")
    return utc, start.astimezone(CENTRAL), (utc + timedelta(hours=1)).astimezone(CENTRAL)


def rows_for_year(year, doc_id, end):
    print(f"  {year}: downloading document {doc_id}")
    archive = zipfile.ZipFile(io.BytesIO(get(DOWNLOAD_URL.format(doc_id))))
    inner = [n for n in archive.namelist() if n.lower().endswith(".csv")]
    if len(inner) != 1:
        raise SystemExit(f"{year}: expected one CSV inside the archive, found {inner}")
    reader = csv.reader(io.StringIO(archive.read(inner[0]).decode("utf-8-sig")))
    header = [h.strip() for h in next(reader)]
    idx = {name: i for i, name in enumerate(header)}
    for need in ["Delivery Date", "Hour Ending", "Repeated Hour Flag", "REGDN", "REGUP", "RRS", "NSPIN"]:
        if need not in idx:
            raise SystemExit(f"{year}: column {need!r} missing from {header}")
    out = []
    for row in reader:
        if not row:
            continue
        day = datetime.strptime(row[idx["Delivery Date"]].strip(), "%m/%d/%Y").date()
        if day > end:
            continue
        he = int(row[idx["Hour Ending"]].strip().split(":")[0])
        flag = row[idx["Repeated Hour Flag"]].strip()
        values = [price(row[idx[col]]) if col in idx else None for _, col in PRODUCTS]
        utc, start, stop = stamps(day, he, flag)
        out.append((utc, day, he, flag, values, start, stop))
    print(f"    {inner[0]}: {len(out):,} hours kept")
    return out


def fmt(v):
    """Numbers as R's write.csv prints them (15 significant digits), blanks empty."""
    return "" if v is None else f"{v:.15g}"


def check(rows, end):
    keys = [(r[1], r[2], r[3]) for r in rows]
    if len(set(keys)) != len(keys):
        raise SystemExit("duplicate (date, hour ending, flag) keys")
    per_day = {}
    for day, _, _ in keys:
        per_day[day] = per_day.get(day, 0) + 1
    day, bad = date(FIRST_YEAR, 1, 1), []
    while day <= end:
        # 23, 24 or 25 hours: count the day's length in UTC, since timedelta
        # arithmetic on aware datetimes ignores the offset change
        a = datetime(day.year, day.month, day.day, tzinfo=CENTRAL).astimezone(timezone.utc)
        nxt = day + timedelta(days=1)
        b = datetime(nxt.year, nxt.month, nxt.day, tzinfo=CENTRAL).astimezone(timezone.utc)
        n = int((b - a).total_seconds() // 3600)
        if per_day.get(day, 0) != n:
            bad.append(f"{day} has {per_day.get(day, 0)} of {n} hours")
        day = nxt
    if bad:
        raise SystemExit("calendar check failed: " + "; ".join(bad[:10]))
    ecrs = [(r[1], r[4][4]) for r in rows]
    if any(v is not None for d, v in ecrs if d < ECRS_LAUNCH):
        raise SystemExit("ECRS price before its 2023-06-10 launch")
    if any(v is None for d, v in ecrs if d >= ECRS_LAUNCH):
        raise SystemExit("ECRS blank after its launch")
    if any(v is None for r in rows for v in r[4][:4]):
        raise SystemExit("a RegDn, RegUp, RRS or Non-Spin price is blank")


def compare_with_disk(rows):
    if not os.path.exists(OUT):
        return
    with gzip.open(OUT, "rt", newline="") as fh:
        old = {(r["deliveryDate"], int(r["hourEnding"]), r["repeatedHourFlag"]):
               [price(r[p]) for p, _ in PRODUCTS] for r in csv.DictReader(fh)}
    shared = diffs = 0
    for r in rows:
        prev = old.get((r[1].isoformat(), r[2], r[3]))
        if prev is None:
            continue
        shared += 1
        diffs += sum(a != b for a, b in zip(prev, r[4]))
    print(f"Against the file on disk: {shared:,} shared hours of {len(old):,}, "
          f"{diffs} value difference(s)")


def main():
    if not os.path.isdir("analysis/data"):
        raise SystemExit("run me from the repo root")
    end = DEFAULT_END if len(sys.argv) < 2 else date.fromisoformat(sys.argv[1])
    docs = {y: d for y, d in year_documents().items() if y <= end.year}
    if not docs:
        raise SystemExit(f"no {STEM} archives found in the ERCOT document list")
    print(f"Report {REPORT_TYPE_ID}, years {', '.join(str(y) for y in docs)}, through {end}")
    rows = []
    for year, doc_id in docs.items():
        rows.extend(rows_for_year(year, doc_id, end))
    rows.sort(key=lambda r: r[0])
    if rows[-1][1] != end:
        raise SystemExit(f"ERCOT's archive ends {rows[-1][1]}, before {end}")
    check(rows, end)
    compare_with_disk(rows)
    with open_gz_text(OUT) as fh:
        fh.write('"deliveryDate","hourEnding","repeatedHourFlag","regdn","regup",'
                 '"rrs","nspin","ecrs","deliveryStart","deliveryEnd"\n')
        for _, day, he, flag, values, start, stop in rows:
            fh.write(",".join([f'"{day.isoformat()}"', str(he), f'"{flag}"']
                              + [fmt(v) for v in values]
                              + [f'"{start.isoformat()}"', f'"{stop.isoformat()}"']) + "\n")
    print(f"\nWrote {OUT}: {len(rows):,} hours, {rows[0][1]} to {rows[-1][1]}")
    # console check: annual DAM standing revenue per product, $/MW-yr (the sum
    # of hourly MCPC over the year; an hourly series, so a plain sum is the
    # annual total)
    for i, (name, _) in enumerate(PRODUCTS):
        tot = {}
        for r in rows:
            if r[4][i] is not None:
                tot[r[1].year] = tot.get(r[1].year, 0.0) + r[4][i]
        print(f"{name.upper():<6} " + "  ".join(f"{y}: ${v:,.0f}" for y, v in sorted(tot.items())))


if __name__ == "__main__":
    main()
