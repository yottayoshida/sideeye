#!/usr/bin/env python3
"""tally.py — the figures and the decision for the 2026-10-15 authoring run (#873).

    tally.py               print the block SYNTHESIS.md carries
    tally.py --check       fail unless SYNTHESIS.md carries that block, the seal is intact, and the
                           seal reached GitHub before every transcript's first event
    tally.py --manifest    print the sealed files' manifest hash
    tally.py --seal-line   print the line every prompt starts with (needs seal.json)
    tally.py --selftest    the decision table and the agreement rules against planted inputs
"""
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SEALED = [
    "PROTOCOL.md", "prompt.md", "grader-prompt.md", "rubric.md", "vocabulary.txt", "CANDIDATES.md",
    "exclude.sh", "screen.sh", "tally.py", "normalise.py", "run-subject.sh", "run-grader.sh", "box.sh",
    "watch-defines.py", "check-sealed.sh", "apparatus/Dockerfile", "apparatus/build.sh",
]
SEALED_AFTER_SCREEN = ["SELECTION.md", "selection.tsv", "screen.tsv", "screen-1.tsv"]
NO_CHANGE = "no product change warranted"
BEGIN, END = "<!-- tally:begin -->", "<!-- tally:end -->"
RESULT = re.compile(r"(?:^|\\n)(PASS|FAIL|UNKNOWN|SETUP ERROR)  ")
SEAL = re.compile(r"Seal: ([0-9a-f]{64})")


def _audit():
    spec = importlib.util.spec_from_file_location("audit618", ROOT / "spike/authoring-cost/audit.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def sealed_files():
    files = list(SEALED)
    if (HERE / "SELECTION.md").exists():
        files += SEALED_AFTER_SCREEN + sorted(str(p.relative_to(HERE)) for p in (HERE / "cards").glob("*.md"))
    return files


def manifest():
    lines = []
    for rel in sealed_files():
        lines.append("%s  %s" % (hashlib.sha256((HERE / rel).read_bytes()).hexdigest(), rel))
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()


def seal():
    path = HERE / "seal.json"
    if not path.exists():
        raise SystemExit("tally: no seal.json — the sealed commit has not been pushed and recorded, so no subject may run")
    return json.loads(path.read_text())


def vocabulary():
    return [l for l in (HERE / "vocabulary.txt").read_text().splitlines() if l and not l.startswith("#")]


def _when(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def agree(g1, g2, vocab):
    """The two graders' agreed findings for one run."""
    out = {"checker": g1["checker"] if g1["checker"] == g2["checker"] else "contested", "controls": {}, "keys": []}
    c2 = {c["file"]: c["breaks_only_its_leg"] for c in g2.get("controls", [])}
    for c in g1.get("controls", []):
        other = c2.get(c["file"])
        out["controls"][c["file"]] = c["breaks_only_its_leg"] if other == c["breaks_only_its_leg"] else "contested"
    f2 = {f["row"]: f["key"] for f in g2.get("friction", [])}
    for f in g1.get("friction", []):
        if f2.get(f["row"]) == f["key"] and f["key"] in vocab:
            out["keys"].append(f["key"])
    used = set()
    for a in g1.get("added", []):
        for i, b in enumerate(g2.get("added", [])):
            if i not in used and a["key"] == b["key"] and a["key"] in vocab and abs(a["event"] - b["event"]) <= 10:
                used.add(i)
                out["keys"].append(a["key"])
                break
    return out


def decide(agreed_by_target, vocab):
    """The PROTOCOL's table: first row that matches."""
    targets, rows = {}, {}
    for target, a in agreed_by_target.items():
        for k in a["keys"]:
            if k in ("target", "other"):
                continue
            targets.setdefault(k, set()).add(target)
            rows[k] = rows.get(k, 0) + 1
    repeated = [k for k, ts in targets.items() if len(ts) >= 2]
    if repeated:
        best = sorted(repeated, key=lambda k: (-len(targets[k]), -rows[k], vocab.index(k)))
        tie = len(best) > 1 and (len(targets[best[0]]), rows[best[0]]) == (len(targets[best[1]]), rows[best[1]])
        return 1, best[0], tie, []
    if targets:
        return 2, NO_CHANGE, False, sorted(targets, key=vocab.index)
    return 3, NO_CHANGE, False, []


def run_figures(run, audit):
    meta = json.loads((run / "meta.json").read_text())
    events = audit.read_transcript(run / "transcript.jsonl")
    explores = [e for e in events if "sideeye explore" in e["text"] or "/sideeye explore" in e["text"]]
    results = [m.group(1) for e in events for m in RESULT.finditer(e["text"])]
    idx = run / "revisions" / "scripts" / "index.tsv"
    script_rows = [l.split("\t") for l in idx.read_text().splitlines() if l and not l.startswith("#")] if idx.exists() else []
    revisions = {}
    for r in script_rows:
        if len(r) >= 4:
            name = Path(r[3]).name
            revisions[name] = revisions.get(name, 0) + 1
    toml_idx = run / "revisions" / "index.tsv"
    revisions["sideeye.toml"] = len([l for l in toml_idx.read_text().splitlines() if l and not l.startswith("#")]) if toml_idx.exists() else 0
    first, last = _when(events[0]["ts"]), _when(events[-1]["ts"])
    first_explore = (_when(explores[0]["ts"]) - first).total_seconds() if explores else None
    return {
        "disposition": meta.get("disposition", "pending"),
        "judged_states": len(audit.judged_sets(events)),
        "revisions": revisions,
        "result": results[-1] if results else "none",
        "session_s": int((last - first).total_seconds()),
        "first_explore_s": None if first_explore is None else int(first_explore),
        "events": events,
    }


def block():
    audit = _audit()
    vocab = vocabulary()
    lines, agreed = [], {}
    for run in sorted(p for p in (HERE / "runs").glob("*") if p.is_dir()):
        f = run_figures(run, audit)
        if f["disposition"] == "void":
            lines.append("%s: void" % run.name)
            continue
        grades = [json.loads(p.read_text()) for p in sorted((run / "grades").glob("g*.json"))]
        a = agree(grades[0], grades[1], vocab) if len(grades) == 2 else None
        if a:
            agreed[run.name] = a
        revs = ", ".join("%s %d" % (k, v) for k, v in sorted(f["revisions"].items()))
        lines.append("%s: %s; judged states %d; revisions: %s; result %s; session %ds, first explore %s (a model's seconds, host clock)"
                     % (run.name, f["disposition"], f["judged_states"], revs, f["result"], f["session_s"],
                        "-" if f["first_explore_s"] is None else "%ds" % f["first_explore_s"]))
        if a:
            ctl = ", ".join("%s %s" % (k, v) for k, v in sorted(a["controls"].items())) or "none"
            lines.append("  checker %s; controls breaking only their leg: %s; agreed keys: %s" % (a["checker"], ctl, ", ".join(a["keys"]) or "none"))
        else:
            lines.append("  not graded by two graders")
    row, change, tie, hyp = decide(agreed, vocab)
    lines.append("decision row %d: next change: %s%s" % (row, change, " (a tie, broken by vocabulary order)" if tie else ""))
    if hyp:
        lines.append("hypotheses (one target each): %s" % ", ".join(hyp))
    return "\n".join(lines)


def check():
    bad = []
    s = seal()
    if manifest() != s["manifest"]:
        bad.append("the sealed files hash to %s, not the %s seal.json records" % (manifest(), s["manifest"]))
    sealed_at = _when(s["pr_created_at"])
    audit = _audit()
    for run in sorted(p for p in (HERE / "runs").glob("*") if p.is_dir()):
        events = audit.read_transcript(run / "transcript.jsonl")
        if _when(events[0]["ts"]) <= sealed_at:
            bad.append("%s's first event precedes the seal reaching GitHub (%s)" % (run.name, s["pr_created_at"]))
        if not any(SEAL.search(e["text"]) and s["manifest"] in e["text"] for e in events[:5]):
            bad.append("%s's transcript does not open with the seal line" % run.name)
    text = (HERE / "SYNTHESIS.md").read_text()
    m = re.search(re.escape(BEGIN) + r"\n```\n(.*?)\n```\n" + re.escape(END), text, re.S)
    if not m or m.group(1) != block():
        bad.append("SYNTHESIS.md's block is not tally.py's output")
    for b in bad:
        print("FAIL " + b)
    if not bad:
        print("ok   seal intact, reached GitHub before every run, and SYNTHESIS.md's block recomputes")
    return 1 if bad else 0


def selftest():
    vocab = ["cookbook:missing", "cli:--scratch", "checker:verification-helper-missing", "target", "other"]
    g = lambda checker, rows, added=(): {"checker": checker, "controls": [{"file": "control-a.sh", "breaks_only_its_leg": "yes"}],
                                          "friction": [{"row": i + 1, "key": k} for i, k in enumerate(rows)],
                                          "added": [{"event": e, "key": k} for e, k in added]}
    cases = [
        ("one key in two targets wins", {"a": agree(g("v", ["cookbook:missing"]), g("v", ["cookbook:missing"]), vocab),
                                         "b": agree(g("v", ["cookbook:missing"]), g("v", ["cookbook:missing"]), vocab)}, (1, "cookbook:missing")),
        ("graders disagreeing on a row count nothing", {"a": agree(g("v", ["cookbook:missing"]), g("v", ["cli:--scratch"]), vocab),
                                                        "b": agree(g("v", ["cookbook:missing"]), g("v", ["cli:--scratch"]), vocab)}, (3, NO_CHANGE)),
        ("a key in one target only is a hypothesis", {"a": agree(g("v", ["cli:--scratch"]), g("v", ["cli:--scratch"]), vocab)}, (2, NO_CHANGE)),
        ("target and other never decide", {"a": agree(g("v", ["target"]), g("v", ["target"]), vocab),
                                           "b": agree(g("v", ["target"]), g("v", ["target"]), vocab)}, (3, NO_CHANGE)),
        ("added rows agree within ten events", {"a": agree(g("v", [], [(40, "cli:--scratch")]), g("v", [], [(48, "cli:--scratch")]), vocab),
                                                "b": agree(g("v", [], [(5, "cli:--scratch")]), g("v", [], [(9, "cli:--scratch")]), vocab)}, (1, "cli:--scratch")),
        ("added rows further apart do not", {"a": agree(g("v", [], [(40, "cli:--scratch")]), g("v", [], [(60, "cli:--scratch")]), vocab),
                                             "b": agree(g("v", [], [(5, "cli:--scratch")]), g("v", [], [(30, "cli:--scratch")]), vocab)}, (3, NO_CHANGE)),
        ("a key outside the vocabulary is not counted", {"a": agree(g("v", ["made-up"]), g("v", ["made-up"]), vocab),
                                                         "b": agree(g("v", ["made-up"]), g("v", ["made-up"]), vocab)}, (3, NO_CHANGE)),
    ]
    fails = 0
    for name, agreed, want in cases:
        got = decide(agreed, vocab)[:2]
        if got != want:
            fails += 1
            print("FAIL %s: got %s, wanted %s" % (name, got, want))
    if agree(g("semantically valid", []), g("vacuous checker", []), vocab)["checker"] != "contested":
        fails += 1
        print("FAIL graders disagreeing on the checker leave it contested")
    total = len(cases) + 1
    print(("ok   tally selftest: %d of %d" % (total, total)) if not fails else "FAIL tally selftest: %d of %d" % (fails, total))
    return 1 if fails else 0


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if argv == ["--manifest"]:
        print(manifest())
        return 0
    if argv == ["--seal-line"]:
        s = seal()
        print("Seal: %s (draft pull request #%s, opened %s)" % (s["manifest"], s["pr"], s["pr_created_at"]))
        return 0
    if argv == ["--check"]:
        return check()
    if not argv:
        print(block())
        return 0
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
