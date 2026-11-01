#!/usr/bin/env python3
"""The known silent windows page and the gaps the ADRs record agree (ADR 0145).

What this does NOT do, so nobody reads a green run as wider than it is:
  - It does not judge whether a gap is a window. spike/silent-windows.tsv carries that judgement,
    and a reviewer reads it; the check only refuses a gap nobody filed.
  - An ADR numbered 0145 or earlier is read through the vocabulary alone. A gap written there in
    other words is not seen; the page was drawn from a reading of those ADRs, not from the grep.
  - The vocabulary is matched line by line, so a phrase an ADR wraps across two lines is not
    matched there.
  - DESIGN.md and docs/report-schema.md are not scanned. A row may cite them as a source, and the
    row's anchor is held to them, but a new gap written only there is not caught.

Exit 0 when they agree, 1 when they do not, 2 when the check could not read what it needs or the
vocabulary no longer reaches the gaps it was built from — never read a 2 as a pass.
"""

import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

VOCABULARY = re.compile(
    r"residual|residues?|left open|knowingly|stays? outside|windows? stays?|window remains|"
    r"remains? (open|unseen|invisible|uncovered|outside)|rides? a PASS|silent(ly)? (PASS|pass)|"
    r"not seen|unseen|invisible|cannot see|can.t see|blind spot|is not refused|not refused\.|"
    r"passes? (silently|unseen)|goes unrecorded|stays unrecorded|recorded by neither",
    re.IGNORECASE)

SECTION_AFTER = 145
SECTION = "## Residual windows"

# If one of these falls out of the vocabulary, the vocabulary broke, not the record.
FLOOR = [
    (2, "knowingly left open"),
    (13, "Two windows stay"),
    (34, "The residual is"),
    (53, "residual"),
    (137, "One shape is not refused"),
]


class Broken(Exception):
    pass


def read(path):
    with open(path) as f:
        return f.read()


def adr_files():
    files = {}
    for path in sorted(os.listdir(os.path.join(ROOT, "docs/adr"))):
        if re.fullmatch(r"\d{4}-.+\.md", path):
            number = int(path[:4])
            if number in files:
                raise Broken("ADR %04d is two files; spike/check-adr-numbering.sh says which" % number)
            files[number] = os.path.join(ROOT, "docs/adr", path)
    if len(files) < 100:
        raise Broken("found %d ADRs; the directory holds far more" % len(files))
    return files


def section_items(lines):
    stripped = [l.strip() for l in lines]
    if SECTION not in stripped:
        return None
    items = []
    for line in stripped[stripped.index(SECTION) + 1:]:
        if line.startswith("#"):
            break
        if line and line not in ("None", "None.") and not line.startswith("None:"):
            items.append(line)
    return items


def read_table(adrs):
    rows = []
    path = os.path.join(ROOT, "spike/silent-windows.tsv")
    for n, line in enumerate(read(path).splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 3 or not all(fields):
            raise Broken("spike/silent-windows.tsv:%d is not source<TAB>anchor<TAB>window or reason" % n)
        source, anchor, filed = fields
        if source.isdigit() and int(source) not in adrs:
            raise Broken("spike/silent-windows.tsv:%d names ADR %s, which does not exist" % (n, source))
        file = adrs[int(source)] if source.isdigit() else os.path.join(ROOT, source)
        rows.append({"line": n, "source": source, "file": file, "anchor": anchor, "filed": filed})
    return rows


def page_windows():
    windows = {}
    for line in read(os.path.join(ROOT, "docs/silent-windows.md")).splitlines():
        m = re.match(r"\| `([a-z0-9-]+)` \|", line)
        if m:
            where = line.rstrip(" |").rsplit(" | ", 1)[-1]
            sources = {"%04d" % int(a) for a in re.findall(r"ADR (\d{4})", where)}
            sources |= {f for f in ("DESIGN.md", "docs/report-schema.md") if os.path.basename(f) in where}
            windows[m.group(1)] = sources
    return windows


def main():
    try:
        adrs = adr_files()
        rows = read_table(adrs)
        windows = page_windows()
        texts = {path: read(path) for path in adrs.values()}
        for row in rows:
            if row["file"] not in texts:
                texts[row["file"]] = read(row["file"])
    except (OSError, Broken) as exc:
        print("  BROKEN %s" % exc)
        print("         could not read what it needs — never read a 2 as a pass")
        return 2

    lines = {path: texts[path].splitlines() for path in adrs.values()}
    for number, words in FLOOR:
        if not any(words in l and VOCABULARY.search(l) for l in lines[adrs[number]]):
            print("  BROKEN ADR %04d's %r is no longer reached by the vocabulary" % (number, words))
            return 2
    if not windows:
        print("  BROKEN docs/silent-windows.md lists no window; its table's first column was not found")
        return 2

    failures = []
    page = read(os.path.join(ROOT, "docs/silent-windows.md"))
    for path in sorted(set(re.findall(r"`([A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+)`", page))):
        if not os.path.exists(os.path.join(ROOT, path)):
            failures.append("docs/silent-windows.md names %s, which does not exist" % path)
    for row in rows:
        # Not read as a reason: a reason is a sentence, and a bare kebab-case word is a window the page lost.
        if re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)+", row["filed"]) and row["filed"] not in windows:
            failures.append("row %d files under window %r, which docs/silent-windows.md does not list"
                            % (row["line"], row["filed"]))
        count = texts[row["file"]].count(row["anchor"])
        if count != 1:
            failures.append("row %d: %r occurs %d times in %s; an anchor names one place"
                            % (row["line"], row["anchor"], count, row["source"]))
    for window, sources in sorted(windows.items()):
        filed_from = {r["source"].zfill(4) if r["source"].isdigit() else r["source"]
                      for r in rows if r["filed"] == window}
        if not filed_from:
            failures.append("docs/silent-windows.md lists %r, which no row files from a source" % window)
        for source in sorted(sources - filed_from):
            failures.append("docs/silent-windows.md gives %s for %r, and no row files it from there" % (source, window))

    anchors = {}
    for row in rows:
        anchors.setdefault(row["file"], []).append(row["anchor"])
    hits = 0
    for number, path in sorted(adrs.items()):
        found = [l for l in lines[path] if VOCABULARY.search(l) and l.strip() != SECTION]
        items = section_items(lines[path])
        if number > SECTION_AFTER:
            if items is None:
                failures.append("ADR %04d has no %r section; write one, even if it says None" % (number, SECTION))
            else:
                found += items
        for line in found:
            hits += 1
            if not any(a in line for a in anchors.get(path, [])):
                failures.append("ADR %04d records a gap no row files: %s" % (number, line.strip()[:120]))

    if failures:
        for f in failures:
            print("  FAILED %s" % f)
        print("         file it in spike/silent-windows.tsv, under a window docs/silent-windows.md lists or with"
              " the reason it is not one")
        return 1
    print("  %d lines across %d ADRs filed by %d rows; docs/silent-windows.md lists %d windows"
          % (hits, len(adrs), len(rows), len(windows)))
    print("  ok   every gap an ADR records is filed, and every listed window is filed from its sources")
    return 0


if __name__ == "__main__":
    sys.exit(main())
