#!/usr/bin/env python3
"""check_citations.py -- enforce the mechanically checkable half of the book's
source standard. Run from the repo root:

    python3 analysis/checks/check_citations.py
    python3 analysis/checks/check_citations.py --press   # before printing

Every rule here exists because the defect it catches actually reached the
manuscript at least once. What a script cannot catch is the class that matters
most, a citation whose metadata is invented or a source that does not support
the claim attached to it; those need somebody to open the document. This checker
is the floor, not the standard.

ERRORS (exit 1) are defects. WARNINGS are advisory and never fail the run.
"""
import re, sys, glob, os, collections

BIB = "book/references.bib"
CHAPTERS = sorted(glob.glob("book/chapters/*.tex"))

# Unacceptable in print per the tier table. Luxor and Hashrate Index are an
# explicit author ban (2026-08-22); Braiins Insights replaces them.
BANNED_DOMAINS = [
    ("wikipedia.org", "Wikipedia"),
    ("researchgate.net", "ResearchGate"),
    ("luxor.tech", "Luxor (author ban)"),
    ("hashrateindex.com", "Hashrate Index (author ban)"),
]

# Words that, in capitals, mean somebody was talking to the editor. The first
# seven notes that leaked into the glossary each used a different marker, so this
# list targets the shape rather than any one of them. It is case-sensitive, so it
# never sees a label in sentence case such as "Locked form:"; the phrase list
# below carries those.
DIRECTIVE_CAPS = ["RULE", "NOTE", "GAP", "TODO", "FIXME", "WARNING", "CHECK", "VERIFY",
                  "LOCK", "THIN", "OPEN", "RESOLVED", "UNVERIFIED", "COLLISION", "CAVEAT", "PLACEHOLDER"]

# Phrases that address an editor rather than a reader. Nine of these reached the
# glossary before anyone noticed, each under a different marker.
EDITOR_PHRASES = [
    r"\bone form must be locked\b", r"\bneeds? (a )?qualifier\b", r"\bthe author (should|must|needs)\b",
    r"\bbefore print\b", r"\bTHIN BOOK", r"\bLOCK VIOLATION\b", r"\bGAP:",
    r"\bTODO\b", r"\bFIXME\b", r"\bnot verified\b",
    r"\bflagged for\b", r"\bin the report\b", r"\breconciler\b",
    # The eighth leak, in the PCLR entry: "so no go-live date should be printed".
    r"\bshould be printed\b", r"\bdo not print\b",
    # The ninth leak (EXEC-003): vocabulary-lock labels and notes to the writer
    # printed in the glossary, e.g. "Locked form: always hashprice", "Lowercase in
    # this book", "do not stack another on top", "Carry the numbers".
    r"\bLocked (form|to)\b", r"\bSorted under\b", r"\bLowercase in this book\b",
    r"\bdo not stack\b", r"\bCarry the numbers\b", r"\bDo not call (this|it)\b",
    r"\bDo not use the two\b", r"\bnever called rule\b", r"\bNever written as\b",
]

errors, warnings = [], []
def err(where, msg): errors.append(f"{where}: {msg}")
def warn(where, msg): warnings.append(f"{where}: {msg}")
# --press: the copyright page's publisher placeholders become errors.
PRESS = "--press" in sys.argv[1:]


def strip_comments(text):
    """Drop LaTeX comments so prose checks never see a % src: note."""
    out = []
    for line in text.split("\n"):
        i = 0
        while True:
            j = line.find("%", i)
            if j < 0: break
            if j > 0 and line[j - 1] == "\\": i = j + 1; continue
            line = line[:j]; break
        out.append(line)
    return "\n".join(out)


def parse_bib(path):
    """Return {key: {"type":..., "fields":{name: raw value}, "line": n}}."""
    text = open(path, encoding="utf-8").read()
    entries = {}
    for m in re.finditer(r"@(\w+)\s*\{\s*([^,\s]+)\s*,", text):
        etype, key = m.group(1).lower(), m.group(2).strip()
        # brace-match the entry body
        start = text.index("{", m.start()); depth = 0; end = len(text)
        for j in range(start, len(text)):
            if text[j] == "{": depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0: end = j; break
        body = text[start + 1:end]
        fields = {}
        for fm in re.finditer(r"(\w+)\s*=\s*\{", body):
            fs = body.index("{", fm.start(1) + len(fm.group(1)))
            d = 0
            for j in range(fs, len(body)):
                if body[j] == "{": d += 1
                elif body[j] == "}":
                    d -= 1
                    if d == 0:
                        fields[fm.group(1).lower()] = body[fs + 1:j]; break
        entries[key] = {"type": etype, "fields": fields,
                        "line": text[:m.start()].count("\n") + 1}
    return entries


def collect_citations(files):
    """{key: [(file, line)]} for every \\autocite-family call, comments excluded."""
    cited = collections.defaultdict(list)
    for f in files:
        for n, raw in enumerate(open(f, encoding="utf-8"), 1):
            line = strip_comments(raw)
            for m in re.finditer(r"\\(?:auto|foot|paren|text|super)?cite[a-z]*\*?(?:\[[^\]]*\])*\{([^}]*)\}", line):
                for key in m.group(1).split(","):
                    key = key.strip()
                    if key: cited[key].append((f, n))
    return cited


def main():
    if not os.path.exists(BIB):
        print(f"error: {BIB} not found; run from the repo root"); return 2
    bib = parse_bib(BIB)
    cited = collect_citations(CHAPTERS)

    # 1. Every citation resolves. A dangling key prints as a bold [?] in the PDF.
    for key, uses in sorted(cited.items()):
        if key not in bib:
            f, n = uses[0]
            err(f"{f}:{n}", f"cites '{key}', which is not in {BIB}")

    # 2. Every entry is cited. The standard drops uncited entries; this book has
    #    no \nocite, so an uncited entry never prints and is dead weight.
    for key, e in sorted(bib.items()):
        if key not in cited:
            warn(f"{BIB}:{e['line']}", f"'{key}' is never cited (the standard drops uncited entries)")

    for key, e in sorted(bib.items()):
        fields, where = e["fields"], f"{BIB}:{e['line']}"
        url = fields.get("url", "")
        note = fields.get("note", "")

        # 3. Banned sources. Unacceptable in print, always replaced.
        for needle, label in BANNED_DOMAINS:
            if needle in url.lower() or needle in note.lower():
                err(where, f"'{key}' points at {label}, which is unacceptable in print")

        # 4. Journal articles carry a DOI, and metadata is taken from it. The
        #    fabricated-citation defects in this repo were all no-DOI entries.
        if e["type"] == "article" and "doi" not in fields:
            warn(where, f"'{key}' is @article with no doi (verify metadata at the resolved DOI, never at an aggregator)")

        # 5. Every entry with a web locator records when it was read, because a
        #    page can move under a citation. An entry with no url is exempt: a
        #    journal article cited by DOI, a statute, or an unpublished report
        #    cannot be "accessed" on a date, and demanding one of them made this
        #    rule fire on three entries that were correct as written.
        if url and not any(w in note.lower() for w in ("accessed", "visited", "retrieved", "downloaded")) \
                and "urldate" not in fields:
            warn(where, f"'{key}' has a url but records no access date")

        # 6. LaTeX hazards that have broken this build before.
        #    (a) an unescaped underscore outside a url field is "Missing $ inserted".
        for fname, val in fields.items():
            if fname == "url": continue
            stripped = re.sub(r"\\(?:no)?(?:link)?url\{[^}]*\}", "", val)
            if re.search(r"(?<!\\)_", stripped):
                err(where, f"'{key}' has an unescaped underscore in its {fname} field (Missing $ inserted)")
        #    (b) a url field must not wrap its own value in \url{}. This is the
        #        fatal input-stack overflow at \printbibliography, and the reason
        #        \url{} inside a plain note field is fine and used widely here.
        if url.strip().startswith("\\url{"):
            err(where, f"'{key}' wraps its url field value in \\url{{}}, which breaks the build")

        #    (c) rule 5: no em dashes in print. A bib note is printed prose, so a
        #        --- or an em dash there reaches the page exactly like a chapter
        #        would. The chapters are swept elsewhere; this file was not, and
        #        one slipped into the bibliography and printed on page 199.
        for fname in ("note", "title", "subtitle", "howpublished", "organization"):
            val = fields.get(fname, "")
            if "\u2014" in val or re.search(r"(?<!-)---(?!-)", val):
                err(where, f"'{key}' has an em dash in its {fname} field, which prints (rule 5)")

    # 7. No citation-needed marker or copyright-page placeholder survives to print.
    for f in CHAPTERS:
        for n, raw in enumerate(open(f, encoding="utf-8"), 1):
            line = strip_comments(raw)
            if "\\citeneeded" in line:
                err(f"{f}:{n}", "\\citeneeded remains; zero may survive at print")
            if "\\presstbd" in line:
                (err if PRESS else warn)(f"{f}:{n}", "\\presstbd remains: a copyright-page fact the publisher has not supplied yet")

    # 8. A key named in a % src: comment must exist, or the audit trail points at
    #    nothing. Deliberate mentions of a removed key are allowed by writing
    #    "removed" or "cut" on the same line.
    for f in CHAPTERS:
        for n, raw in enumerate(open(f, encoding="utf-8"), 1):
            m = re.search(r"%\s*(?:src|tab-src|fig-src):(.*)$", raw)
            if not m: continue
            tail = m.group(1)
            if re.search(r"\b(removed|cut|dropped|retired)\b", tail, re.I): continue
            for token in re.findall(r"(?<![\w/.-])([a-z][a-z0-9]*\d{4}[a-z0-9]*)(?![\w/.-])", tail):
                if token not in bib and token.lower() not in {k.lower() for k in bib}:
                    warn(f"{f}:{n}", f"source comment names '{token}', which is not a bib key")

    # 9. Rule 12: a term is bolded at its first definition only. A second bolding
    #    means two definitions, or a table header colliding with a defined term.
    bolds = collections.defaultdict(list)
    for f in CHAPTERS:
        if f.endswith("glossary.tex"): continue
        text = strip_comments(open(f, encoding="utf-8").read())
        for n, line in enumerate(text.split("\n"), 1):
            if "&" in line: continue          # a tabular row: bold here is a header, not a definition
            for m in re.finditer(r"\\textbf\{([^{}]*)\}", line):
                term = " ".join(m.group(1).split())
                if len(term.split()) > 6 or not re.search(r"[a-z]{3}", term): continue
                bolds[term.lower()].append((f, n, term))
    for term, uses in sorted(bolds.items()):
        if len(uses) > 1:
            spots = ", ".join(f"{os.path.basename(f)}:{n}" for f, n, _ in uses)
            warn("rule 12", f"'{uses[0][2]}' is bolded {len(uses)} times ({spots}); bold at first definition only")

    # 10. Text addressed to an editor rather than a reader. Nine of these
    #     reached the glossary, each under a different marker, so the sweep is
    #     deliberately broad: any unrecognised all-caps run, plus process phrases.
    for f in CHAPTERS:
        text = strip_comments(open(f, encoding="utf-8").read())
        for n, line in enumerate(text.split("\n"), 1):
            for pat in EDITOR_PHRASES:
                m = re.search(pat, line, re.I)
                if m:
                    err(f"{f}:{n}", f"text addressed to an editor, not a reader: {m.group(0)!r}")
            for m in re.finditer(r"(?<![A-Za-z\\])(" + "|".join(DIRECTIVE_CAPS) + r")\b", line):
                err(f"{f}:{n}", f"directive word {m.group(1)!r} in printed text; notes to the editor do not belong in the book")

    for line in errors: print("ERROR   " + line)
    for line in warnings: print("warning " + line)
    print(f"\n{len(errors)} error(s), {len(warnings)} warning(s) "
          f"over {len(bib)} bib entries and {len(CHAPTERS)} chapter files")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
