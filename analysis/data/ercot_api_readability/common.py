"""Shared helpers for the ERCOT API readability poller. Standard library only."""
from __future__ import annotations

import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

# ERCOT publishes in Central Prevailing Time. Never derive the offset from DSTFlag --
# that field only disambiguates the duplicated 01:00-02:00 hour on the November fall-back.
CT = ZoneInfo("America/Chicago")
UTC = ZoneInfo("UTC")

AUTH_URL = ("https://ercotb2c.b2clogin.com/ercotb2c.onmicrosoft.com/"
            "B2C_1_PUBAPI-ROPC-FLOW/oauth2/v2.0/token")
CLIENT_ID = "fec253ea-0d06-4272-a5e6-b478baeecd70"

HOSTS = {
    "direct": "https://api.ercot.com/api/public-reports",
}

ROOT = os.path.dirname(os.path.abspath(__file__))


class ERCOTError(Exception):
    pass


def load_env() -> dict:
    """Parse .env next to this file, then let real environment variables win."""
    cfg = {}
    path = os.path.join(ROOT, ".env")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            cfg[k.strip()] = v.strip().strip('"').strip("'")
    for k in ("ERCOT_USERNAME", "ERCOT_PASSWORD", "ERCOT_SUBSCRIPTION_KEY"):
        if os.environ.get(k):
            cfg[k] = os.environ[k]
    missing = [k for k in ("ERCOT_USERNAME", "ERCOT_PASSWORD", "ERCOT_SUBSCRIPTION_KEY")
               if not cfg.get(k)]
    if missing:
        raise ERCOTError(
            "Missing credentials: " + ", ".join(missing) +
            f"\nCopy {os.path.join(ROOT, '.env.example')} to .env and fill in the three values."
        )
    return cfg


_CTX = ssl.create_default_context()


def _request(url, *, data=None, headers=None, timeout=45):
    """Return (status, headers, body_bytes). Never raises on HTTP status."""
    req = urllib.request.Request(url, data=data, headers=headers or {},
                                 method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_CTX) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


class Session:
    """Token lifecycle + GET with 429/5xx backoff.

    The reference client in ercot-mcp lacks both of these; do not copy it.
    """

    def __init__(self, cfg: dict, host: str = "direct"):
        self.cfg = cfg
        self.base = HOSTS[host]
        self.host = host
        self._tok = None
        self._exp = 0.0
        self.counters = {"requests": 0, "http_429": 0, "http_5xx": 0,
                         "http_4xx": 0, "transport_err": 0}

    def token(self) -> str:
        if self._tok and time.time() < self._exp - 120:   # refresh 2 min early
            return self._tok
        body = urllib.parse.urlencode({
            "username": self.cfg["ERCOT_USERNAME"],
            "password": self.cfg["ERCOT_PASSWORD"],
            "grant_type": "password",
            "scope": f"openid {CLIENT_ID} offline_access",
            "client_id": CLIENT_ID,
            "response_type": "id_token",
        }).encode()
        st, _, raw = _request(AUTH_URL, data=body,
                              headers={"Content-Type": "application/x-www-form-urlencoded"})
        if st != 200:
            raise ERCOTError(f"token mint failed HTTP {st}: {raw[:300]!r}")
        j = json.loads(raw)
        self._tok = j["id_token"]
        self._exp = time.time() + int(j.get("expires_in", 3600))
        return self._tok

    def headers(self) -> dict:
        return {"Authorization": f"Bearer {self.token()}",
                "Ocp-Apim-Subscription-Key": self.cfg["ERCOT_SUBSCRIPTION_KEY"]}

    def get(self, path: str, params: dict, *, tries: int = 5):
        """GET returning (status, parsed_json_or_none, rtt_seconds, note)."""
        url = f"{self.base}{path}?{urllib.parse.urlencode(params)}"
        delay = 2.0
        for attempt in range(tries):
            t0 = time.time()
            try:
                st, hdrs, raw = _request(url, headers=self.headers())
            except Exception as e:                      # transport: DNS, TLS, timeout, reset
                self.counters["transport_err"] += 1
                if attempt == tries - 1:
                    return None, None, time.time() - t0, f"{type(e).__name__}: {e}"
                time.sleep(delay); delay = min(delay * 2, 60)
                continue
            rtt = time.time() - t0
            self.counters["requests"] += 1
            if st == 429:
                self.counters["http_429"] += 1
                wait = float(hdrs.get("Retry-After", delay))
                time.sleep(min(wait, 60)); delay = min(delay * 2, 60)
                continue
            if 500 <= st < 600:
                self.counters["http_5xx"] += 1
                time.sleep(delay); delay = min(delay * 2, 60)
                continue
            if st == 401:                                # token rotated or revoked
                self._tok = None
                if attempt < tries - 1:
                    continue
            if st != 200:
                self.counters["http_4xx"] += 1
                return st, None, rtt, raw[:200].decode("utf-8", "replace")
            try:
                return st, json.loads(raw), rtt, ""
            except Exception as e:
                return st, None, rtt, f"bad json: {e}"
        return st, None, 0.0, "retries exhausted"


def rows_of(payload: dict) -> tuple[list, list]:
    """ERCOT returns `fields` descriptors + `data` as arrays-of-arrays."""
    cols = [f["name"] for f in payload.get("fields", [])]
    return cols, payload.get("data", [])


def iv_end_905(delivery_date: str, hour: int, interval: int) -> datetime:
    """deliveryHour is hour-ENDING (1..24); deliveryInterval is 1..4 (15-minute)."""
    return (datetime.fromisoformat(delivery_date)
            + timedelta(hours=hour - 1, minutes=15 * interval))


def boundary_5min(ts: datetime) -> datetime:
    return ts.replace(minute=(ts.minute // 5) * 5, second=0, microsecond=0)


def now_ct() -> datetime:
    return datetime.now(CT).replace(tzinfo=None)


def egress() -> dict:
    """Which country are we leaving from? ERCOT 403s non-US addresses."""
    try:
        st, _, raw = _request("https://ipinfo.io/json", timeout=15)
        j = json.loads(raw)
        return {"ip": j.get("ip"), "country": j.get("country"),
                "city": j.get("city"), "org": j.get("org")}
    except Exception as e:
        return {"error": f"{type(e).__name__}: {e}"}
