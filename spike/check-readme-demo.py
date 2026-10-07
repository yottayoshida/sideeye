#!/usr/bin/env python3
"""check-readme-demo.py — the report the README shows is lines `sideeye demo` prints (#714).

Usage:
  python3 spike/check-readme-demo.py <README.md> <demo-output-file>
  python3 spike/check-readme-demo.py --selftest

The README's first screen carries a trimmed FAIL report between the markers
`<!-- demo-output:begin -->` and `<!-- demo-output:end -->`, and says it is real output. This
holds it to that: every non-empty line of the fenced block there must be a line of a fresh
`sideeye demo` run, whole, in the same order, each after the one before. The demo writes into
a scratch directory whose name changes every run, so the OUTPUT is normalised, never the
README: the directory is read off the demo's own `demo  compiled … into <dir>` line, and its
spellings (as printed, and resolved — macOS prints `/var/…` and `/private/var/…` in the same
report) become `…`. A `…` in the README stands for that directory; nothing else in the output
is rewritten, and blank lines are matched like any other line.

What this cannot see: whether the block is the most telling part of the report, and whether
the sentence above it is still true of what the block shows. It sees that every line was
printed.

Exit 0 holds, 1 does not, 2 could not run. CI runs it against the demo it has just run: the
macOS job's demo step, and acceptance check 5 on Linux.

Sunset: delete this, and its CI steps, if the README stops carrying demo output or `sideeye
demo` goes away.
"""

import difflib
import os
import re
import sys
import tempfile

BEGIN = "<!-- demo-output:begin -->"
END = "<!-- demo-output:end -->"
MIN_LINES = 8
COMPILED = re.compile(r"^demo  compiled .* into (\S+)\s*$")


class Broken(Exception):
    """The check could not run (exit 2)."""


class Refused(Exception):
    """The README's block is not what the demo printed (exit 1)."""


def excerpt(readme_text):
    """The lines of the one fenced block between the markers, blank lines included, in
    order. The markers hold that block and nothing else: a second fence, or a line written
    outside the fence, would be text the sentence above calls printed output and nothing
    here compares."""
    start, end = readme_text.find(BEGIN), readme_text.find(END)
    if start < 0 or end < 0 or end < start:
        raise Broken("the README does not carry the pair of markers %s ... %s" % (BEGIN, END))
    lines = readme_text[start + len(BEGIN):end].split("\n")
    fences = [i for i, line in enumerate(lines) if line.strip().startswith("```")]
    if len(fences) != 2:
        raise Refused("the block between the demo-output markers holds %d fence lines, want 2"
                      % len(fences))
    outside = [line for i, line in enumerate(lines)
               if (i < fences[0] or i > fences[1]) and line.strip()]
    if outside:
        raise Refused("the demo-output markers hold text outside its one fenced block: %s"
                      % outside[0].strip())
    return [line.rstrip() for line in lines[fences[0] + 1:fences[1]]]


def normalised(output_text):
    """The demo's lines with its scratch directory, in every spelling it printed, as `…`."""
    if "\x1b" in output_text:
        raise Broken("the demo output carries an escape sequence -- it was captured from a "
                     "terminal; capture it through a pipe")
    lines = output_text.split("\n")
    scratch = None
    for line in lines:
        m = COMPILED.match(line)
        if m:
            scratch = m.group(1)
            break
    if scratch is None:
        raise Broken("the demo output has no `demo  compiled ... into <dir>` line, so its "
                     "scratch directory cannot be named")
    spellings = {scratch, "/private" + scratch}
    if os.path.isdir(scratch):
        spellings.add(os.path.realpath(scratch))
    # Longest first, so `/private/var/x` is replaced whole rather than leaving `/private…`.
    out = []
    for line in lines:
        for s in sorted(spellings, key=len, reverse=True):
            line = line.replace(s, "…")
        out.append(line.rstrip())
    return out


def check(readme_text, output_text):
    try:
        want = excerpt(readme_text)
    except Refused as exc:
        return 1, ["FAIL " + str(exc)]
    have = normalised(output_text)
    at = 0
    for line in want:
        try:
            at = have.index(line, at) + 1
        except ValueError:
            near = difflib.get_close_matches(line, have, n=1, cutoff=0.0)
            return 1, ["FAIL the README shows a line the demo did not print, in that order:",
                       "  the README:  %s" % line,
                       "  the nearest: %s" % (near[0] if near else "(nothing)")]
    shown = [line for line in want if line]
    if len(shown) < MIN_LINES:
        return 1, ["FAIL the README's demo block holds %d line(s); a report needs at least %d"
                   % (len(shown), MIN_LINES)]
    if not any(line.startswith("FAIL  ") for line in shown):
        return 1, ["FAIL the README's demo block carries no `FAIL  ` verdict line"]
    return 0, ["ok   the README's demo block is %d lines `sideeye demo` printed, in order"
               % len(shown)]


# --------------------------------------------------------------------------- self-test

SCRATCH = "/var/folders/ab/T/sideeye-demo-Q1w2E3"
OUTPUT = "\n".join([
    "demo  compiled the planted-bug tool with cc into " + SCRATCH,
    "demo  the tool deletes its key before renaming the replacement in; a crash",
    "",
    "falsify: doctor says 'healthy' but the key is unloadable",
    "FAIL  1 of 6 explored worlds violated an invariant",
    "",
    "invariant   built-in atomicity, and the checker",
    "earliest    crash point 5 of 5",
    "            after  unlink(/private" + SCRATCH + "/state/key.json)",
    "            before rename(/private" + SCRATCH + "/state/key.json.tmp)",
    "path        key.json",
    "observed    present before and after the operation, but gone from the crashed state",
    "explored    6 worlds (crash points 5 + 1 baseline)",
    "checker     falsified before the run (corrupted state -> check failed); ran in 6 world(s)",
    "case        " + SCRATCH + "/work/cases/000001.json",
    "not tested  power loss, torn writes, concurrent processes",
    ""])
BLOCK = [
    "FAIL  1 of 6 explored worlds violated an invariant",
    "",
    "invariant   built-in atomicity, and the checker",
    "earliest    crash point 5 of 5",
    "            after  unlink(…/state/key.json)",
    "            before rename(…/state/key.json.tmp)",
    "path        key.json",
    "observed    present before and after the operation, but gone from the crashed state",
    "explored    6 worlds (crash points 5 + 1 baseline)",
    "checker     falsified before the run (corrupted state -> check failed); ran in 6 world(s)",
    "case        …/work/cases/000001.json",
    "not tested  power loss, torn writes, concurrent processes",
]


def _readme(block):
    return "# x\n\ntext\n\n%s\n```\n%s\n```\n%s\n\nmore\n" % (BEGIN, "\n".join(block), END)


def _without(block, i):
    return block[:i] + block[i + 1:]


LEGS = [
    ("the block as printed", _readme(BLOCK), OUTPUT, 0, "lines `sideeye demo` printed"),
    ("a figure composed", _readme([l.replace("1 of 6", "1 of 7") for l in BLOCK]), OUTPUT,
     1, "the README:  FAIL  1 of 7"),
    ("two lines swapped", _readme(BLOCK[:2] + [BLOCK[3], BLOCK[2]] + BLOCK[4:]), OUTPUT,
     1, "did not print, in that order"),
    ("a line cut short", _readme([l.split(", but")[0] for l in BLOCK]), OUTPUT,
     1, "the README:  observed    present before and after the operation"),
    ("an empty fence", _readme([]), OUTPUT, 1, "holds 0 line(s)"),
    ("no markers", "# x\n\n```\nFAIL  1 of 6 explored worlds violated an invariant\n```\n",
     OUTPUT, 2, "does not carry the pair of markers"),
    ("output from a terminal", _readme(BLOCK), OUTPUT.replace("FAIL  1", "\x1b[1;31mFAIL\x1b[0m  1"),
     2, "carries an escape sequence"),
    ("seven lines", _readme(BLOCK[:8]), OUTPUT, 1, "holds 7 line(s)"),
    ("eight lines and no verdict", _readme(BLOCK[2:10]), OUTPUT, 1, "carries no `FAIL  `"),
    ("one line shown twice", _readme(BLOCK[:7] + [BLOCK[6]] + BLOCK[7:]), OUTPUT,
     1, "did not print, in that order"),
    # BLOCK[:9] is the verdict, a blank line and seven more: eight lines to match.
    ("exactly eight lines with the verdict", _readme(BLOCK[:9]), OUTPUT, 0, "is 8 lines"),
    # A block that only grows past what is checked (R1 of the diff): a blank line where the
    # output has none, prose after the fence, a second fence of its own.
    ("a blank line the demo did not print there",
     _readme(BLOCK[:4] + [""] + BLOCK[4:]), OUTPUT, 1, "did not print, in that order"),
    ("a line written after the fence",
     _readme(BLOCK).replace("```\n" + END, "```\nFAIL  0 of 6 explored worlds\n" + END), OUTPUT,
     1, "outside its one fenced block"),
    ("a second fence",
     _readme(BLOCK).replace(END, "```\nPASS  6/6\n```\n" + END), OUTPUT,
     1, "holds 4 fence lines"),
    ("no scratch line to normalise by", _readme(BLOCK), "\n".join(OUTPUT.split("\n")[1:]),
     2, "has no `demo  compiled"),
]


def selftest():
    failed = 0
    for name, readme, output, want, needle in LEGS:
        try:
            rc, lines = check(readme, output)
        except Broken as exc:
            rc, lines = 2, ["BROKEN " + str(exc)]
        body = "\n".join(lines)
        if rc != want or needle not in body:
            failed += 1
            print("== self-test FAILED: %s -- exited %d wanting %d" % (name, rc, want))
            print("\n".join("     | " + line for line in lines))
        else:
            print("== ok: %s" % name)
    return 2 if failed else 0


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if len(argv) != 2:
        print("usage: check-readme-demo.py <README.md> <demo-output-file> | --selftest",
              file=sys.stderr)
        return 2
    try:
        with open(argv[0], encoding="utf-8") as fh:
            readme = fh.read()
        with open(argv[1], encoding="utf-8", errors="replace") as fh:
            output = fh.read()
        rc, lines = check(readme, output)
    except (OSError, Broken) as exc:
        print("BROKEN %s" % exc)
        return 2
    print("\n".join(lines))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
