#!/usr/bin/env python3
"""Render the checker cookbook's recipe blocks from the committed checkers (#276).

    python3 spike/render-cookbook.py emit            # every block, with markers, to stdout
    python3 spike/render-cookbook.py write [PAGE]    # rewrite the blocks in place
    python3 spike/render-cookbook.py check [PAGE]    # compare the page against a fresh render

The manifest below is the trust root for *which* checker each recipe shows;
`docs/checker-cookbook.md`'s recipe blocks are this script's output, and `check` fails if
the page and a fresh render diverge. Editing a block by hand is therefore a check failure.

This is the third instance of a shape the repository already uses twice — `count.py`
holding `docs/unknown-rate.md`, and `render-audit.sh` holding the two tables in
`docs/freeze-audit.md`. Nothing here is a new mechanism. It is written in Python rather
than sh, like `count.py`, because every operation below is exact block surgery
(no newline translation at either end):
a command substitution eats the trailing newline of a checker that ends in one, and
that difference is invisible in a terminal and fatal to `check`.

## Why the page shows the checker rather than pointing at it

`#276`: the page opened by promising "Everything below is a real committed checker …
nothing was invented for this page" and then gave four pointers into `spike/`. A reader
could not copy anything; the promise was true only in the sense of *naming* a file. The
blocks make it true in the sense of *showing* one.

Pasting the text by hand would make the page correct once. These four checkers are edited
— the buku one carries the history of a leg it dropped — so a hand-pasted copy only ever
gets more wrong, silently, and the page's opening sentence would go quietly false.

## What `check` asserts, and why each clause is there

Per recipe, before comparing anything:

  - the BEGIN marker appears exactly once and the END marker appears exactly once.
    Duplicated markers are the failure the freeze audit's renderer already met: with two
    BEGINs a naive slice can compare a region nobody edits and stay green forever.
  - BEGIN comes before END, and the region between them is not empty. An inverted or
    empty region also slices "successfully" into something that trivially matches.
  - the recipe's own `## Recipe N` heading appears exactly once, and both markers fall
    between it and the next heading of level 1 or 2. Review moved recipe 1's whole block under
    `## Failure patterns`: every clause above still held, the comparison still passed,
    and Recipe 1 showed no checker. A block that matches its source in the wrong place
    leaves the promise false and the check green.

then the region must equal a fresh render of that recipe -- the file's characters read
without newline translation, plus a trailing newline where the file lacks one. That one
normalisation is the whole of it, and it is why these notes do not say "byte-exact".

## The fence is chosen from the source, not fixed at three backticks

A checker containing a ``` line would close the block early: the page and a fresh render
would still agree — `check` green — while the Markdown around it broke. None
of today's four contains one. The fence is one backtick longer than the longest run in
the file, which is what CommonMark requires, so the check's green keeps meaning "the page
renders what the file holds" rather than only "the bytes agree".

## The adaptation line is generated too

The owner's requirement for this page is that a reader can copy a recipe and start. Two of
the four run as they stand; two name paths and binaries of the target they were written
for. Each recipe therefore carries one line saying what to swap — and that line lives
*inside* the markers, from the table below, because a hand-written one outside them can be
deleted or attached to the wrong recipe with `check` still green.
"""

import sys
from pathlib import Path

# recipe key -> (marker key, the page heading the block must sit under, checker path,
#                what a reader swaps)
RECIPES = [
    (
        "recipe 1",
        "## Recipe 1",
        "spike/check.sh",
        "Swap `TOY` for your own binary and the two subcommands (`doctor`, `load-key`) "
        "for your target's diagnostic and the operation that depends on the same state.",
    ),
    (
        "recipe 2",
        "## Recipe 2",
        "spike/loop-closure-timew/define/check.sh",
        "Swap `timew export` / `timew undo` for your target's reader and recovery command, "
        "and the interval keying for whatever your reader's records are identified by.",
    ),
    (
        "recipe 3",
        "## Recipe 3",
        "spike/dogfood-watson/check.sh",
        "Swap `watson frames` for your target's own reader — the whole recipe is that "
        "one command.",
    ),
    (
        "recipe 4",
        "## Recipe 4",
        "spike/assisted/buku/ops/check.sh",
        "Swap `XDG_DATA_HOME`, the database path, the bystander query and its expected "
        "row for your target's; the leg ORDER is the part to copy unchanged.",
    ),
]

PAGE = "docs/checker-cookbook.md"


class Failure(Exception):
    pass


def begin(key):
    return "<!-- BEGIN generated: cookbook %s (render-cookbook.py) -->" % key


def end(key):
    return "<!-- END generated: cookbook %s -->" % key


def fence_for(text):
    """One backtick longer than the longest backtick run in the source, minimum three."""
    longest, run = 0, 0
    for ch in text:
        run = run + 1 if ch == "`" else 0
        longest = max(longest, run)
    return "`" * max(3, longest + 1)


def body(root, path, swap):
    """The region between the markers, exclusive, ending in a newline."""
    # newline="" so no CRLF is translated on the way in: `read_text` would fold a
    # CRLF checker to LF, render it that way, and compare its own output with itself --
    # green, while the page did not show the file. The ONE thing normalised is a missing
    # final newline, added so the closing fence gets its own line; that is why the
    # records say "the file's bytes, plus a trailing newline where the file lacks one"
    # rather than "byte-exact".
    with open(root / path, "r", encoding="utf-8", newline="") as fh:
        text = fh.read()
    f = fence_for(text)
    if not text.endswith("\n"):
        text += "\n"
    return (
        "_Generated by `python3 spike/render-cookbook.py emit` — "
        "do not edit between the markers._\n"
        "\n"
        "To adapt this: %s\n"
        "\n"
        "%s\n"
        "%ssh\n"
        "%s"
        "%s\n" % (swap, "`" + path + "`:", f, text, f)
    )


def block(root, key, path, swap):
    return "%s\n%s%s\n" % (begin(key), body(root, path, swap), end(key))


def outside_generated(lines):
    """Line indices that are page prose -- everything not inside a generated region.

    A checker is allowed to contain a line starting with `##`; two of the four already
    open with `#`. Scanning every line for headings makes a checker's own comment end a
    section, or count as a second `## Recipe 1`, and review turned a valid page red both
    ways. Headings are looked for in the prose only.

    Marker lines are located by exact match, so a checker holding one of them verbatim
    would be counted as a duplicate and refused -- fail-closed, and the marker text
    carries this script's own filename, so it is not a line a checker writes by accident.
    """
    inside, spans = False, set()
    for i, ln in enumerate(lines):
        if any(ln == begin(k) for k, _h, _p, _s in RECIPES):
            inside = True
        elif any(ln == end(k) for k, _h, _p, _s in RECIPES):
            inside = False
            spans.add(i)
            continue
        if inside:
            spans.add(i)
    return [i for i in range(len(lines)) if i not in spans]


def locate(lines, key, head, page_path):
    """Line indices of the two markers, with every clause asserted before any slicing.

    Cardinality and ordering are not enough. Review moved recipe 1's whole block under
    `## Failure patterns` and every marker clause below still held, so the comparison
    still passed while Recipe 1 showed no checker at all -- the promise false, the check
    green. The block is therefore bound to its own section: the heading must be unique,
    and both markers must fall between it and the next heading of level 1 or 2. `###` and
    deeper do not end a section -- a recipe may have sub-headings and they belong to it.
    An `#` does end one, which the first version of this clause missed: review put an h1
    between the heading and the block and the page was accepted again.
    """
    b, e = begin(key), end(key)
    bs = [i for i, ln in enumerate(lines) if ln == b]
    es = [i for i, ln in enumerate(lines) if ln == e]
    if len(bs) != 1:
        raise Failure("%s: %d BEGIN markers for %s, wanted exactly 1" % (page_path, len(bs), key))
    if len(es) != 1:
        raise Failure("%s: %d END markers for %s, wanted exactly 1" % (page_path, len(es), key))
    if bs[0] >= es[0]:
        raise Failure("%s: %s's END marker is not after its BEGIN" % (page_path, key))
    if es[0] - bs[0] < 2:
        raise Failure("%s: %s's generated region is empty" % (page_path, key))

    prose = outside_generated(lines)
    hs = [i for i in prose if lines[i] == head or lines[i].startswith(head + " ")]
    if len(hs) != 1:
        raise Failure("%s: %d '%s' headings, wanted exactly 1" % (page_path, len(hs), head))
    nxt = next((i for i in prose
                if i > hs[0] and (lines[i].startswith("## ") or lines[i].startswith("# "))),
               len(lines))
    if not (hs[0] < bs[0] and es[0] < nxt):
        raise Failure("%s: %s's block is not inside the '%s' section (heading at line %d, "
                      "block at lines %d-%d, section ends at line %d)"
                      % (page_path, key, head, hs[0] + 1, bs[0] + 1, es[0] + 1, nxt))
    return bs[0], es[0]


def cmd_emit(root):
    for key, head, path, swap in RECIPES:
        sys.stdout.write(block(root, key, path, swap))
        sys.stdout.write("\n")
    return 0


def read_page(root, page_path):
    """The page's own characters, with no newline translation.

    `Path.read_text()` defaults to newline=None, which folds CRLF to LF on the way in.
    Fixing only `body()` left the asymmetry review measured: a CRLF checker rendered into
    the page, then compared, failed on its own output. Both ends read the same way now,
    and `write` writes with newline="" so it does not rewrite line endings it was not
    asked to touch.
    """
    with open(root / page_path, "r", encoding="utf-8", newline="") as fh:
        return fh.read()


def cmd_write(root, page_path):
    lines = read_page(root, page_path).split("\n")
    for key, head, path, swap in RECIPES:
        b, e = locate(lines, key, head, page_path)
        fresh = body(root, path, swap).split("\n")[:-1]
        lines[b + 1 : e] = fresh
    with open(root / page_path, "w", encoding="utf-8", newline="") as fh:
        fh.write("\n".join(lines))
    print("wrote %d block(s) into %s" % (len(RECIPES), page_path))
    return 0


def cmd_check(root, page_path):
    lines = read_page(root, page_path).split("\n")
    bad = 0
    for key, head, path, swap in RECIPES:
        b, e = locate(lines, key, head, page_path)
        have = "\n".join(lines[b + 1 : e]) + "\n"
        want = body(root, path, swap)
        if have == want:
            print("ok   %s shows %s (%d line(s))" % (key, path, want.count("\n")))
        else:
            print("FAIL %s and %s disagree; re-run `write %s`" % (key, path, page_path))
            for n, (h, w) in enumerate(zip(have.split("\n"), want.split("\n"))):
                if h != w:
                    print("     first difference at line %d of the region" % (n + 1))
                    print("       page:   %r" % h[:100])
                    print("       source: %r" % w[:100])
                    break
            else:
                print("     the regions differ in length: page %d, source %d"
                      % (len(have.split("\n")), len(want.split("\n"))))
            bad += 1
    if bad:
        print("%s does not show what %d of its checker(s) hold" % (page_path, bad))
        return 1
    print("checked %d recipe(s) against their committed checkers" % len(RECIPES))
    return 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("emit", "write", "check"):
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    root = Path(__file__).resolve().parent.parent
    page_path = argv[2] if len(argv) > 2 else PAGE
    try:
        if argv[1] == "emit":
            return cmd_emit(root)
        if argv[1] == "write":
            return cmd_write(root, page_path)
        return cmd_check(root, page_path)
    except Failure as exc:
        # BROKEN, not FAIL: the check could not make its statement, which is a different
        # thing from the statement being false. Never read this as a pass.
        print("BROKEN: %s" % exc, file=sys.stderr)
        return 2
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        # A checker this cannot read is a statement the check could not make, which the
        # three-valued contract spells 2. Decode errors reached rc 1 as a traceback
        # before review pointed at the gap between that and the leg's own comment.
        print("BROKEN: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
