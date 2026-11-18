#!/usr/bin/env python3
"""Schema and connection helpers for analysis/data/prices.db.

One module owns the database layout so the three writers cannot drift apart:
build_prices_db.py (reconstitutes the DB from the committed ERCOT archives),
ingest/ercot_ingest.py (extends it from ERCOT's public API) and the readers in
papo_sim.py and ingest/verify_alignment.py.

Every interval_start in ercot_spp is a UTC instant written as
"YYYY-MM-DDTHH:MM:SSZ". Conversion from ERCOT's Central prevailing time
happens once, on the way in, through the tz database (see
ingest/ercot_ingest.py); nothing downstream ever applies a fixed offset.

Pure stdlib.
"""
import os
import sqlite3
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.normpath(os.path.join(HERE, "..", "data", "prices.db"))
CENTRAL = ZoneInfo("America/Chicago")
UTC_FMT = "%Y-%m-%dT%H:%M:%SZ"


def cpt_local_to_utc(local: datetime, repeated: bool = False) -> str:
    """Central PREVAILING wall-clock time -> UTC ISO-8601 with a trailing Z.

    `repeated` marks the second pass through the duplicated hour on the autumn
    change (ERCOT's DSTFlag / repeatHourFlag / "Repeated Hour Flag" = Y). It is
    NOT a "daylight time is in effect" flag: that is the bug this function
    exists to prevent, where a CDT row read DSTFlag=N and was stamped UTC-6.
    Whether daylight time applies comes from the tz database alone.

    A wall-clock time that does not exist (inside the spring-forward gap)
    raises ValueError rather than silently landing on a neighbouring instant.
    """
    aware = local.replace(tzinfo=CENTRAL, fold=1 if repeated else 0)
    utc = aware.astimezone(timezone.utc)
    back = utc.astimezone(CENTRAL).replace(tzinfo=None)
    if back != local.replace(tzinfo=None):
        raise ValueError(f"{local:%Y-%m-%d %H:%M} does not exist in Central time")
    return utc.strftime(UTC_FMT)

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS ercot_spp ("
    " market TEXT NOT NULL,"             # 'rtm5' | 'rtm15' | 'dam'
    " settlement_point TEXT NOT NULL,"   # load zone, e.g. 'LZ_WEST'
    " interval_start TEXT NOT NULL,"     # UTC, ISO-8601 with trailing Z
    " price REAL NOT NULL,"              # $/MWh
    " PRIMARY KEY (market, settlement_point, interval_start))",
    "CREATE TABLE IF NOT EXISTS ancillary_clearing ("
    " interval_start TEXT NOT NULL,"     # UTC, ISO-8601 with trailing Z
    " service TEXT NOT NULL,"            # 'ECRS' | 'NSRS' | ...
    " clearing_price REAL NOT NULL,"     # $/MW per hour
    " PRIMARY KEY (interval_start, service))",
)


def get_conn(db=DB):
    """Open (creating if needed) the prices database."""
    os.makedirs(os.path.dirname(db), exist_ok=True)
    return sqlite3.connect(db)


def init_db(conn=None, db=DB):
    """Create the tables if they do not exist. Returns the connection used."""
    own = conn is None
    if own:
        conn = get_conn(db)
    for stmt in SCHEMA:
        conn.execute(stmt)
    conn.commit()
    if own:
        conn.close()
        return None
    return conn
