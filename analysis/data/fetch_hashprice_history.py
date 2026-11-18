#!/usr/bin/env python3
"""fetch_hashprice_history.py -- daily bitcoin hashprice back to 2021, derived
from blockchain.info's public charts. Run from the repo root:

    python3 analysis/data/fetch_hashprice_history.py

Output: analysis/data/hashprice_daily_2021on.csv
        date, usd_th_day, miners_revenue_usd, hashrate_th, btc_usd

Hashprice is what one terahash per second earns in a day. It is not published
as a series by anyone this book is willing to cite, so it is derived from two
quantities that are:

    hashprice ($/TH/day) = total miner revenue ($/day) / network hashrate (TH/s)

Miner revenue already includes transaction fees as well as the block subsidy,
so this needs no assumption about fee levels and no halving calendar: both
halvings inside the window (May 2020 and April 2024) show up in the revenue
series on their own.

Sources, all public and credential-free (https://api.blockchain.info/charts/):
    miners-revenue   total USD paid to miners per day
    hash-rate        estimated network hash rate, TH/s
    market-price     USD price of one bitcoin (carried through for reference)

blockchain.info's hash rate is an ESTIMATE inferred from block times, so it is
noisy day to day and the series is smoothed by the provider. That is fine for
a daily strike price, which is what the book uses it for, and it is the same
basis as the repo's existing 2024-onward hashprice_daily.csv -- the two are
cross-checked at the end of this script and agree closely.
"""

import csv
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

BASE = "https://api.blockchain.info/charts/{}?timespan=8years&format=json&sampled=false"
OUT = "analysis/data/hashprice_daily_2021on.csv"
FIRST_DAY = "2021-01-01"


def chart(name):
    for attempt in range(1, 6):
        try:
            with urllib.request.urlopen(BASE.format(name), timeout=120) as r:
                payload = json.loads(r.read().decode("utf-8", "replace"))
            out = {}
            for point in payload["values"]:
                day = datetime.fromtimestamp(point["x"], tz=timezone.utc).strftime("%Y-%m-%d")
                out[day] = point["y"]
            print(f"  {name}: {len(out):,} days, {min(out)} to {max(out)}")
            return out
        except Exception as exc:
            print(f"  {name}: attempt {attempt} failed ({exc}); retrying", file=sys.stderr)
    raise SystemExit(f"gave up on chart {name}")


def main():
    if not os.path.isdir("analysis/data"):
        raise SystemExit("run me from the repo root")
    print("Fetching blockchain.info public charts:")
    revenue = chart("miners-revenue")
    hashrate = chart("hash-rate")
    price = chart("market-price")

    days = sorted(d for d in (set(revenue) & set(hashrate)) if d >= FIRST_DAY)
    rows = []
    for day in days:
        th = hashrate[day]
        if not th:
            continue
        rows.append(
            {
                "date": day,
                "usd_th_day": round(revenue[day] / th, 8),
                "miners_revenue_usd": round(revenue[day], 2),
                "hashrate_th": round(th, 2),
                "btc_usd": round(price.get(day, float("nan")), 2),
            }
        )

    with open(OUT, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"\nWrote {OUT}: {len(rows):,} days, {rows[0]['date']} to {rows[-1]['date']}")

    # annual means, and a cross-check against the repo's existing 2024+ series
    by_year = {}
    for r in rows:
        by_year.setdefault(r["date"][:4], []).append(r["usd_th_day"])
    print("\nMean hashprice by year ($/TH/day):")
    for year in sorted(by_year):
        v = by_year[year]
        print(f"  {year}: {sum(v) / len(v):.5f}  (n={len(v)})")

    # ---- splice against the series chapters 4 and 5 already print -----------
    # chapter 4's $71.6 and $156.5 strikes come from analysis/data/hashprice_daily.csv,
    # which starts 2024-01-01. This derived series runs about 2% higher on the
    # overlap, enough to contradict a printed number, so the book's own series
    # wins wherever it exists and the derived one is scaled onto it before that.
    # The scale factor is the trimmed mean of the daily ratio, which ignores the
    # halving-day fee spike of 2024-04-20 rather than letting it set the level.
    old_path = "analysis/data/hashprice_daily.csv"
    if os.path.exists(old_path):
        with open(old_path) as fh:
            book = {r["date"]: float(r["usd_th_day"]) for r in csv.DictReader(fh)}
        new = {r["date"]: r["usd_th_day"] for r in rows}
        common = sorted(set(book) & set(new))
        ratios = sorted(book[d] / new[d] for d in common if new[d])
        trim = max(1, len(ratios) // 10)
        scale = sum(ratios[trim:-trim]) / len(ratios[trim:-trim])
        diffs = [abs(book[d] - new[d]) / book[d] for d in common if book[d]]
        print(
            f"\nCross-check against {old_path} over {len(common):,} shared days: "
            f"mean absolute deviation {100 * sum(diffs) / len(diffs):.2f}%, "
            f"worst day {100 * max(diffs):.2f}%"
        )
        print(f"Splice scale factor (trimmed mean of book/derived): {scale:.4f}")
        for r in rows:
            r["usd_th_day_spliced"] = round(
                book[r["date"]] if r["date"] in book else r["usd_th_day"] * scale, 8
            )
            r["spliced_source"] = "book" if r["date"] in book else "derived_scaled"
        with open(OUT, "w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
        by_year = {}
        for r in rows:
            by_year.setdefault(r["date"][:4], []).append(r["usd_th_day_spliced"])
        print("\nSpliced hashprice by year, and the strike it implies ($/MWh):")
        for year in sorted(by_year):
            v = sum(by_year[year]) / len(by_year[year])
            print(f"  {year}: ${v:.5f}/TH/day  ->  S19j Pro ${v * 41666.7 / 29.5:6.0f}"
                  f"   S21 XP ${v * 41666.7 / 13.5:6.0f}")


if __name__ == "__main__":
    main()
