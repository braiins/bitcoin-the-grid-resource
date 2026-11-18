#!/usr/bin/env python3
"""fetch_bitcoin_security_budget.py -- the network's security budget and its two
parts, daily, from blockchain.info's public charts (no key, no account). Run from
the repo root:
    python3 analysis/data/fetch_bitcoin_security_budget.py
Writes analysis/data/bitcoin_security_budget_daily.csv with, per day:
    miners_revenue_usd   total miner revenue (subsidy + fees) in USD
    fees_usd             total transaction fees in USD
    subsidy_usd          miners_revenue_usd - fees_usd
    fee_share            fees_usd / miners_revenue_usd
    total_bitcoins       coins in circulation at the day's end
    btc_usd              market price
Charts: miners-revenue, transaction-fees-usd, total-bitcoins, market-price
(https://api.blockchain.info/charts/<name>?timespan=8years&format=json).
"""
import csv, json, urllib.request
from collections import defaultdict
BASE = "https://api.blockchain.info/charts/{}?timespan=8years&format=json&sampled=false"
CHARTS = {"miners-revenue": "miners_revenue_usd", "transaction-fees-usd": "fees_usd",
          "total-bitcoins": "total_bitcoins", "market-price": "btc_usd"}
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 Safari/605.1.15"}
days = defaultdict(dict)
for name, col in CHARTS.items():
    req = urllib.request.Request(BASE.format(name), headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        d = json.load(r)
    for pt in d["values"]:
        import datetime
        day = datetime.datetime.utcfromtimestamp(pt["x"]).strftime("%Y-%m-%d")
        days[day][col] = pt["y"]
    print(f"  {name}: {len(d['values'])} points, {d['values'][0]['x']} .. {d['values'][-1]['x']}")
rows = []
for day in sorted(days):
    r = days[day]
    if "miners_revenue_usd" in r and "fees_usd" in r:
        rev, fees = r["miners_revenue_usd"], r["fees_usd"]
        rows.append({"date": day, "miners_revenue_usd": round(rev, 2), "fees_usd": round(fees, 2),
                     "subsidy_usd": round(rev - fees, 2), "fee_share": round(fees / rev, 6) if rev else "",
                     "total_bitcoins": r.get("total_bitcoins", ""), "btc_usd": r.get("btc_usd", "")})
with open("analysis/data/bitcoin_security_budget_daily.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
print(f"wrote analysis/data/bitcoin_security_budget_daily.csv: {len(rows)} days, {rows[0]['date']} .. {rows[-1]['date']}")
# annual summary for the chapter
by = defaultdict(lambda: {"rev": 0.0, "fees": 0.0, "n": 0})
for r in rows:
    y = r["date"][:4]; by[y]["rev"] += r["miners_revenue_usd"]; by[y]["fees"] += r["fees_usd"]; by[y]["n"] += 1
print("\nyear  days  revenue $bn   fees $bn   fee share   coins at year end")
last_coins = {}
for r in rows: last_coins[r["date"][:4]] = r["total_bitcoins"]
for y in sorted(by):
    b = by[y]; print(f"{y}  {b['n']:4d}  {b['rev']/1e9:10.2f}  {b['fees']/1e9:9.3f}  {100*b['fees']/b['rev']:8.2f}%   {float(last_coins[y])/1e6 if last_coins[y] != '' else float('nan'):.3f}M")
