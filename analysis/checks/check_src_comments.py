#!/usr/bin/env python3
"""check_src_comments.py -- flag prose that follows a '% src:' comment on the same
source line, which LaTeX silently drops. Run from the repo root:
    python3 analysis/checks/check_src_comments.py [--count] [book/chapters/*.tex]
--count also prints the tallies the appendix quotes.
Heuristic: the text after the first unescaped '%' is a comment; if that tail
contains LaTeX prose markers (\\autocite, \\ref, \\$, \\textbf, \\emph, a '~' tie)
or a sentence-looking run ('. ' followed by a capital and then 60+ characters),
the line is flagged for a human look.

Two tiers, because a check that is always red teaches everyone to ignore it:
  ERROR    a LaTeX text command after the '%' (\\textit, \\autocite, \\ref, ...).
           No source note has a reason to contain one, so this is prose that
           was meant to print and is being swallowed. Exit status 1.
  warning  prose-like sentences inside the comment. Usually a deliberate audit
           note; listed for a human look but never fails the run.
The ERROR tier exists because the second tier was not enough: chapter 1's
opening paragraph lost five sentences, the book's thesis among them, behind a
mid-line src comment. The old marker list lacked \\textit, so the line surfaced
only as one soft flag among eighteen, and nobody saw it. Two more swallowed
sentences, in chapters 5 and 9, turned up later with no full stop before them,
which neither tier could see; APPENDED below catches that shape.

ORPHAN, also an ERROR: a src, fig-src or tab-src note alone on its line. That
is valid LaTeX, so this rule enforces the house convention rather than a LaTeX
fact: a note ends the line of the sentence it sources, so a note on a line of
its own belongs to no sentence, and the prose it sourced was cut. The appendix
carried one from 074f5e1, which cut its paragraph, to cd27322, and neither
tier above could see it, because both read only the text after the '%'.
"""
import re, sys, glob, os, collections

def comment_tail(line):
    i = 0
    while True:
        j = line.find("%", i)
        if j < 0: return None
        if j > 0 and line[j - 1] == "\\": i = j + 1; continue
        return line[j:]

FUNCTION_WORDS = {"the", "a", "an", "of", "and", "that", "which", "is", "was", "were", "to", "in", "on", "for", "with", "it", "its", "this", "as", "at", "by", "from", "but", "not", "or", "be", "are", "has", "have", "had", "than", "so", "into", "when", "because"}

def prose_like(sentence):
    words = re.findall(r"[A-Za-z']+", sentence)
    return len(sentence) >= 60 and sum(w.lower() in FUNCTION_WORDS for w in words) >= 5

# Text commands that only make sense in printed prose. Calibrated on 447 src
# comments: this list matches exactly one, the real swallowed paragraph.
LATEX_PROSE = re.compile(r"\\(textit|textsc|textsf|texttt|textbf|emph|underline|autocite|cite[a-z]*"
                         r"|parencite|textcite|footnote|ref|eqref|autoref|label|url|href|S)\b|~\\")

# The second shape, found twice after the first was fixed: a sentence appended
# to the comment with no full stop at all ("...not the ramp The loop must move
# only when moving pays."), which the sentence splitter below cannot see. The
# signal is a capitalised function word straight after a lowercase word with no
# punctuation between. Source notes put proper nouns there, never "The" or
# "What". "A" is left out because notes use it as a label ("rules A and B").
FW = (r"(The|This|That|These|Those|It|Its|An|In|On|For|But|And|So|Every|Each|No|If"
      r"|When|What|Why|How|We|Our|Their|There|Then|Once|Only|Now)")
APPENDED = re.compile(r"[a-z0-9)\]] " + FW + r" [a-z]")

def suspicious(tail):
    """Return (level, reason) or None."""
    body = tail[1:]
    m = LATEX_PROSE.search(body)
    if m: return ("ERROR", f"LaTeX '{m.group(0)}' after the comment: this prose never prints")
    m = APPENDED.search(body)
    if m: return ("ERROR", f"sentence appended with no full stop at '{body[m.start()+2:m.start()+42]}': this prose never prints")
    # sentences after the comment's first one: a source note rarely runs to several prose-like sentences
    parts = re.split(r"(?<=[.)])\s+(?=[A-Z])", body)
    for sent in parts[1:]:
        if prose_like(sent): return ("warning", "prose-like sentence after comment: " + sent[:90])
    return None

# --count prints the tallies the appendix quotes: the src comments per file (by
# the comment_tail rule above, not by string match), chapters 1-3 and 9 by kind,
# the analysis/checks inventory and which of its scripts each chapter's source
# notes (src, fig-src and tab-src) name. A comment names a script if it names a
# .R or .py file, and a committed data file if it names a path under
# analysis/data/. Every "% src:" string that does not open a src comment is
# listed with its line, so a string count can be reconciled with the comment
# count.
COUNT = "--count" in sys.argv
files = [a for a in sys.argv[1:] if a != "--count"] or sorted(glob.glob("book/chapters/*.tex"))
NAMES_SCRIPT = re.compile(r"[A-Za-z0-9_]\.(R|py)\b")
NAMES_DATA = re.compile(r"analysis/data/")
SCRIPT_NAME = re.compile(r"([A-Za-z0-9_]+\.(?:R|py))\b")
CHECKS = {os.path.basename(p) for p in glob.glob("analysis/checks/*.R") + glob.glob("analysis/checks/*.py")}
src = collections.Counter(); script = collections.Counter(); script_or_data = collections.Counter()
notes = collections.Counter(); named = collections.defaultdict(set); strings = 0; strays = []
errors = warnings = 0
for f in files:
    for n, line in enumerate(open(f, encoding="utf-8"), 1):
        tail = comment_tail(line.rstrip("\n"))
        start = len(line.rstrip("\n")) - len(tail) if tail else -1
        for m in re.finditer(r"% src:", line):
            strings += 1
            if m.start() == start: continue
            where = "escaped, prints" if m.start() > 0 and line[m.start() - 1] == "\\" else "inside a comment"
            strays.append(f"{f}:{n} ({where})")
        if not tail or not tail.lstrip("%").lstrip().startswith(("src:", "tab-src:", "fig-src:")): continue
        kind = tail.lstrip("%").lstrip().split(":", 1)[0]
        if kind == "src":
            src[f] += 1
            s = bool(NAMES_SCRIPT.search(tail))
            script[f] += s
            script_or_data[f] += s or bool(NAMES_DATA.search(tail))
        else:
            notes[kind] += 1
        named[f] |= {x for x in SCRIPT_NAME.findall(tail) if x in CHECKS}
        hit = (("ERROR", "source note on a line of its own: a note ends its sentence's line; "
                "if the prose above it was cut, this is an orphan")
               if not line[:start].strip() else suspicious(tail))
        if not hit: continue
        level, why = hit
        if level == "ERROR": errors += 1
        else: warnings += 1
        print(f"{level:7} {f}:{n}: {why}")
        if level == "ERROR": print(f"        {tail[:200]}{'...' if len(tail) > 200 else ''}")
if COUNT:
    chap = {f: int(m.group(1)) for f in files if (m := re.search(r"chapter-(\d+)\.tex$", f))}
    ch = sum(src[f] for f in chap)
    pre = sum(v for f, v in src.items() if f.endswith("preface.tex"))
    app = sum(v for f, v in src.items() if f.endswith("appendix-methodology.tex"))
    print(f"\nsrc comments: {sum(src.values())} in all: chapters 1-10 {ch} + preface {pre} = {ch + pre}, appendix {app}")
    for f in sorted(chap, key=chap.get):
        print(f"  chapter {chap[f]:2}: {src[f]:3} src, {script[f]:3} naming a script, {script_or_data[f]:3} a script or an analysis/data file")
    first3 = [f for f in chap if chap[f] <= 3]
    print(f"  chapters 1-3: {' + '.join(str(src[f]) for f in sorted(first3, key=chap.get))} = {sum(src[f] for f in first3)} src, "
          f"{sum(script_or_data[f] for f in first3)} a script or an analysis/data file")
    print(f"string matches of '% src:': {strings}, the src comments plus {len(strays)} that open none: " + "; ".join(strays))
    print(f"fig-src {notes['fig-src']}, tab-src {notes['tab-src']} (not in the totals)")
    r = sorted(c for c in CHECKS if c.endswith(".R")); py = sorted(c for c in CHECKS if c.endswith(".py"))
    chk = [c for c in py if c.startswith("check_")]
    print(f"\nanalysis/checks: {len(r)} .R, {len(py) - len(chk)} .py analysis scripts, {len(chk)} .py checkers ({', '.join(chk)})")
    for f in sorted(chap, key=chap.get):
        print(f"  chapter {chap[f]:2} source notes name {len(named[f])}: {', '.join(sorted(named[f])) or 'none'}")
print(f"\n{errors} error(s), {warnings} warning(s)")
sys.exit(1 if errors else 0)
