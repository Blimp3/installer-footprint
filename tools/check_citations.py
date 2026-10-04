#!/usr/bin/env python3
"""Check the excerpt citations in a FACTS file.

A citation looks like [`run1-install.unified-log.txt:4378,4416`](run1-install.unified-log.txt#L136)
or, for a snapshot excerpt with several sections, [`file.txt#launchd:9-10`](file.txt#L11).
The numbers are raw line numbers, and every excerpt line starts with the raw
line number. The check fails if a cited raw line is missing from the excerpt
(or from the named section), or if the #L anchor does not open at the first
cited line.

Usage: check_citations.py [FACTS.md ...]   (default: case-studies/*/evidence/FACTS*.md)
Exit 0 = all citations resolve, 1 = mismatches (printed), 2 = usage error.
"""
import glob
import os
import re
import sys

CITE = re.compile(r"\[`([^`:#]+?)(?:#([A-Za-z0-9_-]+))?:([0-9,-]+)`\]\(([^)#]+)#L([0-9]+)\)")
RAW = re.compile(r"^\s*([0-9]+)  ")
SOURCE = re.compile(r"^# source: (\S+)")


def sections(path):
    """Map section name (and '' for the whole file) to {raw line: file line}."""
    out = {"": {}}
    name = ""
    with open(path, encoding="utf-8", errors="replace") as f:
        for n, line in enumerate(f, 1):
            m = SOURCE.match(line)
            if m:
                name = os.path.splitext(os.path.basename(m.group(1)))[0]
                out.setdefault(name, {})
                continue
            m = RAW.match(line)
            if m:
                raw = int(m.group(1))
                out[name].setdefault(raw, n)
                out[""].setdefault(raw, n)
    return out


def raw_lines(spec):
    nums = []
    for part in spec.split(","):
        a, _, b = part.partition("-")
        nums.extend(range(int(a), int(b or a) + 1))
    return nums


def check(facts):
    base = os.path.dirname(facts)
    cache, bad, count = {}, [], 0
    with open(facts, encoding="utf-8") as f:
        text = f.read()
    for m in CITE.finditer(text):
        shown, sec, spec, target, anchor = m.group(1), m.group(2) or "", m.group(3), m.group(4), int(m.group(5))
        count += 1
        where = f"{facts}: [{shown}{'#' + sec if sec else ''}:{spec}]"
        if shown != target:
            bad.append(f"{where} links to {target}")
            continue
        path = os.path.join(base, target)
        if not os.path.isfile(path):
            bad.append(f"{where}: no such excerpt")
            continue
        if path not in cache:
            cache[path] = sections(path)
        lines = cache[path].get(sec)
        if lines is None:
            bad.append(f"{where}: no section '{sec}'")
            continue
        wanted = raw_lines(spec)
        missing = [n for n in wanted if n not in lines]
        if missing:
            bad.append(f"{where}: raw lines not in the excerpt: {missing[:5]}")
        elif lines[wanted[0]] != anchor:
            bad.append(f"{where}: anchor #L{anchor}, first cited line is at #L{lines[wanted[0]]}")
    return count, bad


def main(argv):
    files = argv or sorted(glob.glob("case-studies/*/evidence/FACTS*.md"))
    if not files:
        print("check_citations.py: no FACTS file found", file=sys.stderr)
        return 2
    total, problems = 0, []
    for facts in files:
        n, bad = check(facts)
        total += n
        problems += bad
    for p in problems:
        print("BAD " + p)
    if problems:
        print(f"check_citations.py: {len(problems)} of {total} citations do not resolve", file=sys.stderr)
        return 1
    print(f"check_citations.py: {total} citations resolve ({len(files)} file(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
