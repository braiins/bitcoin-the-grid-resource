#!/usr/bin/env python3
"""check_glossary_trace.py -- trace every number the glossary prints to the chapter
line it restates, and hold the result against a reviewed baseline. Run from the
repo root:
    python3 analysis/checks/check_glossary_trace.py [--update] [--show KIND]
--update rewrites analysis/data/glossary_trace.csv after you have read the rows the
default run printed as changed; commit the file with the edit. --show also lists
the rows of one match kind (contextual, value_only, exception, untraced).

Why it exists: the glossary carries no '% src:' comments. Its numbers restate
figures the chapters already give and source, so a second source note would only
be a second place to go stale. What can go stale instead is the restatement
itself: a chapter number changes and the glossary keeps the old one. This check
makes that visible. It finds, for each quantitative token in the glossary, the
chapter lines that print the same value in prose (never in comments) across
chapter-*.tex, preface.tex and appendix-methodology.tex, and picks a best hit.
Run it after any change to a chapter number or to the glossary.

The baseline: analysis/data/glossary_trace.csv is the reviewed trace map, one row
per token, and each of its best hits was read by hand. The matcher alone is loose
enough that a mistyped number usually finds some other line that prints it (a
glossary 59.4 Hz meets chapter 2's protective relays at 59.4), so the default run
does not rewrite the file: it regenerates the rows and fails on every row whose
value, match kind, best-hit file or best_context (the chapter's number as printed
with about six words either side) differs from the committed one, printing both.
Line numbers are not compared, so a line inserted above a number changes nothing.
Read each printed row; fix the glossary or the chapter, or, if the new best hit is
the real home, run --update and commit the file.

What counts as a token: money (\$5,000, 96 cents, \$17.4 billion), shares
(14 percent, 14\%, and the fractions a fifth, seven tenths, nearly half, which
compare against percentages), quantities with units (MW, GW, GW-s, MWh, kW, W,
J/TH, TH/s, EH/s, Hz, kV, s, min, h, days, weeks, months, years, decades, BTC, in
symbol or word form, hyphenated or not: "ten-minute" is 600 s; "a megawatt or
more" and "a decade ago" are one of the unit), rates ("twice a year", "once per
hour", compared only with a rate), plain counts in digits or words ("twelve",
"sixty-seven", "two dozen", and a "one" that closes a list of counts: "three DC
ties and one variable-frequency transformer"), positions ("the fourth block", "the
third of the four gates", "the first layer": first to eighth before block, gate or
layer, compared only with a position), calendar dates and years, and clock times.
A range or list takes the unit of its last member ("200 and 400 gigawatt-seconds",
"9.0, 8.0 and 15.8 percent"). Not tokens: identifiers (S19j Pro, 5x16, 4CP,
chapter, section, bill and docket numbers, anything glued to letters, file names
in \texttt); "two" used as a pronoun, for the entry's own terms or for a span's
two ends ("keep the two in sync", "the two words share a root", "under two names",
"the stretch between two halvings"); and, out of scope, any other bare "one" ("the
one unit in the book", "one reason") and any other ordinal ("its first naming").

How a token matches: the same value after normalisation (thousands separators,
the \$, ~ and {,} of LaTeX, "percent" against \%, word units against symbols,
MW against GW), in a compatible class: money against money, a share against a
share, a unit against the same dimension, a date against a date, a year against
a year or a date inside it, a clock time against a clock time. Two looser
matches count only with a shared word within 6 words: a plain count against any
number that prints the same digits ("floor of 100" against "100 GW-s"), and a
money, share or unit value with no thousand, million or billion against a bare
number with none either (a table cell under a unit header). The best hit is the
one whose neighbourhood shares most with the token's: the words within 6, 12 and
25 words, the other specific numbers printed nearby, the entry's term, and a
chapter the entry names. match_kind records the outcome:
  contextual   the best hit shares a word, or a nearby specific number, with the
               entry. For a weak value (a year, a clock time, a position, a whole
               count under 100) the word must sit within 6 words of the chapter's
               number, because such values turn up everywhere
  value_only   the value is printed, but nowhere near a shared word
  exception    pinned in analysis/checks/glossary_trace_exceptions.csv
  untraced     no chapter prose prints the value and no exception covers it

An exception pins a restatement to its chapter line: a rounding (9 percent for
chapter 9's 8.8), a count or position the chapter gives by naming the things in
order rather than numbering them, a complement (one third for two-thirds), or a
real home the matcher passes over for a coincidence. Its columns: entry, token as
printed, glossary_text (a few words of the entry around the token, which must
cover that one occurrence and no other), chapter_ref (file:line), chapter_text
(verbatim LaTeX from that line, outside its comment, that the pin rests on:
where it can, the chapter's own number, so that "2.4, 8.8," fails when 8.8
changes) and reason. It overrides whatever the matcher found.

ERRORS (exit 1): an untraced token; a value_only token (printed only out of
context: pin it or fix it); an exception row with a missing field, a repeated
(entry, token, glossary_text), a chapter_ref that is not a line of a traced file,
a line that no longer contains its chapter_text (the check says where the text
went, if anywhere: the chapter moved or changed, so re-read the glossary number
before re-pinning), a line that prints no number in prose, a glossary_text that
covers no token (stale), or more than one, or a token the matcher traces in
context to the same line anyway (stale); two rows pinning one token; a row that
differs from the baseline; and the appendix's src comment naming this check
(appendix-methodology.tex) quoting totals other than this run's.
"""
import bisect, csv, difflib, glob, os, re, sys, collections

GLOSSARY = "book/chapters/glossary.tex"
SOURCES = (sorted(glob.glob("book/chapters/chapter-*.tex"),
                  key=lambda p: int(re.search(r"chapter-(\d+)", p).group(1)))
           + ["book/chapters/preface.tex", "book/chapters/appendix-methodology.tex"])
EXCEPTIONS = "analysis/checks/glossary_trace_exceptions.csv"
OUT = "analysis/data/glossary_trace.csv"
MAX_HITS = 8

# ---------------------------------------------------------------- LaTeX to prose

def strip_comment(line):
    i = 0
    while True:
        j = line.find("%", i)
        if j < 0: return line
        if j > 0 and line[j - 1] == "\\": i = j + 1; continue
        return line[:j]

def _match_close(s, j, open_, close):
    depth = 0
    for k in range(j, len(s)):
        if s[k] == open_: depth += 1
        elif s[k] == close:
            depth -= 1
            if depth == 0: return k + 1
    return len(s)

def blank_command(s, name, nargs):
    """Blank out \\name[opt]{arg}... (nargs braced arguments), keeping newlines so
    line numbers survive."""
    pat = re.compile(r"\\" + name + r"\*?(?![A-Za-z])")
    out, i = [], 0
    for m in pat.finditer(s):
        if m.start() < i: continue
        j, k = m.end(), 0
        while True:
            t = j
            while t < len(s) and s[t] in " \n": t += 1
            if t < len(s) and s[t] == "[" and k == 0:
                j = _match_close(s, t, "[", "]"); continue
            if k < nargs and t < len(s) and s[t] == "{":
                j = _match_close(s, t, "{", "}"); k += 1; continue
            break
        out.append(s[i:m.start()])
        out.append(re.sub(r"[^\n]", " ", s[m.start():j]))
        i = j
    out.append(s[i:])
    return "".join(out)

# Commands whose arguments never print, or print no quantity of the chapter's.
BLANK = [("autocite", 1), ("autocites", 2), ("cite", 1), ("parencite", 1), ("textcite", 1),
         ("citeauthor", 1), ("ref", 1), ("eqref", 1), ("autoref", 1), ("pageref", 1),
         ("label", 1), ("glossaryterm", 1), ("hypertarget", 1), ("url", 1), ("input", 1), ("include", 1), ("includegraphics", 1),
         ("setlength", 2), ("setcounter", 2), ("renewcommand", 2), ("newcommand", 2),
         ("vspace", 1), ("hspace", 1), ("addcontentsline", 3), ("markboth", 2), ("rule", 2),
         ("resizebox", 2), ("multicolumn", 2), ("cline", 1), ("item", 0), ("begin", 1),
         ("end", 1), ("bibliographystyle", 1), ("texttt", 1)]

def clean_line(s):
    s = s.replace("\\$", "\x01").replace("$", "").replace("\x01", "$")   # math delimiters go
    s = s.replace("{,}", ",").replace("\\%", "%").replace("\\_", "_").replace("\\&", "&")
    s = re.sub(r"\\[,;:! ]", " ", s).replace("~", " ")
    s = s.replace("---", " ").replace("--", "–")
    s = s.replace("``", '"').replace("''", '"')
    s = re.sub(r"\\pm(?![A-Za-z])", "±", s)
    s = re.sub(r"\\[A-Za-z]+\*?", " ", s)
    s = s.replace("{", "").replace("}", "").replace("\\\\", " ").replace("\\", " ")
    s = re.sub(r"\b(\d{4})-(\d{4})\b", r"\1–\2", s)     # 2019-2025 is a year range
    return re.sub(r"[ \t]+", " ", s)

def prose_lines(path):
    """The file's printed text, line by line, comments and non-printing arguments removed."""
    raw = [strip_comment(l.rstrip("\n")) for l in open(path, encoding="utf-8")]
    text = "\n".join(raw)
    for env in ("tabular", "tabularx", "tabular*"):                    # column specs print nothing
        text = re.sub(r"\\begin\{" + re.escape(env) + r"\}", r"\\begintab ", text)
    text = blank_command(text, "begintab", 1)
    text = re.sub(r"\\(hbadness|emergencystretch|tolerance)\s*=\s*[\d.]+\w*", lambda m: " " * len(m.group(0)), text)
    for name, n in BLANK:
        text = blank_command(text, name, n)
    return [clean_line(l) for l in text.split("\n")]

class Doc:
    """Cleaned lines joined into one string, with a map back to line numbers."""
    def __init__(self, lines, every_line=False):
        self.starts, parts, pos = [], [], 0
        for l in lines:
            l = l if l.strip() else " ¶ "      # a blank line ends a paragraph
            if every_line: l += " ¶ "          # in the glossary every line is its own entry
            self.starts.append(pos); parts.append(l); pos += len(l) + 1
        self.text = " ".join(parts)
        ms = list(re.finditer(r"¶|[A-Za-z][A-Za-z0-9'’]*", self.text))
        self.words = [(m.start(), stem(m.group(0))) if m.group(0) != "¶" else (m.start(), None)
                      for m in ms]
        self.wpos = [p for p, _ in self.words]
        self.wend = [m.end() for m in ms]
    def context(self, s, e, n=6):
        """The text from s to e with n words either side, inside one paragraph: what a
        best hit reads like, independent of the line it sits on."""
        lo, hi = s, e
        k = bisect.bisect_left(self.wpos, s) - 1
        for _ in range(n):
            if k < 0 or self.words[k][1] is None: break
            lo = self.wpos[k]; k -= 1
        k = bisect.bisect_left(self.wpos, e)
        for _ in range(n):
            if k >= len(self.words) or self.words[k][1] is None: break
            hi = self.wend[k]; k += 1
        return re.sub(r"\s+", " ", self.text[lo:hi]).strip()
    def line(self, pos):
        return bisect.bisect_right(self.starts, pos)
    def window(self, pos, n=25):
        """Stems of the n words either side of pos, inside one paragraph."""
        i = bisect.bisect_left(self.wpos, pos)
        out = set()
        for rng in (range(i - 1, max(-1, i - 1 - n), -1), range(i, min(len(self.words), i + n))):
            for k in rng:
                w = self.words[k][1]
                if w is None: break
                out.add(w)
        return out

# ---------------------------------------------------------------- tokens

MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august",
          "september", "october", "november", "december"]
MON = "|".join(m.capitalize() for m in MONTHS)
SMALL = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
         "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
         "eighteen", "nineteen"]
TENS = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
WORDVAL = {w: i for i, w in enumerate(SMALL)}
WORDVAL.update({w: 20 + 10 * i for i, w in enumerate(TENS)})
DIGIT_W = "one|two|three|four|five|six|seven|eight|nine"
CARD = r"(?:(?:%s)(?:-(?:%s))?|%s)" % ("|".join(TENS), DIGIT_W, "|".join(SMALL))
FRACS = {"half": 2, "halves": 2, "third": 3, "thirds": 3, "quarter": 4, "quarters": 4,
         "fifth": 5, "fifths": 5, "sixth": 6, "sixths": 6, "eighth": 8, "eighths": 8,
         "tenth": 10, "tenths": 10, "hundredth": 100, "hundredths": 100,
         "thousandth": 1000, "thousandths": 1000}
FRAC = "|".join(sorted(FRACS, key=len, reverse=True))
NUMER = r"(?:a|an|one|two|three|four|five|six|seven|eight|nine|ten)"
CLOCK_W = "one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve"
SCALES = {"thousand": 1e3, "million": 1e6, "billion": 1e9, "trillion": 1e12}

SYM_UNITS = [("GW-s", "GW-s", 1), ("GWs", "GW-s", 1), ("J/TH", "J/TH", 1), ("TH/s", "H/s", 1e12),
             ("PH/s", "H/s", 1e15), ("EH/s", "H/s", 1e18), ("kWh", "Wh", 1e3), ("MWh", "Wh", 1e6),
             ("GWh", "Wh", 1e9), ("TWh", "Wh", 1e12), ("kW", "W", 1e3), ("MW", "W", 1e6),
             ("GW", "W", 1e9), ("W", "W", 1), ("kV", "V", 1e3), ("Hz", "Hz", 1), ("ms", "s", 1e-3),
             ("min", "s", 60), ("s", "s", 1), ("h", "s", 3600), ("BTC", "BTC", 1)]
SYM_RE = re.compile(r"\s?(" + "|".join(re.escape(u) for u, _, _ in SYM_UNITS) + r")(?![A-Za-z0-9])")
SYM = {u: (d, f) for u, d, f in SYM_UNITS}
WORD_UNITS = [("gigawatt-seconds?", "GW-s", 1), ("megawatt-hours?", "Wh", 1e6),
              ("kilowatt-hours?", "Wh", 1e3), ("gigawatt-hours?", "Wh", 1e9),
              ("terawatt-hours?", "Wh", 1e12), ("gigawatts?", "W", 1e9), ("megawatts?", "W", 1e6),
              ("kilowatts?", "W", 1e3), ("watts?", "W", 1), ("kilovolts?", "V", 1e3),
              ("hertz", "Hz", 1), ("milliseconds?", "s", 1e-3), ("seconds?", "s", 1),
              ("minutes?", "s", 60), ("hours?", "s", 3600), ("days?", "day", 1),
              ("weeks?", "week", 1), ("months?", "month", 1), ("years?", "year", 1),
              ("decades?", "year", 10), ("bitcoins?", "BTC", 1)]
WORD_UNIT = "|".join(u for u, _, _ in WORD_UNITS)
NOT_ADJ = {"of", "to", "and", "or", "in", "on", "at", "for", "the", "a", "an", "per", "than",
           "from", "by", "with", "as", "is", "was", "each", "every", "more", "less", "that",
           "which", "into", "over", "under", "a", "its", "their", "his", "her", "if", "when"}

def unit_of_word(w):
    w = w.lower()
    for pat, d, f in WORD_UNITS:
        if re.fullmatch(pat, w): return d, f
    return None

def card_value(w):
    w = w.lower()
    if "-" in w:
        a, b = w.split("-", 1)
        return WORDVAL[a] + WORDVAL[b]
    return WORDVAL[w]

# "the two" as a pronoun points back at two things the sentence has just named
# ("keep the two in sync", "the two read the same feed"), and "the two words" or
# "the two units" counts the entry's own terms; neither restates a chapter figure.
# "the two-week window" and "the two gentlest settings" are counts and stay tokens.
PRONOUN_TWO = re.compile(r"\s*(?:[,.;:)]|(?:as|is|are|was|were|in|of|at|to|and|or|do|does|did|read|"
                         r"share|sit|differ|can|cannot|must|never|only|together|words|terms|names|"
                         r"senses|units)\b)")
# The same holds for "between two" that defines a span by its ends ("the stretch
# between two halvings", "between two of them") and for "under two names", which
# counts the entry's own terms. "between two and three" is a range and stays a token.
def definitional_two(T, s, e):
    before, after = T[max(0, s - 9):s], T[e:]
    if re.search(r"\b(?:the|The)\s+$", before) and PRONOUN_TWO.match(after): return True
    if re.search(r"\bbetween\s+$", before) and not re.match(r"\s*(?:and|to|or|–)\b", after): return True
    return bool(re.search(r"\bunder\s+$", before) and re.match(r"\s+names\b", after))

ORDINALS = {"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6,
            "seventh": 7, "eighth": 8}
ORD = "|".join(ORDINALS)
# the things this book numbers by position: ERS blocks, the four gates, the layers of a bill
ORD_THINGS = r"(?:blocks?|gates?|layers?)"
ORD_STEMS = {"block", "gate", "layer"}
RATE_PERIODS = r"(?:year|month|week|day|hour)"

def list_tail_one(T, s, e, toks):
    """A bare "one" usually names no quantity ("the one unit", "one reason"). It
    does when it closes a list of counts: "three DC ties and one variable-frequency
    transformer", "two for weekends and holidays, and one for everything left over"."""
    if not re.search(r"\band\s+$", T[max(0, s - 5):s]): return False
    if re.match(r"\s+(?:of|that|who|which|at|in|is|was|another|more|level|way|day)\b", T[e:]): return False
    prev = [t for t in toks if t.e <= s and s - t.e <= 100]
    if not prev: return False
    p = max(prev, key=lambda t: t.e)
    return p.cls == "count" and not p.scale_set and not re.search(r"[.;:]\s", T[p.e:s])

def fmt(x):
    return f"{x:.10g}"

class Tok:
    __slots__ = ("s", "e", "surf", "cls", "dim", "num", "val", "scale_set", "key", "ampm")
    def __init__(self, s, e, surf, cls, num=None, val=None, dim=None, key=None, ampm=None):
        self.s, self.e, self.surf, self.cls = s, e, re.sub(r"\s+", " ", surf.strip()), cls
        self.num, self.val, self.dim, self.key, self.ampm = num, val, dim, key, ampm
        self.scale_set = False
    def value(self):
        if self.cls == "money": return "money:" + fmt(self.val)
        if self.cls == "share": return "share:" + fmt(self.val)
        if self.cls == "unit": return f"{self.dim}:" + fmt(self.val)
        if self.cls == "count": return "count:" + fmt(self.val)
        if self.cls == "time":
            return "time:" + self.key + ({"am": " a.m.", "pm": " p.m."}.get(self.ampm, ""))
        return f"{self.cls}:{self.key}"

def ampm_of(s):
    if not s: return None
    s = s.lower()
    if s.startswith("a"): return "am"
    if s.startswith("p") or "afternoon" in s or "evening" in s: return "pm"
    if "morning" in s: return "am"
    return None

def clock(h, m):
    """A 12-hour key; the a.m./p.m. flag is kept beside it."""
    h = int(h) % 12
    return f"{h}:{int(m):02d}"

def tokenize(T, glossary=False):
    toks, taken = [], bytearray(len(T))
    def free(s, e): return not any(taken[s:e])
    def take(s, e):
        for k in range(s, e): taken[k] = 1
    def add(t):
        toks.append(t); take(t.s, t.e)

    # 1. calendar dates, before anything reads their digits
    for m in re.finditer(r"\b(\d{4})-(\d{2})-(\d{2})\b", T):
        add(Tok(m.start(), m.end(), m.group(0), "date", key=m.group(0)))
    for m in re.finditer(r"\b(%s)\s+(\d{1,2}),?\s+(\d{4})\b" % MON, T):
        if free(m.start(), m.end()):
            key = f"{m.group(3)}-{MONTHS.index(m.group(1).lower()) + 1:02d}-{int(m.group(2)):02d}"
            add(Tok(m.start(), m.end(), m.group(0), "date", key=key))
    for m in re.finditer(r"\b(\d{1,2})\s+(%s)\s+(\d{4})\b" % MON, T):
        if free(m.start(), m.end()):
            key = f"{m.group(3)}-{MONTHS.index(m.group(2).lower()) + 1:02d}-{int(m.group(1)):02d}"
            add(Tok(m.start(), m.end(), m.group(0), "date", key=key))
    for m in re.finditer(r"\b(%s)\s+(\d{4})\b" % MON, T):
        if free(m.start(), m.end()):
            add(Tok(m.start(), m.end(), m.group(0), "date",
                    key=f"{m.group(2)}-{MONTHS.index(m.group(1).lower()) + 1:02d}"))
    for m in re.finditer(r"\b(%s)\s+(\d{1,2})(?![\d:,.]|\s*(?:a\.m\.|p\.m\.))\b" % MON, T):
        if free(m.start(), m.end()):
            add(Tok(m.start(), m.end(), m.group(0), "date",
                    key=f"--{MONTHS.index(m.group(1).lower()) + 1:02d}-{int(m.group(2)):02d}"))

    # 2. clock times
    H = r"\d{1,2}(?::\d{2})?"
    AMPM = r"(a\.m\.|p\.m\.|in the afternoon|in the evening|in the morning)"
    def hm(x):
        x = x.lower()
        if x in WORDVAL: return WORDVAL[x], 0
        h, _, m = x.partition(":")
        return int(h), int(m or 0)
    for m in re.finditer(r"\b(%s|%s)(?:\s+to\s+|-to-|\s*–\s*)(%s|%s)[- ]?\s*%s" % (H, CLOCK_W, H, CLOCK_W, AMPM), T, re.I):
        if not free(m.start(), m.end()): continue
        ap = ampm_of(m.group(3))
        for g in (1, 2):
            h, mi = hm(m.group(g))
            add(Tok(m.start(g), m.end(g) if g == 1 else m.end(), m.group(g), "time", key=clock(h, mi), ampm=ap))
    for m in re.finditer(r"\b(half past|a quarter past|quarter past|a quarter to)\s+(%s|\d{1,2})\b" % CLOCK_W, T, re.I):
        if not free(m.start(), m.end()): continue
        h, _ = hm(m.group(2)); w = m.group(1).lower()
        mi = 30 if "half" in w else 15
        if w.endswith(" to"): h, mi = h - 1, 45
        add(Tok(m.start(), m.end(), m.group(0), "time", key=clock(h, mi)))
    for m in re.finditer(r"\b(\d{1,2})(?::(\d{2}))?\s*(a\.m\.|p\.m\.)", T):
        if free(m.start(), m.end()):
            ap = ampm_of(m.group(3))
            add(Tok(m.start(), m.end(), m.group(0), "time", key=clock(m.group(1), m.group(2) or 0), ampm=ap))
    for m in re.finditer(r"\b(%s)[- ](a\.m\.|p\.m\.)" % CLOCK_W, T, re.I):
        if free(m.start(), m.end()):
            ap = ampm_of(m.group(2))
            add(Tok(m.start(), m.end(), m.group(0), "time", key=clock(WORDVAL[m.group(1).lower()], 0), ampm=ap))
    for m in re.finditer(r"(?<![\d.,:])\b(\d{1,2}):(\d{2})\b(?![\d:])", T):
        if free(m.start(), m.end()):
            add(Tok(m.start(), m.end(), m.group(0), "time", key=clock(m.group(1), m.group(2))))
    for m in re.finditer(r"\b(noon|midnight)\b", T, re.I):
        if free(m.start(), m.end()):
            ap = "pm" if m.group(1).lower() == "noon" else "am"
            add(Tok(m.start(), m.end(), m.group(0), "time", key="0:00", ampm=ap))
    for m in re.finditer(r"\b(?:HE|[Hh]our ending)\s+(\d{1,2})\b", T):
        if free(m.start(), m.end()):
            add(Tok(m.start(), m.end(), m.group(0), "he", key=m.group(1)))

    # 3. numbers that are names, not quantities
    for m in re.finditer(r"\b(?:Chapters?|Sections?|Parts?|Figures?|Tables?|Rules?)\s+\d{1,2}(?:\.\d+)?"
                         r"(?:(?:\s*,\s*(?:and\s+)?|\s+and\s+|\s+or\s+|\s*–\s*|\s+to\s+)\d{1,2}(?![\d,.]\d))*", T):
        take(m.start(), m.end())
    for m in re.finditer(r"\b(?:Senate Bill|House Bill|SB|HB|No\.|Docket|Item|Project|Hut|Order)\s+\d+|§\s*[\d.]+", T):
        take(m.start(), m.end())

    # 4. special number-word shapes
    for m in re.finditer(r"\b(%s|\d+)\s+and\s+a\s+half\s+(%s)\b" % (CARD, WORD_UNIT), T, re.I):
        if not free(m.start(), m.end()): continue
        n = float(m.group(1)) if m.group(1).isdigit() else card_value(m.group(1))
        d, f = unit_of_word(m.group(2))
        add(Tok(m.start(), m.end(), m.group(0), "unit", num=n + 0.5, val=(n + 0.5) * f, dim=d))
    for m in re.finditer(r"\b(?:an?|one)\s+(%s)\s+and\s+(a half|a quarter|three-quarters|three quarters)\b" % WORD_UNIT, T, re.I):
        if not free(m.start(), m.end()): continue
        d, f = unit_of_word(m.group(1))
        n = 1 + {"a half": .5, "a quarter": .25}.get(m.group(2).lower(), .75)
        add(Tok(m.start(), m.end(), m.group(0), "unit", num=n, val=n * f, dim=d))
    FR = r"\b(?:(%s)[\s-])?(%s)\b(?!-)" % (NUMER, FRAC)
    for m in re.finditer(FR, T, re.I):
        if not free(m.start(), m.end()): continue
        numer, den = m.group(1), m.group(2).lower()
        if numer is None and den not in ("half",): continue           # "the third" is an ordinal
        if numer is None and re.match(r"\s+past\b", T[m.end():]): continue
        n = 1 if numer is None or numer.lower() in ("a", "an", "one") else WORDVAL[numer.lower()]
        frac = n / FRACS[den]
        rest = T[m.end():]
        u = re.match(r"\s+(?:of\s+)?(?:an?\s+)?(%s)\b" % WORD_UNIT, rest, re.I)
        if u:
            d, f = unit_of_word(u.group(1))
            add(Tok(m.start(), m.end() + u.end(), m.group(0) + u.group(0), "unit", num=frac, val=frac * f, dim=d))
        else:
            add(Tok(m.start(), m.end(), m.group(0), "share", num=frac * 100, val=frac * 100))
    # "a megawatt or more", "a decade ago": one of the unit, with no number word
    for m in re.finditer(r"\b(an?)\s+(%s)(?=\s+(?:or\s+more|or\s+less|and\s+up|and\s+over|ago)\b)" % WORD_UNIT, T, re.I):
        if not free(m.start(), m.end()): continue
        d, f = unit_of_word(m.group(2))
        add(Tok(m.start(), m.end(), m.group(0), "unit", num=1, val=f, dim=d))
    # "twice a year", "once per hour": a rate, compared only with the same rate
    for m in re.finditer(r"\b(once|twice)\s+(?:a|an|per|each)\s+(%s)\b" % RATE_PERIODS, T, re.I):
        if not free(m.start(), m.end()): continue
        n = 1 if m.group(1).lower() == "once" else 2
        add(Tok(m.start(), m.end(), m.group(0), "unit", num=n, val=n, dim="/" + m.group(2).lower()))
    # "the fourth block", "the third of the four gates": a position, compared only with a position
    for m in re.finditer(r"\b(%s)(?=\s+(?:of\s+the\s+(?:[A-Za-z-]+\s+){1,3}?)?%s\b)" % (ORD, ORD_THINGS), T, re.I):
        if not free(m.start(), m.end()): continue
        n = ORDINALS[m.group(1).lower()]
        add(Tok(m.start(), m.end(), m.group(0), "ordinal", num=n, val=n, key=str(n)))

    # 5. digits and number words
    NUM = re.compile(r"(?<![A-Za-z0-9_.,/])(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?|\b((?:an?|one)\s+(?:hundred|thousand)|%s)\b" % CARD, re.I)
    for m in NUM.finditer(T):
        s, e = m.start(), m.end()
        if not free(s, e): continue
        if m.group(3):
            w = m.group(3).lower()
            if re.match(r"(?:an?|one)\s+", w):
                num = 100.0 if w.endswith("hundred") else 1000.0
            else:
                num = float(card_value(w))
                if glossary and w == "two" and definitional_two(T, s, e):
                    continue                                            # "keep the two in sync": a pronoun
            digits = False
        else:
            if s > 0 and T[s - 1] == "-" and s > 1 and (T[s - 2].isdigit() or T[s - 2].isupper()):
                continue                                                # NP6-788, a document id
            if e < len(T) and T[e].isalpha() and not re.match(r"(M|bn|k)\b", T[e:]):
                continue                                                # 4CP, 5x16, 19j, 3.5pt
            num = float(m.group(1).replace(",", "") + (m.group(2) or ""))
            digits = True
        rest = T[e:]
        before = T[max(0, s - 12):s]
        cls, val, dim, surf_e = "count", num, None, e
        money = digits and before.endswith("$")
        if money:
            sign = -1 if re.search(r"(?:^|[\s(])[-−]\$$|\b(?:of|at|to|is|was|reach|reached|below|near|floor)\s+minus\s+\$$", before) else 1
            s -= 1 + (1 if before.endswith("-$") or before.endswith("−$") else 0)
            cls, val = "money", sign * num
        elif digits and before.endswith("-") and (len(before) < 2 or before[-2] in " (±≈"):
            num, val, s = -num, -num, s - 1
        tok = Tok(s, e, "", cls, num=num, val=val)
        r = re.match(r"(M|bn|k)\b", rest) if money else None
        scale = 1
        dz = re.match(r"\s+dozen\b", rest) if not digits else None
        if dz:
            tok.num, tok.val = num * 12, val * 12; e += dz.end(); surf_e = e; rest = T[e:]
        if r:
            scale = {"M": 1e6, "bn": 1e9, "k": 1e3}[r.group(1)]; surf_e = e + r.end(); rest = T[surf_e:]
        else:
            r = re.match(r"\s+(thousand|million|billion|trillion)\b", rest)
            if r:
                scale = SCALES[r.group(1)]; surf_e = e + r.end(); rest = T[surf_e:]
        if scale != 1: tok.scale_set = True
        tok.val = tok.val * scale
        if not money:
            r = re.match(r"\s+dollars\b", rest)
            c = re.match(r"\s+cents\b", rest)
            p = re.match(r"\s*%|\s+(?:percent|per cent|percentage points?)\b", rest)
            sym = SYM_RE.match(rest) if digits else None
            wu = re.match(r"(?:-|\s+(?:([a-z]+)\s+)?)(%s)(?:'|’)?(?![A-Za-z])" % WORD_UNIT, rest)
            if wu and wu.group(1) and wu.group(1) in NOT_ADJ: wu = None
            if r:
                tok.cls = "money"; surf_e += r.end()
            elif c:
                tok.cls, tok.val = "money", tok.val / 100; surf_e += c.end()
            elif p:
                tok.cls = "share"; surf_e += p.end()
            elif sym and (sym.group(1) not in ("s", "h", "min") or rest.startswith(" ")):
                d, f = SYM[sym.group(1)]
                tok.cls, tok.dim, tok.val = "unit", d, tok.val * f; surf_e += sym.end()
            elif wu:
                d, f = unit_of_word(wu.group(2))
                tok.cls, tok.dim, tok.val = "unit", d, tok.val * f; surf_e += wu.end()
            elif not digits and tok.num == 1 and not list_tail_one(T, s, e, toks):
                continue                                                # "one" names no quantity alone
            elif (digits and tok.cls == "count" and "." not in m.group(0) and "," not in m.group(0)
                  and len(m.group(1)) == 4 and 1990 <= num <= 2039 and scale == 1):
                tok.cls, tok.key = "year", m.group(1)
        tok.e = surf_e
        tok.surf = re.sub(r"\s+", " ", T[tok.s:tok.e].strip())
        add(tok)

    toks.sort(key=lambda t: t.s)
    # 6. a range or list takes the class of its last member: "200 and 400 gigawatt-seconds"
    # ", and" closes a clause in this book (no serial comma), so it does not join a list
    SEP = re.compile(r"(?:\s*,\s*|\s+(?:and|or|to|through)\s+|\s*–\s*|-to-|\s*/\s*)(?:about\s+)?")
    for i in range(len(toks) - 2, -1, -1):
        a, b = toks[i], toks[i + 1]
        if not SEP.fullmatch(T[a.e:b.s]): continue
        if a.cls == "count" and b.cls in ("share", "unit") and not a.surf.lower().startswith(("a ", "an ")):
            a.cls, a.dim, a.val = b.cls, b.dim, a.val * (b.val / b.num if b.num else 1)
        elif a.cls == "money" and b.cls == "money" and b.scale_set and not a.scale_set:
            a.val, a.scale_set = a.val * abs(b.val / b.num), True
        elif a.cls == "count" and b.cls == "count" and b.scale_set and not a.scale_set:
            a.val, a.scale_set = a.val * (b.val / b.num), True
    return toks

# ---------------------------------------------------------------- context words

STOP = set("""a an the of and or but nor so to in on at by for with from into onto upon over under
above below between across after before since until within without against toward towards
is are was were be been being has have had do does did it its this that these those there here
which who whom whose what when where while whether why how than then as if because not no yes
any all each every both either neither some more most less least much many few other another
such same own only just even also still very too can could may might must shall should will
would one ones about roughly nearly almost around approximately near exactly just under over
per percent year years month months day days hour hours minute minutes second seconds time
times price prices cost costs book chapter chapters ercot site sites mw mwh gw kw w hz s h
average mean total first last new old like see says said say we our you your they their them
he she his her i me my up down out off again once twice half third quarter fifth tenth""".split())
STOP |= set(SMALL) | set(TENS) | set(FRACS) | set(SCALES)

def stem(w):
    w = w.lower().replace("’", "'")
    if w.endswith("'s"): w = w[:-2]
    w = w.rstrip("'")
    if len(w) > 4 and w.endswith("ies"): return w[:-3] + "y"
    if len(w) > 3 and w.endswith("s") and not w.endswith("ss"): return w[:-1]
    return w

def content(words):
    return {w for w in words if w and w not in STOP and len(w) > 1 and not w.isdigit()}

# ---------------------------------------------------------------- matching

NUMERIC = ("count", "money", "share", "unit")

def near(x, y):
    return x is not None and y is not None and abs(x - y) <= 1e-9 * max(1.0, abs(x), abs(y))

def compatible(g, c):
    """2: same value in the same class. 1: a money, share or unit value printed as a
    bare number, as a table cell under a unit header prints it; it counts only in
    context. 0: no match."""
    if g.cls == "count":
        if not (c.cls in NUMERIC and (near(c.num, g.num) or near(c.val, g.val))): return 0
        if c.dim and c.dim.startswith("/"): return 0            # "twice a year" is not a count of two
        return 2 if c.cls == "count" else 1      # "five members" is not "five-minute" unless in context
    if g.cls in ("money", "share", "unit"):
        if c.cls == g.cls and c.dim == g.dim and near(c.val, g.val): return 2
        # a bare table cell under a unit header prints the number, never its scale:
        # "$228 million" is not the 228 of a strike cell, nor "61 Hz" the 61 of "61-fold"
        if g.dim and g.dim.startswith("/"): return 0          # a rate matches only a rate
        return 1 if (c.cls == "count" and not c.scale_set and not g.scale_set
                     and near(c.num, g.num)) else 0
    return 2 if same_calendar(g, c) else 0

def same_calendar(g, c):
    if g.cls == "year":
        return (c.cls == "year" and c.key == g.key) or (c.cls == "date" and c.key.startswith(g.key + "-"))
    if g.cls == "date":
        if c.cls != "date": return False
        if g.key.startswith("--"): return c.key.endswith(g.key[1:]) and len(c.key) in (7, 10)
        return c.key == g.key or (len(g.key) == 7 and c.key.startswith(g.key + "-"))
    if g.cls == "time":
        return c.cls == "time" and c.key == g.key and (g.ampm is None or c.ampm is None or g.ampm == c.ampm)
    if g.cls in ("he", "ordinal"):
        return c.cls == g.cls and c.key == g.key
    return False

def weak(t):
    """A value common enough to turn up by coincidence: a small whole count, a year, a
    clock hour, a position. Such a token counts as contextual only if a shared word sits
    within NEAR words of the chapter's number, not merely in the same passage."""
    if t.cls in ("year", "he", "time", "ordinal"): return True
    return t.cls == "count" and float(t.num).is_integer() and abs(t.num) < 100

NEAR, MID, WIDE = 6, 12, 25

def lookup_keys(t):
    if t.cls in NUMERIC: return [("n", fmt(abs(t.num))), ("v", fmt(abs(t.val)))]
    if t.cls in ("year",): return [("y", t.key)]
    if t.cls == "date": return [("y", t.key[:4]) if not t.key.startswith("--") else ("md", t.key[-5:]),
                                ("md", t.key[-5:]) if len(t.key) == 10 else ("d", t.key)]
    return [(t.cls, t.key)]

def load_sources():
    docs, index = {}, collections.defaultdict(list)
    for path in SOURCES:
        d = Doc(prose_lines(path)); docs[path] = d
        d.toks = tokenize(d.text); d.tpos = [t.s for t in d.toks]
        for t in d.toks:
            for k in set(lookup_keys(t)):
                index[k].append((path, t))
    return docs, index

def neighbours(doc, tok, reach=90):
    """Values of the other specific tokens printed within reach characters, same
    paragraph. Weak values (years, small counts) are too common to be evidence."""
    lo = bisect.bisect_left(doc.tpos, tok.s - reach); hi = bisect.bisect_right(doc.tpos, tok.e + reach)
    out = set()
    for t in doc.toks[lo:hi]:
        if t is tok or t.s == tok.s or weak(t): continue
        a, b = sorted((t.s, tok.s))
        if "¶" in doc.text[a:b]: continue
        out.add(t.value())
    return out

def load_glossary():
    entries, cur = [], None
    for n, line in enumerate(open(GLOSSARY, encoding="utf-8").read().split("\n"), 1):
        code = strip_comment(line)
        m = re.match(r"\s*\\item\[([^\]]*)\]", code)
        if m:
            cur = {"term": clean_line(m.group(1)).strip(), "lines": [n]}
            entries.append(cur)
        elif re.match(r"\s*\\end\{description\}", code):
            cur = None
        elif cur is not None and code.strip():
            cur["lines"].append(n)
    glines = prose_lines(GLOSSARY)
    gdoc = Doc(glines, every_line=True)
    gdoc.toks = tokenize(gdoc.text, glossary=True); gdoc.tpos = [t.s for t in gdoc.toks]
    return entries, glines, gdoc

EXC_COLS = ["entry", "token", "glossary_text", "chapter_ref", "chapter_text", "reason"]

def load_exceptions(docs, raw):
    """Rows of the exceptions file, each checked against the chapter line it pins."""
    rows, problems = [], []
    if not os.path.exists(EXCEPTIONS): return rows, problems
    with open(EXCEPTIONS, newline="", encoding="utf-8") as fh:
        rd = csv.DictReader(fh)
        missing = [c for c in EXC_COLS if c not in (rd.fieldnames or [])]
        if missing:
            return rows, [f"{EXCEPTIONS}:1: missing column(s) {', '.join(missing)}"]
        seen = {}
        for k, r in enumerate(rd, 2):
            r = {c: (r[c] or "").strip() for c in EXC_COLS}
            key = (r["entry"], re.sub(r"\s+", " ", r["token"]).lower(), r["glossary_text"])
            ref, anchor = r["chapter_ref"], r["chapter_text"]
            mm = re.fullmatch(r"(?:book/chapters/)?([\w.-]+\.tex):(\d+)", ref)
            path = "book/chapters/" + mm.group(1) if mm else None
            why = None
            if not r["reason"]: why = "no reason given"
            elif not r["glossary_text"]: why = "no glossary_text (the entry's words around the token)"
            elif not anchor: why = "no chapter_text (the chapter line's words the pin rests on)"
            elif not mm or path not in docs: why = f"chapter_ref '{ref}' is not file:line in a traced file"
            else:
                ln, d = int(mm.group(2)), docs[path]
                if ln > len(d.starts): why = f"{ref} is past the end of the file"
                else:
                    hi = d.starts[ln] if ln < len(d.starts) else len(d.text)
                    if anchor not in raw[path][ln - 1]:
                        moved = [str(i) for i, l in enumerate(raw[path], 1) if anchor in l]
                        why = (f"{ref} no longer prints '{anchor}'"
                               + (f" (it is on line {', '.join(moved)} now)" if moved else " (nor does any line of the file)")
                               + ": the chapter moved or changed, so re-read the glossary number before re-pinning")
                    elif not tokenize(d.text[d.starts[ln - 1]:hi]): why = f"{ref} prints no number in prose"
            if key in seen: why = f"duplicates row {seen[key]} ({key[0]}, {key[1]}, '{key[2]}')"
            if why: problems.append(f"{EXCEPTIONS}:{k}: {why}"); continue
            seen[key] = k
            rows.append({"entry": key[0], "token": key[1], "gtext": key[2], "ref": ref.replace("book/chapters/", ""),
                         "anchor": anchor, "row": k, "toks": []})
    return rows, problems

def trace():
    """One row per glossary token, plus the chapter token each best hit points at."""
    docs, index = load_sources()
    raw = {p: [strip_comment(l.rstrip("\n")) for l in open(p, encoding="utf-8")] for p in SOURCES}
    entries, glines, gdoc = load_glossary()
    entry_of = {n: e for e in entries for n in e["lines"]}
    exc, problems = load_exceptions(docs, raw)
    # where each exception's glossary_text sits: spans of the cleaned glossary text
    for x in exc:
        want = re.sub(r"\s+", " ", clean_line(x["gtext"])).strip()
        x["spans"] = [(m.start(), m.end()) for m in re.finditer(re.escape(want), gdoc.text)] if want else []
    rows = []
    for g in gdoc.toks:
        gl = gdoc.line(g.s)
        e = entry_of.get(gl)
        if e is None: continue                       # the introduction, not an entry
        term = content(stem(w) for w in re.findall(r"[A-Za-z][A-Za-z0-9'’]*", e["term"]))
        g_near, g_mid, g_wide = (content(gdoc.window(g.s, n)) for n in (NEAR, MID, WIDE))
        if g.cls == "ordinal":      # "layer" made it a token, so it is no evidence of the hit
            g_near, g_mid, g_wide = (x - ORD_STEMS for x in (g_near, g_mid, g_wide))
        g_nums = neighbours(gdoc, g)
        entry_text = " ".join(glines[n - 1] for n in e["lines"])
        named = {int(x) for ref in re.findall(r"Chapters?\s+(\d+(?:(?:,\s*|\s+and\s+)\d+)*)", entry_text)
                 for x in re.findall(r"\d+", ref)}
        seen, hits = set(), []
        for k in lookup_keys(g):
            for path, c in index.get(k, []):
                if (path, c.s) in seen: continue
                seen.add((path, c.s))
                strength = compatible(g, c)
                if not strength: continue
                d = docs[path]
                c_near, c_mid, c_wide = (content(d.window(c.s, n)) for n in (NEAR, MID, WIDE))
                shared_nums = g_nums & neighbours(d, c)
                # a cross-class hit (strength 1) needs a shared word as close as a weak value does
                if weak(g) or strength == 1: in_context = bool((g_near | term) & c_near) or bool(shared_nums)
                else: in_context = bool((g_mid | term) & c_wide) or bool(shared_nums)
                if strength == 1 and not in_context: continue   # a cross-class number counts only in context
                mch = re.search(r"chapter-(\d+)\.tex$", path)
                score = (3 * len(g_near & c_near) + 2 * len(g_mid & c_mid) + len(g_wide & c_wide) + 3 * len(shared_nums)
                         + 0.5 * len(term & c_wide) + (1 if mch and int(mch.group(1)) in named else 0))
                # a bare glossary count has elided its unit, so class says nothing about the hit
                rank = strength if g.cls != "count" else 2
                hits.append((in_context, rank, score, -SOURCES.index(path), -c.s,
                             f"{os.path.basename(path)}:{d.line(c.s)}", path, c))
        hits.sort(key=lambda h: h[:5], reverse=True)
        pins = [x for x in exc if x["entry"] == e["term"] and x["token"] == g.surf.lower()
                and any(a <= g.s and g.e <= b for a, b in x["spans"])]
        for x in pins: x["toks"].append((g, hits[0] if hits and hits[0][0] else None))
        if len(pins) > 1:
            problems.append(f"{EXCEPTIONS}: rows {', '.join(str(x['row']) for x in pins)} all pin "
                            f"'{g.surf}' in [{e['term']}] ({GLOSSARY}:{gl})")
        context = ""
        if pins:
            # an exception pins the real home, overriding a coincidental automatic hit
            kind, best, context = "exception", pins[0]["ref"], pins[0]["anchor"]
        elif hits:
            kind, best = ("contextual" if hits[0][0] else "value_only"), hits[0][5]
            context = docs[hits[0][6]].context(hits[0][7].s, hits[0][7].e)
        else:
            kind, best = "untraced", ""
        refs = []
        for h in hits:
            if h[5] not in refs: refs.append(h[5])
        cell = ";".join(refs[:MAX_HITS]) + (f";+{len(refs) - MAX_HITS} more" if len(refs) > MAX_HITS else "")
        rows.append({"entry": e["term"], "glossary_line": gl, "token": g.surf, "value": g.value(),
                     "hits": cell, "best_hit": best, "best_context": context, "match_kind": kind, "_g": g})
    for x in exc:
        where = f"'{x['token']}' at '{x['gtext']}' in [{x['entry']}]"
        if not x["toks"]:
            problems.append(f"{EXCEPTIONS}:{x['row']}: stale, no glossary token {where}: fix the row or delete it")
        elif len(x["toks"]) > 1:
            problems.append(f"{EXCEPTIONS}:{x['row']}: {where} covers {len(x['toks'])} tokens; "
                            f"lengthen glossary_text so that it covers one")
        elif x["toks"][0][1] is not None and x["toks"][0][1][5] == x["ref"]:
            problems.append(f"{EXCEPTIONS}:{x['row']}: stale, {where} is traced in context at {x['ref']} anyway; delete the row")
    return rows, len(entries), problems, len(exc)

# ---------------------------------------------------------------- baseline

COLS = ["entry", "glossary_line", "token", "value", "hits", "best_hit", "best_context", "match_kind"]

def signature(r):
    """What a reviewed row stands for. Line numbers are left out, so a line inserted
    above a chapter's number, or a glossary entry added above, changes nothing."""
    return (r["value"], r["match_kind"], r["best_hit"].split(":")[0], r.get("best_context", ""))

def show_row(r):
    return (f"{r['value']}  {r['best_hit'] or '-'}  {r['match_kind']}"
            + (f"  \"{r['best_context']}\"" if r.get("best_context") else ""))

def compare(old, new):
    """Rows whose value, match kind, best-hit file or best-hit context differ from the
    committed trace map, aligned entry by entry."""
    def by_entry(rows):
        d = collections.OrderedDict()
        for r in rows: d.setdefault(r["entry"], []).append(r)
        return d
    o, n = by_entry(old), by_entry(new)
    out = []
    for entry in list(n) + [x for x in o if x not in n]:
        a, b = o.get(entry, []), n.get(entry, [])
        if [signature(r) for r in a] == [signature(r) for r in b]: continue
        sm = difflib.SequenceMatcher(None, [r["value"] for r in a], [r["value"] for r in b], autojunk=False)
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            pairs = list(zip(range(i1, i2), range(j1, j2)))
            for i, j in pairs:
                if signature(a[i]) != signature(b[j]):
                    out.append(f"CHANGED {GLOSSARY}:{b[j]['glossary_line']} [{entry}] '{a[i]['token']}' -> '{b[j]['token']}'\n"
                               f"    committed  {show_row(a[i])}\n    now        {show_row(b[j])}")
            for i in range(i1 + len(pairs), i2):
                out.append(f"GONE    [{entry}] '{a[i]['token']}'\n    committed  {show_row(a[i])}")
            for j in range(j1 + len(pairs), j2):
                out.append(f"NEW     {GLOSSARY}:{b[j]['glossary_line']} [{entry}] '{b[j]['token']}'\n    now        {show_row(b[j])}")
    return out

APPENDIX = "book/chapters/appendix-methodology.tex"
NOTE = re.compile(r"%\s*src:\s*python3 analysis/checks/check_glossary_trace\.py:\s*(\d+) quantitative tokens in "
                  r"(\d+) glossary entries, (\d+) traced in context[^,]*, (\d+) pinned by the (\d+) rows")

def appendix_note(counts):
    """The appendix quotes this check's totals in a src comment; they must be this run's."""
    for n, line in enumerate(open(APPENDIX, encoding="utf-8"), 1):
        m = NOTE.search(line)
        if m:
            said = tuple(int(x) for x in m.groups())
            if said == counts: return None
            names = ("tokens", "entries", "in context", "pinned tokens", "exception rows")
            return (f"{APPENDIX}:{n}: the src comment naming this check says "
                    + ", ".join(f"{k} {v}" for k, v in zip(names, said)) + "; this run has "
                    + ", ".join(f"{k} {v}" for k, v in zip(names, counts)))
    return f"{APPENDIX}: no src comment quotes this check's totals"

def main():
    show = sys.argv[sys.argv.index("--show") + 1] if "--show" in sys.argv else None
    update = "--update" in sys.argv
    rows, n_entries, problems, n_exc = trace()
    for p in problems: print("ERROR   " + p)
    bad = 0
    for r in rows:
        if r["match_kind"] == "untraced":
            bad += 1
            print(f"ERROR   {GLOSSARY}:{r['glossary_line']}: [{r['entry']}] '{r['token']}' ({r['value']}) is printed in no chapter prose")
        elif r["match_kind"] == "value_only":
            bad += 1
            print(f"ERROR   {GLOSSARY}:{r['glossary_line']}: [{r['entry']}] '{r['token']}' ({r['value']}) is printed only "
                  f"out of context, at {r['best_hit']}: pin it or fix it")
    kinds = collections.Counter(r["match_kind"] for r in rows)
    note = appendix_note((len(rows), n_entries, kinds["contextual"], kinds["exception"], n_exc))
    if note: print("ERROR   " + note)
    old = list(csv.DictReader(open(OUT, newline="", encoding="utf-8"))) if os.path.exists(OUT) else []
    diffs = compare(old, rows)
    if show:
        for r in rows:
            if r["match_kind"] == show:
                print(f"  {r['glossary_line']:4} [{r['entry']}] {r['token']!r} {r['value']} -> {r['best_hit'] or '-'}  ({r['hits']})")
    by_cls = collections.Counter(r["_g"].cls for r in rows)
    print(f"\n{len(rows)} quantitative tokens in {n_entries} glossary entries; {n_exc} exception rows")
    print("  by class: " + ", ".join(f"{k} {v}" for k, v in sorted(by_cls.items(), key=lambda x: (-x[1], x[0]))))
    print("  by match: " + ", ".join(f"{k} {kinds[k]}" for k in ("contextual", "value_only", "exception", "untraced")))
    errors = len(problems) + bad + (1 if note else 0)
    if update:
        if problems or bad:
            print(f"\n{OUT} NOT updated: fix the errors above first")
            sys.exit(1)
        with open(OUT, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=COLS, lineterminator="\n", extrasaction="ignore")
            w.writeheader(); w.writerows(rows)
        print(f"\n{OUT} updated: {len(diffs)} row change(s) accepted")
    elif diffs:
        print(f"\n{len(diffs)} row(s) differ from the reviewed trace map {OUT}:")
        for x in diffs: print(x)
        print(f"Read each: fix the glossary or the chapter, or, if the new best hit is the real home, "
              f"accept it with --update and commit {OUT} with the edit.")
        errors += len(diffs)
    print(f"\n{errors} error(s)")
    sys.exit(1 if errors else 0)

if __name__ == "__main__":
    main()
