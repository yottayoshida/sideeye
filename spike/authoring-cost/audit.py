#!/usr/bin/env python3
"""Derive an authoring run's figures from its committed evidence (#618, ADR 0077).

The figures this study publishes are not typed by hand. They come from two committed things:

  * the normalised transcript (`transcript.jsonl`) — one JSON object per line, each with a
    `ts` (ISO 8601) and a `text`, in the order the session produced them;
  * the watcher's snapshots (`revisions/NN.toml` and `revisions/index.tsv`) — every define the
    subject wrote, in the order it was observed, copied by the apparatus rather than by the
    subject (`watch-defines.py`).

**Elapsed figures come from the transcript; the rest is counted, not timed.** The watcher runs
on the container's clock and the session on the host's, so this never subtracts one from the
other: `runnable` is published as an elapsed and a revision number, and the semantic point is
published as a **revision number only**.

**The primary count is `judged_states`, not `revisions`.** A define handed to the engine on the
command line never becomes a file, so the watcher never sees it — measured across the four runs,
three reached a judged set no snapshot caught, and one of those is the state its card calls the
wrong question. The engine prints what it judged on every run, so the transcript holds them all.

What this refuses on is evidence that cannot be read: a gap in the snapshot sequence, an index
row that does not match its snapshot, a verdict in the transcript with no define ever seen — a
run whose watcher stopped is void, not short — and a record that does not carry its judged-set
sequence, or carries one that is not what its transcript holds.

Usage:
    audit.py <run-dir>               derive and print
    audit.py --check <run-dir>       same, non-zero exit on any refusal
    audit.py --check-all             every published run; a void run is reported, not enforced
    audit.py --check-page <page.md>  hold a page's run table to what the evidence derives
    audit.py --write-sequence <run>  write the judged-set sequence into the run's meta.json
    audit.py --selftest              synthetic fixtures only; touches no run
"""

import hashlib
import json
import re
import sys
import tempfile
from datetime import datetime
from pathlib import Path

# A verdict line as the engine prints it: the run became *runnable* here.
#
# The line start is matched in the ENCODED text. Each event arrives here as `json.dumps(event)`
# (run-authoring.sh, "Normalisation"), so a newline the engine printed is carried as the two
# characters `\` and `n`, and a plain `re.M` anchor has nothing but the leading `{` to sit on.
# Measured on the first real run: `^(PASS|FAIL)\b` with re.M matched 0 of 500 events while
# three of them held a real engine verdict, so every run would have published no runnable point
# and the null would have read as "the subject never got that far".
#
# The alternation keeps `^` (re.M) as well — a decoded transcript, were one ever passed in,
# still matches — and adds the escape, which is the shape this apparatus actually writes.
VERDICT = re.compile(r"(?:^|\\n)(PASS|FAIL)\b", re.M)
# The rubric's closed set of verdicts (grade-rubric.md). A sheet must carry one of these for
# every revision its own map names — see the `missing` refusal below.
VERDICTS = frozenset(
    {"semantically valid", "wrong question", "vacuous checker", "unresolved by card"}
)
# The engine's own account of WHAT IT JUDGED, echoed on every run: `N path(s) judged
# pre-or-post`, and when the define declared scratch, `; K path(s) matched by scratch, not
# judged (declared: …)`. This is the study's second ledger.
#
# `watch-defines.py` snapshots `*.toml`, so a define handed to the engine on the command line
# never becomes a revision. Measured on the four runs: three of them decided something the
# graders never saw, and `fossil`'s unrecorded state is the one its card calls the wrong
# question. The transcript holds those states because the engine printed this line for each.
#
# The count must sit immediately before ` path(s)`: a transcript also carries the bare format
# string out of a grep of the engine's own source (`33477: path(s) judged pre-or-post`, measured
# in `lmdb-utils` at 07:48:06), and an anchorless pattern reads that as a judged set.
# Read in two steps, because one expression got this wrong in three ways at once and could not
# detect any of them: `--write-sequence` and `derive()` share the walk, so a misreading is
# self-consistent and the guard agrees with itself forever.
#
# What the single expression that stood here —
#   `…pre-or-post(?:; …matched by scratch, not judged \(declared: ([^)\\"]{0,200})\))?`
# — got wrong, each measured against that exact pattern:
#   * the HISTORY form puts a clause between the two (`; H file(s) judged by the history
#     form …; K path(s) matched by scratch …`), so the optional group did not match at all and
#     the scratch declaration silently became "";
#   * `(+K more)` truncation ends in `))`, and the class stopping at the first `)` stored
#     `a, b, c (+3 more` — which reached `runs/fossil/meta.json` before this was fixed;
#   * the class excludes `"` and `\` and caps at 200, so a declaration holding either, or
#     longer than that, also silently became "" (`appendSanitized` escapes neither character).
# Each one collapses two adjacent states that differ only in their scratch into one, which
# undercounts the study's primary figure with nothing refusing.
JUDGED_COUNT = re.compile(r"([0-9]+) path\(s\) judged pre-or-post")
# The declaration's end is found by BALANCING the parenthesis `(declared:` opened, not by
# position. Two measured failures of position-based reads, both silent: a lazy `(.*?)\)(?!\))`
# read `data (1).mdb` as `data (1`, and reading to the last `)` on the line broke the moment an
# l0 line was the final thing in its event, where the window carries the JSON's own `)"}`.
# Balance is indifferent to both. A clause that never closes is refused rather than guessed.
SCRATCH_START = re.compile(r"([0-9]+) path\(s\) matched by scratch, not judged \(declared: ")
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


def judged_sets(events):
    """The judged sets the subject actually had the engine judge, in order.

    **Adjacent repeats are collapsed, non-adjacent ones are not.** Each event reaches this
    file twice — once as the tool call, once as its result — so an un-collapsed walk doubles
    every entry; and two consecutive runs of the same define are the same state, not two.
    What must survive is a RETURN: `lmdb-utils` went `2` → `1 (scratch lock.mdb)` → **`2`** →
    `1 (scratch data.mdb)`, and a walk that collapsed by value rather than by adjacency read
    that as three states and lost the round trip — which is the single best piece of evidence
    that the subject had no handle on the judged set. The first draft of this study's
    conclusion made exactly that mistake.
    """
    seq = []
    for e in events:
        for m in JUDGED_COUNT.finditer(e["text"]):
            # The rest of this l0 line only. Lines arrive as the two characters `\` and `n`
            # inside a serialised event, so that is the terminator.
            tail = e["text"][m.end() :]
            end = tail.find("\\n")
            line = tail if end < 0 else tail[:end]
            scratch, matched = "", 0
            hit = SCRATCH_START.search(line)
            if hit:
                rest = line[hit.end() :]
                # Close on the parenthesis that balances `(declared:`, counting depth rather
                # than trusting position. `a, b, c (+3 more))` closes on the second, a path
                # holding `data (1).mdb` closes at the end, and whatever follows the clause —
                # the l0 string sits inside a JSON value, so it can be `)"}` or `)'` — is
                # irrelevant. Reading to the last `)` on the line got this wrong the moment an
                # l0 line was the final thing in its event.
                depth, close = 1, -1
                for i, ch in enumerate(rest):
                    depth += (ch == "(") - (ch == ")")
                    if depth == 0:
                        close = i
                        break
                if close < 0:
                    raise Refusal(
                        f"an l0 line at {e['ts']} declares scratch and does not close it: "
                        f"{line[:160]!r}"
                    )
                scratch, matched = rest[:close].strip(), int(hit.group(1))
            elif "matched by scratch" in line:
                # Refuse rather than record "". An unreadable declaration used to read as no
                # declaration at all, which merges this state into its neighbour.
                raise Refusal(
                    f"an l0 line at {e['ts']} declares scratch and could not be read: "
                    f"{line[:160]!r}"
                )
            # `matched` is the engine's count of RECORDED paths the declaration reached, which
            # is not the number of patterns declared — `fossil` declared six and four matched.
            # Two states with the same declaration and a different reach are different states.
            entry = {"judged": int(m.group(1)), "scratch": scratch, "matched": matched}
            if seq and all(seq[-1][k] == entry[k] for k in ("judged", "scratch", "matched")):
                continue
            seq.append({"ts": e["ts"], **entry})
    return seq


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

    # The judged-set sequence, derived here and held against what the run publishes.
    #
    # `watch-defines.py`'s docstring already promised this: a define piped straight into the
    # engine "is not seen (the run's transcript still holds it, and **the audit's counts will
    # disagree, which is a refusal rather than a silent gap**)". Nothing implemented it, and
    # five published runs went through in silence. The refusal is on the RECORD, not on the
    # disagreement: a count that differs from the snapshot total is a fact this study publishes
    # (the watcher's first documented blind spot — a rewrite inside one second — produces one
    # legitimately), while a run that does not carry its sequence at all cannot be read.
    derived = judged_sets(events)
    meta_path = Path(run_dir) / "meta.json"
    if not meta_path.exists():
        raise Refusal(
            "no meta.json — a run with no record cannot carry its judged-set sequence, and "
            "skipping it here let the new refusal be avoided by deleting a file"
        )
    else:
        recorded = json.loads(meta_path.read_text(encoding="utf-8")).get("judged_sets")
        if recorded is None:
            raise Refusal(
                "meta.json carries no `judged_sets`: the engine printed what it judged on every "
                f"run ({len(derived)} state(s) in this transcript) and the record does not hold "
                "them, so the states no snapshot caught are unreadable. Write them with "
                "`audit.py --write-sequence <run>`"
            )
        keys = ("judged", "scratch", "matched")
        if [{k: s.get(k) for k in keys} for s in recorded] != [
            {k: s.get(k) for k in keys} for s in derived
        ]:
            raise Refusal(
                f"meta.json's `judged_sets` ({len(recorded)} state(s)) is not what this "
                f"transcript holds ({len(derived)} state(s)) — the record was edited away from "
                "its evidence"
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
        # How many judged sets the subject reached, against how many the watcher caught. These
        # are not the same measurement and the study stopped calling `revisions` its primary
        # figure when they came apart: a define never written to a file is invisible to the
        # watcher and fully visible here.
        "judged_states": len(derived),
        "judged_sets": derived,
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

    # `semantic_status` is the GRADING state, not the run's outcome form. The two overlap but
    # are not the same list: PROTOCOL.md's forms include `void` (an operator's disposition, in
    # meta.json) and `no-verdict` (no runnable define, visible here as a null elapsed), and this
    # field adds `ungraded`, which is not an outcome at all — it is the state before grading.
    # A run's published form is its disposition plus this field, not this field alone.
    #
    # The semantic point is not derived here: it is whichever revision BOTH graders accepted,
    # and grading happens after this. When grades/*.tsv exist, the agreed revision is read from
    # them; where they disagree the run is `contested` and no semantic figure is published.
    grades_dir = Path(run_dir) / "grades"
    accepted = []
    # `ungraded` until two sheets say otherwise: fewer than two is an unfinished measurement,
    # and it must not read the same as a finished one.
    status = "ungraded"
    if grades_dir.is_dir():
        per_grader = []
        for path in sorted(grades_dir.glob("*.tsv")):
            # Each sheet carries its own mapping, because the two graders see the same
            # revisions under DIFFERENT given ids and in different orders. Intersecting the
            # raw ids — which an earlier version did — would call two graders who accepted the
            # same revision "contested" whenever their labels differed, which is always.
            mapping, ok, judged, verdicts_seen = {}, set(), set(), {}
            with path.open(encoding="utf-8") as fh:
                for line in fh:
                    if line.startswith("# map"):
                        bits = [b.strip() for b in line.split("\t")]
                        if len(bits) >= 3:
                            mapping[bits[1]] = bits[2]
                        continue
                    parts = line.split("\t")
                    if len(parts) >= 2 and parts[1].strip() in VERDICTS:
                        gid, verdict = parts[0].strip(), parts[1].strip()
                        # Two verdict rows for one id is not a grader changing their mind; it
                        # is a sheet that says two things, and one of them is being dropped.
                        # The first version of this compared only *acceptance*, so
                        # `wrong question` beside `vacuous checker` passed — measured. The
                        # comparison is between the verdicts themselves.
                        if gid in verdicts_seen and verdicts_seen[gid] != verdict:
                            raise Refusal(
                                f"grades/{path.name} carries two different verdicts for {gid!r}: "
                                f"{verdicts_seen[gid]!r} and {verdict!r}"
                            )
                        verdicts_seen[gid] = verdict
                        judged.add(gid)
                        if verdict == "semantically valid":
                            ok.add(gid)
            if not mapping:
                raise Refusal(
                    f"grades/{path.name} carries no `# map<TAB>given-id<TAB>revision` lines: "
                    "its verdicts cannot be attached to revisions, and two graders' sheets "
                    "cannot be compared"
                )
            # The map must name the run's revisions — all of them, and nothing else. Neither
            # direction was checked, and both were measured wrong on a fixture: a map covering
            # one of two revisions published `none-valid` for a revision no grader was shown,
            # and a map naming `07` in a run with two revisions published
            # `semantic_revision: "07"` — a semantic point at a snapshot that does not exist.
            # The map↔verdict check below cannot see either: it compares a sheet with itself.
            on_disk = {f"{n:02d}" for n in revisions}
            named = set(mapping.values())
            if named != on_disk:
                unseen = sorted(on_disk - named)
                invented = sorted(named - on_disk)
                detail = []
                if unseen:
                    detail.append(f"never shown to this grader: {unseen}")
                if invented:
                    detail.append(f"named but not in revisions/: {invented}")
                raise Refusal(
                    f"grades/{path.name} maps {sorted(named)} but the run holds "
                    f"{sorted(on_disk)} — " + "; ".join(detail)
                )
            unknown = judged - set(mapping)
            if unknown:
                raise Refusal(
                    f"grades/{path.name} judges {sorted(unknown)}, which its own map does not name"
                )
            # A sheet with its map and NO verdict at all is an assignment that has been drawn
            # and not yet graded — the state every run passes through between
            # `assign-grading.py` and the grader's answer. It does not count as a grader, which
            # leaves the run `ungraded`; refusing it here would have refused the apparatus's own
            # procedure, which is what the first version of this check did.
            if not judged:
                continue
            # A revision the sheet was assigned and PARTLY judged. Without this, a grader who
            # skipped one produces a sheet that reads exactly like a grader who rejected it:
            # both leave the id out of `ok`, and the run publishes `none-valid` or `contested`
            # off a verdict nobody gave. It is the same shape as the two figures this file
            # already lost — a missing measurement must never read as a measured negative.
            missing = set(mapping) - judged
            if missing:
                raise Refusal(
                    f"grades/{path.name} was assigned {sorted(mapping)} but carries no verdict for "
                    f"{sorted(missing)}: an ungraded revision would otherwise be counted as one "
                    "the grader rejected"
                )
            per_grader.append({mapping[g] for g in ok})
        # PROTOCOL.md defines two graders. Three sheets would silently change the rule from
        # "both agreed" to "all three agreed", turning a `graded` run into `contested` with
        # nothing saying why — measured on a fixture.
        if len(per_grader) > 2:
            raise Refusal(
                f"{len(per_grader)} graded sheets in grades/ — the protocol defines two graders, "
                "and the agreement rule is written for two"
            )
        if len(per_grader) >= 2:
            agreed = set.intersection(*per_grader)
            accepted = sorted(agreed, key=lambda s: (len(s), s))
            if accepted:
                status = "graded"
            elif any(per_grader):
                # At least one grader accepted a revision and they never met on one. PROTOCOL.md
                # publishes the disagreement as the finding and no semantic point.
                status = "contested"
            else:
                # Both graded; neither accepted anything. This is a RESULT — the session reached
                # a define the engine would run and never reached one that asked the target's
                # question — and it used to print the same string as a run nobody had graded.
                # `lmdb-utils`, the first measured run, was exactly this, with the two graders
                # agreeing on the verdict and on the deciding card line.
                status = "none-valid"
    result["semantic_revision"] = accepted[0] if accepted else None
    result["semantic_status"] = status
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
    # Every `text` is a SERIALISED EVENT, because that is the only shape the normaliser in
    # run-authoring.sh produces: it stores `json.dumps(event)`, so the field always begins with
    # `{` and every newline inside it is the two characters `\` and `n`. The fixture used to
    # write the verdict as a bare `"PASS over 3 crash points"` — a string that starts with the
    # word — and that shape made the selftest green over a detector that could not fire once on
    # a real run. Measured on the first real transcript: 3 events carried a real engine verdict
    # (13 mention PASS or FAIL at all, which is not the same thing), 0 events
    # carried a real newline, and the audit reported no runnable point at all.
    def event(payload):
        return json.dumps({"type": "assistant", "message": payload}, ensure_ascii=False)

    lines = [{"ts": "2026-09-19T00:00:00Z", "text": event("start")}]
    for i in range(invocations):
        lines.append(
            {"ts": f"2026-09-19T00:0{i + 1}:00Z", "text": event("sideeye explore --state /s")}
        )
    if verdict:
        lines.append(
            {"ts": "2026-09-19T00:09:00Z", "text": event("explored 3 worlds\nPASS over 3 crash points")}
        )
    (run / "transcript.jsonl").write_text(
        "".join(json.dumps(obj) + "\n" for obj in lines), encoding="utf-8"
    )
    # Every run carries a record, and the record carries its judged-set sequence — a fixture
    # without one would exercise a shape the apparatus refuses, so the other cases could not
    # reach what they are about.
    (run / "meta.json").write_text(
        json.dumps({"target": "fixture", "judged_sets": judged_sets(read_transcript(run / "transcript.jsonl"))}),
        encoding="utf-8",
    )
    return run


def _grade_sheets(run, sheets):
    """Write grade sheets into a fixture: {letter: (id -> revision, [accepted ids])}.

    Each sheet gets its own mapping, the way `assign-grading.py` writes them, so a case can
    give the two graders different ids for the same revision — which is the arrangement the
    real study runs under and the one an id-level comparison gets wrong.
    """
    grades = Path(run) / "grades"
    grades.mkdir(exist_ok=True)
    for letter, (mapping, accepted) in sheets.items():
        rows = [f"# grader {letter}"]
        rows += [f"# map\t{gid}\t{rev}" for gid, rev in mapping.items()]
        # EVERY assigned id gets a verdict row: a sheet that judges only the ones it accepted
        # is the skipped-revision shape the audit refuses, and a fixture built that way would
        # have made the refusal impossible to reach.
        for gid in mapping:
            verdict = "semantically valid" if gid in accepted else "wrong question"
            rows.append(f"{gid}\t{verdict}\tnone\tclaim 1")
        (grades / f"{letter}.tsv").write_text("\n".join(rows) + "\n", encoding="utf-8")


def selftest():
    failures = 0
    cases = 0
    with tempfile.TemporaryDirectory() as tmp:
        cases += 1
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
        cases += 1
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
        cases += 1
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

    # 5. The four grading states are distinguishable. They were not: a run both graders had
    #    graded, agreeing exactly that no revision was valid, printed `contested-or-ungraded`
    #    — the same string as a run nobody had opened. That is the study's own headline
    #    quantity reported as a gap, and the first measured run (`lmdb-utils`) was it.
    for label, sheets, expected in [
        ("nobody has graded it", None, "ungraded"),
        (
            "both graded, neither accepted anything",
            {"a": ({"G": "02", "K": "01"}, []), "b": ({"R": "01", "W": "02"}, [])},
            "none-valid",
        ),
        (
            "each accepted a different revision",
            {"a": ({"G": "02", "K": "01"}, ["G"]), "b": ({"R": "01", "W": "02"}, ["R"])},
            "contested",
        ),
        (
            "both accepted the same revision under different ids",
            {"a": ({"G": "02", "K": "01"}, ["K"]), "b": ({"R": "01", "W": "02"}, ["R"])},
            "graded",
        ),
    ]:
        with tempfile.TemporaryDirectory() as tmp:
            cases += 1
            run = _fixture(tmp, 2, 2)
            if sheets:
                _grade_sheets(run, sheets)
            try:
                out = derive(run)
            except Refusal as exc:
                print(f"FAIL selftest: {label}: refused: {exc}")
                failures += 1
                continue
            if out["semantic_status"] != expected:
                print(
                    f"FAIL selftest: {label}: status {out['semantic_status']!r}, "
                    f"expected {expected!r}"
                )
                failures += 1
            elif expected == "graded" and out["semantic_revision"] != "01":
                print(f"FAIL selftest: {label}: revision {out['semantic_revision']!r}, expected '01'")
                failures += 1
            else:
                print(f"ok   grading state: {label} reads as `{expected}`")

    # 5b. The negative half of the verdict detector, which had none: a session with explore
    #     invocations and no verdict line must read null, not a number. Without it every case
    #     above would pass on a detector that matched anything, and `_fixture`'s `verdict`
    #     parameter was dead — nothing called it False, so the "no verdict" shape was never
    #     exercised after the detector was widened to match the escaped line start.
    with tempfile.TemporaryDirectory() as tmp:
        cases += 1
        run = _fixture(tmp, 2, 2, verdict=False)
        try:
            out = derive(run)
        except Refusal as exc:
            print(f"FAIL selftest: a verdictless run was refused: {exc}")
            failures += 1
        else:
            if out["runnable_elapsed_s"] is not None:
                print(f"FAIL selftest: verdictless run read {out['runnable_elapsed_s']}s")
                failures += 1
            else:
                print("ok   a session with no verdict line publishes no runnable point")

    # 6a. Sheets holding their maps and no verdicts: the state between drawing the assignment
    #     and the grader answering. It reads `ungraded`, and refusing it would refuse the
    #     apparatus's own procedure — which the first version of 6b did, on all four real runs.
    with tempfile.TemporaryDirectory() as tmp:
        cases += 1
        run = _fixture(tmp, 2, 2)
        _grade_sheets(run, {"a": ({"G": "02", "K": "01"}, []), "b": ({"R": "01", "W": "02"}, [])})
        for sheet in (run / "grades").glob("*.tsv"):
            kept = [
                line
                for line in sheet.read_text(encoding="utf-8").splitlines()
                if line.startswith("#")
            ]
            sheet.write_text("\n".join(kept) + "\n", encoding="utf-8")
        try:
            out = derive(run)
        except Refusal as exc:
            print(f"FAIL selftest: a drawn-but-ungraded assignment was refused: {exc}")
            failures += 1
        else:
            if out["semantic_status"] != "ungraded":
                print(f"FAIL selftest: drawn-but-ungraded read as {out['semantic_status']!r}")
                failures += 1
            else:
                print("ok   an assignment drawn and not yet graded reads as `ungraded`")

    # 6a2. A map that does not cover the run's revisions, in both directions.
    for label, mapping, needle in [
        ("a map covering one of two revisions", {"G": "01"}, "never shown to this grader"),
        ("a map naming a revision that does not exist", {"G": "07"}, "named but not in revisions/"),
    ]:
        with tempfile.TemporaryDirectory() as tmp:
            cases += 1
            run = _fixture(tmp, 2, 2)
            _grade_sheets(run, {"a": (mapping, []), "b": (dict(mapping), [])})
            try:
                derive(run)
                print(f"FAIL selftest: {label} was accepted")
                failures += 1
            except Refusal as exc:
                if needle not in str(exc):
                    print(f"FAIL selftest: refused for the wrong reason: {exc}")
                    failures += 1
                else:
                    print(f"ok   {label} is refused, naming which revisions")

    # 6a3. Two verdicts for one id, and a third grade sheet. Both refusals were added from a
    #      review finding and neither had a committed case — the code said "measured on a
    #      fixture" about a fixture that lived in a scratch directory for one afternoon, which
    #      is the shape of a guard nobody will notice losing. The contradiction pair is two
    #      NON-accepting verdicts on purpose: the first version compared acceptance only and
    #      let exactly this through.
    with tempfile.TemporaryDirectory() as tmp:
        cases += 1
        run = _fixture(tmp, 1, 1)
        _grade_sheets(run, {"a": ({"G": "01"}, []), "b": ({"R": "01"}, [])})
        sheet = run / "grades" / "a.tsv"
        sheet.write_text(
            sheet.read_text(encoding="utf-8") + "G\tvacuous checker\tnone\tclaim 9\n",
            encoding="utf-8",
        )
        try:
            derive(run)
            print("FAIL selftest: a sheet with two verdicts for one id was accepted")
            failures += 1
        except Refusal as exc:
            if "two different verdicts" not in str(exc):
                print(f"FAIL selftest: refused for the wrong reason: {exc}")
                failures += 1
            else:
                print("ok   two verdicts for one id are refused, naming both")

    with tempfile.TemporaryDirectory() as tmp:
        cases += 1
        run = _fixture(tmp, 1, 1)
        _grade_sheets(
            run,
            {"a": ({"G": "01"}, ["G"]), "b": ({"R": "01"}, ["R"]), "c": ({"W": "01"}, ["W"])},
        )
        try:
            derive(run)
            print("FAIL selftest: a third grade sheet was accepted")
            failures += 1
        except Refusal as exc:
            if "the protocol defines two graders" not in str(exc):
                print(f"FAIL selftest: refused for the wrong reason: {exc}")
                failures += 1
            else:
                print("ok   a third grade sheet is refused rather than tightening the rule")

    # 6b. A sheet that was assigned two revisions and judged only one. The other simply does
    #     not appear in `ok`, which is indistinguishable from a rejection — so the run would
    #     publish `none-valid` or `contested` off a verdict nobody gave.
    with tempfile.TemporaryDirectory() as tmp:
        cases += 1
        run = _fixture(tmp, 2, 2)
        _grade_sheets(run, {"a": ({"G": "02", "K": "01"}, ["G"])})
        sheet = run / "grades" / "a.tsv"
        kept = [
            line
            for line in sheet.read_text(encoding="utf-8").splitlines()
            if not line.startswith("K\t")
        ]
        sheet.write_text("\n".join(kept) + "\n", encoding="utf-8")
        try:
            derive(run)
            print("FAIL selftest: a sheet with an unjudged revision was accepted")
            failures += 1
        except Refusal as exc:
            if "carries no verdict for" not in str(exc):
                print(f"FAIL selftest: refused for the wrong reason: {exc}")
                failures += 1
            else:
                print("ok   a revision a sheet was assigned and never judged is refused")

    # 7. The judged-set sequence: the round trip survives, the noise does not, and a record
    #    that is missing or edited away from its transcript is refused.
    with tempfile.TemporaryDirectory() as tmp:
        cases += 1
        run = _fixture(tmp, 2, 2)
        lines = [json.loads(l) for l in (run / "transcript.jsonl").open(encoding="utf-8")]

        def judged_event(ts, text):
            # Doubled on purpose: every event reaches the audit twice, as the call and as its
            # result, and an un-collapsed walk would read eight states where there are four.
            return [{"ts": ts, "text": json.dumps({"m": text})}] * 2

        # The shape `lmdb-utils` actually produced, plus the grep of the engine's own source
        # that sits in the same transcript and has no count in front of ` path(s)`.
        lines += judged_event("2026-09-19T00:10:00Z", "atomicity 2 path(s) judged pre-or-post")
        lines += judged_event(
            "2026-09-19T00:11:00Z",
            "1 path(s) judged pre-or-post; 1 path(s) matched by scratch, not judged (declared: lock.mdb)",
        )
        lines += judged_event("2026-09-19T00:12:00Z", "33477: path(s) judged pre-or-post")
        lines += judged_event("2026-09-19T00:13:00Z", "atomicity 2 path(s) judged pre-or-post")
        lines += judged_event(
            "2026-09-19T00:14:00Z",
            "1 path(s) judged pre-or-post; 1 path(s) matched by scratch, not judged (declared: data.mdb)",
        )
        (run / "transcript.jsonl").write_text(
            "".join(json.dumps(o) + "\n" for o in lines), encoding="utf-8"
        )
        seq = judged_sets(read_transcript(run / "transcript.jsonl"))
        want = [(2, ""), (1, "lock.mdb"), (2, ""), (1, "data.mdb")]
        got = [(s["judged"], s["scratch"]) for s in seq]
        if got != want:
            print(f"FAIL selftest: judged-set sequence {got}, expected {want}")
            failures += 1
        else:
            print("ok   the judged-set sequence keeps its round trip and drops the grep noise")

        cases += 1
        meta = run / "meta.json"
        meta.write_text(json.dumps({"target": "fixture"}), encoding="utf-8")
        try:
            derive(run)
            print("FAIL selftest: a run with no recorded judged_sets was accepted")
            failures += 1
        except Refusal as exc:
            if "carries no `judged_sets`" not in str(exc):
                print(f"FAIL selftest: refused for the wrong reason: {exc}")
                failures += 1
            else:
                print("ok   a run whose record holds no judged-set sequence is refused")

        cases += 1
        meta.write_text(json.dumps({"target": "fixture", "judged_sets": seq}), encoding="utf-8")
        try:
            derive(run)
        except Refusal as exc:
            print(f"FAIL selftest: the correct sequence was refused: {exc}")
            failures += 1
        else:
            print("ok   a run whose record matches its transcript reads")

        cases += 1
        # The round trip removed — the exact edit the first draft of the conclusion made.
        meta.write_text(
            json.dumps({"target": "fixture", "judged_sets": [seq[0], seq[1], seq[3]]}),
            encoding="utf-8",
        )
        try:
            derive(run)
            print("FAIL selftest: a record edited away from its transcript was accepted")
            failures += 1
        except Refusal as exc:
            if "not what this transcript holds" not in str(exc):
                print(f"FAIL selftest: refused for the wrong reason: {exc}")
                failures += 1
            else:
                print("ok   a record edited away from its transcript is refused")

    # 8. The l0 reader, against every shape the engine actually prints — the single expression
    #    this replaced got three of them wrong and, sharing its walk with the writer, agreed
    #    with itself about all three.
    cases += 1
    shapes = [
        ("plain", "2 path(s) judged pre-or-post\\n", (2, "")),
        (
            "with a scratch declaration",
            "2 path(s) judged pre-or-post; 1 path(s) matched by scratch, not judged (declared: a.txt)\\n",
            (2, "a.txt"),
        ),
        (
            "with the history clause in between",
            "2 path(s) judged pre-or-post; 3 file(s) judged by the history form (appended tails "
            "not judged): x; 1 path(s) matched by scratch, not judged (declared: a.txt)\\n",
            (2, "a.txt"),
        ),
        (
            "with the (+K more) truncation",
            "2 path(s) judged pre-or-post; 6 path(s) matched by scratch, not judged "
            "(declared: a, b, c (+3 more))\\n",
            (2, "a, b, c (+3 more)"),
        ),
        (
            "with parentheses inside a declared path",
            "2 path(s) judged pre-or-post; 1 path(s) matched by scratch, not judged "
            "(declared: data (1).mdb)\\n",
            (2, "data (1).mdb"),
        ),
        (
            "as the last thing in its event, with no trailing newline",
            "2 path(s) judged pre-or-post; 1 path(s) matched by scratch, not judged "
            '(declared: a.txt)"}',
            (2, "a.txt"),
        ),
    ]
    bad = 0
    for label, text, want in shapes:
        got = judged_sets([{"ts": "T", "text": text}])
        if [(g["judged"], g["scratch"]) for g in got] != [want]:
            print(f"FAIL selftest: l0 {label}: read {got}, expected {want}")
            bad += 1
    try:
        judged_sets([{"ts": "T", "text": "2 path(s) judged pre-or-post; 1 path(s) matched by "
                                         "scratch, not judged (declared: unterminated\\n"}])
        print("FAIL selftest: an unreadable scratch declaration was recorded as none")
        bad += 1
    except Refusal:
        pass
    if bad:
        failures += 1
    else:
        print("ok   every l0 shape the engine prints reads, and an unreadable one is refused")

    # 9. A run with no record at all. `derive()` used to skip the sequence check when meta.json
    #    was absent, so the new refusal could be avoided by deleting a file.
    with tempfile.TemporaryDirectory() as tmp:
        cases += 1
        run = _fixture(tmp, 1, 1)
        (run / "meta.json").unlink()
        try:
            derive(run)
            print("FAIL selftest: a run with no meta.json was accepted")
            failures += 1
        except Refusal as exc:
            if "no meta.json" not in str(exc):
                print(f"FAIL selftest: refused for the wrong reason: {exc}")
                failures += 1
            else:
                print("ok   a run with no record is refused rather than skipped")

    with tempfile.TemporaryDirectory() as tmp:
        cases += 1
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
    # The count is printed from the lines above, not typed: this said "4 case(s)" while
    # eight ran, because the body grew and the number beside it did not.
    print(
        f"ok   audit selftest: {cases} case(s) — refusals on unreadable evidence, and the "
        "four grading states told apart"
    )
    return 0


def write_sequence(run_dir):
    """Derive the judged-set sequence and write it into the run's meta.json.

    Derived and written by the same walk `derive()` checks against, so a record and its
    evidence cannot be produced by two different readings of the transcript.
    """
    run = Path(run_dir)
    events = read_transcript(run / "transcript.jsonl")
    seq = judged_sets(events)
    meta_path = run / "meta.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta["judged_sets"] = seq
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    snaps = len(read_revisions(run))
    print(f"{run.name}: {len(seq)} judged state(s), {snaps} snapshot(s)")
    return 0


def counted_runs(runs_dir):
    """The published runs this study counts — every one with a record, minus the void ones.

    One definition, because it had two: this function and a shell loop in `ci.yml` each decided
    what `void` meant, and a check whose subject is chosen in two places is one edit away from
    two different subjects.
    """
    out = []
    for d in sorted(Path(runs_dir).iterdir()):
        meta = d / "meta.json"
        if not meta.is_file():
            continue
        if json.loads(meta.read_text(encoding="utf-8")).get("disposition") == "void":
            continue
        out.append(d)
    return out


def check_all(runs_dir):
    """Every published run re-derives; a void run is reported rather than enforced.

    PROTOCOL.md requires a run that starts to be published, and one of the things that makes a
    run void is evidence the audit refuses to read. Enforcing both would leave only a choice
    between a permanently red job and an unpublished run, so this guard's predicate is "every
    run the study COUNTS still reads".
    """
    runs_dir = Path(runs_dir)
    published = [d for d in sorted(runs_dir.iterdir()) if (d / "meta.json").is_file()]
    counted = {d.name for d in counted_runs(runs_dir)}
    bad = 0
    for d in published:
        try:
            derive(d)
        except Refusal as exc:
            if d.name in counted:
                print(f"REFUSED: {d.name}: {exc}")
                bad += 1
            else:
                print(f"note: {d.name} is void; refusal reported, not enforced: {exc}")
    if not counted:
        print("REFUSED: no counted run was audited — a check that scanned nothing is not a check")
        return 1
    if bad:
        return 1
    print(f"ok   {len(published)} published run(s), {len(counted)} counted, all re-derive")
    return 0


PAGE_ROW = re.compile(
    r"^\|\s*`([a-z0-9-]+)`\s*\|\s*\**(\d+)\**\s*\|\s*\**(\d+)\**\s*\|\s*(\d+) s\s*\|", re.M
)


def check_page(page_path):
    """Hold a page's run table to what `audit.py` derives, row by row.

    The study's figures are derived; a table retyping them is not, and a table is what a reader
    actually reads. Two pages carry one (`RESULTS.md` and `runs/README.md`), and the columns are
    `run | judged states | revisions | runnable`.
    """
    page = Path(page_path)
    runs_dir = Path(__file__).resolve().parent / "runs"
    text = page.read_text(encoding="utf-8")
    rows = PAGE_ROW.findall(text)
    if not rows:
        print(f"REFUSED: {page} holds no run table row — a check that scanned nothing is not a check")
        return 1
    # The row SET, not just the rows that happened to match. Measured on a copy: deleting a
    # run's row left this green at "3 row(s) match", and so did a row whose name lost its
    # backticks and carried a figure off by 97 — the pattern simply stopped seeing them.
    # A check that only inspects what it recognises cannot notice a row going missing.
    counted = {d.name for d in counted_runs(runs_dir)}
    listed = {name for name, *_ in rows}
    if listed != counted:
        missing, extra = sorted(counted - listed), sorted(listed - counted)
        print(
            f"REFUSED: {page.name}'s run table lists {sorted(listed)}; the counted runs are "
            f"{sorted(counted)}" + (f" — missing {missing}" if missing else "")
            + (f" — unknown {extra}" if extra else "")
        )
        return 1
    bad = 0
    for name, states, revisions, runnable in rows:
        try:
            out = derive(runs_dir / name)
        except Refusal as exc:
            print(f"REFUSED: {name}: {exc}")
            bad += 1
            continue
        want = (out["judged_states"], out["revisions"], out["runnable_elapsed_s"])
        got = (int(states), int(revisions), int(runnable))
        if got != want:
            print(f"REFUSED: {page.name} says {name} is {got}, the evidence says {want}")
            bad += 1
    if bad:
        return 1
    print(f"ok   {page.name}: {len(rows)} row(s) match what the evidence derives")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) == 3 and argv[1] == "--check-page":
        return check_page(argv[2])
    if len(argv) == 2 and argv[1] == "--check-all":
        return check_all(Path(__file__).resolve().parent / "runs")
    if len(argv) == 3 and argv[1] == "--write-sequence":
        return write_sequence(argv[2])
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
