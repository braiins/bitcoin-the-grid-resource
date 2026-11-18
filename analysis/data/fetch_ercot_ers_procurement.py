#!/usr/bin/env python3
"""fetch_ercot_ers_procurement.py -- what ERCOT paid for Emergency Response
Service, block by block, straight from ERCOT's own procurement results.
Credential-free. Run from the repo root:

    python3 analysis/data/fetch_ercot_ers_procurement.py

Output:
    analysis/data/ercot_ers_procurement.csv
        service, term_start, term_end, doc_id, posted, time_period,
        hours, mw_procured, clearing_price, projected_cost

Source: ERCOT Market Information System report NP3-144-M, "ERS Procurement
Results" (reportTypeId 11465), one small .docx per service type and Standard
Contract Term. Each report gives, for every ERS Time Period of the term, the
Time Period's hours (ERCOT's own count, holidays and daylight saving applied),
the MW procured or self-arranged, the clearing price in dollars per MW per hour
and the projected cost. No account, no API key, no credentials: these are
public files. The document list is queried live, as
fetch_ercot_rtm15_spp_history.py does, so re-postings are picked up.

What is kept: every report whose term starts on or after December 1, 2024, the
first term of the 2025 program year (December 2024 to November 2025), for all
three service types ERCOT posts results for: Non-Weather-Sensitive ERS-30,
Non-Weather-Sensitive ERS-10 and Weather-Sensitive ERS-30. The service is read
from each report's own DESCRIPTION line and the term from its DAYS AFFECTED
line, not from the file's friendly name (ERCOT has misspelled one: "WS ERS
Procurement JunSepr26"). Where ERCOT re-posted a report, the newest posting
wins: the Non-Weather-Sensitive ERS-30 results for June to September 2026 were
posted on 2026-05-29 (doc 1232494519) and again on 2026-06-29 (doc 1244371881),
which moved Time Period 8 from $0.15 to $0.12.

The three services clear at the same price in every Time Period both report;
the run stops if they do not. Non-Weather-Sensitive ERS-30 is the program:
ERS-10 procured under half a megawatt in any Time Period of the 2025 program
year and Weather-Sensitive ERS-30 at most about 84 MW, against 1,100 to 2,800 MW
of Non-Weather-Sensitive ERS-30. analysis/checks/ch8_ers_blocks.R prints the
shares.

The run also stops unless every row reconciles: MW x hours x clearing price
must equal ERCOT's projected cost to within a cent per thousand dollars
(the MW are posted to three decimals and the price to the cent).
"""

import csv
import io
import json
import re
import sys
import urllib.request
import zipfile
from datetime import datetime

REPORT_TYPE_ID = 11465
LIST_URL = f"https://www.ercot.com/misapp/servlets/IceDocListJsonWS?reportTypeId={REPORT_TYPE_ID}"
DOWNLOAD_URL = "https://www.ercot.com/misdownload/servlets/mirDownload?doclookupId={}"
OUT = "analysis/data/ercot_ers_procurement.csv"
FIRST_TERM = "2024-12-01"
COLS = ["service", "term_start", "term_end", "doc_id", "posted", "time_period",
        "hours", "mw_procured", "clearing_price", "projected_cost"]
SERVICES = {
    "Non-Weather-Sensitive ERS-30": "NWS ERS-30",
    "Non-Weather-Sensitive ERS-10": "NWS ERS-10",
    "Weather-Sensitive ERS-30": "WS ERS-30",
}
UA = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 "
        "(KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    )
}


def get(url, timeout=120):
    for attempt in range(1, 6):
        try:
            with urllib.request.urlopen(
                urllib.request.Request(url, headers=UA), timeout=timeout
            ) as r:
                return r.read()
        except Exception as exc:  # transient network / ERCOT throttling
            print(f"    attempt {attempt} failed ({exc}); retrying", file=sys.stderr)
    raise SystemExit(f"gave up on {url}")


def paragraphs(blob):
    """The report's text, one entry per Word paragraph (table cells included)."""
    xml = zipfile.ZipFile(io.BytesIO(blob)).read("word/document.xml").decode("utf8")
    paras = re.findall(r"<w:p[ >].*?</w:p>", xml, flags=re.S)
    text = ["".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", p)).strip() for p in paras]
    return [t for t in text if t]


def money(s):
    return float(s.replace("$", "").replace(",", "").strip())


def us_date(s):
    return datetime.strptime(s.strip(), "%B %d, %Y").strftime("%Y-%m-%d")


def header(lines, doc_id):
    """(service, term_start, term_end) from the report's own header lines."""
    head = "\n".join(lines)
    desc = re.search(r"DESCRIPTION:\s*Procurement results for\s*(.+)", head)
    days = re.search(r"DAYS AFFECTED:\s*(\w+ \d+, \d{4})\s*\S\s*(\w+ \d+, \d{4})", head)
    if not desc or not days:
        raise SystemExit(f"doc {doc_id}: no DESCRIPTION or DAYS AFFECTED line")
    service = SERVICES.get(desc.group(1).strip())
    if service is None:
        raise SystemExit(f"doc {doc_id}: unknown service {desc.group(1)!r}")
    return service, us_date(days.group(1)), us_date(days.group(2))


def parse(lines, doc_id, posted):
    service, term_start, term_end = header(lines, doc_id)
    rows, cur = [], None
    for i, t in enumerate(lines):
        m = re.match(r"^Time Period (\d)\b.*;\s*([\d,]+)(?:\s*hours)?\s*$", t)
        if m:
            cur = {"time_period": int(m.group(1)), "hours": int(m.group(2).replace(",", ""))}
            rows.append(cur)
            continue
        if cur is None or i + 1 >= len(lines):
            continue
        nxt = lines[i + 1]
        if t.startswith("MW Procured"):
            cur["mw_procured"] = float(nxt.replace(",", ""))
        elif t.startswith("Clearing Price"):
            cur["clearing_price"] = money(nxt)
        elif t.startswith("Projected cost"):
            cur["projected_cost"] = money(nxt)
    out = []
    for r in rows:
        missing = {"mw_procured", "clearing_price", "projected_cost"} - set(r)
        if missing:
            raise SystemExit(f"doc {doc_id} Time Period {r['time_period']}: missing {sorted(missing)}")
        implied = r["mw_procured"] * r["hours"] * r["clearing_price"]
        if abs(implied - r["projected_cost"]) > max(0.02, 1e-5 * r["projected_cost"]):
            raise SystemExit(
                f"doc {doc_id} Time Period {r['time_period']}: {r['mw_procured']} MW x "
                f"{r['hours']} h x ${r['clearing_price']} = ${implied:,.2f}, "
                f"ERCOT projects ${r['projected_cost']:,.2f}")
        out.append({"service": service, "term_start": term_start, "term_end": term_end,
                    "doc_id": doc_id, "posted": posted, **r})
    if not out:
        raise SystemExit(f"doc {doc_id}: no Time Period found")
    return out


def main():
    listing = json.loads(get(LIST_URL))["ListDocsByRptTypeRes"]["DocumentList"]
    docs = sorted((e["Document"] for e in listing), key=lambda d: d["PublishDate"])
    print(f"{len(docs)} documents in the NP3-144-M listing")
    latest = {}
    for doc in docs:
        lines = paragraphs(get(DOWNLOAD_URL.format(doc["DocID"])))
        service, term_start, _ = header(lines, doc["DocID"])
        if term_start < FIRST_TERM:
            continue
        key = (service, term_start)
        if key in latest:
            print(f"  {service} {term_start}: doc {doc['DocID']} ({doc['PublishDate'][:10]}) "
                  f"replaces doc {latest[key][0]} ({latest[key][1]})")
        latest[key] = (doc["DocID"], doc["PublishDate"][:10], lines)   # posting order: newest wins
    # only the newest posting of each report is parsed and reconciled; a
    # superseded one may carry the error its re-posting fixed (doc 1232494519
    # prints one MW figure as "2,511.98.3", where the re-posting has 2,511.983)
    newest = {k: parse(v[2], v[0], v[1]) for k, v in latest.items()}
    out = [r for k in sorted(newest) for r in newest[k]]
    # one clearing price per Time Period and term, whatever the service
    price = {}
    for r in out:
        k = (r["term_start"], r["time_period"])
        if k in price and abs(price[k] - r["clearing_price"]) > 1e-9:
            raise SystemExit(f"term {k[0]} Time Period {k[1]}: services clear at "
                             f"${price[k]} and ${r['clearing_price']}")
        price[k] = r["clearing_price"]
    with open(OUT, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=COLS)
        w.writeheader()
        w.writerows(out)
    for k in sorted(newest):
        print(f"  {k[0]:11s} {k[1]} to {newest[k][0]['term_end']}: doc {newest[k][0]['doc_id']}, "
              f"{len(newest[k])} Time Periods, projected ${sum(r['projected_cost'] for r in newest[k]):,.2f}")
    print(f"wrote {OUT}: {len(out)} rows, every row reconciled to ERCOT's projected cost")


if __name__ == "__main__":
    main()
