#!/usr/bin/env python3
"""Derive an authoring run's figures from its committed evidence (#618, ADR 0077).

The figures this study publishes are not typed by hand. They come from two committed things:

  * the normalised transcript (`transcript.jsonl`) — one JSON object per line, each with a
    `ts` (ISO 8601) and a `text`, in the order the session produced them;
  * the watcher's snapshots (`revisions/NN.toml` and `revisions/index.tsv`) — every define the
    subject wrote, in the order it was observed, copied by the apparatus rather than by the
    subject (`watch-defines.py`).

**Elapsed figures come from the transcript; revisions are counted, not timed.** The watcher runs
on the container's clock and the session on the host's, so this never subtracts one from the
other: `runnable` is published as an elapsed and a revision number, and the semantic point is
published as a **revision number only**. What this refuses on is evidence that cannot be read:
a gap in the snapshot sequence, an index row that does not match its snapshot, or a verdict in
the transcript with no define ever seen — a run whose watcher stopped is void, not short. Those
refusals are what the selftest exercises, and none of them depends on how many times a
particular subject happened to revise.

Usage:
    audit.py <run-dir>             derive and print
    audit.py --check <run-dir>     same, non-zero exit on any refusal
    audit.py --selftest            synthetic fixtures only; touches no run
"""

import hashlib
import json
import re
import sys
import tempfile
from datetime import datetime
from pathlib import Path

# A verdict line as the engine prints it: the run became *runnable* here.
VERDICT = re.compile(r"^(PASS|FAIL)\b", re.M)
# Strings that say the subject reached this repository. The Disposition step reads this list.
# Strings that say the subject REACHED this repository — a route, not a mention.
#
# `github.com/yottayoshida/sideeye` and `checker-cookbook` were in the first version and are
# out: the README this apparatus copies into the box quotes both, and the prompt tells the
# subject to read that README. Every run would have lit the detector for obeying its
# instructions — the void run did, and reading why is how this was found. What is left is a
# fetch, a clone, or a path that exists only inside the repository's working tree.
REPO_TRACE = [
    "raw.githubusercontent.com",
    "git clone",
    # The tool's USE, not its name: a session's opening event lists every tool available to it,
    # so the bare word `WebFetch` matched the void run for existing rather than for being called.
    '"name": "WebFetch"',
    '"name": "WebSearch"',
    "defines-b2",
    "spike/unknown-rate",
    # The study's own directory: `cards/` IS the answer key, and a subject that reached it would
    # otherwise have been graded without the list ever saying so.
    "spike/authoring-cost",
    "authoring-cost/cards",
    "grade-rubric",
]


class Refusal(Exception):
    pass


def _ts(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _rows(path):
    """The data rows of a tab-separated record, without comments or blanks."""
    return [
        line.split("\t")
        for line in path.read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    ]


def read_transcript(path):
    path = Path(path)
    events = []
    with path.open(encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as exc:
                raise Refusal(f"{path}:{n} is not JSON: {exc}")
            if "ts" not in obj or "text" not in obj:
                raise Refusal(f"{path}:{n} lacks ts or text")
            events.append(obj)
    if not events:
        raise Refusal(f"{path} holds no events")
    return events


def read_revisions(run_dir):
    d = Path(run_dir) / "revisions"
    if not d.is_dir():
        raise Refusal("no revisions/ — the watcher wrote nothing, so no define was seen")
    numbers = []
    for f in d.glob("*.toml"):
        stem = f.stem
        if not stem.isdigit():
            raise Refusal(f"revisions/{f.name} is not a number")
        numbers.append(int(stem))
    # Sorted as numbers, not as names: the watcher writes `100.toml` after `99.toml`, and a
    # lexicographic sort would put it between `1` and `2` and read the sequence as a gap.
    numbers.sort()
    if not numbers:
        raise Refusal(
            "revisions/ holds no .toml snapshot — the watcher copied nothing, so this run is "
            "void rather than fast, whatever the transcript shows"
        )
    expected = list(range(1, len(numbers) + 1))
    if numbers != expected:
        raise Refusal(
            f"revisions/ is not a complete sequence: found {numbers}, expected {expected} — "
            "a snapshot is missing, so the order the defines were written in is unknown"
        )
    # The index is the watcher's own account of what it copied. A snapshot it does not claim,
    # or a claim whose digest is not the snapshot's, means the two halves of the evidence
    # disagree — which is exactly the state that would otherwise be published as a figure.
    index = d / "index.tsv"
    if index.exists():
        rows = _rows(index)
        if len(rows) != len(numbers):
            raise Refusal(
                f"revisions/index.tsv claims {len(rows)} snapshot(s) but {len(numbers)} exist"
            )
        for row in rows:
            if len(row) < 3:
                raise Refusal(f"revisions/index.tsv row is malformed: {row}")
            snap = d / f"{int(row[0]):02d}.toml"
            got = hashlib.sha256(snap.read_bytes()).hexdigest()
            if got != row[2]:
                raise Refusal(
                    f"revisions/{snap.name} hashes to {got[:12]}… but its index row says {row[2][:12]}…"
                )
    return numbers


def derive(run_dir):
    events = read_transcript(Path(run_dir) / "transcript.jsonl")
    revisions = read_revisions(run_dir)

    # The clock's start. A transcript's first event may carry no timestamp — the onboarding
    # clock measured exactly that on its own run 1 — so the launcher stamps `started` into
    # meta.json and this falls back to it. An unusable start is a refusal, not a traceback:
    # every elapsed figure below would otherwise be derived from a guess.
    start = None
    for e in events:
        if e["ts"]:
            start = _ts(e["ts"])
            break
    if start is None:
        meta = Path(run_dir) / "meta.json"
        if meta.exists():
            stamped = json.loads(meta.read_text(encoding="utf-8")).get("started", "")
            if stamped:
                start = _ts(stamped)
    if start is None:
        raise Refusal(
            "no event carries a timestamp and meta.json stamps no start: the session's clock "
            "cannot be read, so no elapsed figure can be published"
        )

    runnable = None
    for e in events:
        if VERDICT.search(e["text"]):
            runnable = e
            break

    # No `runnable_revision`: which snapshot was in the box when the verdict arrived would need
    # the watcher's clock compared with the session's, and this refuses to cross them. An
    # earlier version published one and computed it as the highest row in the index — always the
    # total, whatever the verdict's timestamp, with a comment claiming otherwise.
    result = {
        "run": Path(run_dir).resolve().name,
        "revisions": len(revisions),
        "started": start.isoformat().replace("+00:00", "Z"),
        "runnable_elapsed_s": None,
        "repo_traces": [],
    }
    if runnable is not None and runnable["ts"]:
        result["runnable_elapsed_s"] = int((_ts(runnable["ts"]) - start).total_seconds())

    for e in events:
        for needle in REPO_TRACE:
            if needle in e["text"]:
                result["repo_traces"].append({"ts": e["ts"], "matched": needle})

    # The semantic point is not derived here: it is whichever revision BOTH graders accepted,
    # and grading happens after this. When grades/*.tsv exist, the agreed revision is read from
    # them; where they disagree the run is `contested` and no semantic figure is published.
    grades_dir = Path(run_dir) / "grades"
    accepted = []
    if grades_dir.is_dir():
        per_grader = []
        for path in sorted(grades_dir.glob("*.tsv")):
            ok = set()
            with path.open(encoding="utf-8") as fh:
                for line in fh:
                    parts = line.split("\t")
                    if len(parts) >= 2 and parts[1].strip() == "semantically valid":
                        ok.add(parts[0].strip())
            per_grader.append(ok)
        if len(per_grader) >= 2:
            agreed = set.intersection(*per_grader)
            accepted = sorted(agreed, key=lambda s: (len(s), s))
    result["semantic_revision"] = accepted[0] if accepted else None
    result["semantic_status"] = "graded" if accepted else "contested-or-ungraded"
    # No elapsed for the semantic point on purpose: it would cross the two clocks.
    return result


def _fixture(tmp, revisions, invocations, gap=False, bad_digest=False, verdict=True):
    run = Path(tmp) / "fixture"
    (run / "revisions").mkdir(parents=True, exist_ok=True)
    rows = []
    for i in range(1, revisions + 1):
        n = i + 1 if (gap and i == revisions) else i
        body = f'operation = "true"  # {n}\n'
        (run / "revisions" / f"{n:02d}.toml").write_text(body, encoding="utf-8")
        h = hashlib.sha256(body.encode()).hexdigest()
        if bad_digest and i == 1:
            h = "0" * 64
        rows.append(f"{n:02d}\t2026-09-19T00:0{i}:30Z\t{h}\t/home/user/sideeye.toml")
    (run / "revisions" / "index.tsv").write_text(
        "# NN\tobserved\tsha256\tpath\n" + "\n".join(rows) + "\n", encoding="utf-8"
    )
    lines = [{"ts": "2026-09-19T00:00:00Z", "text": "start"}]
    for i in range(invocations):
        lines.append({"ts": f"2026-09-19T00:0{i + 1}:00Z", "text": "sideeye explore --state /s"})
    if verdict:
        lines.append({"ts": "2026-09-19T00:09:00Z", "text": "PASS over 3 crash points"})
    (run / "transcript.jsonl").write_text(
        "".join(json.dumps(obj) + "\n" for obj in lines), encoding="utf-8"
    )
    return run


def selftest():
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        # 1. A complete run: three snapshots, three invocations, one verdict.
        run = _fixture(tmp, 3, 3)
        try:
            out = derive(run)
            if out["revisions"] != 3:
                print(f"FAIL selftest: complete run read {out['revisions']} revisions")
                failures += 1
            elif out["runnable_elapsed_s"] != 540:
                print(f"FAIL selftest: elapsed {out['runnable_elapsed_s']}s, expected 540")
                failures += 1
            else:
                print("ok   a complete run derives its revision count and its runnable point")
        except Refusal as exc:
            print(f"FAIL selftest: complete run refused: {exc}")
            failures += 1

    with tempfile.TemporaryDirectory() as tmp:
        # 2. A gap: snapshots 01, 02, 04. Nothing about the subject changed.
        run = _fixture(tmp, 3, 3, gap=True)
        try:
            derive(run)
            print("FAIL selftest: a gapped revision sequence was accepted")
            failures += 1
        except Refusal as exc:
            if "complete sequence" not in str(exc):
                print(f"FAIL selftest: refused for the wrong reason: {exc}")
                failures += 1
            else:
                print("ok   a gapped revision sequence is refused, naming the gap")

    with tempfile.TemporaryDirectory() as tmp:
        # 3. The watcher's own account disagrees with what it copied.
        run = _fixture(tmp, 3, 3, bad_digest=True)
        try:
            derive(run)
            print("FAIL selftest: an index row that does not match its snapshot was accepted")
            failures += 1
        except Refusal as exc:
            if "index row says" not in str(exc):
                print(f"FAIL selftest: refused for the wrong reason: {exc}")
                failures += 1
            else:
                print("ok   an index row whose digest is not its snapshot's is refused")

    with tempfile.TemporaryDirectory() as tmp:
        # 4. A verdict with no define seen: the watcher was not running.
        run = _fixture(tmp, 0, 1)
        try:
            derive(run)
            print("FAIL selftest: a verdict with no snapshot was accepted")
            failures += 1
        except Refusal as exc:
            if "void rather than fast" not in str(exc):
                print(f"FAIL selftest: refused for the wrong reason: {exc}")
                failures += 1
            else:
                print("ok   a verdict with no define ever snapshotted is refused")

    if failures:
        print(f"FAIL {failures} selftest case(s)")
        return 1
    print("ok   audit selftest: 4 case(s), the apparatus refuses on incomplete evidence")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    check = len(argv) == 3 and argv[1] == "--check"
    if not (len(argv) == 2 or check):
        print(__doc__)
        return 2
    run_dir = argv[2] if check else argv[1]
    try:
        out = derive(run_dir)
    except Refusal as exc:
        print(f"REFUSED: {exc}")
        return 1 if check else 0
    print(json.dumps(out, indent=2, sort_keys=True))
    if out["repo_traces"]:
        print(
            f"\nnote: {len(out['repo_traces'])} transcript event(s) name this repository; "
            "PROTOCOL.md's Disposition step 2 (adjudicate) applies before grading.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
