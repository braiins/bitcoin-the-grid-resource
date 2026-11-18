#!/usr/bin/env python3
"""fetch_ercot_fuel_mix.py -- ERCOT generation by fuel, 15-minute intervals,
straight from ERCOT's own Fuel Mix Report. Run from the repo root:

    python3 analysis/data/fetch_ercot_fuel_mix.py            # 2025
    python3 analysis/data/fetch_ercot_fuel_mix.py 2025 2026  # both single-year workbooks ERCOT posts

Historical rebuild, 2019 to an inclusive month end:
    python3 analysis/data/fetch_ercot_fuel_mix.py --history --through YYYY-MM-DD

The end the committed file was built with is the Rebuild command in
analysis/data/README.md; pass it to reproduce that file. Without --through the
rebuild ends at the last month the newest posted workbook covers completely,
and the run prints the end it chose. Extending the series is a runbook in
analysis/data/README.md ("Refreshing the fuel-mix series"): --out writes the
rebuild somewhere other than analysis/data, so it can be compared with the
committed file (compare_fuel_mix_refresh.py) before it replaces it.

Earlier years are read from ERCOT's multi-year FuelMixReport_PreviousYears.zip.
The history output is ercot_fuel_mix_15min_2019on.csv.gz. --cache-dir optionally
reuses downloaded workbooks, and a cached workbook is never refreshed: point it
at a new, empty directory to pick up a month ERCOT has posted since. Omit it to
fetch fresh source files. Requires
openpyxl. The ZIP inspected 2026-09-27 contains 2007-2024 (2016 onward XLSX).
History supports 2019 onward. In 2019-2021 the workbook Summary notes say
Other already includes Wholesale Storage Load adjustments. The separate WSL
column is padded with zero to avoid double-counting; 2022 onward reports WSL
separately. Summing all categories includes the adjustment in both layouts.
This is a generation-based demand proxy, not measured system demand. Net
DC-tie imports are omitted. Settlement status is retained, including INITIAL
months at the current edge; this report is not a real-time feed.

Output (one file per run, named for the years fetched):
    analysis/data/ercot_fuel_mix_15min_<years>.csv.gz
        interval_start, dst_repeated_flag, settlement_type,
        Biomass, Coal, Gas, Gas-CC, Hydro, Nuclear, Other, Solar, WSL, Wind

Every fuel column is the ERCOT-wide energy that fuel produced in the interval,
in MWh (multiply by four to obtain the interval's average MW). WSL is wholesale storage
load, the batteries' charging, and is negative. interval_start is Central
PREVAILING time, ISO-8601 with no offset, the same convention as
ercot_rtm15_spp_loadzones_2021on.csv.gz, so the two join on
(interval_start, dst_repeated_flag) with no conversion.

Source: ERCOT, "Fuel Mix Report" (Interval Generation by Fuel Report), one
workbook per year, linked from https://www.ercot.com/gridinfo/generation. The
page is read live and the link for each year taken from it, so the script keeps
working when ERCOT reposts a year under a new path. No account, no key, no
credentials: these are public files.

The workbook's native shape: one sheet per month, one row per (day, fuel),
columns "0:15" .. "0:00" labelling each 15-minute interval by its END time
("0:00" at the end of the row is 24:00). On the spring-forward day the four
intervals ending 2:15 .. 3:00 are blank; they never happened. On the
fall-back day the November sheet carries four extra columns, "01:15 (DST)" ..
"02:00 (DST)": they are the SECOND pass through 01:00-02:00 (the load series
runs smoothly only with them placed after the first pass), and are written
with dst_repeated_flag = Y, as ERCOT's settlement price archive flags the same
four intervals.

The script checks itself against the workbook: each row's intervals must sum
to its "Total" column, every day must carry 92, 96 or 100 intervals, and each
fuel's annual energy is printed next to the workbook's own Summary sheet.
"""

import argparse
import calendar
import zipfile
from pathlib import Path
from zoneinfo import ZoneInfo
import csv
import gzip
import io
import os
import re
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

import openpyxl

PAGE_URL = "https://www.ercot.com/gridinfo/generation"
UA = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    )
}
FUELS = ["Biomass", "Coal", "Gas", "Gas-CC", "Hydro", "Nuclear", "Other",
         "Solar", "WSL", "Wind"]
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
          "Oct", "Nov", "Dec"]


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


def workbook_links():
    """Map year -> workbook URL, from the anchors titled 'Fuel Mix Report: YYYY'."""
    html = get(PAGE_URL, timeout=120).decode("utf-8", "replace")
    links = {}
    for href, year in re.findall(
        r'href="([^"]+\.xlsx)"[^>]*title="Fuel Mix Report: (\d{4})"', html
    ):
        links[int(year)] = href if href.startswith("http") else "https://www.ercot.com" + href
    archive = re.search(r'href="([^"]*FuelMixReport_PreviousYears\.zip)"', html)
    if not archive:
        raise SystemExit("historical Fuel Mix ZIP link missing")
    links["archive"] = archive.group(1)
    return links


def interval_start(day, label):
    """'H:MM' or 'HH:MM (DST)' interval-END label -> (start, repeated flag)."""
    repeated = "(DST)" in label
    hh, mm = label.replace("(DST)", "").strip().split(":")
    end = day + timedelta(hours=int(hh), minutes=int(mm))
    if label.strip() == "0:00":           # the row's last column is 24:00
        end = day + timedelta(days=1)
    return end - timedelta(minutes=15), "Y" if repeated else "N"


def rows_for_year(year, url, blob=None):
    print(f"  {year}: {url}")
    if blob is None:
        blob = get(url)
    print(f"    {len(blob) / 1e6:.1f} MB workbook")
    book = openpyxl.load_workbook(io.BytesIO(blob), read_only=True, data_only=True)

    # Older files incorrectly declare A1:A1 as their used range.
    for sheet in book:
        sheet.reset_dimensions()

    # the workbook's own annual totals, GWh, for the self-check
    summary = {}
    if "data_Summary_1" in book.sheetnames:
        for r in book["data_Summary_1"].iter_rows(values_only=True):
            if r[0] and isinstance(r[1], (int, float)):
                summary[str(r[0]).strip()] = float(r[1])

    cells = {}   # (start, flag) -> {"type": .., fuel: mwh}
    per_day = {}
    for month in MONTHS:
        if month not in book.sheetnames:
            continue
        sheet = book[month]
        header = None
        for row in sheet.iter_rows(values_only=True):
            if header is None:
                header = [str(c).strip() if c is not None else "" for c in row]
                continue
            if not row or row[0] is None:
                continue
            day = row[0] if isinstance(row[0], datetime) else datetime.strptime(str(row[0]).strip(), "%m/%d/%Y")
            fuel = str(row[1]).strip()
            stype = str(row[2]).strip()
            if fuel not in FUELS:
                raise SystemExit(f"{day:%Y-%m-%d}: unknown fuel {fuel!r}")
            got = 0.0
            n = 0
            for label, value in zip(header[4:], row[4:]):
                if value is None or label == "":
                    continue
                start, flag = interval_start(day, label)
                slot = cells.setdefault((start, flag), {"type": stype})
                if fuel in slot or slot["type"] != stype:
                    raise SystemExit(f"duplicate fuel or mixed settlements: {day} {fuel} {label}")
                slot[fuel] = float(value)
                got += float(value)
                n += 1
            total = row[3]
            if total is not None and abs(got - float(total)) > 1e-3 * max(1.0, abs(float(total))):
                raise SystemExit(f"{day:%Y-%m-%d} {fuel}: intervals sum to {got}, Total says {total}")
            if fuel == "Wind":
                per_day[day] = n
        print(f"    {month}: {len(cells):,} intervals so far")
    book.close()

    bad = {d: n for d, n in per_day.items() if n not in (92, 96, 100)}
    if bad:
        raise SystemExit(f"{year}: days with an impossible interval count: {bad}")
    # The 2019-2021 Summary notes put WSL adjustments inside Other.
    # Zero is a schema placeholder, not a claim that storage charging was zero.
    # Do not subtract charging again: Other already includes that adjustment.
    if year in (2019, 2020, 2021):
        for v in cells.values():
            v.setdefault("WSL", 0.0)
    missing = [(k, f) for k, v in cells.items() for f in FUELS if f not in v]
    if missing:
        raise SystemExit(f"{year}: {len(missing)} (interval, fuel) cells missing, e.g. {missing[:3]}")

    print(f"    {year} annual energy, GWh (this file / the workbook's Summary sheet):")
    for fuel in FUELS:
        mine = sum(v[fuel] for v in cells.values()) / 1000
        theirs = summary.get(fuel)
        cmp = f"{theirs:12,.1f}" if theirs is not None else "   (not in summary)"
        print(f"      {fuel:8s} {mine:12,.1f} {cmp}")
    return cells


def validate_calendar(cells, first, last):
    """Exact UTC-grid equality also rejects wrong-day 92/100 counts and DST flags."""
    central = ZoneInfo("America/Chicago")
    t = first.replace(tzinfo=central).astimezone(timezone.utc)
    end = (last + timedelta(days=1)).replace(tzinfo=central).astimezone(timezone.utc)
    expected = set()
    while t < end:
        local = t.astimezone(central)
        expected.add((local.replace(tzinfo=None), "Y" if local.fold else "N"))
        t += timedelta(minutes=15)
    if set(cells) != expected:
        raise ValueError(f"calendar mismatch: {len(expected - set(cells))} missing, "
                         f"{len(set(cells) - expected)} extra intervals")


def last_complete_month_end(cells):
    """The last month end the cells reach; a month cut short counts as absent.
    validate_calendar then checks that every interval up to it is there."""
    end = max(k[0] for k in cells) + timedelta(minutes=15)   # end of the last interval
    first_of_month = end.replace(day=1, hour=0, minute=0, second=0)
    if end == first_of_month:       # the data run to midnight ending a month
        return end - timedelta(days=1)
    return first_of_month - timedelta(days=1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("years", nargs="*", type=int)
    parser.add_argument("--history", action="store_true")
    parser.add_argument("--through",
                        help="history's inclusive last month end, YYYY-MM-DD; default: "
                             "the last month the newest posted workbook covers completely")
    parser.add_argument("--cache-dir", type=Path)
    parser.add_argument("--out", type=Path,
                        help="write here instead of analysis/data/ercot_fuel_mix_15min_<years>.csv.gz")
    args = parser.parse_args()
    if not os.path.isdir("analysis/data"):
        raise SystemExit("run me from the repo root")
    if args.through and not args.history:
        raise SystemExit("--through needs --history")
    last = None
    if args.through:
        last = datetime.strptime(args.through, "%Y-%m-%d")
        if last.day != calendar.monthrange(last.year, last.month)[1]:
            raise SystemExit("--through must be a month end")
    links = workbook_links()
    if args.history:
        newest = max(y for y in links if isinstance(y, int))
        years = list(range(2019, (last.year if last else newest) + 1))
    else:
        years = args.years or [2025]
    if min(years) < 2019:
        raise SystemExit("supported years start at 2019")
    def cached(url, name):
        path = args.cache_dir / name if args.cache_dir else None
        if path and path.exists():
            print(f"  reusing cached {path} (not refreshed)")
            return path.read_bytes()
        blob = get(url)
        if path:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(blob)
        return blob
    archive = None
    cells = {}
    for year in years:
        if year in links:
            url = links[year]
            blob = cached(url, f"{year}.xlsx")
        else:
            if archive is None:
                archive = zipfile.ZipFile(io.BytesIO(cached(links["archive"], "FuelMixReport_PreviousYears.zip")))
                print("Archive members:", ", ".join(archive.namelist()))
            names = [n for n in archive.namelist() if re.search(rf"{year}\.xlsx$", n, re.I)]
            if len(names) != 1:
                raise SystemExit(f"no unique XLSX for {year} in archive")
            url = links["archive"] + "#" + names[0]
            blob = archive.read(names[0])
        cells.update(rows_for_year(year, url, blob))
    if args.history:
        if last is None:
            last = last_complete_month_end(cells)
            print(f"--through not given: ending at {last:%Y-%m-%d}, the last complete month posted")
        cells = {k: v for k, v in cells.items() if k[0] < last + timedelta(days=1)}
        validate_calendar(cells, datetime(2019, 1, 1), last)
    else:
        validate_calendar(cells, min(k[0] for k in cells).replace(hour=0, minute=0),
                          max(k[0] for k in cells).replace(hour=0, minute=0))
    keys = sorted(cells, key=lambda k: (k[0], k[1]))
    tag = "2019on" if args.history else str(years[0]) if len(years) == 1 else f"{min(years)}_{max(years)}"
    out_path = str(args.out or f"analysis/data/ercot_fuel_mix_15min_{tag}.csv.gz")
    # gzip stores the file's base name in its header, so keep the committed
    # name (ercot_fuel_mix_15min_2019on.csv.gz) in --out for a byte comparison
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    with open_gz_text(out_path) as fh:
        writer = csv.writer(fh)
        writer.writerow(["interval_start", "dst_repeated_flag", "settlement_type"] + FUELS)
        for start, flag in keys:
            v = cells[(start, flag)]
            writer.writerow([start.strftime("%Y-%m-%dT%H:%M:%S"), flag, v["type"]]
                            + [f"{v[f]:.6f}" for f in FUELS])
    types = sorted({cells[k]["type"] for k in keys})
    print(f"Wrote {out_path}: {len(keys):,} intervals, "
          f"{keys[0][0]:%Y-%m-%d} to {keys[-1][0]:%Y-%m-%d}, settlement types {types}")


if __name__ == "__main__":
    main()
