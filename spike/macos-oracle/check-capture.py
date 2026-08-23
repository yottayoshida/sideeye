#!/usr/bin/env python3
"""Judge one observer capture against the toy's fixed sequence (#181).

The check is deliberately narrow and says so: PRESENCE of the three marker
tokens and their FIRST-APPEARANCE order (marker-a.tmp, then marker-b, then
marker-c). It does not verify per-operation completeness or attribute
events to a pid; the human reads the excerpt the survey prints next to
this verdict for that.

A capture that mentions nothing is reported distinctly from one that is
out of order, because "saw nothing" usually means the observer never ran
or never saw the process, which is a different failure from reordering.

Usage: check-capture.py <capture-file> <label>
       check-capture.py --selftest
Exit 0 verdict OK, 1 verdict not OK, 2 could not judge.
"""
import sys

TOKENS = ["marker-a.tmp", "marker-b", "marker-c"]


def judge(text, label):
    firsts = []
    for t in TOKENS:
        i = text.find(t)
        if i < 0:
            print(f"  {label}: FAIL - token '{t}' never appears "
                  f"({len(text)} bytes searched)")
            if not any(t2 in text for t2 in TOKENS):
                print(f"  {label}: (no marker token at all: the observer "
                      f"saw nothing of the toy)")
            return 1
        firsts.append(i)
    if firsts != sorted(firsts):
        print(f"  {label}: FAIL - tokens present but first appearances out "
              f"of order: {list(zip(TOKENS, firsts))}")
        return 1
    lines = sum(1 for ln in text.splitlines() if "marker-" in ln)
    print(f"  {label}: ok - all 3 tokens present, first appearances in "
          f"order, {lines} line(s) mention a marker")
    return 0


def selftest():
    fails = 0

    def case(name, text, want):
        nonlocal fails
        got = judge(text, f"selftest/{name}")
        verdict = "ok" if got == want else "FAIL"
        if got != want:
            fails += 1
        print(f"  selftest {verdict}: {name} -> rc {got} (wanted {want})")

    case("complete-in-order",
         "x marker-a.tmp y\nz marker-b\nq marker-c\n", 0)
    case("missing-middle-token",
         "x marker-a.tmp y\nq marker-c\n", 1)
    case("out-of-order",
         "q marker-c\nx marker-a.tmp\nz marker-b\n", 1)
    case("empty-capture", "", 1)
    print(f"  selftest failures: {fails}")
    return 1 if fails else 0


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    try:
        text = open(sys.argv[1], errors="replace").read()
    except OSError as e:
        print(f"  {sys.argv[2]}: BROKEN - capture unreadable: {e}")
        sys.exit(2)
    sys.exit(judge(text, sys.argv[2]))


if __name__ == "__main__":
    main()
