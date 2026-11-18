"""
ercot_ingest.py extends analysis/data/prices.db with ERCOT market price data.

Datasets:
  rtm:      Real-Time Market 15-min Settlement Point Prices (NP6-905-CD)
  dam:      Day-Ahead Market hourly Settlement Point Prices (NP4-190-CD)
  rtm_as:   RTM Ancillary Service Clearing Prices post-RTC+B (NP6-331-CD)
             Available from 2025-12-05 onward; ECRS only.
  dam_as:   DAM Ancillary Service Clearing Prices pre-RTC+B (NP4-188-CD)
             Available from ~2023 (ECRS launch) through end of DAM-cleared AS era.
  as:       Historical AS Clearing Prices XLSX archive (NP6-796-ER, legacy fallback)
             Available from 2025-12-05 onward.

Auth: ROPC via ercot_auth.py (ERCOT_USERNAME + ERCOT_PASSWORD in .env.local)
Geo:  api.ercot.com is restricted to US IPs.

Usage:
  python ingest/ercot_ingest.py --from 2023-01-01 --to 2025-12-31
  python ingest/ercot_ingest.py --days 7
  python ingest/ercot_ingest.py --from 2024-01-01 --to 2024-12-31 --datasets rtm dam
  python ingest/ercot_ingest.py --from 2024-01-01 --to 2026-04-26 --datasets dam_as rtm_as
"""
from __future__ import annotations

import argparse
import io
import sys
import time
from datetime import date, timedelta, datetime
from pathlib import Path
from typing import Iterator

import requests

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from db import cpt_local_to_utc, get_conn, init_db

ERCOT_API_BASE = "https://api.ercot.com/api/public-reports"

ALL_LZ_ZONES = [
    "LZ_AEN", "LZ_CPS", "LZ_HOUSTON", "LZ_LCRA",
    "LZ_NORTH", "LZ_RAYBN", "LZ_SOUTH", "LZ_WEST",
]

# Default zones to pull for the high-frequency 5-min SCED feed. Kept narrow
# because 5-min data is ~12x the volume of the 15-min product; widen via
# --zones on the CLI if needed.
DEFAULT_RTM5_ZONES = ["LZ_WEST"]

# ── Time conversion ───────────────────────────────────────────────────────────

def _parse_delivery_date(date_str: str) -> datetime:
    for fmt in ("%m/%d/%Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(date_str).strip()[:10], fmt)
        except ValueError:
            continue
    raise ValueError(f"Cannot parse delivery date: {date_str!r}")


def cpt_to_utc(date_str: str, hour: int, interval: int = 1,
               repeat: bool = False) -> str:
    """Convert an ERCOT CPT delivery period to a UTC ISO-8601 string.

    ERCOT hour 1 = 00:00-01:00 CPT; interval 1 = first 15 min.

    `repeat` is ERCOT's DSTFlag / repeatHourFlag. That flag marks the
    DUPLICATED hour on the autumn fall-back day and nothing else; it is 'N'
    all summer. The pre-2026-08 version of this function read it as "daylight
    time is in effect" and applied a fixed UTC-6 otherwise, which stamped every
    CDT row one hour late. The offset now comes from the tz database
    (db.cpt_local_to_utc), and the flag only disambiguates the repeated hour.
    """
    base = _parse_delivery_date(date_str)
    local = base + timedelta(hours=hour - 1, minutes=(interval - 1) * 15)
    return cpt_local_to_utc(local, repeat)


def cpt_hour_ending_to_utc(date_str: str, hour_ending: str,
                           repeat: bool = False) -> str:
    """Convert an ERCOT hour-ENDING label ("HH:MM", "01:00".."24:00") to UTC.

    Hour ending 15:00 is the hour that starts at 14:00, the same interval as
    deliveryHour 15, so this must agree with cpt_to_utc(date, 15).
    """
    hh, mm = str(hour_ending).strip().split(":")
    start_min = int(hh) * 60 + int(mm) - 60
    local = _parse_delivery_date(date_str) + timedelta(minutes=start_min)
    return cpt_local_to_utc(local, repeat)


def _flag(value) -> bool:
    """ERCOT boolean flags arrive as True/False, 'Y'/'N', 'true'/'false'."""
    return str(value).strip().lower() in ("true", "1", "y", "yes")


def sced_to_utc(ts_str: str, repeat_hour: bool = False) -> str:
    """Convert an ERCOT SCEDTimestamp (local CPT, 5-min cadence) to UTC ISO-8601.

    NP6-788-CD stamps each SCED run in Central Prevailing Time with ~10-second
    jitter after the nominal 5-min mark (e.g. "2025-06-01T00:05:10"). We strip
    the sub-minute seconds and round down to the nearest 5-min boundary so the
    stored interval_start matches the nominal dispatch interval.
    repeat_hour=True marks the duplicated 1–2 AM hour at the fall-back DST
    transition (fold=1).
    """
    from zoneinfo import ZoneInfo

    s = ts_str.strip().replace("T", " ")
    naive = None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%m/%d/%Y %H:%M:%S",
                "%Y-%m-%d %H:%M", "%m/%d/%Y %H:%M"):
        try:
            naive = datetime.strptime(s, fmt)
            break
        except ValueError:
            continue
    if naive is None:
        raise ValueError(f"Cannot parse SCEDTimestamp: {ts_str!r}")

    # Round down to nearest 5-min boundary (strip sub-interval jitter).
    rounded = naive.replace(minute=(naive.minute // 5) * 5, second=0, microsecond=0)
    local = rounded.replace(tzinfo=ZoneInfo("America/Chicago"),
                            fold=1 if repeat_hour else 0)
    return local.astimezone(ZoneInfo("UTC")).strftime("%Y-%m-%dT%H:%M:%SZ")


# ── API helpers ───────────────────────────────────────────────────────────────

def _get(endpoint: str, params: dict, timeout: int = 120) -> tuple[list[list], list[str]]:
    """
    GET a direct ERCOT query endpoint. Returns (rows, field_names).
    Handles pagination automatically.
    Retries once on 401 after clearing the token cache.

    Response shape:
      { "_meta": {"totalRecords": N, "totalPages": P, "currentPage": C},
        "fields": [{"name": "deliveryDate", ...}, ...],
        "data":   [["2024-01-01", 1, 1, "LZ_HOUSTON", "LZ", 25.5, False], ...] }
    """
    from ercot_auth import get_headers, clear_cache

    url = f"{ERCOT_API_BASE}/{endpoint}"
    all_rows: list[list] = []
    fields: list[str] = []
    page = 1

    while True:
        p = {**params, "size": 2_000_000, "page": page}
        for attempt in range(2):
            resp = requests.get(url, headers=get_headers(), params=p, timeout=timeout)
            if resp.status_code == 401 and attempt == 0:
                clear_cache()
                continue
            resp.raise_for_status()
            break

        data = resp.json()

        if not fields:
            raw_fields = data.get("fields", [])
            fields = [
                f["name"] if isinstance(f, dict) else str(f)
                for f in raw_fields
            ]

        rows = data.get("data", [])
        all_rows.extend(rows)

        meta        = data.get("_meta", {})
        total_pages = int(meta.get("totalPages", 1))
        current     = int(meta.get("currentPage", page))

        if not rows or current >= total_pages:
            break
        page = current + 1

    return all_rows, fields


def _month_ranges(start: date, end: date) -> Iterator[tuple[date, date]]:
    """Yield (month_start, month_end) pairs covering start..end."""
    cur = start.replace(day=1)
    while cur <= end:
        next_month = (cur.replace(day=28) + timedelta(days=4)).replace(day=1)
        month_end  = min(next_month - timedelta(days=1), end)
        yield max(cur, start), month_end
        cur = next_month


# ── RTM 15-min Settlement Point Prices ───────────────────────────────────────

def ingest_rtm_spp(start: date, end: date, conn=None) -> int:
    """Fetch RTM 15-min SPP for all LZ zones and upsert into ercot_spp."""
    close_conn = conn is None
    if conn is None:
        conn = get_conn()

    total = 0
    for m_start, m_end in _month_ranges(start, end):
        print(f"  [RTM] {m_start} → {m_end}...", end=" ", flush=True)
        t0 = time.time()
        try:
            rows, fields = _get("np6-905-cd/spp_node_zone_hub", {
                "deliveryDateFrom":    m_start.isoformat(),
                "deliveryDateTo":      m_end.isoformat(),
                "settlementPointType": "LZ",
            })
        except requests.HTTPError as e:
            print(f"HTTP {e.response.status_code}, skip")
            continue
        except Exception as e:
            print(f"error ({e}), skip")
            continue

        inserted = _upsert_spp_rows(conn, rows, fields, "rtm15")
        total += inserted
        print(f"{inserted:,} rows  ({time.time()-t0:.1f}s)")

    if close_conn:
        conn.close()
    return total


def _upsert_spp_rows(conn, rows: list[list], fields: list[str], market: str) -> int:
    """Parse and upsert SPP data rows into ercot_spp."""
    if not rows or not fields:
        return 0

    fi = {name: i for i, name in enumerate(fields)}

    i_date     = fi.get("deliveryDate")
    i_hour     = fi.get("deliveryHour")
    i_hour_end = fi.get("hourEnding")
    i_int      = fi.get("deliveryInterval")
    i_sp       = fi.get("settlementPoint")
    i_type     = fi.get("settlementPointType")
    i_price    = fi.get("settlementPointPrice")
    i_dst      = fi.get("DSTFlag")

    if i_date is None or i_sp is None or i_price is None:
        print(f"\n    [warn] missing expected fields; got: {fields}")
        return 0
    if i_hour is None and i_hour_end is None:
        print(f"\n    [warn] no hour field in: {fields}")
        return 0

    records: list[tuple] = []
    for row in rows:
        if i_type is not None:
            sp_type = str(row[i_type]).strip().upper()
            if sp_type != "LZ":
                continue
        sp = str(row[i_sp]).strip()
        if sp not in ALL_LZ_ZONES:
            continue

        try:
            price  = float(row[i_price])
        except (TypeError, ValueError):
            continue
        # DSTFlag marks the repeated fall-back hour, NOT daylight time.
        repeat = _flag(row[i_dst]) if i_dst is not None else False

        try:
            if i_hour is not None:
                hour  = int(row[i_hour])
                intvl = int(row[i_int]) if i_int is not None else 1
                if hour > 24:
                    continue
                ts = cpt_to_utc(str(row[i_date]), hour, intvl, repeat)
            else:
                ts = cpt_hour_ending_to_utc(str(row[i_date]), row[i_hour_end], repeat)
        except (TypeError, ValueError, AttributeError):
            continue

        records.append((ts, sp, market, price))

    if not records:
        return 0

    with conn:
        conn.executemany("""
            INSERT OR REPLACE INTO ercot_spp (interval_start, settlement_point, market, price)
            VALUES (?, ?, ?, ?)
        """, records)

    return len(records)


# ── RTM 5-min SCED LMPs (NP6-788-CD) ─────────────────────────────────────────

def ingest_rtm5_lmp(start: date, end: date, conn=None,
                    zones: list[str] | None = None) -> int:
    """Fetch 5-min SCED LMPs (NP6-788-CD) for the given LZ zones into ercot_spp
    under market='rtm5'.

    This is the true 5-min real-time price (SCED energy LMP at the load zone),
    distinct from the 15-min settlement point price stored under 'rtm15'. The
    higher cadence is what the spike-morphology / safety-shutdown analysis needs.
    """
    close_conn = conn is None
    if conn is None:
        conn = get_conn()
    zones = zones or DEFAULT_RTM5_ZONES

    total = 0
    for m_start, m_end in _month_ranges(start, end):
        for zone in zones:
            print(f"  [RTM5] {zone} {m_start} → {m_end}...", end=" ", flush=True)
            t0 = time.time()
            try:
                rows, fields = _get("np6-788-cd/lmp_node_zone_hub", {
                    "SCEDTimestampFrom": f"{m_start.isoformat()}T00:00:00",
                    "SCEDTimestampTo":   f"{m_end.isoformat()}T23:59:59",
                    "settlementPoint":   zone,
                })
            except requests.HTTPError as e:
                print(f"HTTP {e.response.status_code}, skip")
                continue
            except Exception as e:
                print(f"error ({e}), skip")
                continue

            inserted = _upsert_rtm5_rows(conn, rows, fields)
            total += inserted
            print(f"{inserted:,} rows  ({time.time()-t0:.1f}s)")

    if close_conn:
        conn.close()
    return total


def _upsert_rtm5_rows(conn, rows: list[list], fields: list[str]) -> int:
    """Parse NP6-788-CD 5-min SCED LMP rows and upsert into ercot_spp (rtm5).

    Expected fields (matched case-insensitively, variants tolerated):
      SCEDTimestamp, repeatHourFlag, settlementPoint, settlementPointType, LMP
    """
    if not rows or not fields:
        return 0

    fi = {name.lower(): i for i, name in enumerate(fields)}

    def col(*names):
        for n in names:
            if n.lower() in fi:
                return fi[n.lower()]
        return None

    i_ts     = col("SCEDTimestamp", "SCEDTimestampUTC", "RTDTimestamp")
    i_repeat = col("repeatHourFlag", "DSTFlag")
    i_sp     = col("settlementPoint", "settlementPointName")
    i_price  = col("LMP", "settlementPointPrice")

    if i_ts is None or i_sp is None or i_price is None:
        print(f"\n    [warn] missing expected rtm5 fields; got: {fields}")
        return 0

    records: list[tuple] = []
    for row in rows:
        sp = str(row[i_sp]).strip()
        if sp not in ALL_LZ_ZONES:
            continue
        try:
            price = float(row[i_price])
        except (TypeError, ValueError):
            continue
        repeat = (str(row[i_repeat]).strip().lower() in ("true", "1", "y", "yes")
                  if i_repeat is not None else False)
        try:
            ts = sced_to_utc(str(row[i_ts]), repeat)
        except ValueError:
            continue
        records.append((ts, sp, "rtm5", price))

    if not records:
        return 0

    with conn:
        conn.executemany("""
            INSERT OR REPLACE INTO ercot_spp (interval_start, settlement_point, market, price)
            VALUES (?, ?, ?, ?)
        """, records)

    return len(records)


# ── DAM hourly Settlement Point Prices ───────────────────────────────────────

def ingest_dam_spp(start: date, end: date, conn=None) -> int:
    """Fetch DAM hourly SPP for all LZ zones and upsert into ercot_spp."""
    close_conn = conn is None
    if conn is None:
        conn = get_conn()

    total = 0
    for m_start, m_end in _month_ranges(start, end):
        print(f"  [DAM] {m_start} → {m_end}...", end=" ", flush=True)
        t0 = time.time()
        try:
            rows, fields = _get("np4-190-cd/dam_stlmnt_pnt_prices", {
                "deliveryDateFrom": m_start.isoformat(),
                "deliveryDateTo":   m_end.isoformat(),
            })
        except requests.HTTPError as e:
            print(f"HTTP {e.response.status_code}, skip")
            continue
        except Exception as e:
            print(f"error ({e}), skip")
            continue

        inserted = _upsert_spp_rows(conn, rows, fields, "dam")
        total += inserted
        print(f"{inserted:,} rows  ({time.time()-t0:.1f}s)")

    if close_conn:
        conn.close()
    return total


# ── RTM Ancillary Service Clearing Prices (post-RTC+B, Dec 2025+) ────────────

def ingest_rtm_as_clearing(start: date, end: date, conn=None) -> int:
    """
    Fetch RTM ECRS clearing prices from NP6-331-CD and upsert into ancillary_clearing.
    Available from 2025-12-05 (post RTC+B implementation).
    Endpoint: np6-331-cd/rt_clear_price_cap
    """
    close_conn = conn is None
    if conn is None:
        conn = get_conn()

    total = 0
    for m_start, m_end in _month_ranges(start, end):
        print(f"  [RTM_AS] {m_start} → {m_end}...", end=" ", flush=True)
        t0 = time.time()
        try:
            rows, fields = _get("np6-331-cd/rt_clear_price_cap", {
                "deliveryDateFrom": m_start.isoformat(),
                "deliveryDateTo":   m_end.isoformat(),
                "ASType":           "ECRS",
            })
        except requests.HTTPError as e:
            print(f"HTTP {e.response.status_code}, skip")
            continue
        except Exception as e:
            print(f"error ({e}), skip")
            continue

        inserted = _upsert_as_rows(conn, rows, fields, "ECRS", market="rtm15")
        total += inserted
        print(f"{inserted:,} rows  ({time.time()-t0:.1f}s)")

    if close_conn:
        conn.close()
    return total


# ── DAM Ancillary Service Clearing Prices (pre-RTC+B, Jan 2024+) ─────────────

def ingest_dam_as_clearing(start: date, end: date, conn=None) -> int:
    """
    Fetch DAM ECRS clearing prices from NP4-188-CD and upsert into ancillary_clearing.
    Uses the same JSON API pattern as ingest_dam_spp.
    ECRS was launched in ERCOT in mid-2023; prices have been declining since.
    Endpoint: np4-188-cd/dam_clear_price_for_cap
    """
    close_conn = conn is None
    if conn is None:
        conn = get_conn()

    total = 0
    for m_start, m_end in _month_ranges(start, end):
        print(f"  [DAM_AS] {m_start} → {m_end}...", end=" ", flush=True)
        t0 = time.time()
        try:
            rows, fields = _get("np4-188-cd/dam_clear_price_for_cap", {
                "deliveryDateFrom": m_start.isoformat(),
                "deliveryDateTo":   m_end.isoformat(),
                "ancillaryType":    "ECRS",
            })
        except requests.HTTPError as e:
            print(f"HTTP {e.response.status_code}, skip")
            continue
        except Exception as e:
            print(f"error ({e}), skip")
            continue

        inserted = _upsert_as_rows(conn, rows, fields, "ECRS", market="dam")
        total += inserted
        print(f"{inserted:,} rows  ({time.time()-t0:.1f}s)")

    if close_conn:
        conn.close()
    return total


def _upsert_as_rows(conn, rows: list[list], fields: list[str], service: str, market: str) -> int:
    """
    Parse ancillary clearing price rows and upsert into ancillary_clearing.

    Handles two field layouts:
      RTM (NP6-331-CD): deliveryDate, deliveryHour (int 1-24), deliveryInterval (int 1-4),
                        repeatHourFlag/DSTFlag, ASType, MCPC (clearing price $/MW)
      DAM (NP4-188-CD): deliveryDate, hourEnding (str "HH:MM"), DSTFlag,
                        ancillaryType, MCPC (clearing price $/MW)
    """
    if not rows or not fields:
        return 0

    fi = {name: i for i, name in enumerate(fields)}

    i_date     = fi.get("deliveryDate")
    i_hour     = fi.get("deliveryHour")        # RTM: int 1–24
    i_hour_end = fi.get("hourEnding")          # DAM: str "HH:MM"
    i_int      = fi.get("deliveryInterval")    # RTM only
    i_dst      = fi.get("DSTFlag") if "DSTFlag" in fi else fi.get("repeatHourFlag")
    i_price    = fi.get("MCPC")               # Market Clearing Price for Capacity

    if i_date is None or i_price is None:
        print(f"\n    [warn] missing expected fields; got: {fields}")
        return 0
    if i_hour is None and i_hour_end is None:
        print(f"\n    [warn] no hour field in: {fields}")
        return 0

    records: list[tuple] = []
    for row in rows:
        try:
            price = float(row[i_price])
        except (TypeError, ValueError):
            continue
        # DSTFlag / repeatHourFlag marks the repeated fall-back hour only.
        repeat = _flag(row[i_dst]) if i_dst is not None else False

        try:
            if i_hour is not None:
                # RTM path
                hour  = int(row[i_hour])
                intvl = int(row[i_int]) if i_int is not None else 1
                if hour > 24:
                    continue
                ts = cpt_to_utc(str(row[i_date]), hour, intvl, repeat)
            else:
                # DAM path: hourEnding "HH:MM"
                ts = cpt_hour_ending_to_utc(str(row[i_date]), row[i_hour_end], repeat)
        except (TypeError, ValueError, AttributeError):
            continue

        records.append((ts, service, price))

    if not records:
        return 0

    with conn:
        conn.executemany("""
            INSERT OR REPLACE INTO ancillary_clearing
                (interval_start, service, clearing_price)
            VALUES (?, ?, ?)
        """, records)

    return len(records)


# ── Ancillary Service Clearing Prices (XLSX archive, legacy) ─────────────────

def _list_as_archive_docs() -> list[dict]:
    """Return list of NP6-796-ER archive documents."""
    from ercot_auth import get_headers, clear_cache

    url = f"{ERCOT_API_BASE}/archive/np6-796-er"
    for attempt in range(2):
        resp = requests.get(url, headers=get_headers(), timeout=30)
        if resp.status_code == 401 and attempt == 0:
            clear_cache()
            continue
        resp.raise_for_status()
        break

    data = resp.json()
    if isinstance(data, list):
        return data
    return (
        data.get("data", [])
        or data.get("_embedded", {}).get("archives", [])
        or data.get("_embedded", {}).get("files", [])
        or []
    )


def _download_as_xlsx(doc_id: str) -> bytes:
    """Download a single NP6-796-ER XLSX file by docId."""
    from ercot_auth import get_headers, clear_cache

    url = f"{ERCOT_API_BASE}/archive/np6-796-er"
    for attempt in range(2):
        resp = requests.get(
            url, headers=get_headers(),
            params={"download": doc_id}, timeout=60,
        )
        if resp.status_code == 401 and attempt == 0:
            clear_cache()
            continue
        resp.raise_for_status()
        break
    return resp.content


def _parse_as_xlsx(content: bytes) -> list[tuple]:
    """Parse NP6-796-ER XLSX into (interval_start_utc, service, price) tuples."""
    import pandas as pd

    df = pd.read_excel(io.BytesIO(content), header=0)
    df.columns = [str(c).strip() for c in df.columns]

    col_map: dict[str, str] = {}
    for col in df.columns:
        lc = col.lower().replace(" ", "").replace("_", "").replace("-", "")
        if "deliverydate" in lc or "delivery_date" in lc[:15]:
            col_map.setdefault("date", col)
        elif "deliveryhour" in lc:
            col_map.setdefault("hour", col)
        elif "deliveryinterval" in lc:
            col_map.setdefault("interval", col)
        elif "dstflag" in lc or "dst" == lc:
            col_map.setdefault("dst", col)
        elif "ecrs" in lc:
            col_map.setdefault("ECRS", col)
        elif "nonspin" in lc or "non-spin" in lc or "nonspinning" in lc or "nsrs" in lc:
            col_map.setdefault("NSRS", col)

    if "date" not in col_map or "hour" not in col_map:
        print(f"\n    [AS] cannot map time columns from: {list(df.columns)[:10]}")
        return []

    records: list[tuple] = []
    for _, row in df.iterrows():
        try:
            date_val = str(row[col_map["date"]])
            hour     = int(float(str(row[col_map["hour"]])))
            interval = int(float(str(row[col_map["interval"]]))) if "interval" in col_map else 1
            repeat   = _flag(row.get(col_map.get("dst", ""), ""))
        except (ValueError, TypeError, KeyError):
            continue

        if hour > 24:
            continue

        try:
            ts = cpt_to_utc(date_val, hour, interval, repeat)
        except ValueError:
            continue

        for svc in ("ECRS", "NSRS"):
            if svc not in col_map:
                continue
            raw = row.get(col_map[svc])
            try:
                price = float(raw)
            except (TypeError, ValueError):
                continue
            records.append((ts, svc, price))

    return records


def ingest_as_clearing(start: date | None = None, end: date | None = None, conn=None) -> int:
    """Download NP6-796-ER archive XLSX files and upsert ECRS + NSRS prices (legacy)."""
    close_conn = conn is None
    if conn is None:
        conn = get_conn()

    print("  [AS] fetching NP6-796-ER archive list...", end=" ", flush=True)
    try:
        docs = _list_as_archive_docs()
    except Exception as e:
        print(f"error: {e}")
        if close_conn:
            conn.close()
        return 0
    print(f"{len(docs)} files")

    if not docs:
        print("  [AS] no archive files found (product may not be available)")
        if close_conn:
            conn.close()
        return 0

    total = 0
    for doc in docs:
        doc_id   = str(doc.get("docId") or doc.get("id") or doc.get("artifactId", ""))
        doc_name = str(doc.get("docName") or doc.get("fileName") or doc.get("name", doc_id))
        pub_dt   = str(doc.get("publishDateTime") or doc.get("publishDate", ""))

        if not doc_id:
            continue

        if (start or end) and pub_dt:
            try:
                pub_date = datetime.fromisoformat(pub_dt[:10]).date()
                if start and pub_date < start:
                    continue
                if end and pub_date > end:
                    continue
            except ValueError:
                pass

        print(f"    ↓ {doc_name}...", end=" ", flush=True)
        try:
            content = _download_as_xlsx(doc_id)
            records = _parse_as_xlsx(content)
        except Exception as e:
            print(f"error ({e})")
            continue

        if not records:
            print("0 rows (no matching columns)")
            continue

        with conn:
            conn.executemany("""
                INSERT OR REPLACE INTO ancillary_clearing
                    (interval_start, service, clearing_price)
                VALUES (?, ?, ?)
            """, records)
        total += len(records)
        print(f"{len(records):,} rows")

    if close_conn:
        conn.close()
    return total


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / ".env.local")
    load_dotenv()
    init_db()

    parser = argparse.ArgumentParser(
        description="Ingest ERCOT market data into analysis/data/prices.db (requires US IP)"
    )
    parser.add_argument("--from",    dest="date_from", help="Start date YYYY-MM-DD")
    parser.add_argument("--to",      dest="date_to",   help="End date YYYY-MM-DD")
    parser.add_argument("--days",    type=int,          help="Fetch last N days")
    parser.add_argument(
        "--datasets", nargs="*",
        choices=["rtm", "rtm5", "dam", "rtm_as", "dam_as", "as"],
        default=["rtm", "dam", "as"],
        help=(
            "Datasets to fetch (default: rtm dam as). "
            "rtm5 = RTM 5-min SCED LMP (NP6-788-CD; LZ_WEST by default, see --zones). "
            "rtm_as = RTM ECRS post-RTC+B (NP6-331-CD). "
            "dam_as = DAM ECRS pre-RTC+B (NP4-188-CD). "
            "as = legacy XLSX archive (NP6-796-ER)."
        ),
    )
    parser.add_argument(
        "--zones", nargs="*", default=None,
        help="LZ zones for the rtm5 dataset (default: LZ_WEST).",
    )
    args = parser.parse_args()

    if args.days:
        end   = date.today() - timedelta(days=1)
        start = end - timedelta(days=args.days - 1)
    elif args.date_from and args.date_to:
        start = date.fromisoformat(args.date_from)
        end   = date.fromisoformat(args.date_to)
    elif "as" in args.datasets and not args.date_from:
        start = end = None
    else:
        parser.error("Specify --days N  or  --from YYYY-MM-DD --to YYYY-MM-DD")
        return

    datasets = set(args.datasets)
    conn = get_conn()
    grand_total = 0

    try:
        if "rtm" in datasets:
            if start is None:
                print("  [RTM] --from/--to required for RTM dataset, skipping")
            else:
                print(f"\nIngest RTM 15-min SPP  {start} → {end}")
                n = ingest_rtm_spp(start, end, conn)
                grand_total += n
                print(f"  RTM total: {n:,} rows\n")

        if "rtm5" in datasets:
            if start is None:
                print("  [RTM5] --from/--to required for RTM5 dataset, skipping")
            else:
                zones = args.zones or DEFAULT_RTM5_ZONES
                print(f"\nIngest RTM 5-min SCED LMP  {start} → {end}  zones={zones}")
                n = ingest_rtm5_lmp(start, end, conn, zones=zones)
                grand_total += n
                print(f"  RTM5 total: {n:,} rows\n")

        if "dam" in datasets:
            if start is None:
                print("  [DAM] --from/--to required for DAM dataset, skipping")
            else:
                print(f"\nIngest DAM hourly SPP  {start} → {end}")
                n = ingest_dam_spp(start, end, conn)
                grand_total += n
                print(f"  DAM total: {n:,} rows\n")

        if "rtm_as" in datasets:
            if start is None:
                print("  [RTM_AS] --from/--to required, skipping")
            else:
                print(f"\nIngest RTM ECRS Clearing (NP6-331-CD)  {start} → {end}")
                n = ingest_rtm_as_clearing(start, end, conn)
                grand_total += n
                print(f"  RTM_AS total: {n:,} rows\n")

        if "dam_as" in datasets:
            if start is None:
                print("  [DAM_AS] --from/--to required, skipping")
            else:
                print(f"\nIngest DAM ECRS Clearing (NP4-188-CD)  {start} → {end}")
                n = ingest_dam_as_clearing(start, end, conn)
                grand_total += n
                print(f"  DAM_AS total: {n:,} rows\n")

        if "as" in datasets:
            print(f"\nIngest AS Clearing XLSX archive (NP6-796-ER)")
            n = ingest_as_clearing(start, end, conn)
            grand_total += n
            print(f"  AS total:  {n:,} rows\n")

    finally:
        conn.close()

    print(f"\nDone. {grand_total:,} total rows upserted.")


if __name__ == "__main__":
    main()
