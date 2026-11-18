"""
ercot_auth.py handles ERCOT ROPC authentication with in-memory token caching.

Azure B2C ROPC flow (policy B2C_1_PUBAPI-ROPC-FLOW).
Tokens expire in 1h; refreshed automatically via refresh_token.
Every ERCOT API call also needs the public subscription key in a header.
"""
from __future__ import annotations

import os
import time
from pathlib import Path

import requests
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env.local")
load_dotenv()

TOKEN_URL = (
    "https://ercotb2c.b2clogin.com/ercotb2c.onmicrosoft.com"
    "/B2C_1_PUBAPI-ROPC-FLOW/oauth2/v2.0/token"
)
CLIENT_ID = "fec253ea-0d06-4272-a5e6-b478baeecd70"
# Public key embedded in the data.ercot.com SPA, not a secret.
SUB_KEY   = "91b5bf397376444a85633af5ecdfcc8e"
SCOPE     = f"openid {CLIENT_ID} offline_access"

_cache: dict = {}


def _fetch_token() -> dict:
    username = os.environ.get("ERCOT_USERNAME", "")
    password = os.environ.get("ERCOT_PASSWORD", "")
    if not username or not password:
        raise RuntimeError(
            "ERCOT_USERNAME and ERCOT_PASSWORD must be set in .env.local\n"
            "  ERCOT_USERNAME=your@email.com\n"
            "  ERCOT_PASSWORD=yourpassword"
        )
    resp = requests.post(TOKEN_URL, data={
        "grant_type":    "password",
        "username":      username,
        "password":      password,
        "client_id":     CLIENT_ID,
        "scope":         SCOPE,
        "response_type": "token",
    }, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    data["_fetched_at"] = time.time()
    return data


def _refresh_token(refresh_tok: str) -> dict:
    resp = requests.post(TOKEN_URL, data={
        "grant_type":    "refresh_token",
        "refresh_token": refresh_tok,
        "client_id":     CLIENT_ID,
        "scope":         SCOPE,
    }, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    data["_fetched_at"] = time.time()
    return data


def get_access_token() -> str:
    """Return a valid access token, refreshing or re-authenticating as needed."""
    tok = _cache.get("token")
    if tok:
        age = time.time() - tok["_fetched_at"]
        if age < int(tok.get("expires_in", 3600)) - 60:
            return tok["access_token"]
        if "refresh_token" in tok:
            try:
                _cache["token"] = _refresh_token(tok["refresh_token"])
                return _cache["token"]["access_token"]
            except Exception:
                pass  # fall through to full re-auth
    _cache["token"] = _fetch_token()
    return _cache["token"]["access_token"]


def get_headers() -> dict[str, str]:
    """Return headers required on every ERCOT API request."""
    return {
        "Authorization":             f"Bearer {get_access_token()}",
        "Ocp-Apim-Subscription-Key": SUB_KEY,
        "Accept":                    "application/json",
    }


def clear_cache() -> None:
    """Force re-authentication on next request (e.g. after a 401)."""
    _cache.clear()
