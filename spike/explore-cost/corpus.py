#!/usr/bin/env python3
"""What the committed dogfood reports already say about exploration cost.

`measure.sh` beside this file measured what one world costs and said plainly that it says
nothing about a total: "a run costs the per-world figure times crash points plus one, and
the file count does not predict the multiplier". This reads the multiplier off every report
this repository has committed, so the distribution comes from the record rather than from
an impression.

    python3 spike/explore-cost/corpus.py            # the tables, to stdout
    python3 spike/explore-cost/corpus.py --tsv OUT  # the per-report rows as TSV

What it reads: every `*.json` under `spike/dogfood/` whose `schema` is `sideeye/report`.
Nothing else in the tree is a report this engine wrote -- the assisted and blind-hunt
directories hold saved cases, which carry no counters.

Three things this deliberately does not do.

It does not merge two reports into one target. A file name is not a define: `nvim.json` and
`nvim-scratch.json` are two defines over one program, and `aws.2.json` is the same define
run again. The rows are per report; the grouping below is by the file's stem with a run
suffix stripped, printed so a reader can see what was merged, and every aggregate over
targets says which of the two units it used.

It does not read wall-clock anywhere, because no report carries it and no committed
transcript recorded it. Time is `measure-targets.sh`'s to measure, not this file's to guess.

It does not count a refusal's `crash_points` as a cost: a run that refused may have refused
before exploring, and `explored` says what actually ran. Refusals are reported separately
and excluded from the distribution, which is therefore about targets that reach a verdict --
the population the question is about.
"""

import argparse
import json
import os
import re
import statistics
import sys
from collections import Counter, defaultdict

REPORT_SCHEMA = "sideeye/report"
# A trailing run index (`aws.2.json`, `oxipng3.json`) and an observation-mode infix
# (`mlr.after.wrappers.4.json`) are not different defines. A trailing word that is not a
# mode (`nvim-scratch`, `ninja-recovery`) is: those stay apart.
MODES = ("wrappers", "syscalls")
# Neither is a different define: `.main` says the run used a build of `main` rather than the
# release, `.rep` says it is a repetition. A trailing word that is not one of these is left
# alone -- `nvim-scratch` declares scratch paths and `ninja-recovery` declares a rebuild
# checker, and those are different questions about one program.
BUILDS = ("main", "rep")


def stem_of(path):
    """The report's target key: file stem, minus a mode infix and a run index."""
    name = os.path.basename(path)[: -len(".json")]
    parts = [p for p in name.split(".") if p not in MODES and p not in BUILDS]
    parts = [p for p in parts if not p.isdigit()]
    base = ".".join(parts) if parts else name
    return re.sub(r"\d+$", "", base) or base


def funnel_names(root):
    """target names from `spike/outcome-funnel.tsv` (#605), keyed by the record they name.

    A report's file name is not its target: `B.1.json` is cargo, `privileged-root.*.json`
    is ansible-core, `main-original.json` is mogrify's upstream build -- each named for the
    slate or the build its run was about. The funnel already carries, per (campaign,
    target), the record the row was taken from, so the naming is taken from there rather
    than invented here. It names one record per campaign and target; the name is carried
    to that record's siblings -- same directory, same stem after a mode infix and a run
    index are dropped -- which is how the repeat runs of one define get named.
    """
    path = os.path.join(root, "spike", "outcome-funnel.tsv")
    named = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("#") or not line.strip():
                    continue
                cols = line.rstrip("\n").split("\t")
                if len(cols) >= 7 and cols[6].endswith(".json"):
                    named[cols[6]] = cols[1]
    except OSError:
        return {}, {}
    # (directory, stem) -> name, for carrying to siblings.
    by_stem = {}
    for rec, name in named.items():
        by_stem[(os.path.dirname(rec), stem_of(rec))] = name
    return named, by_stem


def load(root):
    rows = []
    for dirpath, _dirnames, filenames in os.walk(os.path.join(root, "spike", "dogfood")):
        for fn in sorted(filenames):
            if not fn.endswith(".json"):
                continue
            p = os.path.join(dirpath, fn)
            try:
                with open(p, encoding="utf-8") as fh:
                    d = json.load(fh)
            except (OSError, ValueError):
                continue
            if not isinstance(d, dict) or d.get("schema") != REPORT_SCHEMA:
                continue
            earliest = d.get("earliest") or {}
            rows.append(
                {
                    "path": os.path.relpath(p, root),
                    "run": os.path.relpath(dirpath, os.path.join(root, "spike", "dogfood")).split(os.sep)[0],
                    "target": stem_of(p),
                    "verdict": d.get("verdict"),
                    "contract": d.get("contract_version"),
                    "crash_points": d.get("crash_points"),
                    "explored": d.get("explored"),
                    "violations": d.get("violations"),
                    "earliest": earliest.get("crash_point"),
                    "unknown_reason": d.get("unknown_reason"),
                }
            )
    return rows


def pct(part, whole):
    return "-" if not whole else f"{100.0 * part / whole:.0f}%"


def quantiles(xs):
    xs = sorted(xs)
    if not xs:
        return {}
    return {
        "n": len(xs),
        "min": xs[0],
        "p50": statistics.median(xs),
        "p90": xs[min(len(xs) - 1, int(round(0.9 * (len(xs) - 1))))],
        "max": xs[-1],
        "sum": sum(xs),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    ap.add_argument("--tsv")
    args = ap.parse_args()
    root = os.path.abspath(args.root)

    rows = load(root)
    if not rows:
        print("no reports found under spike/dogfood -- wrong --root?", file=sys.stderr)
        return 2

    named, by_stem = funnel_names(root)
    for r in rows:
        p = r["path"]
        r["name"] = named.get(p) or by_stem.get((os.path.dirname(p), stem_of(p)))
        r["target"] = r["name"] or r["target"]

    judged = [r for r in rows if r["verdict"] in ("PASS", "FAIL")]
    refused = [r for r in rows if r["verdict"] not in ("PASS", "FAIL")]
    # A judged run with no state-changing operation explores nothing; it is a verdict about
    # a define, not an exploration, and it would pull every distribution toward zero.
    explored = [r for r in judged if (r["crash_points"] or 0) > 0]
    fails = [r for r in explored if r["verdict"] == "FAIL"]

    print(f"reports read: {len(rows)}  (judged {len(judged)}, refused {len(refused)})")
    print(f"judged runs that explored at least one crash point: {len(explored)}")
    by_target = defaultdict(list)
    for r in explored:
        by_target[r["target"]].append(r)
    unnamed = sorted({r["target"] for r in explored if not r["name"]})
    # Two counts, because one number cannot be both. A key is a define -- `nvim` and
    # `nvim-scratch` are two questions about one program, and the funnel names one record
    # `aws-cli` where its siblings keep the stem `aws`. The program count folds a key at its
    # first separator, which merges those pairs and also merges the two nvim defines; the
    # define count keeps them apart and double-counts the program. The truth is between.
    programs = {re.split(r"[.\-]", t)[0] for t in by_target}
    print(f"distinct defines among them: {len(by_target)} "
          f"({len(by_target) - len(unnamed)} named by spike/outcome-funnel.tsv, {len(unnamed)} by file stem) "
          f"over {len(programs)} distinct programs")
    if unnamed:
        print("   named by stem only (the funnel has no row pointing at these records): " + ", ".join(unnamed))
    print()

    print("== 1. crash points per run (judged runs only) ==")
    q = quantiles([r["crash_points"] for r in explored])
    print(f"   n={q['n']} min={q['min']} median={q['p50']} p90={q['p90']} max={q['max']} total={q['sum']}")
    hist = Counter(r["crash_points"] for r in explored)
    print("   " + "  ".join(f"{k}:{v}" for k, v in sorted(hist.items())))
    buckets = Counter()
    for r in explored:
        c = r["crash_points"]
        b = "1" if c == 1 else "2-4" if c <= 4 else "5-9" if c <= 9 else "10-19" if c <= 19 else "20-99" if c <= 99 else "100+"
        buckets[b] += 1
    order = ["1", "2-4", "5-9", "10-19", "20-99", "100+"]
    print("   buckets: " + "  ".join(f"{b}:{buckets.get(b, 0)} ({pct(buckets.get(b, 0), len(explored))})" for b in order))
    # Per target, taking each target's largest run, so a target measured ten times is one row.
    per_target_max = [max(x["crash_points"] for x in v) for v in by_target.values()]
    qt = quantiles(per_target_max)
    print(f"   per target (largest run of each): n={qt['n']} median={qt['p50']} p90={qt['p90']} max={qt['max']}")
    print()

    print("== 2. worlds actually explored ==")
    off = [r for r in explored if r["explored"] != (r["crash_points"] or 0) + 1]
    print(f"   runs where explored == crash_points + 1: {len(explored) - len(off)} of {len(explored)}")
    for r in off:
        print(f"     {r['path']}: crash_points={r['crash_points']} explored={r['explored']} verdict={r['verdict']}")
    print(f"   total worlds run across the corpus: {sum(r['explored'] for r in explored)}")
    print()

    print("== 3. failing crash points per FAIL run ==")
    print("   (violations = crash worlds whose invariant did not hold; the report's own counter)")
    ratios = []
    for r in fails:
        if r["crash_points"]:
            ratios.append(r["violations"] / r["crash_points"])
    qv = quantiles([r["violations"] for r in fails])
    print(f"   FAIL runs: {len(fails)}  violations: median={qv['p50']} max={qv['max']}")
    if ratios:
        print(f"   violations/crash_points: median={statistics.median(ratios):.2f} min={min(ratios):.2f} max={max(ratios):.2f}")
    one = sum(1 for r in fails if r["violations"] == 1)
    print(f"   FAIL runs with exactly one failing crash point: {one} of {len(fails)} ({pct(one, len(fails))})")
    print()

    print("== 4. where the first failing crash point sits ==")
    pos = [(r["earliest"], r["crash_points"], r["path"]) for r in fails if r["earliest"]]
    print(f"   FAIL runs naming an earliest crash point: {len(pos)} of {len(fails)}")
    if pos:
        qa = quantiles([e for e, _c, _p in pos])
        print(f"   as an address: median={qa['p50']} min={qa['min']} max={qa['max']}")
        fracs = sorted(e / c for e, c, _ in pos)
        print(f"   as a fraction of the run: median={statistics.median(fracs):.2f} min={min(fracs):.2f} max={max(fracs):.2f}")
        first_two = sum(1 for e, _c, _p in pos if e <= 2)
        print(f"   earliest <= 2: {first_two} of {len(pos)} ({pct(first_two, len(pos))})")
        # The fraction is what the pruning question is about, and on a two-crash-point run
        # it can only be 0.5 or 1.0 -- 39 of the 123 runs have exactly two. Read it where
        # there is room for it to be small.
        big = [(e, c, p) for e, c, p in pos if c >= 5]
        if big:
            bf = sorted(e / c for e, c, _ in big)
            qb = quantiles([e for e, _c, _p in big])
            print(f"   runs with >= 5 crash points: n={len(big)} earliest median={qb['p50']} "
                  f"(fraction median={statistics.median(bf):.2f}, min={min(bf):.2f}, max={max(bf):.2f})")
        worst = sorted(pos, key=lambda t: -(t[0] / t[1]))[:5]
        print("   latest by fraction:")
        for e, c, p in worst:
            print(f"     {e}/{c} = {e / c:.2f}  {p}")
    print()

    print("== 5. per target (each target's runs merged; crash points are the max seen) ==")
    print(f"   {'target':24s} {'runs':>4s} {'cp':>5s} {'worlds':>7s} {'viol':>5s} {'earliest':>8s}  verdicts")
    for t in sorted(by_target, key=lambda k: -max(x["crash_points"] for x in by_target[k])):
        v = by_target[t]
        cps = sorted({x["crash_points"] for x in v})
        es = sorted({x["earliest"] for x in v if x["earliest"]})
        vios = sorted({x["violations"] for x in v})
        vs = "/".join(sorted({x["verdict"] for x in v}))
        print(
            f"   {t:24s} {len(v):4d} {max(cps):5d} {sum(x['explored'] for x in v):7d} "
            f"{','.join(str(x) for x in vios):>5s} {','.join(str(x) for x in es) or '-':>8s}  {vs}"
        )
    print()

    print("== 6. refusals, for completeness (excluded from every figure above) ==")
    rc = Counter(r["unknown_reason"] or r["verdict"] for r in refused)
    for k, n in rc.most_common():
        print(f"   {n:3d}  {k}")

    if args.tsv:
        with open(args.tsv, "w", encoding="utf-8") as fh:
            cols = ["path", "run", "target", "verdict", "contract", "crash_points", "explored", "violations", "earliest", "unknown_reason"]
            fh.write("\t".join(cols) + "\n")
            for r in sorted(rows, key=lambda r: r["path"]):
                fh.write("\t".join("" if r[c] is None else str(r[c]) for c in cols) + "\n")
        print(f"\nper-report rows written to {args.tsv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
