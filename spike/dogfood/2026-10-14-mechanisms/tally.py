#!/usr/bin/env python3
"""Recompute the 2026-10-14 mechanisms run's answers (#861) from its committed records.

    python3 tally.py           print the counts and the decision-table row
    python3 tally.py --check   also require SYNTHESIS.md's generated block to equal that output

Reads baseline.tsv, screen.tsv, results.tsv and the engine reports results.tsv names, and the
repository's spike/upstream-reports.tsv and spike/outcome-funnel.tsv for the baseline's provenance.
This file is committed with SELECTION.md, before the first explore, so the table below cannot be
fitted to the results.
"""
import csv
import importlib.util
import json
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "../../.."))
CLASSES = ("M1", "M2", "M3", "M4", "M5", "M6", "unclassifiable")
OLD = ("M1", "M2", "unclassifiable")
BEGIN, END = "<!-- tally:begin -->", "<!-- tally:end -->"


class Broken(Exception):
    pass


def rows(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def funnel():
    spec = importlib.util.spec_from_file_location("of", os.path.join(ROOT, "spike/outcome-funnel.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def machine_provenance(of, all_rows, report):
    mine = [r for r in all_rows if r["report"] == report]
    if any((d := of.read_report(ROOT, r["evidence"])) and d.get("verdict") == "FAIL" for r in mine):
        return "sideeye"
    if mine and all(r["note"].startswith(("Not a Sideeye verdict", "Not an explore")) for r in mine):
        return "other"
    return "unclear"


def check_baseline(base):
    of = funnel()
    _, all_rows, _ = of.load(ROOT)
    filed = [r for r in base if r["section"] == "filed"]
    keys = Counter(r["key"] for r in filed)
    ledger = [u["report"] for u in of.read_upstream(ROOT)]
    if sorted(keys) != sorted(ledger) or any(n != 1 for n in keys.values()):
        raise Broken("baseline.tsv's filed rows are not spike/upstream-reports.tsv's rows, each once")
    for r in base:
        if r["mechanism"] not in CLASSES:
            raise Broken("baseline.tsv: %s has mechanism %r" % (r["key"], r["mechanism"]))
        if r["section"] == "filed" and r["provenance"] != machine_provenance(of, all_rows, r["key"]):
            raise Broken("baseline.tsv: %s says %s; the rule says %s"
                         % (r["key"], r["provenance"], machine_provenance(of, all_rows, r["key"])))
        if r["provenance"] == "unclear" and r["provenance_read"].split(":")[0] not in ("sideeye", "other"):
            raise Broken("baseline.tsv: %s is unclear and has no reading" % r["key"])
    return len(filed), len(base) - len(filed)


def effective(r):
    return r["provenance"] if r["provenance"] != "unclear" else r["provenance_read"].split(":")[0]


def check_results(res, screen):
    taken = sum(s["outcome"] == "taken" for s in screen)
    if res and len(res) != taken:
        raise Broken("results.tsv has %d rows for %d fixed targets" % (len(res), taken))
    for r in res:
        if r["verdict"] == "not-measured":
            continue
        doc = json.load(open(os.path.join(HERE, r["report"]), encoding="utf-8"))
        if doc.get("verdict") != r["verdict"]:
            raise Broken("results.tsv: %s says %s, its report %s" % (r["target"], r["verdict"], doc.get("verdict")))
        if r["verdict"] == "UNKNOWN" and (doc.get("unknown_reason") or "-") != r["unknown_reason"]:
            raise Broken("results.tsv: %s's reason is not its report's" % r["target"])
        caught = "yes" if doc.get("checker_earliest") else "no"
        if r["verdict"] == "FAIL" and caught != r["checker_caught"]:
            raise Broken("results.tsv: %s says checker_caught=%s, its report %s" % (r["target"], r["checker_caught"], caught))
        if r["verdict"] == "FAIL" and r["checker_caught"] == "yes" and r["mechanism"] not in CLASSES:
            raise Broken("results.tsv: %s is a checker FAIL with no class" % r["target"])


def tally():
    base, screen, res = rows("baseline.tsv"), rows("screen.tsv"), rows("results.tsv")
    n_filed, n_unfiled = check_baseline(base)
    check_results(res, screen)
    unmeasured = [r for r in res if r["verdict"] == "not-measured"]
    res = [r for r in res if r["verdict"] != "not-measured"]
    machine_seen = {r["mechanism"] for r in base if r["provenance"] == "sideeye"}
    read_seen = {r["mechanism"] for r in base if effective(r) == "sideeye"}
    caught = [r for r in res if r["verdict"] == "FAIL" and r["checker_caught"] == "yes"]
    primary = [r for r in caught if r["mechanism"] not in OLD]
    strict = [r for r in primary if r["mechanism"] not in machine_seen]
    strict_read = [r for r in primary if r["mechanism"] not in read_seen]
    reach_out = [s for s in screen if s["outcome"] == "out-reach"]
    unknown = [r for r in res if r["verdict"] == "UNKNOWN"]
    judged = [r for r in res if r["verdict"] in ("PASS", "FAIL")]
    tried = len(reach_out) + len(res)
    reasons = Counter([s["reason"] for s in reach_out] + [r["unknown_reason"] for r in unknown])
    repeated = sorted(k for k, n in reasons.items() if n >= 2)
    if primary:
        row = 1
    elif tried and 2 * (len(reach_out) + len(unknown)) >= tried and repeated:
        row = 2
    elif tried and 2 * (len(reach_out) + len(unknown)) >= tried:
        row = 3
    elif any(r["verdict"] == "FAIL" for r in judged):
        row = 4
    else:
        row = 5
    table = {
        1: ("-", "make semantic invariants easier to write"),
        2: ("reach", "the reach fix for %s" % ", ".join(repeated)),
        3: ("reach (dispersed)", "no further expansion"),
        4: ("target and invariant selection", "measure third-party use"),
        5: ("no counterexample in judgeable worlds", "no further expansion"),
    }
    base_counts = Counter(r["mechanism"] for r in base)
    lines = [
        "baseline: %d filed reports, %d unfiled targets" % (n_filed, n_unfiled),
        "baseline by class: " + ", ".join("%s %d" % (c, base_counts[c]) for c in CLASSES),
        "classes with a sideeye row (machine): " + ", ".join(c for c in CLASSES if c in machine_seen),
        "classes with a sideeye row (read): " + ", ".join(c for c in CLASSES if c in read_seen),
        "tried: %d (out at the screen for reach: %d; fixed targets: %d)" % (tried, len(reach_out), len(res)),
        "fixed targets: %d PASS, %d FAIL, %d UNKNOWN, %d not measured in the time box" % (
            sum(r["verdict"] == "PASS" for r in res), sum(r["verdict"] == "FAIL" for r in res), len(unknown), len(unmeasured)),
        "FAILs the checker caught: %d; by class: %s" % (
            len(caught), ", ".join("%s %d" % (c, n) for c, n in sorted(Counter(r["mechanism"] for r in caught).items())) or "-"),
        "primary (not M1, M2 or unclassifiable): %d %s" % (len(primary), [r["target"] for r in primary]),
        "strict, machine provenance: %d %s" % (len(strict), [r["target"] for r in strict]),
        "strict, read provenance: %d %s" % (len(strict_read), [r["target"] for r in strict_read]),
        "refusals counted twice or more: %s" % (repeated or "-"),
        "decision row %d: binding constraint %s; next investment: %s" % (row, table[row][0], table[row][1]),
    ]
    return "\n".join(lines)


def main():
    try:
        out = tally()
    except (Broken, OSError, ValueError, KeyError) as e:
        print("tally: %s" % e, file=sys.stderr)
        return 1
    print(out)
    if "--check" in sys.argv[1:]:
        doc = open(os.path.join(HERE, "SYNTHESIS.md"), encoding="utf-8").read()
        block = doc.split(BEGIN, 1)[1].split(END, 1)[0].strip().strip("`").strip() if BEGIN in doc else None
        if block != out:
            print("tally: SYNTHESIS.md's generated block is not this output", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
