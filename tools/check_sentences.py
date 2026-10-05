#!/usr/bin/env python3
"""Fail on a long sentence in the README files.

A sentence ends with ".", "!" or "?" before a space, or at the end of a
paragraph or list item. An ellipsis ("...") does not end a sentence.
Table rows, headings, code blocks and HTML comments are skipped. Inline code
counts as one word, a link counts as its text, and fact IDs in parentheses,
such as "(SET-20, R1-19)", do not count. A word holds a letter or a digit.

Usage: check_sentences.py [--max N] [file ...]
  (default: 25 words, README.md and case-studies/*/README.md)
Exit 0 = no long sentence, 1 = long sentences (printed), 2 = usage error.
"""
import glob
import re
import sys

FACT_IDS = re.compile(r"\((?:[A-Z][A-Z0-9]*-\d+(?: to (?:[A-Z][A-Z0-9]*-)?\d+)?(?:, | and )?)+\)")
LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
CODE = re.compile(r"`[^`]*`")
END = re.compile(r"(?<![.][.])(?<=[.!?])['\"*_]*\s+(?=\S)")
WORD = re.compile(r"[A-Za-z0-9]")
ITEM = re.compile(r"^\s*(?:[-*]|\d+\.)\s+")


def blocks(text):
    """Yield (line number, text) for each paragraph or list item outside tables and code."""
    buf, start, fence = [], 0, False
    for n, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if s.startswith("```"):
            fence = not fence
            s = ""
        if fence or s.startswith(("|", "#", "<!--")) or not s or ITEM.match(line):
            if buf:
                yield start, " ".join(buf)
            buf = []
            if fence or not s or s.startswith(("|", "#", "<!--", "```")):
                continue
            s = ITEM.sub("", line).strip()
        if not buf:
            start = n
        buf.append(s)
    if buf:
        yield start, " ".join(buf)


def words(sentence):
    s = FACT_IDS.sub("", sentence)
    s = LINK.sub(r"\1", s)
    s = CODE.sub("code", s)
    return sum(1 for w in s.split() if WORD.search(w))


def check(path, limit):
    long = []
    with open(path, encoding="utf-8") as f:
        text = f.read()
    for line, block in blocks(text):
        for sentence in END.split(block):
            n = words(sentence)
            if n > limit:
                long.append(f"{path}:{line}: {n} words: {sentence[:90]}...")
    return long


def main(argv):
    limit = 25
    if argv[:1] == ["--max"]:
        if len(argv) < 2 or not argv[1].isdigit():
            print(__doc__, file=sys.stderr)
            return 2
        limit, argv = int(argv[1]), argv[2:]
    files = argv or ["README.md"] + sorted(glob.glob("case-studies/*/README.md"))
    long = [hit for path in files for hit in check(path, limit)]
    for hit in long:
        print(hit)
    if long:
        print(f"check_sentences.py: {len(long)} sentence(s) over {limit} words", file=sys.stderr)
        return 1
    print(f"check_sentences.py: no sentence over {limit} words ({len(files)} file(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
