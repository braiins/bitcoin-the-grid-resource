"""Standalone LZ_WEST SPP fetcher on the ERCOT Public API.

Reuses only the public ERCOT API (same endpoints as ercot-mcp), with
explicit rate limiting and 429 retry so pagination never silently truncates.
Credentials are read from ercot-mcp/.env; values are never printed.
"""
import os
import sys
import time

import httpx
import pandas as pd
from dotenv import load_dotenv

load_dotenv()  # expects ERCOT_USERNAME / ERCOT_PASSWORD / ERCOT_SUBSCRIPTION_KEY (free ERCOT API Explorer account)

AUTH_URL = (
    "https://ercotb2c.b2clogin.com/ercotb2c.onmicrosoft.com/"
    "B2C_1_PUBAPI-ROPC-FLOW/oauth2/v2.0/token"
)
CLIENT_ID = "fec253ea-0d06-4272-a5e6-b478baeecd70"
BASE_URL = "https://api.ercot.com/api/public-reports"
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

_token = {"value": None, "exp": 0.0}


def get_token() -> str:
    if _token["value"] and time.time() < _token["exp"] - 60:
        return _token["value"]
    resp = httpx.post(
        AUTH_URL,
        data={
            "username": os.environ["ERCOT_USERNAME"],
            "password": os.environ["ERCOT_PASSWORD"],
            "grant_type": "password",
            "scope": f"openid {CLIENT_ID} offline_access",
            "client_id": CLIENT_ID,
            "response_type": "id_token",
        },
        timeout=30,
    )
    resp.raise_for_status()
    body = resp.json()
    _token["value"] = body["id_token"]
    _token["exp"] = time.time() + int(body.get("expires_in", 3600))
    return _token["value"]


def fetch_pages(endpoint: str, params: dict) -> pd.DataFrame:
    """GET all pages with 2.2s spacing and 429/5xx retry."""
    url = f"{BASE_URL}/{endpoint}"
    params = dict(params)
    params.setdefault("size", 1000)
    rows, cols = [], None
    page, total_pages = 1, 1
    while page <= total_pages:
        params["page"] = page
        for attempt in range(6):
            headers = {
                "Authorization": f"Bearer {get_token()}",
                "Ocp-Apim-Subscription-Key": os.environ["ERCOT_SUBSCRIPTION_KEY"],
            }
            r = httpx.get(url, params=params, headers=headers, timeout=60)
            if r.status_code == 200:
                break
            if r.status_code == 401:
                _token["value"] = None
                continue
            if r.status_code in (429, 500, 502, 503, 504):
                time.sleep(10 * (attempt + 1))
                continue
            print(f"FATAL {r.status_code}: {r.text[:300]}", flush=True)
            sys.exit(1)
        else:
            print("FATAL: retries exhausted", flush=True)
            sys.exit(1)
        body = r.json()
        meta = body.get("_meta", {})
        total_pages = meta.get("totalPages", 1)
        if cols is None:
            cols = [f["name"] for f in body.get("fields", [])]
        rows.extend(body.get("data", []))
        print(f"  {endpoint} page {page}/{total_pages} rows={len(rows)}", flush=True)
        page += 1
        time.sleep(2.2)
    return pd.DataFrame(rows, columns=cols)


def stats(name: str, s: pd.Series, expected: int) -> None:
    s = pd.to_numeric(s, errors="coerce").dropna()
    flag = "OK" if len(s) == expected else f"MISMATCH expected {expected}"
    print(
        f"{name}: N={len(s)} [{flag}] mean={s.mean():.4f} median={s.median():.2f} "
        f"min={s.min():.2f} max={s.max():.2f} pct_neg={(s < 0).mean() * 100:.2f}%",
        flush=True,
    )


def main() -> None:
    year = sys.argv[1]
    market = sys.argv[2]  # 'dam' or 'rtm'
    leap = year == "2024"
    if market == "dam":
        df = fetch_pages(
            "np4-190-cd/dam_stlmnt_pnt_prices",
            {
                "deliveryDateFrom": f"{year}-01-01",
                "deliveryDateTo": f"{year}-12-31",
                "settlementPoint": "LZ_WEST",
            },
        )
        out = os.path.join(OUT_DIR, f"lz_west_dam_{year}.csv")
        df.to_csv(out, index=False)
        # 8784 leap / 8760 normal; DST: -1 hour Mar, +1 hour Nov -> net 0
        stats(f"DAM LZ_WEST {year}", df["settlementPointPrice"], 8784 if leap else 8760)
    else:
        frames = []
        for m in range(1, 13):
            nxt_y, nxt_m = (int(year) + 1, 1) if m == 12 else (int(year), m + 1)
            end = (pd.Timestamp(nxt_y, nxt_m, 1) - pd.Timedelta(days=1)).date()
            frames.append(
                fetch_pages(
                    "np6-905-cd/spp_node_zone_hub",
                    {
                        "deliveryDateFrom": f"{year}-{m:02d}-01",
                        "deliveryDateTo": str(end),
                        "settlementPoint": "LZ_WEST",
                    },
                )
            )
        df = pd.concat(frames, ignore_index=True)
        out = os.path.join(OUT_DIR, f"lz_west_rtm_{year}.csv")
        df.to_csv(out, index=False)
        stats(f"RTM LZ_WEST {year}", df["settlementPointPrice"], (8784 if leap else 8760) * 4)
    print(f"saved -> {out}", flush=True)


if __name__ == "__main__":
    main()
