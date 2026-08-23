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

A capture whose every marker line is the toy's own stdout (lines starting
with "op ") is REJECTED unless --allow-self-account is given: runner-style
observers (dtruss, ktrace -c) execute the toy themselves, the toy's
self-account lands in the same stream, and the first privileged run of
this survey returned a confident "ok" for dtruss that was really the
check reading the toy's own words back. The ground truth IS a
self-account, so the survey's positive control passes the flag; no
observer leg does.

Usage: check-capture.py [--allow-self-account] <capture-file> <label>
       check-capture.py --selftest
Exit 0 verdict OK, 1 verdict not OK, 2 could not judge.
"""
import sys

TOKENS = ["marker-a.tmp", "marker-b", "marker-c"]


def judge(text, label, allow_self_account=False):
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
    marker_lines = [ln for ln in text.splitlines() if "marker-" in ln]
    own = sum(1 for ln in marker_lines if ln.startswith("op "))
    if own == len(marker_lines) and not allow_self_account:
        print(f"  {label}: FAIL - every marker line is the toy's own "
              f"stdout ('op ...'): this capture proves the toy ran, not "
              f"that the observer saw it")
        return 1
    print(f"  {label}: ok - all 3 tokens present, first appearances in "
          f"order, {len(marker_lines)} line(s) mention a marker "
          f"({len(marker_lines) - own} from the observer itself)")
    return 0


def selftest():
    fails = 0

    def case(name, text, want, allow=False):
        nonlocal fails
        got = judge(text, f"selftest/{name}", allow_self_account=allow)
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
    # The contamination this guard exists for, in the shape the first
    # privileged run actually produced: a runner-style capture holding
    # only the toy's own account.
    contaminated = ("op open+write marker-a.tmp\nop rename marker-a.tmp "
                    "-> marker-a\nop open+write marker-b\nop unlink "
                    "marker-b\nop open+write marker-sub/marker-c\n")
    case("self-account-only", contaminated, 1)
    case("self-account-allowed (the ground-truth control)",
         contaminated, 0, allow=True)
    # One observer line among the op-lines is enough: the observer saw it.
    case("mixed-observer-and-self-account",
         contaminated + "17:31:15 open /x/marker-a.tmp toy.123\n", 0)
    print(f"  selftest failures: {fails}")
    return 1 if fails else 0


def main():
    args = sys.argv[1:]
    if args == ["--selftest"]:
        sys.exit(selftest())
    allow = False
    if args and args[0] == "--allow-self-account":
        allow = True
        args = args[1:]
    if len(args) != 2:
        print(__doc__)
        sys.exit(2)
    try:
        text = open(args[0], errors="replace").read()
    except OSError as e:
        print(f"  {args[1]}: BROKEN - capture unreadable: {e}")
        sys.exit(2)
    sys.exit(judge(text, args[1], allow_self_account=allow))


if __name__ == "__main__":
    main()
