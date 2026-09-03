#!/usr/bin/env python3
"""The upstream suite verdict, in one place (#64): timewarrior's C++ test framework
(test/test.cpp) prints TAP-like lines and a summary, and this module is the only text
that reads them. The loop-closure judge imports it for the secondary observation.

parse(text) -> dict with passed / failed / skipped (from the summary line, or None when
  there is none), planned (every `1..N` line, in order), under_run and over_run (the
  framework's own two mismatch lines, as [ran, planned] or None), summary_seen.
gate(rc, parsed) -> ("pass" | "fail", detail)
  pass: rc == 0, the summary line was seen, failed == 0, passed >= 1, and no under-run
  line. Why those and not the obvious ones: the rc alone is exit(_failed > 0); a skip
  prints as `ok ... # skip`, so counting `ok` lines overcounts; the `1..N` plan is a
  declaration a suite may exceed (AtomicFileTest at the loop-closure pin declares 22 and
  runs 24) and is recorded, never judged; an under-run prints `# Only N tests, out of a
  planned M were run.`, folds the rest into "skipped" and still exits 0.

CLI: suite_summary.py <output.txt> <rc>   exit 0 iff pass; otherwise gate and detail
     on stderr, exit 1.
     suite_summary.py --selftest          synthetic outputs through parse(), gate() and
     the CLI; acceptance runs it.
"""
import re
import sys

SUMMARY = re.compile(r"^# (\d+) passed, (\d+) failed, (\d+) skipped\.")
PLAN = re.compile(r"^1\.\.(\d+)$")
UNDER = re.compile(r"^# Only (\d+) tests, out of a planned (\d+) were run\.")
OVER = re.compile(r"^# (\d+) tests were run, but only (\d+) were planned\.")


def parse(text):
    out = {"passed": None, "failed": None, "skipped": None, "planned": [],
           "under_run": None, "over_run": None, "summary_seen": False}
    for line in text.splitlines():
        m = SUMMARY.match(line)
        if m:
            out["passed"], out["failed"], out["skipped"] = (int(x) for x in m.groups())
            out["summary_seen"] = True
        m = PLAN.match(line)
        if m:
            out["planned"].append(int(m.group(1)))
        m = UNDER.match(line)
        if m:
            out["under_run"] = [int(m.group(1)), int(m.group(2))]
        m = OVER.match(line)
        if m:
            out["over_run"] = [int(m.group(1)), int(m.group(2))]
    return out


def gate(rc, parsed):
    missed = []
    if rc != 0:
        missed.append("rc %r" % (rc,))
    if not parsed.get("summary_seen"):
        missed.append("no summary line")
    if parsed.get("failed") != 0:
        missed.append("failed %r" % (parsed.get("failed"),))
    if not (parsed.get("passed") or 0) >= 1:
        missed.append("passed %r" % (parsed.get("passed"),))
    if parsed.get("under_run") is not None:
        missed.append("under-run %r" % (parsed.get("under_run"),))
    if missed:
        return "fail", "; ".join(missed)
    return "pass", ""


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) != 3:
        sys.exit("usage: suite_summary.py <output.txt> <rc>")
    with open(argv[1]) as f:
        text = f.read()
    verdict, detail = gate(int(argv[2]), parse(text))
    if verdict == "pass":
        return 0
    print("suite summary: %s -- %s" % (verdict, detail or "no detail"), file=sys.stderr)
    return 1


def selftest():
    import os
    import tempfile
    plain = "1..3\nok 1 - a\nok 2 - b\nok 3 - c\n# 3 passed, 0 failed, 0 skipped. 100% passed.\n"
    skips = ("1..22\n" + "".join("ok %d - t\n" % i for i in range(1, 19))
             + "".join("ok %d - t # skip\n" % i for i in range(19, 25))
             + "# 24 tests were run, but only 22 were planned.\n"
             + "# 18 passed, 0 failed, 6 skipped. 75% passed.\n")
    notok = "1..2\nok 1 - a\nnot ok 2 - b\n# 1 passed, 1 failed, 0 skipped. 50% passed.\n"
    under = "1..5\nok 1 - a\nok 2 - b\n# Only 2 tests, out of a planned 5 were run.\n# 2 passed, 0 failed, 3 skipped. 40% passed.\n"
    nosum = "1..2\nok 1 - a\nok 2 - b\n"
    zero = "1..0\n# 0 passed, 0 failed, 0 skipped. 0% passed.\n"
    replan = "1..1\nok 1 - a\n1..2\nok 2 - b\n# 2 passed, 0 failed, 0 skipped. 100% passed.\n"
    # (text, rc, expected gate, expected fields)
    cases = [
        (plain, 0, "pass", {"passed": 3, "planned": [3], "over_run": None}),
        (skips, 0, "pass", {"passed": 18, "skipped": 6, "planned": [22], "over_run": [24, 22]}),
        (notok, 1, "fail", {"failed": 1}),
        (plain, 1, "fail", {"passed": 3}),
        (under, 0, "fail", {"under_run": [2, 5], "skipped": 3}),
        (nosum, 0, "fail", {"summary_seen": False, "passed": None}),
        (zero, 0, "fail", {"passed": 0}),
        (replan, 0, "pass", {"planned": [1, 2]}),
    ]
    failures = []
    fd, path = tempfile.mkstemp(prefix="suite-summary-selftest-", suffix=".txt")
    os.close(fd)
    try:
        for text, rc, want, fields in cases:
            parsed = parse(text)
            for k, v in fields.items():
                if parsed.get(k) != v:
                    failures.append("parse: %s = %r, wanted %r in %r" % (k, parsed.get(k), v, text[:40]))
            got, _ = gate(rc, parsed)
            if got != want:
                failures.append("gate(rc=%r, %r) = %r, wanted %r" % (rc, text[:40], got, want))
            with open(path, "w") as f:
                f.write(text)
            cli_pass = main(["suite_summary.py", path, str(rc)]) == 0
            if cli_pass != (want == "pass"):
                failures.append("CLI disagrees with gate() on %r: pass=%r" % (text[:40], cli_pass))
    finally:
        os.unlink(path)
    if failures:
        print("suite_summary selftest: %d failure(s)" % len(failures), file=sys.stderr)
        for line in failures:
            print("  " + line, file=sys.stderr)
        return 1
    print("suite_summary selftest: ok (%d outputs, parse(), gate() and the CLI agree)" % len(cases))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
