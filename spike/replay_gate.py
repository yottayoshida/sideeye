#!/usr/bin/env python3
"""The replay gate: the one predicate that says a saved case replayed clean (#65).

Two consumers read it -- spike/loop-closure-timew/judge.sh (the pos control and the
run verdict) and spike/dogfood-timew-replay.sh (leg C) -- and before this file each
carried its own copy of the same four-clause test. A refinement in one copy would
have left the other measuring something else, both green.

gate(report, rc, ops_total, expected_explored=2) returns (gate, detail):
  "pass"             rc 0, verdict PASS, explored == expected_explored, no
                     unknown_reason key, crash_points == ops_total
  "fail_reproduced"  rc 1, verdict FAIL
  "other"            anything else; detail says which clause missed
Missing keys read as None and land in "other" (the judge's .get form; the old
leg C raised KeyError instead). "unknown_reason" present -- even null -- is not a
pass, as before. expected_explored is 2 for a replay (the baseline plus the case's
world); a full exploration under the same define expects ops_total + 1.

CLI: replay_gate.py <report.json> <rc> <ops_total> [expected_explored]
     exit 0 iff pass; otherwise the gate and its detail go to stderr, exit 1. The
     CLI does not restate the default: without a fourth argument it calls gate()
     with none, so the function's default is the only place the number lives (a
     mutation of that default once reached the judge and not leg C, because the
     CLI carried its own 2).
     replay_gate.py --selftest
     runs gate() and the CLI on the same synthetic documents and fails if they
     disagree or if a clause is not what this docstring says; acceptance runs it.
"""
import json
import sys


def gate(report, rc, ops_total, expected_explored=2):
    verdict = report.get("verdict")
    if (rc == 0 and verdict == "PASS" and report.get("explored") == expected_explored
            and "unknown_reason" not in report
            and report.get("crash_points") == ops_total):
        return "pass", ""
    if rc == 1 and verdict == "FAIL":
        return "fail_reproduced", ""
    missed = []
    if rc != 0:
        missed.append("rc %r" % (rc,))
    if verdict != "PASS":
        missed.append("verdict %r (%s) %s" % (verdict, report.get("unknown_reason"),
                                              report.get("message", "")))
    if report.get("explored") != expected_explored:
        missed.append("explored %r != %r" % (report.get("explored"), expected_explored))
    if "unknown_reason" in report:
        missed.append("unknown_reason present: %r" % (report.get("unknown_reason"),))
    if report.get("crash_points") != ops_total:
        missed.append("crash_points %r != ops_total %r" % (report.get("crash_points"), ops_total))
    return "other", "; ".join(missed)


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) not in (4, 5):
        sys.exit("usage: replay_gate.py <report.json> <rc> <ops_total> [expected_explored]")
    with open(argv[1]) as f:
        report = json.load(f)
    rc, ops_total = int(argv[2]), int(argv[3])
    if len(argv) == 5:
        verdict, detail = gate(report, rc, ops_total, int(argv[4]))
    else:
        verdict, detail = gate(report, rc, ops_total)
    if verdict == "pass":
        return 0
    print("replay gate: %s -- %s" % (verdict, detail or "no detail"), file=sys.stderr)
    return 1


def selftest():
    import os
    import tempfile
    # (document, rc, ops_total, expected_explored or None for the default, gate)
    cases = [
        ({"verdict": "PASS", "explored": 2, "crash_points": 24}, 0, 24, None, "pass"),
        ({"verdict": "FAIL", "explored": 2, "crash_points": 24}, 1, 24, None, "fail_reproduced"),
        ({"verdict": "PASS", "explored": 3, "crash_points": 24}, 0, 24, None, "other"),
        ({"verdict": "PASS", "explored": 25, "crash_points": 24}, 0, 24, 25, "pass"),
        ({"verdict": "PASS", "explored": 2, "crash_points": 24, "unknown_reason": None}, 0, 24, None, "other"),
        ({"verdict": "PASS", "explored": 2, "crash_points": 23}, 0, 24, None, "other"),
        ({"verdict": "PASS", "explored": 2, "crash_points": 24}, 2, 24, None, "other"),
        ({"verdict": "FAIL", "explored": 2, "crash_points": 24}, 0, 24, None, "other"),
        ({}, 0, 24, None, "other"),
    ]
    failures = []
    fd, path = tempfile.mkstemp(prefix="replay-gate-selftest-", suffix=".json")
    os.close(fd)
    try:
        for doc, rc, ops_total, expected_explored, want in cases:
            got, _ = (gate(doc, rc, ops_total) if expected_explored is None
                      else gate(doc, rc, ops_total, expected_explored))
            if got != want:
                failures.append("gate(%r, %r, %r, %r) = %r, wanted %r"
                                % (doc, rc, ops_total, expected_explored, got, want))
            with open(path, "w") as f:
                json.dump(doc, f)
            argv = ["replay_gate.py", path, str(rc), str(ops_total)]
            if expected_explored is not None:
                argv.append(str(expected_explored))
            cli_pass = main(argv) == 0
            if cli_pass != (want == "pass"):
                failures.append("CLI %r disagrees with gate(): pass=%r, wanted %r"
                                % (argv[1:], cli_pass, want == "pass"))
    finally:
        os.unlink(path)
    if failures:
        print("replay_gate selftest: %d failure(s)" % len(failures), file=sys.stderr)
        for line in failures:
            print("  " + line, file=sys.stderr)
        return 1
    print("replay_gate selftest: ok (%d documents, gate() and the CLI agree)" % len(cases))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
