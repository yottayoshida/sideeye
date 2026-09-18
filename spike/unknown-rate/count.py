#!/usr/bin/env python3
"""Recompute the #84 UNKNOWN-rate tables from the committed artifacts.

Four modes:

  count.py emit  [--root DIR]   print the canonical results block (markdown)
  count.py check [--root DIR]   exit non-zero unless the checked-out docs,
                                corpus, ledgers, manifests, reports and
                                define bytes all agree
  count.py ledger-sizes [--root DIR]
                                print the five cohort-ledger counts the pages
                                state in prose, as one key=value line
  count.py b2-selection [--selftest] [--root DIR]
                                exit non-zero unless the committed B2 target
                                list is the keyed first-N derivation of the
                                pool minus the exclusions, and every name the
                                five machine-readable ledgers spell is excluded
                                directly or through the alias table (#619);
                                --selftest proves each of the mode's own reds
                                on a scratch copy

The published numbers in docs/unknown-rate.md are pasted from `emit` and
held there by `check` (wired into spike/acceptance.sh): the block between
the begin/end markers must equal a fresh recomputation byte for byte, so a
number cannot drift from the reports it claims to summarize. `check` also
recomputes every manifest define digest from the checkout — "the committed
defines ran verbatim" is checked, not asserted — and requires every
unknown_reason to be a member of the closed set documented in
docs/report-schema.md (the docs hold each other).

Generations (#239). A generation is one sweep: one engine build, one
artifacts directory, listed in generations.tsv. Corpus rows carry the
generation they enter from, so a generation's expected trial set is every
row with since <= it in a group it covers. A generation is `complete` (its
manifest matches that set exactly) or `unstarted` (no manifest, and the
docs carry the placeholder). Anything between the two is a partially
measured sweep, which is an error rather than a state that can be recorded
— `partial` is not a value generations.tsv accepts, so a half-finished
sweep cannot be published by writing it down. This is what lets a rulebook
PR add corpus rows for a generation that has not run: the completed
generation's expected set does not include them.

The counting rules are frozen in docs/unknown-rate.md; this file is their
implementation. Cells with n < 5 print counts only, never a percentage.
"""
import hashlib
import json
import re
import sys
from datetime import datetime
from pathlib import Path

MARK_BEGIN = "<!-- unknown-rate:results:begin -->"
MARK_END = "<!-- unknown-rate:results:end -->"
PLACEHOLDER = "_Not yet measured: the sweep has not run. This line is asserted by count.py check._"
SMALL_N = 5
CORPUS_COLS = ["id", "group", "tool", "cls", "judge", "launcher", "args",
               "artdir", "rpath", "defines", "since", "flags"]
GEN_COLS = ["id", "date", "dir", "groups", "status"]
EXCLUSION_COLS = ["id", "reason"]
GEN_STATUSES = ("complete", "unstarted")
GROUPS = ("A", "B", "B2", "control")
# The mechanically selected groups: the ones with a funnel (a wall row runs no
# engine) and the ones a re-measurement is labelled on. One name for the pair,
# because the two rules that mention it must agree on which groups it is.
MECHANICAL_GROUPS = frozenset(("B", "B2"))
OUTCOME_COLS = ["tool", "disposition", "source"]
ENGINE_PIN_COLS = ["generation", "tag", "asset", "sha256"]
CLOCK_COLS = ["target", "event", "utc"]
# The events b2-clock.sh writes, in the order authoring reaches them. Held on the
# reading side as well: the writer refuses a fourth name, but the file is plain
# text and a hand edit is not a writer.
CLOCK_EVENTS = ("setup_started", "first_accepted_recording", "final")
# The sweep's own record, one row per trial. `rsha` (#349) is the report's sha256, which
# binds the file at `rpath` to the sweep that wrote it rather than to a name; a funnel
# wall runs no engine and carries `-` there, as it does in `image`, `rpath` and `rc`.
MANIFEST_COLS = ["id", "group", "tool", "cls", "judge", "image", "argv",
                 "digest", "rpath", "rc", "rsha"]
# The four the outcome table prints, plus one for a tool the record carries
# no FAIL for. A tool marked no-fail-recorded that then produces a FAIL is
# caught by the conservation check in check(), not by this list.
PRINTED_DISPOSITIONS = ("reported-upstream", "withdrawn", "kept-unreported", "new-this-sweep")
DISPOSITIONS = PRINTED_DISPOSITIONS + ("no-fail-recorded",)
COHORT_PREFIX = "spike/cohort"
# A cohort target directory is <target> or <target>-rN with N >= 2: the first
# revision carries no suffix. The bounds are fail-closed on purpose — a
# permissive pattern read "-r2" as base "" revision 2 and "foo-r0" as base
# "foo" revision 0, either of which satisfies the supersession predicate for
# a pair that is not a revision chain at all.
REVISION_RE = re.compile(r"^(?P<base>[A-Za-z0-9][A-Za-z0-9._-]*?)(?:-r(?P<rev>[2-9][0-9]*))?$")
# The page class-exclusions.tsv rests on, and the heading its supported classes sit under.
CLASSES_DOC = "docs/target-classes.md"
FIRST_TABLE_HEADING = "## Measured, with verdicts"
# A Tool cell part's first word: leading whitespace (NBSP included) and emphasis, code and link
# openers skipped, then a word that starts with a letter — a version number is not a tool.
TOOL_WORD_RE = re.compile(r"[\s*`\[]*([A-Za-z][A-Za-z0-9._+-]*)")
# A cohort target directory cited inside a table row, followed by at least one more path part.
ROW_COHORT_DIR_RE = re.compile(r"spike/(cohort[0-9A-Za-z_-]*)/([^/\s`|]+)/")

def die(msg):
    print(f"count.py: {msg}", file=sys.stderr)
    sys.exit(1)

def assert_one_marker_pair(text, subject):
    """At most one of each results marker, in order — the rule the page and the
    recomputation are both held to (#444).

    The docstring's promise is about "the block between the begin/end markers", and a
    naive slice reads only the first pair: content between a second pair passes as
    generated while nothing checks it. The byte-compare cannot see the injection either,
    because published and computed shorten at the same point.

    Zero of each is legal here — the pre-data page carries none — so the callers that
    need the pair say so themselves: `check` requires it once anything is measured, and
    `emit` appends both markers before it calls this.

    Counted as substrings of the whole text, so neither prose nor a table cell can spell
    a marker: fail-closed, and wider than render-cookbook.py's whole-line match.
    """
    for mk, name, why in (
            (MARK_BEGIN, "begin",
             "a second begin makes the compared slice start where nobody edits"),
            (MARK_END, "end",
             "content after a second end reads as generated while nothing checks it")):
        n = text.count(mk)
        if n > 1:
            die(f"{subject} carries {n} {name} markers, wanted exactly one — {why}")
    if MARK_BEGIN in text and MARK_END in text \
            and text.index(MARK_BEGIN) > text.index(MARK_END):
        die(f"{subject}'s results end marker precedes its begin marker")

def pct_or_counts(k, n):
    if n == 0:
        return f"{k}/{n}"
    if n < SMALL_N:
        return f"{k}/{n} (counts only, n<{SMALL_N})"
    return f"{k}/{n} ({100.0 * k / n:.1f}%)"

def read_corpus(root):
    rows = []
    for line in (root / "spike/unknown-rate/corpus.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != len(CORPUS_COLS):
            die(f"corpus.tsv row does not have {len(CORPUS_COLS)} columns: {line!r}")
        rows.append(dict(zip(CORPUS_COLS, f)))
    _reject_duplicate_ids(rows)
    return rows

def _reject_duplicate_ids(rows):
    """A trial id names one row. Nothing downstream survives two.

    `by_id` and `reports` are dicts, so a duplicate collapses silently there
    while `expected_for` keeps both — the two then disagree about how many
    trials a generation has. The retired flag guard caught this for the three
    flagged rows; this catches it for all 57.
    """
    seen = {}
    for r in rows:
        if r["id"] in seen:
            die(f"corpus.tsv names {r['id']!r} twice — a trial id is one row")
        seen[r["id"]] = True


def read_generations(root):
    rows = []
    for line in (root / "spike/unknown-rate/generations.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != len(GEN_COLS):
            die(f"generations.tsv row does not have {len(GEN_COLS)} columns: {line!r}")
        g = dict(zip(GEN_COLS, f))
        if g["status"] not in GEN_STATUSES:
            die(f"generation {g['id']}: status {g['status']!r} is not one of "
                f"{'/'.join(GEN_STATUSES)} — a partially measured sweep is an error, "
                f"not a status to record")
        # An unrecognised group name silently covers nothing, which removes
        # every row in that group from every expected set — the corpus rows
        # are then measured by no generation and missed by every check.
        for grp in g["groups"].split(","):
            if grp not in GROUPS:
                die(f"generation {g['id']}: group {grp!r} is not one of {'/'.join(GROUPS)}")
        rows.append(g)
    if not rows:
        die("generations.tsv lists no generations")
    return rows

def expected_for(corpus, generations, gen):
    """The trial rows a generation is responsible for, in corpus order."""
    order = {g["id"]: i for i, g in enumerate(generations)}
    limit = order[gen["id"]]
    groups = set(gen["groups"].split(","))
    out = []
    for c in corpus:
        if c["since"] not in order:
            die(f"corpus row {c['id']}: since={c['since']!r} is not a generation")
        if order[c["since"]] <= limit and c["group"] in groups:
            out.append(c)
    return out

def read_manifest(root, gen_dir):
    p = root / "spike/unknown-rate" / gen_dir / "manifest.tsv"
    if not p.exists():
        return None
    rows = []
    for line in p.read_text().splitlines():
        f = line.split("\t")
        if len(f) != len(MANIFEST_COLS):
            die(f"{gen_dir}/manifest.tsv row does not have {len(MANIFEST_COLS)} "
                f"columns: {line!r}")
        rows.append(dict(zip(MANIFEST_COLS, f)))
    return rows

def enum_from_schema_doc(root):
    text = (root / "docs/report-schema.md").read_text()
    m = re.search(r"`unknown_reason` values \(closed set[^)]*\):(.*?)\n\n",
                  text, re.S)
    if not m:
        die("could not find the unknown_reason closed set in docs/report-schema.md")
    return set(re.findall(r"`([a-z0-9_]+)`", m.group(1)))

def sha256_file(p):
    h = hashlib.sha256()
    h.update(p.read_bytes())
    return h.hexdigest()

_digest_cache = {}

def digest_for(root, defines):
    # Mirror of sweep.sh digest_for: sorted "sha256  path" lines, hashed.
    # Memoized: several corpus rows share one defines directory (topydo's
    # thirteen trials hash the same ops/ tree).
    if defines in _digest_cache:
        return _digest_cache[defines]
    lines = []
    for spec in defines.split(";"):
        p = root / spec
        if not p.exists():
            die(f"define path missing from checkout: {spec}")
        files = sorted(q for q in p.rglob("*") if q.is_file()) if p.is_dir() else [p]
        for q in files:
            lines.append(f"{sha256_file(q)}  {q.relative_to(root)}")
    payload = "\n".join(sorted(lines)) + "\n"
    d = hashlib.sha256(payload.encode()).hexdigest()
    _digest_cache[defines] = d
    return d

def load_reports(root, gen_dir, manifest):
    """Attach verdict data to every non-wall manifest row.

    The reports are read from THIS generation's directory. Reading them from
    another one would attach a previous sweep's verdicts to this sweep's
    rows with every classifying column intact.
    """
    out = {}
    arts = root / "spike/unknown-rate" / gen_dir
    for row in manifest:
        if row["argv"].startswith("wall:"):
            out[row["id"]] = {"wall": row["argv"][5:]}
            continue
        rp = arts / row["rpath"]
        if not rp.exists():
            die(f"report missing for {row['id']} in {gen_dir}: {row['rpath']}")
        sha, doc = read_report_doc(rp, f"{row['id']}")
        out[row["id"]] = {
            "verdict": doc["verdict"],
            "reason": doc.get("unknown_reason", ""),
            "crash_points": doc.get("crash_points"),
            "sha": sha,
            "legs": read_legs(row["id"], row["group"], rp.parent, sha, gen_dir),
        }
    return out


def read_report_doc(path, who):
    """(sha256, document) of one report file, refused when it is not one.

    Read once as bytes: the hash and the parse want the same file, and reading it
    twice would put the two a window apart as well as costing a second pass over
    every report on every check. Shared by the manifest-bound report and the
    per-leg reports, so a leg is held to the same schema the verdict is.
    """
    raw = path.read_bytes()
    try:
        doc = json.loads(raw)
    except ValueError:
        die(f"{who}: {path.name} is not JSON — a report the engine did not finish "
            f"writing, or one something else wrote over")
    if doc.get("schema") != "sideeye/report":
        die(f"{who}: {path.name} is not a sideeye/report document")
    return hashlib.sha256(raw).hexdigest(), doc


LEG_COLS = ["leg", "mode", "verdict", "reason", "report", "sha"]
# The opening of the `observe_syscalls` step (src/contract.zig) — the one step that
# asks for the mode. Matched on this phrase, not on the flag's spelling: the
# `syscalls_may_have_killed` step names the flag too, in a sentence that says the
# opposite. bgroup.sh matches the same phrase.
SYSCALLS_STEP = "Run explore or preflight again with --observe syscalls"

def read_legs(trial_id, group, art, final_sha, gen_dir):
    """The observation legs a launcher recorded beside a trial's report (#619).

    `legs.tsv` names each leg's mode, verdict, reason, report and sha256. Each
    leg's report is opened and its digest recomputed — without that, the "two
    legs" rule below would be satisfied by two lines nobody had to earn, the
    same hole #349 closed for `rpath`. Then the rule itself: a second leg exists
    exactly when the first refused with a `next_step` naming `--observe syscalls`,
    and the report the manifest binds is the last leg's bytes. A trial with no
    legs.tsv reads as it always did — except a B2 trial, whose launcher always
    writes one: there the absence is a launcher that did not run its protocol,
    and a verdict with no legs behind it would otherwise pass untouched.
    """
    p = art / "legs.tsv"
    if not p.exists():
        if group == "B2":
            die(f"{trial_id}: a B2 trial with no legs.tsv — bgroup.sh writes one for every "
                f"trial it runs, so this verdict was not produced by the two-leg protocol")
        return []
    legs = []
    for line in p.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != len(LEG_COLS):
            die(f"{trial_id}: legs.tsv row does not have {len(LEG_COLS)} columns: {line!r}")
        leg = dict(zip(LEG_COLS, f))
        lp = art / leg["report"]
        if not lp.exists():
            die(f"{trial_id}: leg {leg['leg']} names {leg['report']}, which is not in {gen_dir}")
        lsha, ldoc = read_report_doc(lp, f"{trial_id}: leg {leg['leg']}")
        if lsha != leg["sha"]:
            die(f"{trial_id}: leg {leg['leg']}'s report {leg['report']} hashes differently from "
                f"legs.tsv — not the file the launcher recorded")
        if ldoc.get("verdict") != leg["verdict"]:
            die(f"{trial_id}: legs.tsv says leg {leg['leg']} is {leg['verdict']} and its report "
                f"says {ldoc.get('verdict')}")
        # The reason column is published (the legs table); hold it to the report
        # as the verdict is. The mode column has no field in the report to be held
        # to — it is the launcher's record of which flag it passed — and the page
        # says so.
        if (ldoc.get("unknown_reason") or "-") != leg["reason"]:
            die(f"{trial_id}: legs.tsv says leg {leg['leg']}'s reason is {leg['reason']} and its "
                f"report says {ldoc.get('unknown_reason') or '-'}")
        leg["next_step"] = ldoc.get("next_step", "") or ""
        legs.append(leg)
    order = [l["leg"] for l in legs]
    if order not in (["1"], ["1", "2"]):
        die(f"{trial_id}: legs.tsv must list leg 1, optionally followed by leg 2 — it lists {order}")
    if legs[0]["mode"] != "wrappers" or (len(legs) == 2 and legs[1]["mode"] != "syscalls"):
        die(f"{trial_id}: legs.tsv modes are {[l['mode'] for l in legs]}, not wrappers then syscalls")
    asked = legs[0]["verdict"] == "UNKNOWN" and SYSCALLS_STEP in legs[0]["next_step"]
    if asked and len(legs) == 1:
        die(f"{trial_id}: leg 1 refused with a next_step naming --observe syscalls and no second "
            f"leg was recorded")
    if not asked and len(legs) == 2:
        die(f"{trial_id}: a second leg was recorded without leg 1 asking for it (leg 1 is "
            f"{legs[0]['verdict']} and its next_step does not name --observe syscalls)")
    if legs[-1]["sha"] != final_sha:
        die(f"{trial_id}: the report the manifest binds is not the last leg's bytes "
            f"({legs[-1]['report']})")
    return legs


def read_engine_pins(root):
    """generation -> (tag, asset, sha256) from engine-pins.tsv; empty when the file is absent."""
    if not (root / "spike/unknown-rate/engine-pins.tsv").exists():
        return {}
    out = {}
    for r in read_ledger(root, "engine-pins.tsv", ENGINE_PIN_COLS):
        if r["generation"] in out:
            die(f"engine-pins.tsv pins generation {r['generation']!r} twice")
        out[r["generation"]] = (r["tag"], r["asset"], r["sha256"])
    return out


def read_clock(root):
    """target -> (minutes to first accepted recording, minutes to final) from b2-clock.tsv.

    Self-reported by the author; this only does the arithmetic. A target with no
    setup_started has no baseline and is left out; an event without its partner
    prints `-`. The shape is held the way read_outcome_map holds its file: an
    event outside the three the writer knows, a (target, event) stamped twice,
    or a time the format does not parse is a refusal, not a row that quietly
    wins or a traceback.
    """
    if not (root / "spike/unknown-rate/b2-clock.tsv").exists():
        return {}
    events = {}
    for r in read_ledger(root, "b2-clock.tsv", CLOCK_COLS):
        if r["event"] not in CLOCK_EVENTS:
            die(f"b2-clock.tsv: {r['target']!r} carries event {r['event']!r}, not one of "
                f"{'/'.join(CLOCK_EVENTS)}")
        if r["event"] in events.get(r["target"], {}):
            die(f"b2-clock.tsv stamps {r['target']!r} {r['event']} twice — the once-guard is "
                f"in b2-clock.sh, and this row did not come through it")
        try:
            when = datetime.strptime(r["utc"], "%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            die(f"b2-clock.tsv: {r['target']!r} {r['event']} has a time that is not "
                f"YYYY-MM-DDTHH:MM:SSZ: {r['utc']!r}")
        events.setdefault(r["target"], {})[r["event"]] = when
    out = {}
    for t, ev in events.items():
        if "setup_started" not in ev:
            continue
        def mins(k):
            return round((ev[k] - ev["setup_started"]).total_seconds() / 60) if k in ev else None
        out[t] = (mins("first_accepted_recording"), mins("final"))
    return out

def read_outcome_map(root):
    """tool -> disposition, with the shape held rather than assumed.

    Every loosening here is silent in the published table: a row short of
    its source column loses the provenance the disposition rests on, a
    duplicate tool lets the later row win with nothing said, and a
    misspelt disposition matches none of the four printed outcome rows —
    so that tool's FAILs leave the ratio without leaving a trace.
    """
    m = {}
    p = root / "spike/unknown-rate/outcome-map.tsv"
    for line in p.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != len(OUTCOME_COLS):
            die(f"outcome-map.tsv row does not have {len(OUTCOME_COLS)} columns "
                f"({', '.join(OUTCOME_COLS)}): {line!r}")
        if f[0] in m:
            die(f"outcome-map.tsv lists {f[0]!r} twice — the later row would win in silence")
        if f[1] not in DISPOSITIONS:
            die(f"outcome-map.tsv: disposition {f[1]!r} for {f[0]} is not one of "
                f"{'/'.join(DISPOSITIONS)}")
        m[f[0]] = f[1]
    return m

def read_ledger(root, name, cols):
    """A tab-separated ledger with a comment header; first column is the key."""
    rows = []
    for line in (root / "spike/unknown-rate" / name).read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != len(cols):
            die(f"{name} row does not have {len(cols)} columns: {line!r}")
        rows.append(dict(zip(cols, f)))
    return rows

def read_exclusions(root):
    """trial id -> why its apparatus failure was not fixable.

    The page's SETUP_ERROR rule has two halves — "fix the apparatus and re-run
    that trial; if unfixable, the row is published as excluded, with the reason".
    The first half is the default and leaves no record. This is the second: the
    judgement that a failure could not be fixed is made in a commit, in front of
    a reviewer, rather than by a sweep that drops the row and publishes the rate
    from what remains. The report's `message` says what failed and is not read
    here — it cannot say whether anyone tried to fix it, and the page states that
    count.py reads only machine fields.

    The three shape rules are checked where the file is read, so `emit` and
    `check` both get them: a ledger that is itself broken should refuse in either
    mode, and the message names this predicate rather than whatever downstream
    thing tripped over the bad row.
    """
    m = {}
    for r in read_ledger(root, "exclusions.tsv", EXCLUSION_COLS):
        if r["id"] in m:
            die(f"exclusions.tsv lists {r['id']!r} twice — the later row would win in "
                f"silence, and the reason a reviewer approved would publish as the other one")
        if not r["reason"].strip():
            die(f"exclusions.tsv: {r['id']} is waived with no reason — the page publishes "
                f"an excluded row *with the reason*, and an empty cell is not one")
        if "|" in r["reason"]:
            die(f"exclusions.tsv: {r['id']}'s reason contains a pipe, which would split the "
                f"published table row it is written into")
        if MARK_END in r["reason"]:
            die(f"exclusions.tsv: {r['id']}'s reason carries the results block's end marker. "
                f"The reason is written into that block and `check` finds the block by "
                f"splitting the page on this string, so an injected one shortens the compared "
                f"region on both sides at once — everything past it stops being checked, and "
                f"the reason a reviewer approved can differ from the one the page publishes")
        # That rule was written, withdrawn, and restored, and the withdrawal is the part
        # worth keeping. Four placements were tried and every one died on a predicate
        # that already existed — injected early the truncated block loses rows and the
        # published-rows-against-measured guard fires, injected late the group's rate
        # line goes missing and attribution fires — which read as "structurally
        # unreachable": a SETUP_ERROR row only renders inside a detail table, and a
        # detail table appeared to always be followed by a rate line or an outcome
        # table. The generalisation was false and all four measurements sat inside its
        # blind spot. `check_attribution` skips a group with no rated trial, and the
        # outcome table is only required when the A group has one — so a generation
        # covering B alone, whose trials are all walls and SETUP_ERRORs, has nothing
        # after that detail table. This page contemplates exactly that generation
        # ("A future B measurement is its own decision, with its own generation").
        # Measured on it: green, with the comparison ending mid-cell, and the reason
        # editable past the marker without the gate noticing.
        m[r["id"]] = r["reason"]
    return m


def read_apparatus(root, gen_dir):
    """The apparatus record a completed generation was swept under.

    `sweep.sh` writes this file (its apparatus block) and nothing has ever read
    it, so a truncated or absent record passed every rate check that exists
    (#348). Four rules answer that, three of them here and the fourth — that the
    manifest's images are named — in `check`, where the manifest is in hand. They
    sit in the order truncation reaches: a write that stops partway loses the image
    lines, then `head:`, then the digests. The banner is the one line truncation
    can never take alone, which
    is why no rule below asks for it — a banner-only deletion is a targeted edit,
    not the accident this file is here for, and it is indistinguishable in value
    from the targeted edits nothing here catches (rewriting one character of a
    digest, say).

    Two of the three answer failures the producer does not guard. `sweep.sh`
    checks the rc of its docker run and greps for the banner, but nothing looks
    at `git rev-parse HEAD` (a failure writes `head: ` with no value and the
    sweep continues) or at `docker images | grep`, whose empty result writes no
    image lines at all.

    Returns the ids named by image lines, how many such lines there were, and the
    lines themselves (so a caller with one more rule — the engine pin — reads the
    file once, here, rather than a window later). The
    ids come from the image lines only, not from every token in the file: taking
    the whole file lets an id satisfy the rule from anywhere in it, and the page
    promises "a line naming every image the manifest used". Measured before
    narrowing it — deleting all three image lines and appending their ids to the
    banner passed.

    That set is a SUPERSET of what the sweep used: the producer lists every
    `sideeye-ur-*` on the host rather than the ones it ran, so a match establishes
    that the record is intact, never that these are the images the trials ran under.
    The count is returned for the same reason the waiver count above is — the
    obvious alternative, how many distinct images the manifest names, is derivable
    from the manifest alone, so an implementation that opened nothing here would
    print an identical number.
    """
    p = root / "spike/unknown-rate" / gen_dir / "apparatus.txt"
    if not p.exists():
        die(f"{gen_dir}/apparatus.txt is missing — the generation is marked complete but "
            f"records no apparatus, and every rate check below would pass over that")
    lines = p.read_text().splitlines()
    digests = [l for l in lines if re.match(r"^[0-9a-f]{64}\s\s", l)]
    if len(digests) != 2:
        die(f"{gen_dir}/apparatus.txt carries {len(digests)} digest lines, not the engine's "
            f"and the shim's — a record that lost them cannot say which binaries ran")
    if not any(re.match(r"^head: [0-9a-f]{40}$", l) for l in lines):
        die(f"{gen_dir}/apparatus.txt has no resolved head: line — `git rev-parse` failing "
            f"during the sweep writes the key with no value and the sweep continues, so the "
            f"empty form is the one this catches")
    named, n_images = set(), 0
    for l in lines:
        m = re.match(r"^sideeye-ur-\S+\s+(\S+)$", l)
        if m:
            named.add(m.group(1))
            n_images += 1
    return named, n_images, lines


def excluded_cell(trial_id, exclusions):
    """The cell that reports an excluded row, carrying its reason when one is waived.

    Deliberately tolerant where `check` is strict: an unwaived SETUP_ERROR renders
    the way it always did. `check` calls `emit` before its own predicates run, so
    refusing here would kill the unwaived fixture inside the renderer — red, and
    about the renderer rather than about the missing waiver.
    """
    reason = exclusions.get(trial_id)
    return f"SETUP_ERROR (excluded: {reason})" if reason else "SETUP_ERROR (excluded, published)"


def split_revision(define):
    """spike/cohortN/<target>[-rM]/ops -> (cohortN, base target, revision).

    An unsuffixed directory is revision 1: cohort 2's chain is hg, hg-r2,
    hg-r3, hg-r4, and the first one carries no suffix.
    """
    parts = define.split("/")
    if (len(parts) != 4 or parts[0] != "spike"
            or not parts[1].startswith("cohort") or parts[3] != "ops"):
        die(f"not a cohort define path (want spike/cohortN/<target>/ops): {define!r}")
    m = REVISION_RE.match(parts[2])
    if not m:
        die(f"cohort target directory {parts[2]!r} is not <target> or <target>-rN with N >= 2")
    return parts[1], m.group("base"), int(m.group("rev") or 1)

def cohort_defines_on_disk(root):
    """Every committed cohort define directory, as repo-relative paths."""
    out = set()
    for toml in sorted((root / "spike").glob("cohort*/*/ops/*.toml")):
        out.add(str(toml.parent.relative_to(root)))
    return out

def rate_line(label, trials, verdict="UNKNOWN"):
    n = len(trials)
    k = sum(1 for t in trials if t["v"] == verdict)
    return f"| {label} | {pct_or_counts(k, n)} |"

def tabulate(manifest, reports, by_id):
    """Split a generation's manifest into rated trials, walls and setup errors.

    Returned separately from the rendering so `check` can assert what
    reaches the arithmetic rather than what reaches the table — a flagged
    row that a renderer prints and an aggregation skips would look right in
    both places otherwise.
    """
    trials, walls, setup_errors = [], [], []
    for row in manifest:
        r = reports[row["id"]]
        c = by_id[row["id"]]
        base = {"id": row["id"], "group": row["group"], "tool": row["tool"],
                "cls": row["cls"], "judge": row["judge"], "flags": c["flags"]}
        if "wall" in r:
            walls.append({**base, "wall": r["wall"]})
        elif r["verdict"] == "SETUP_ERROR":
            setup_errors.append(base)
        else:
            trials.append({**base, "v": r["verdict"], "reason": r["reason"],
                           "cp0": r["verdict"] == "PASS" and r["crash_points"] == 0,
                           "legs": r.get("legs", [])})
    return trials, walls, setup_errors

# The headings emit_generation prints, in its own order. Kept as data beside the
# emitter rather than re-derived by the parser: a parser that keys on prose is
# one wording edit away from selecting the wrong table shape, and a mis-shaped
# parse yields zero rows — which reads as green unless something counts.
GROUP_HEADINGS = (
    ("A", "A-group (the engine's development input — not the threshold basis)"),
    ("control", "Control trials (outside every denominator)"),
    ("B", "B-group (mechanically selected; the threshold basis)"),
    ("B2", "B2-group (mechanically selected on trixie after v1.5; measured, no threshold)"),
)
OUTCOME_HEADING = "Outcome ratio (A-group, per the committed disposition map)"
DETAIL_WIDE = "| trial | tool | class | judge | verdict | unknown_reason | flags |"
DETAIL_FUNNEL = "| target | class | funnel stage | verdict | unknown_reason |"


def parse_k_n(cell):
    """`0/13 (0.0%)` and `1/1 (counts only, n<5)` both mean (k, n)."""
    k, _, n = cell.split(" ")[0].partition("/")
    return int(k), int(n)


def split_published(published):
    """The published block as {(generation, group): section text}.

    Located by heading, never by counting tables: the same slice label appears
    under several groups — `class: c-cli` sits in g1's A, g1's B and g2's A — so
    anything that aggregates across the whole block sums to a number that
    matches no denominator (72 against 28/1/7/36, measured).
    """
    out, gid, cur = {}, None, None
    for line in published.splitlines():
        if line.startswith("### Generation "):
            gid, cur = line[len("### Generation "):].split(" ")[0], None
        elif line.startswith("#### "):
            head, cur = line[len("#### "):], None
            if head == OUTCOME_HEADING:
                cur = (gid, "outcome")
                out[cur] = []
            else:
                for group, name in GROUP_HEADINGS:
                    if head == name:
                        cur = (gid, group)
                        out[cur] = []
                        break
        elif cur is not None:
            out[cur].append(line)
    return {k: "\n".join(v) for k, v in out.items()}


def parse_section(text):
    """One section as (detail rows, slices, reason counts, rate).

    A detail row carries only the columns its own header declares: the wide
    table has `judge`, the funnel table does not, so the caller cannot
    reconstruct that axis for a funnel section and has to say so.

    SETUP_ERROR rows are dropped, and wall rows with them: both are published
    and neither belongs to a denominator. An implementation that forgets the
    exclusion is green on the live tree and on `fixtures/good` — neither
    contains a SETUP_ERROR row — which is why that exclusion carries a fixture.
    """
    detail, slices, reasons, rate, shape = [], {}, {}, None, None
    for line in text.splitlines():
        if line == DETAIL_WIDE:
            shape = "wide"
        elif line == DETAIL_FUNNEL:
            shape = "funnel"
        elif line.startswith("UNKNOWN rate, per-trial: **"):
            rate = parse_k_n(line.split("**")[1])
        elif line.startswith("| ") and not line.startswith("|---"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) == 2 and cells[0].partition(":")[0] in ("tool", "class", "judge"):
                axis, _, value = cells[0].partition(": ")
                if (axis, value) in slices:
                    # Not a new detection: the renderer builds slices from sets, so
                    # it cannot emit a duplicate without also drifting from the
                    # recomputation, and the byte-compare already refuses that. What
                    # this converts is the diagnosis — a generic drift becomes the
                    # specific reason — and it stops the scan volume this check
                    # reports from silently undercounting, since a duplicate would
                    # otherwise collapse into one dict entry.
                    die(f"the published block repeats slice {axis}: {value} — a duplicated row "
                        f"collapses into one and would be counted once by every check here")
                slices[(axis, value)] = parse_k_n(cells[1])
            elif len(cells) == 2 and cells[1].isdigit():
                reasons[cells[0]] = int(cells[1])
            elif shape == "wide" and len(cells) == 7 and cells[0] != "trial":
                if not cells[4].startswith("SETUP_ERROR"):
                    detail.append({"tool": cells[1], "cls": cells[2], "judge": cells[3],
                                   "v": cells[4].split(" (")[0]})
            elif shape == "funnel" and len(cells) == 5 and cells[0] != "target":
                if cells[2] == "explored":
                    detail.append({"tool": cells[0], "cls": cells[1],
                                   "v": cells[3].split(" (")[0]})
    return detail, slices, reasons, rate


AXES = (("tool", "tool"), ("class", "cls"), ("judge", "judge"))


def check_attribution(tables, published):
    """Every rated row reaches every published aggregate exactly once.

    `docs/unknown-rate.md` promises a marked row "sits in the denominator, its
    slices and the outcome ratio exactly once"; before this, only the
    denominator was checked, and `tabulate`'s own docstring says why that is not
    enough — a renderer that prints a row and skips it when aggregating looks
    right in both places. The byte-compare cannot see it either: both sides come
    from the same renderer.

    Named attribution, not conservation, because `check` already has an assert
    called that (the disposition one below) and `spike/acceptance.sh` names it in
    the sentence listing predicates without fixtures.

    Two things this deliberately does NOT do, each for a measured reason:

      * It sums nothing. A total is preserved by a renderer that counts a row
        twice under one label and drops another — and the row that mutation can
        hide is `a-himalaya-copy`, which carries `apparatus_declared`, i.e. the
        very subject of the sentence. Attribution is per label, not in aggregate.

      * It takes denominators from the measurement and numerators from the
        published detail rows, never the reverse. Only one fixture
        (`tampered-verdict`) reaches the docs comparison at all, and it moves a
        verdict — a numerator. Binding numerators to `trials` here would fire on
        it first and turn its pinned message into a hollow red. Denominators
        carry no such constraint. The numerator IS bound to the measurement,
        after the byte-compare, where that displacement cannot happen.

    Returns (sections, detail rows, slice rows, axes measured by denominator
    alone) so the caller can name its own scan volume: this walks the
    measurement and demands the published side match it, so an empty parse
    fails on the first section rather than passing over nothing.
    """
    sections = split_published(published)
    n_sec = n_detail = n_slice = n_outcome = 0
    sum_only = []
    for gen, _exp, _man, trials, _walls, _serr in tables:
        gid = gen["id"]
        for group, name in GROUP_HEADINGS:
            g = [t for t in trials if t["group"] == group]
            if not g:
                continue
            if (gid, group) not in sections:
                die(f"{gid}/{group}: {len(g)} rated trials, but the published block has no "
                    f"section headed {name!r}")
            detail, slices, reasons, rate = parse_section(sections[(gid, group)])
            n_sec, n_detail, n_slice = n_sec + 1, n_detail + len(detail), n_slice + len(slices)

            # The denominator, first: it is what every later comparison is
            # relative to, and a fixture that perturbs it must die here rather
            # than on a slice that disagrees for a downstream reason.
            if rate is None:
                die(f"{gid}/{group}: the published section carries no per-trial rate line")
            k_pub, n_pub = rate
            if n_pub != len(g):
                die(f"{gid}/{group}: the published denominator is {n_pub} against {len(g)} rated "
                    f"trials — the table and the measurement disagree about how many ran")
            if len(detail) != len(g):
                die(f"{gid}/{group}: the published per-trial table carries {len(detail)} rated "
                    f"rows against {len(g)} rated trials")

            # Family presence, before attribution: a family the renderer dropped
            # entirely leaves nothing to compare, and a loop over the families
            # that happen to be present would pass over it.
            for axis, field in AXES:
                want = sorted({t[field] for t in g})
                got = sorted({v for (a, v) in slices if a == axis})
                if want != got:
                    die(f"{gid}/{group}: the {axis} slices name {got} against {want} in the "
                        f"measurement — a slice family that loses a label loses its rows with it")

            funnel = any("judge" not in d for d in detail)
            for axis, field in AXES:
                for value in sorted({t[field] for t in g}):
                    k_s, n_s = slices[(axis, value)]
                    want_n = sum(1 for t in g if t[field] == value)
                    if n_s != want_n:
                        die(f"{gid}/{group}: slice {axis}: {value} counts {n_s} against {want_n} "
                            f"rated trials — a row reaches its slice exactly once or not at all")
                    if funnel and axis == "judge":
                        sum_only.append(f"{gid}/{group}/judge")
                        continue
                    want_k = sum(1 for d in detail if d[field] == value and d["v"] == "UNKNOWN")
                    if k_s != want_k:
                        die(f"{gid}/{group}: slice {axis}: {value} claims {k_s} UNKNOWN against "
                            f"{want_k} in the published rows — the table disagrees with itself "
                            f"(the measurement-bound comparison runs after the byte-compare)")

            # A biconditional, not a sum: the table is emitted only when the
            # numerator is non-zero, so "sum it when present" is green for a
            # renderer that drops it while rows remain.
            if bool(reasons) != (k_pub > 0):
                die(f"{gid}/{group}: the reason table is "
                    f"{'present' if reasons else 'absent'} with a published numerator of {k_pub}")
            if reasons and sum(reasons.values()) != k_pub:
                die(f"{gid}/{group}: the reason counts sum to {sum(reasons.values())} against a "
                    f"published numerator of {k_pub}")

        # The third thing the sentence names, and the one a section-shaped loop
        # walks past: the outcome table is emitted once per generation, after the
        # group loop, under its own heading — so a check that iterates group
        # sections never reaches it. It partitions the A-group by verdict (FAIL
        # split by disposition, then UNKNOWN, then PASS), which makes it the one
        # aggregate whose rows must sum to a denominator rather than match a
        # slice: every A-group trial lands in exactly one row.
        ga = [t for t in trials if t["group"] == "A"]
        if ga:
            if (gid, "outcome") not in sections:
                die(f"{gid}: {len(ga)} A-group trials, but the published block has no outcome "
                    f"table — the ratio the promise names is not there to check")
            _d, _s, rows, _r = parse_section(sections[(gid, "outcome")])
            n_outcome += len(rows)
            if sum(rows.values()) != len(ga):
                die(f"{gid}: the outcome rows sum to {sum(rows.values())} against {len(ga)} "
                    f"A-group trials — a row leaves the ratio without leaving a trace")
            # The per-row comparison is NOT here: it reads verdicts, which makes it
            # numerator-side, and `tampered-verdict` reaches this point. Measured:
            # placing it here takes that fixture's pinned message. It runs after
            # the byte-compare with the rate numerator, for the same reason.
    return n_sec, n_detail, n_slice, n_outcome, sorted(set(sum_only))


def emit_generation(gen, trials, walls, setup_errors, outcome, exclusions,
                    remeasured=frozenset(), clock=None):
    L = []
    L.append("")
    L.append(f"### Generation {gen['id']} — measured {gen['date']} ({gen['groups']})")
    # The headings come from GROUP_HEADINGS, not a literal here: `check` locates
    # its sections by these strings, so two copies means a wording edit silently
    # stops the attribution check finding anything to check.
    for group, gname in GROUP_HEADINGS:
        g = [t for t in trials if t["group"] == group]
        gw = [w for w in walls if w["group"] == group]
        gs = [s for s in setup_errors if s["group"] == group]
        if not g and not gw and not gs:
            continue
        L.append("")
        L.append(f"#### {gname}")
        # A mechanically selected group an earlier complete generation already
        # measured is labelled under its heading rather than in it:
        # `split_published` finds sections by the exact heading, and a prose line
        # is not a table row (#619). `emit` narrows the set to MECHANICAL_GROUPS —
        # freshness is what those groups are for; the A-group's re-measurement in
        # g2 is the page's own subject and carries its prose outside the markers.
        if group in remeasured:
            L.append("")
            L.append(f"_Re-measured in {gen['id']} on this generation's engine — a historical "
                     f"comparison against the names an earlier generation measured, not fresh "
                     f"evidence; the threshold basis is unchanged._")
        # Both mechanically selected groups print the funnel table: a wall row
        # runs no engine and only this shape has a column for it. The wide
        # table loops over trials alone, so a group sent there loses its walls
        # in silence (the first draft of #619 sent B2 there).
        if group in MECHANICAL_GROUPS:
            L.append("")
            L.append("| target | class | funnel stage | verdict | unknown_reason |")
            L.append("|---|---|---|---|---|")
            for w in gw:
                L.append(f"| {w['tool']} | {w['cls']} | wall {w['wall']} | - | - |")
            for t in g:
                flag = " (0 crash points)" if t["cp0"] else ""
                L.append(f"| {t['tool']} | {t['cls']} | explored | {t['v']}{flag} | {t['reason'] or '-'} |")
            for s in gs:
                L.append(f"| {s['tool']} | {s['cls']} | {excluded_cell(s['id'], exclusions)} | - | - |")
        else:
            L.append("")
            L.append("| trial | tool | class | judge | verdict | unknown_reason | flags |")
            L.append("|---|---|---|---|---|---|---|")
            for t in g:
                flag = " (0 crash points)" if t["cp0"] else ""
                L.append(f"| {t['id']} | {t['tool']} | {t['cls']} | {t['judge']} | "
                         f"{t['v']}{flag} | {t['reason'] or '-'} | {t['flags']} |")
            for s in gs:
                L.append(f"| {s['id']} | {s['tool']} | {s['cls']} | {s['judge']} | "
                         f"{excluded_cell(s['id'], exclusions)} | - | {s['flags']} |")
        if not g:
            continue
        L.append("")
        L.append(f"UNKNOWN rate, per-trial: **{pct_or_counts(sum(1 for t in g if t['v']=='UNKNOWN'), len(g))}**")
        L.append("")
        L.append("| slice | UNKNOWN |")
        L.append("|---|---|")
        for tool in sorted({t["tool"] for t in g}):
            L.append(rate_line(f"tool: {tool}", [t for t in g if t["tool"] == tool]))
        for cls in sorted({t["cls"] for t in g}):
            L.append(rate_line(f"class: {cls}", [t for t in g if t["cls"] == cls]))
        for judge in sorted({t["judge"] for t in g}):
            L.append(rate_line(f"judge: {judge}", [t for t in g if t["judge"] == judge]))
        reasons = sorted({t["reason"] for t in g if t["v"] == "UNKNOWN"})
        if reasons:
            L.append("")
            L.append("| unknown_reason | count |")
            L.append("|---|---|")
            for r in reasons:
                L.append(f"| {r} | {sum(1 for t in g if t['reason'] == r)} |")

    ga = [t for t in trials if t["group"] == "A"]
    if ga:
        L.append("")
        L.append(f"#### {OUTCOME_HEADING}")
        L.append("")
        L.append("| outcome | count |")
        L.append("|---|---|")
        fails = [t for t in ga if t["v"] == "FAIL"]
        for d in PRINTED_DISPOSITIONS:
            k = sum(1 for t in fails if outcome.get(t["tool"], "new-this-sweep") == d)
            L.append(f"| FAIL, {d} | {k} |")
        L.append(f"| UNKNOWN | {sum(1 for t in ga if t['v'] == 'UNKNOWN')} |")
        L.append(f"| PASS | {sum(1 for t in ga if t['v'] == 'PASS')} |")

    # Trials whose launcher recorded observation legs (#619): their own heading,
    # outside GROUP_HEADINGS, so the attribution check neither reads these rows as
    # a denominator nor mistakes a cell for a reason count.
    legged = [t for t in trials if t.get("legs")]
    if legged:
        def leg_cell(l):
            if l is None:
                return "-"
            reason = f" ({l['reason']})" if l["verdict"] == "UNKNOWN" and l["reason"] != "-" else ""
            return f"{l['mode']}: {l['verdict']}{reason}"
        L.append("")
        L.append("#### Observation legs (trials whose launcher recorded them; the verdict above is the last leg's)")
        L.append("")
        L.append("| target | group | first leg | second leg | final mode |")
        L.append("|---|---|---|---|---|")
        for t in legged:
            l2 = t["legs"][1] if len(t["legs"]) > 1 else None
            L.append(f"| {t['tool']} | {t['group']} | {leg_cell(t['legs'][0])} | {leg_cell(l2)} | "
                     f"{t['legs'][-1]['mode']} |")
    if clock and any(x["group"] == "B2" for x in trials + walls):
        L.append("")
        L.append("#### B2 authoring clock (self-reported; minutes from setup_started)")
        L.append("")
        L.append("| target | to first accepted recording | to final |")
        L.append("|---|---|---|")
        for tool in sorted(clock):
            a, b = clock[tool]
            L.append(f"| {tool} | {'-' if a is None else a} | {'-' if b is None else b} |")

    L.append("")
    L.append("#### macOS column (derived, not measured)")
    L.append("")
    L.append("Formula (mechanism: `requireCompleteness`, src/refuse.zig — no oracle exists on macOS,")
    L.append("so every strict PASS becomes `completeness_not_verified`; a FAIL stands on its own")
    L.append("evidence and is unchanged; a Linux UNKNOWN is not re-derived):")
    for group in ("A", "B", "B2"):
        g = [t for t in trials if t["group"] == group]
        if not g:
            continue
        k = sum(1 for t in g if t["v"] in ("UNKNOWN", "PASS"))
        L.append(f"- {group}-group derived UNKNOWN rate on macOS: {pct_or_counts(k, len(g))}")
    return L

def generation_tables(root):
    """Per generation: (gen, expected, manifest, trials, walls, setup_errors).

    Shared by emit and check so the two cannot disagree about what a
    generation measured.
    """
    corpus = read_corpus(root)
    generations = read_generations(root)
    by_id = {c["id"]: c for c in corpus}
    out = []
    for gen in generations:
        exp = expected_for(corpus, generations, gen)
        man = read_manifest(root, gen["dir"])
        # Reports are read only for a generation that claims to be complete.
        # Reading them for one recorded as unstarted would die on a missing
        # report — true, but about the wrong thing: the defect there is the
        # status, and a check that reports "report missing" for it is red for
        # a reason nobody asked about (measured while building the fixture
        # for exactly that case).
        if man is None or gen["status"] != "complete":
            out.append((gen, exp, man, [], [], []))
            continue
        reports = load_reports(root, gen["dir"], man)
        trials, walls, setup_errors = tabulate(man, reports, by_id)
        out.append((gen, exp, man, trials, walls, setup_errors))
    return corpus, generations, out

def emit(root):
    corpus, generations, tables = generation_tables(root)
    outcome = read_outcome_map(root)
    exclusions = read_exclusions(root)
    clock = read_clock(root)
    L = [MARK_BEGIN,
         "_Generated by `spike/unknown-rate/count.py emit` — do not edit between the markers._"]
    seen = set()  # groups a complete generation before this one measured
    for gen, exp, man, trials, walls, setup_errors in tables:
        if man is None:
            L.append("")
            L.append(f"### Generation {gen['id']} — not yet measured ({gen['groups']})")
            L.append("")
            L.append(PLACEHOLDER)
            continue
        groups = set(gen["groups"].split(","))
        L.extend(emit_generation(gen, trials, walls, setup_errors, outcome, exclusions,
                                 remeasured=groups & seen & MECHANICAL_GROUPS, clock=clock))
        seen |= groups
    L.append(MARK_END)
    out = "\n".join(L) + "\n"
    # Held where the block is built, so both modes get the rule (the same reasoning
    # read_exclusions gives for its shape checks). The pair is appended three lines up,
    # so the only way it is not well formed here is a corpus or ledger cell carrying the
    # marker text into the block — the route read_exclusions covers for MARK_END in one
    # ledger column and for no other cell.
    assert_one_marker_pair(out, "recomputation")
    return out

def cohort_ledger_sets(root, corpus):
    """The three sets the cohort ledgers sort the committed defines into.

    One definition with two callers: `check_ledgers` compares them against each other and
    against the disk, and `ledger_sizes` prints their sizes for the page checker. Written
    out twice, a change to how the corpus rows are narrowed would move one and not the
    other, and the page would then be validated against a set the gate no longer uses
    (#342 review).
    """
    sup = read_ledger(root, "supersession.tsv", ["predecessor", "successor", "reason"])
    exc = read_ledger(root, "class-exclusions.tsv", ["define", "row", "reason"])
    return (
        {c["defines"] for c in corpus if c["defines"].startswith(COHORT_PREFIX)},
        {r["predecessor"] for r in sup},
        {r["define"] for r in exc},
        sup,
        exc,
    )

def table_cells(line):
    """A table row's cells, split on the pipes GitHub splits on: every `|` not escaped as `\\|`,
    code spans included — the `|` in `O_WRONLY|O_CREAT` ends a cell there too."""
    parts = re.split(r"(?<!\\)\|", line.strip())[1:]
    if parts and not parts[-1].strip():
        parts = parts[:-1]
    return [c.strip() for c in parts]

def read_class_tables(root):
    """The rows of docs/target-classes.md's Class tables, first table marked (#598).

    That page defines "supported" by position: "supported classes are exactly the rows of
    the first table below". A table here is one whose header row starts with a `Class`
    cell, and it runs from that header to the next `## ` heading. Two things GitHub does to
    such a table are refused rather than read past, because either leaves the table this
    reads different from the one a reader is shown. A blank line inside that span, before a
    further row, ends the table there: measured on 2026-09-16, two such lines left 24 rows
    rendered as loose text. And a row with more cells than its header loses the extra ones:
    an unescaped `|`, inside a code span or not, splits a cell, and on the same day one row
    had been losing its `Recorded in` cell that way, Bun's — the cell that ties Bun's exclusion
    to its row — and removing the blank lines brought a second such row, rrdtool's, into the
    table. The directory references a row cites are read off the whole line, which is sound
    only because no cell is dropped and `row_targets` removes comments first.
    """
    path = root / CLASSES_DOC
    if not path.is_file():
        die(f"{CLASSES_DOC} is missing — class-exclusions.tsv has rows, and the page that "
            f"defines which classes are supported is what they rest on")
    lines = path.read_text().splitlines()
    headings = sum(1 for line in lines if line == FIRST_TABLE_HEADING)
    if headings != 1:
        die(f"{CLASSES_DOC} carries {headings} '{FIRST_TABLE_HEADING}' headings, not 1 — the "
            f"first table is found by that heading, and without it every class would read "
            f"as unsupported")
    rows, section, width, blank = [], None, None, None
    for n, line in enumerate(lines, 1):
        if line.startswith("## "):
            section, width, blank = line, None, None
            continue
        if line.startswith("|"):
            cells = table_cells(line)
            if cells and cells[0] == "Class":
                width, blank = len(cells), None
                continue
            if width is None or set(line) <= set("|-: "):
                continue
            if blank is not None:
                die(f"{CLASSES_DOC}:{blank}: a blank line splits the Class table under "
                    f"'{section}' — GitHub ends the table there, so the row at line {n} and "
                    f"those after it are not in the table a reader sees")
            if len(cells) > width:
                die(f"{CLASSES_DOC}:{n}: the row has {len(cells)} cells where its table's header "
                    f"has {width} — an unescaped | splits a cell, and GitHub drops the cells past "
                    f"the header's; escape it as \\|")
            rows.append({"line": n, "first": section == FIRST_TABLE_HEADING,
                         "cls": cells[0], "tool": cells[1] if len(cells) > 1 else "",
                         "targets": row_targets(line)})
        elif width is not None and not line.strip():
            blank = n
    if not any(r["first"] for r in rows):
        die(f"{CLASSES_DOC} has no Class rows under '{FIRST_TABLE_HEADING}' — an empty "
            f"first table agrees with every exclusion, which is what a broken reader produces")
    return rows

def row_targets(text):
    """The cohort targets a table row names by directory, as (cohort, base target).

    The same (cohort, base) `split_revision` gives a define, read off references such as
    `spike/cohort2/hg-r4/RUNLOG.md`. A directory `REVISION_RE` does not accept is skipped
    rather than refused: rows cite files at any depth, and this reads names, not paths. HTML
    comments are removed first: a path inside one ties nothing, because no reader sees it.
    """
    out = set()
    for m in ROW_COHORT_DIR_RE.finditer(re.sub(r"<!--.*?-->", "", text)):
        dm = REVISION_RE.match(m.group(2))
        if dm:
            out.add((m.group(1), dm.group("base")))
    return out

def tool_words(cell):
    """The tools a Tool cell names, one lower-cased first word per comma-separated part that
    starts with a letter once emphasis, code and link markup is skipped: `git, Borg` -> git,
    borg; `Bun 1.4.0, 1.4.2` -> bun; `[Bun](…) 1.4.2` and `**Bun**` -> bun."""
    out = set()
    for part in cell.split(","):
        m = TOOL_WORD_RE.match(part)
        if m:
            out.add(m.group(1).lower())
    return out

def check_class_exclusions(root, exc):
    """Each class-exclusions.tsv row rests on its target's own refusal-table row (#598).

    The file's criterion is the one ADR 0025 and docs/target-classes.md state: the target's
    class is not supported, which that page defines as not being a row of its first table,
    whatever verdicts a refusal row records. A quoted class string alone does not hold that
    — any define, a supported target's included, could be parked here under a refusal
    table's class, the shape the supersession check above refuses for its own file. So the
    define is tied to rows by the cohort directory the row cites, and held from both sides.

    Nothing in the first table may reach the target, by any of three keys:
    - a first-table row citing its cohort directory;
    - a first-table row naming the same tool — a word from the Tool cell of the row the
      define is tied to, or the define's own directory name. Targets have crossed into the
      first table by gaining a new row that cites a later record and keeping the refusal
      row (virtualenv and ansible-core cite dogfood runs, zstd a follow-up), and that new
      row cites no cohort directory;
    - the quoted class being a Class cell of the first table as well, which is how a class
      becomes supported without this target moving: ansible-core crossed under its own
      Class cell, and mlr shares cargo's.
    What none of them sees: a first-table row naming the tool by a word neither the tied
    row nor the directory uses.

    And something outside the first table must: a row citing the define's directory,
    carrying the quoted Class cell verbatim.

    Not held: whether the refusal row is right about the target. Returns the rows checked.
    """
    if not exc:
        return 0
    rows = read_class_tables(root)
    first_tools = {}
    for r in rows:
        if r["first"]:
            for word in tool_words(r["tool"]):
                first_tools.setdefault(word, r)
    first_classes = {r["cls"]: r for r in rows if r["first"]}
    for x in exc:
        cohort, base, _rev = split_revision(x["define"])
        named = [r for r in rows if (cohort, base) in r["targets"]]
        in_first = [r["line"] for r in named if r["first"]]
        if in_first:
            die(f"class-exclusions.tsv: {x['define']} is excluded as unsupported, but "
                f"{CLASSES_DOC}:{in_first[0]}, a first-table row, names its directory — its "
                f"class is supported, so the define belongs in corpus.tsv or supersession.tsv")
        linked = [r for r in named if not r["first"]]
        keys = {base.lower()}
        for r in linked:
            keys |= tool_words(r["tool"])
        crossed = sorted(keys & set(first_tools))
        if crossed:
            f = first_tools[crossed[0]]
            die(f"class-exclusions.tsv: {x['define']} is excluded as unsupported, but the "
                f"first-table row {CLASSES_DOC}:{f['line']} and this target name the same tool "
                f"({crossed[0]!r}) — the target has crossed into the first table, so its class "
                f"is supported")
        if x["row"] in first_classes:
            die(f"class-exclusions.tsv: {x['define']} quotes the class {x['row']!r}, which is "
                f"also a Class cell of the first table ({CLASSES_DOC}:"
                f"{first_classes[x['row']]['line']}) — that class is supported, so the define "
                f"belongs in corpus.tsv or supersession.tsv")
        if not linked:
            die(f"class-exclusions.tsv: {x['define']} names no row outside the first table "
                f"of {CLASSES_DOC} — no refusal row cites spike/{cohort}/{base} or a "
                f"revision of it, so the row this exclusion rests on cannot be found")
        if not any(r["cls"] == x["row"] for r in linked):
            found = "; ".join(f"line {r['line']}: {r['cls']!r}" for r in linked)
            die(f"class-exclusions.tsv: {x['define']} quotes the class {x['row']!r}, and the "
                f"row that names it says {found} — quote the Class cell verbatim")
    return len(exc)

def check_ledgers(root, corpus):
    """The three cohort ledgers partition the committed cohort defines, a supersession row
    names a later revision of its own target that is measured, and a class exclusion rests
    on its target's own refusal-table row. Returns the class-exclusion rows checked."""
    in_corpus, in_sup, in_exc, sup, exc = cohort_ledger_sets(root, corpus)

    for a, b, na, nb in ((in_corpus, in_sup, "corpus.tsv", "supersession.tsv"),
                         (in_corpus, in_exc, "corpus.tsv", "class-exclusions.tsv"),
                         (in_sup, in_exc, "supersession.tsv", "class-exclusions.tsv")):
        both = a & b
        if both:
            die(f"{na} and {nb} both claim {sorted(both)} — the ledgers must be disjoint")

    on_disk = cohort_defines_on_disk(root)
    union = in_corpus | in_sup | in_exc
    missing = on_disk - union
    if missing:
        die(f"committed cohort defines in no ledger: {sorted(missing)} — every one must be "
            f"measured, superseded or excluded by class, and silence is not one of those")
    extra = union - on_disk
    if extra:
        die(f"ledgers name defines that are not on disk: {sorted(extra)}")

    # A supersession row's whole claim is narrow: a LATER REVISION OF THE
    # SAME TARGET replaced this define, and that revision is measured.
    # Checking only "the successor is some corpus define" leaves the file a
    # place to park anything — measured, with hg's successor rewritten to
    # borg-r3 and the check still green. All three parts are held here.
    for r in sup:
        if r["successor"] not in in_corpus:
            die(f"supersession.tsv: {r['predecessor']} names successor {r['successor']}, "
                f"which is not a corpus define — a superseded row must be replaced by a "
                f"measured one")
        pc, pb, pr = split_revision(r["predecessor"])
        sc, sb, sr = split_revision(r["successor"])
        if (pc, pb) != (sc, sb):
            die(f"supersession.tsv: {r['predecessor']} names successor {r['successor']}, "
                f"which is a different target ({pc}/{pb} vs {sc}/{sb}) — this file records "
                f"revisions of one target replacing each other, not arbitrary exclusions")
        if sr <= pr:
            die(f"supersession.tsv: {r['predecessor']} (revision {pr}) names successor "
                f"{r['successor']} (revision {sr}), which is not later — a define is not "
                f"superseded by one that came before it")

    return check_class_exclusions(root, exc)

def ledger_sizes(root):
    """The counts the pages state in prose, from the sets `check_ledgers` compares.

    A third mode rather than a second copy, and that goes for the sets as well as for the
    glob: `cohort_ledger_sets` above is what `check_ledgers` compares, so the page is held
    to the same three sets the ledger gate uses rather than to a second reading of them.
    `spike/check-ledger-prose.sh` holds `docs/unknown-rate.md` and `PRD.md` to these
    numbers; a shell reimplementation of "committed cohort define" would drift from the
    glob the first time a revision directory appeared or a non-toml file landed under an
    `ops/` (#342).

    `remaining` is the sum the page states rather than a sixth set: the two ledgers are
    already checked disjoint by `check_ledgers`, so their sizes add.
    """
    in_corpus, in_sup, in_exc, _sup, _exc = cohort_ledger_sets(root, read_corpus(root))
    on_disk = cohort_defines_on_disk(root)
    print(f"sorted={len(on_disk)} corpus={len(in_corpus)} superseded={len(in_sup)} "
          f"excluded={len(in_exc)} remaining={len(in_sup) + len(in_exc)}")

def check_dispositions(root, corpus, outcome):
    """Cohort tools are triaged from the record, not parked as new."""
    tools = sorted({c["tool"] for c in corpus if c["defines"].startswith(COHORT_PREFIX)})
    for t in tools:
        if t not in outcome:
            die(f"outcome-map.tsv has no row for {t} — a corpus tool with no disposition "
                f"falls through to new-this-sweep by default, which is indistinguishable "
                f"from an untriaged finding")
        if outcome[t] == "new-this-sweep":
            die(f"outcome-map.tsv records {t} as new-this-sweep, but its verdicts predate "
                f"this sweep and docs/target-classes.md states their disposition — "
                f"declaring an already-triaged tool untriaged satisfies the map without "
                f"carrying its meaning")

def check(root):
    corpus, generations, tables = generation_tables(root)
    outcome = read_outcome_map(root)
    exclusions = read_exclusions(root)
    docs = (root / "docs/unknown-rate.md").read_text()
    block = emit(root)
    # After the recomputation, deliberately, though the page is already in hand: a cell
    # that poisons the block poisons the published page too (the page is pasted from
    # `emit`), so checking the page first would take every such tree on the page's
    # message and leave emit's own guard with nothing that reaches it. Ordering decides
    # which guard a fixture proves. Still before the pre-data branch, so a duplicated
    # marker dies on a tree with nothing measured too, and before the row-count and
    # drift guards, so it is named as a duplication rather than as their symptom.
    assert_one_marker_pair(docs, "docs/unknown-rate.md")

    # The B-group rows must be exactly the committed mechanical selection,
    # order included — "no hand touched the list" is checked, not narrated.
    # This binds pre-data too: the apparatus PR is where a hand-edit would
    # first try to slip in.
    def read_lines(rel):
        p = root / rel
        if not p.exists():
            die(f"{rel} is missing — the selection chain cannot be checked")
        return p.read_text().splitlines()

    bt = [l for l in read_lines("spike/unknown-rate/b-targets.txt") if l]
    bc = [c["tool"] for c in corpus if c["group"] == "B"]
    if bc != bt:
        die("corpus B rows differ from the committed b-targets.txt selection (order included)")
    # The same binding for B2 (#619): a corpus row naming a target the committed
    # list does not would break "committed before any of them ran" in silence.
    # Only when B2 rows exist — g1 and g2 carried none, and the selection chain
    # itself is held by `b2-selection` on the live tree.
    bc2 = [c["tool"] for c in corpus if c["group"] == "B2"]
    if bc2:
        if not (root / "spike/unknown-rate/b2-targets.txt").exists():
            die("corpus carries B2 rows and b2-targets.txt is missing — the rows cannot be held "
                "to the committed selection")
        # Read the way `b2-selection` reads it (comment lines dropped), so a header
        # added to the file fails neither side or both.
        bt2 = _b2_lines(root, "spike/unknown-rate/b2-targets.txt")
        if bc2 != bt2:
            die("corpus B2 rows differ from the committed b2-targets.txt selection (order included)")
    # And the selection itself must still be the mechanical derivation:
    # first N of (candidates minus exclusions). Without this, editing
    # b-targets.txt and the corpus together would keep everything
    # "consistent" (R2 measured that pair-edit passing).
    cands = [l for l in read_lines("spike/unknown-rate/b-candidates.txt") if l]
    excl = set()
    for line in read_lines("spike/unknown-rate/b-exclusions.txt"):
        if line and not line.startswith("#"):
            excl.add(line.split("\t")[0])
    derived = [c for c in cands if c not in excl][:len(bt)]
    if derived != bt:
        die("b-targets.txt is not the first-N derivation of b-candidates.txt minus b-exclusions.txt")

    n_class = check_ledgers(root, corpus)
    check_dispositions(root, corpus, outcome)

    # Every corpus row must be inside some generation's expected set. A row
    # whose entering generation does not cover its group belongs to no
    # generation at all: it is measured by nothing, and every completeness
    # check passes over it. Narrowing a generation's groups is enough to do
    # that to eight rows at once.
    # `since` is already known to name a generation: `generation_tables` above calls
    # `expected_for`, whose own check refuses first. A duplicate of that refusal used to
    # sit here, and it was unreachable -- measured 2026-09-01 (#341) by removing the one
    # in `expected_for` and feeding a bad `since`: the run died with `KeyError` inside
    # `expected_for`, never arriving here. A fixture aimed at it could only ever have
    # died on its twin, which is why it was removed rather than given one.
    by_gen = {g["id"]: g for g in generations}
    for c in corpus:
        cover = by_gen[c["since"]]["groups"].split(",")
        if c["group"] not in cover:
            die(f"corpus row {c['id']} is in group {c['group']} but enters at generation "
                f"{c['since']}, which covers {'/'.join(cover)} — a row no generation covers "
                f"is measured by nothing and missed by every completeness check")

    enum = enum_from_schema_doc(root)
    by_id_c = {c["id"]: c for c in corpus}
    measured = 0
    # Counted, not just checked: on a tree with no apparatus failures the waiver
    # predicates look at nothing, and a success line that does not say so cannot be
    # told apart from one that checked something. The live tree is that tree today.
    waived, seen_waivers = 0, set()
    # Both halves are reported, and the wording says "covered by" rather than
    # "against" on purpose: every other pair on the success line is a comparison this
    # check enforces, and this one is not. The record lists every `sideeye-ur-*` on
    # the sweep host, so its count can exceed what the manifests use without anything
    # being wrong. The apparatus side is here because it cannot be derived from
    # anything else in the tree — that is what separates a run that read the records
    # from one that opened nothing. Neither is asserted non-zero: a generation whose
    # trials are all walls names no images, and zero is the honest count.
    apparatus_images, manifest_images = 0, 0
    pins = read_engine_pins(root)
    pinned = 0

    for gen, exp, manifest, trials, walls, setup_errors in tables:
        gid = gen["id"]
        if gen["status"] == "unstarted":
            if manifest is not None:
                die(f"generation {gid} is marked unstarted but {gen['dir']}/manifest.tsv "
                    f"exists — a sweep that ran is not unstarted")
            continue
        # status is complete (read_generations rejects anything else)
        if manifest is None:
            die(f"generation {gid} is marked complete but has no manifest at "
                f"{gen['dir']}/manifest.tsv")
        # After the unstarted `continue` and the missing-manifest die on purpose: a
        # generation with no manifest has no images to bind, and an unstarted one has
        # no apparatus to record. Not in `generation_tables` either — that is shared
        # with `emit`, and moving the refusal there would change which surface says no.
        apparatus, n_img, alines = read_apparatus(root, gen["dir"])
        # A generation engine-pins.tsv names a release for must say so in its own
        # record (#619): the two digest lines describe whatever was mounted, and
        # only this line says it was the pinned asset, checked against the digest.
        if gid in pins:
            tag, asset, psha = pins[gid]
            want = f"engine: release {tag} {asset} {psha}"
            if not any(l == want or l.startswith(want + " ") for l in alines):
                die(f"{gid}: engine-pins.tsv pins {tag} but {gen['dir']}/apparatus.txt carries no "
                    f"line `{want}` — the record does not say the pinned release ran")
            pinned += 1
        used = {row["image"] for row in manifest if not row["argv"].startswith("wall:")}
        unlisted = sorted(used - apparatus)
        if unlisted:
            die(f"{gid}: manifest names images the apparatus record does not: {unlisted} — "
                f"the record is short of the run it is supposed to describe")
        apparatus_images += n_img
        manifest_images += len(used)

        ids_e = [c["id"] for c in exp]
        ids_m = [m["id"] for m in manifest]
        if ids_m != ids_e:
            die(f"generation {gid}: manifest covers {len(ids_m)} trials against its expected "
                f"{len(ids_e)} (order included) — a partially measured generation is not "
                f"publishable, and recording it as complete is how it would become so")
        measured += len(ids_e)

        # The published tables are built from MANIFEST columns; hold every
        # classifying column to the frozen corpus, or a re-labeled manifest row
        # (a trial moved between groups, an UNKNOWN re-filed as a funnel wall)
        # would flow into the tables with the docs regenerated to match — R1
        # measured exactly that passing the byte-compare alone.
        for row in manifest:
            c = by_id_c[row["id"]]
            for k in ("group", "tool", "cls", "judge"):
                if row[k] != c[k]:
                    die(f"{gid}/{row['id']}: manifest {k} {row[k]!r} differs from the frozen corpus {c[k]!r}")
            wall_m = row["argv"].startswith("wall:")
            wall_c = c["launcher"] == "-"
            if wall_m != wall_c:
                die(f"{gid}/{row['id']}: wall-ness differs between manifest and corpus")
            if wall_m and row["rsha"] != "-":
                die(f"{gid}/{row['id']}: a funnel wall row carries a report hash "
                    f"({row['rsha']!r}) — a wall runs no engine and produces no report")
            if wall_c and row["argv"] != f"wall:{c['args']}":
                die(f"{gid}/{row['id']}: wall reason {row['argv']!r} differs from corpus {c['args']!r}")
            if not wall_c:
                # The report path decides WHICH report speaks for the trial; an
                # unbound rpath lets verdicts swap between trials with every
                # classifying column intact (R2 measured the B-group rate
                # flipping 1/1 -> 0/1 that way). The argv binding closes the
                # same door for the record's invocation column.
                if row["rpath"] != f"{c['artdir']}/{c['rpath']}":
                    die(f"{gid}/{row['id']}: manifest report path {row['rpath']!r} differs from the frozen corpus")
                if row["argv"] != f"{c['launcher']} {c['args']}":
                    die(f"{gid}/{row['id']}: manifest argv {row['argv']!r} differs from the frozen corpus")

        reports = load_reports(root, gen["dir"], manifest)
        for row in manifest:
            r = reports[row["id"]]
            # The report is bound to the sweep by its bytes (#349). Without this the
            # manifest's `rpath` says only WHERE a report should be, never that the file
            # there is the one this sweep produced — measured before the fix: the
            # twenty-eight A-group reports g1 and g2 share, copied byte-for-byte from one
            # generation into the other, and every check still said OK. Shared rows are
            # the vulnerable ones: the part of a re-measurement that stays the same is the
            # part a substitution leaves no trace in. The `digest` column beside it hashes
            # the DEFINE, which says the recipe was the committed one and nothing about
            # the result.
            if "wall" not in r and row["rsha"] != r["sha"]:
                die(f"{gid}/{row['id']}: the report at {row['rpath']} hashes {r['sha']}, "
                    f"and the manifest recorded {row['rsha']} — this file is not the one "
                    f"the sweep wrote")
            if "wall" not in r and r["verdict"] == "UNKNOWN" and r["reason"] not in enum:
                die(f"{gid}/{row['id']}: unknown_reason {r['reason']!r} not in the documented closed set")

        for row in manifest:
            want = digest_for(root, by_id_c[row["id"]]["defines"])
            if want != row["digest"]:
                die(f"{gid}/{row['id']}: define digest mismatch — the defines in the checkout are "
                    f"not the bytes the sweep hashed")

        # The flagged-trial guard that stood here is gone. It asked whether a
        # marked row reached the rated set exactly once, and could only fire on a
        # duplicate corpus id: `:543` pins the manifest id list to the expected one
        # order-included, `tabulate` puts each manifest row in exactly one bucket,
        # and the guard re-derived its skip conditions from the same `reports`
        # mapping `tabulate` branches on. Measured before deleting it — a corpus
        # with a duplicated id made it fire with its own message, and nothing else
        # did — and that input is now covered more widely by `_reject_duplicate_ids`,
        # which applies to all 57 corpus rows rather than the 3 that carry flags.
        #
        # What a flagged row reaches is checked where the promise lives:
        # `check_attribution`, against every published aggregate.
        #
        # A partition assert over `tabulate`'s output stood here briefly and was
        # removed on review. `tabulate` performs exactly one unconditional append
        # per manifest row (if/elif/else, no filter), so the assert was unsatisfiable
        # for every input — true by construction, which is the same reason the guard
        # above was deleted. Falsifying it required mutating `tabulate` itself, i.e.
        # asserting an invariant about code rather than about data, and this file's
        # own standard is that a new guard is falsified once against its predicate.

        # Conservation: every A-group FAIL lands in one of the four rows the
        # outcome table prints. A disposition outside that set — a tool
        # recorded as having no FAIL that then produces one — would drop out
        # of the ratio with the table still summing to something plausible.
        ga = [t for t in trials if t["group"] == "A"]
        fails = [t for t in ga if t["v"] == "FAIL"]
        stray = sorted({t["tool"] for t in fails
                        if outcome.get(t["tool"], "new-this-sweep") not in PRINTED_DISPOSITIONS})
        if stray:
            die(f"{gid}: A-group FAILs from {stray} carry a disposition the outcome table does "
                f"not print — they would leave the ratio without leaving a trace")

        # The page's SETUP_ERROR rule is two-sided and only one side was enforced.
        # A row that failed to set up leaves the rated denominator whatever anyone
        # decided about it, so a sweep with one apparatus failure publishes a rate
        # over n-1 and reads exactly like a sweep of n. The default the page states
        # is "fix the apparatus and re-run that trial"; publishing the row instead
        # is the exception, allowed only "if unfixable", and that judgement is a
        # person's. This is where the person has to have written it down.
        for s in setup_errors:
            waived += 1
            if s["id"] not in exclusions:
                die(f"{gid}/{s['id']}: SETUP_ERROR with no row in exclusions.tsv — the page "
                    f"re-runs an apparatus failure and publishes it as excluded only if it "
                    f"cannot be fixed, so a generation cannot be complete while nobody has "
                    f"said which of those two happened")
            seen_waivers.add(s["id"])

    # And the other direction. A waiver whose trial no longer fails — or never did —
    # excuses nothing, and the reason it carries would go on reading as approved
    # while the row it named has moved on.
    orphans = sorted(set(exclusions) - seen_waivers)
    if orphans:
        die(f"exclusions.tsv waives {orphans}, which is not a SETUP_ERROR in any complete "
            f"generation — a waiver outliving its trial excuses nothing")

    if measured == 0:
        if PLACEHOLDER not in docs:
            die("no generation has measured anything, and docs/unknown-rate.md lacks the "
                "not-yet-measured placeholder")
        # No waiver count here: the orphan check above runs before this branch, so a
        # pre-data tree with any waiver at all has already died. The number would be
        # zero on every run that reaches this line, which is the opposite of the
        # reason the main success line carries one.
        print(f"count.py check: pre-data state — placeholder asserted, corpus parsed "
              f"({len(corpus)} rows, {len(generations)} generations); {n_class} class exclusions "
              f"matched to refusal-table rows")
        return

    if MARK_BEGIN not in docs or MARK_END not in docs:
        die("docs/unknown-rate.md lacks the results markers")
    # Cardinality and order were asserted at the top of check(), before the pre-data
    # branch; together with the existence check above, the measured page carries
    # exactly one pair, in order, by this line.
    published = docs.split(MARK_BEGIN)[1].split(MARK_END)[0]
    # Row-count first, on the PUBLISHED side: after the byte-compare passes
    # this could never fire (the recomputation always emits one row per
    # measured row — R1 proved the original order unreachable), so the
    # empty-table guard has to look at the docs before trusting them.
    pub_rows = [l for l in published.splitlines() if l.startswith("| ")]
    if len(pub_rows) < measured:
        die(f"published tables carry {len(pub_rows)} rows for {measured} measured trials — "
            f"an empty or truncated table cannot stand in for the measurement")
    n_sec, n_detail, n_slice, n_outcome, sum_only = check_attribution(tables, published)
    computed = block.split(MARK_BEGIN)[1].split(MARK_END)[0]
    if published != computed:
        die("published results block differs from recomputation (drift)")

    # The numerator, bound to the measurement — and it has to sit HERE, after the
    # byte-compare, not with the rest of attribution. Before it, this fires on
    # `tampered-verdict` (the only fixture that reaches the block) and displaces
    # its pinned message. After it, it is still live: the byte-compare proves
    # published == computed, and computed came from the renderer, so recomputing
    # k from `trials` directly is the one comparison a renderer bug in the
    # numerator cannot survive. Unlike `pub_rows` above, this is not dead here.
    #
    # No data-only fixture can make it red — a fixture that perturbs the number
    # dies earlier — so it is named in acceptance.sh's list of predicates
    # carrying no fixture rather than pretending to have one.
    pub_sections = split_published(published)
    for gen, _e, _m, trials, _w, _s in tables:
        for group, _name in GROUP_HEADINGS:
            g = [t for t in trials if t["group"] == group]
            if not g:
                continue
            _d, _sl, _r, rate = parse_section(pub_sections[(gen["id"], group)])
            want_k = sum(1 for t in g if t["v"] == "UNKNOWN")
            if rate[0] != want_k:
                die(f"{gen['id']}/{group}: the published numerator is {rate[0]} against {want_k} "
                    f"UNKNOWN in the measurement")
            # Per slice, and against the measurement — not against the published
            # detail rows. Reconciling a slice numerator with the detail table is
            # published-against-published: both come from the renderer, which is
            # the defect this whole check exists to close, and the first version
            # of it reproduced that defect one level down. Measured: a renderer
            # that reports the flagged row as PASS in the detail table AND drops
            # it from every slice numerator, while leaving the rate line honest,
            # passed everything until this ran.
            funnel = any("judge" not in d for d in _d)
            for axis, field in AXES:
                if funnel and axis == "judge":
                    continue
                for value in sorted({t[field] for t in g}):
                    k_s, _n = _sl[(axis, value)]
                    wk = sum(1 for t in g if t[field] == value and t["v"] == "UNKNOWN")
                    if k_s != wk:
                        die(f"{gen['id']}/{group}: slice {axis}: {value} claims {k_s} UNKNOWN "
                            f"against {wk} in the measurement")
        ga = [t for t in trials if t["group"] == "A"]
        if ga:
            _d, _s, rows, _r = parse_section(pub_sections[(gen["id"], "outcome")])
            for label, want in (("UNKNOWN", sum(1 for t in ga if t["v"] == "UNKNOWN")),
                                ("PASS", sum(1 for t in ga if t["v"] == "PASS"))):
                if rows.get(label) != want:
                    die(f"{gen['id']}: the outcome table puts {rows.get(label)} in {label} "
                        f"against {want} in the measurement")
            fails = sum(1 for t in ga if t["v"] == "FAIL")
            pub_fails = sum(v for k, v in rows.items() if k.startswith("FAIL, "))
            if pub_fails != fails:
                die(f"{gen['id']}: the outcome table's FAIL rows sum to {pub_fails} against "
                    f"{fails} A-group FAILs")

    weaker = f"; {len(sum_only)} axis measured by denominator alone ({', '.join(sum_only)})" if sum_only else ""
    print(f"count.py check: OK — {len(corpus)} corpus rows across {len(generations)} generations, "
          f"{measured} measured, digests verified, docs in sync; attribution reconciled "
          f"{n_detail} published rows against {n_slice} slices and {n_outcome} outcome rows "
          f"across {n_sec} sections{weaker}; {waived} SETUP_ERROR rows against "
          f"{len(exclusions)} waivers; {manifest_images} manifest images covered by "
          f"{apparatus_images} apparatus image lines read; {n_class} class exclusions matched "
          f"to refusal-table rows; {pinned} generation(s) held to a pinned release")

# --- The B2 selection chain (#619, ADR 0073) ---------------------------------
#
# A mode of its own rather than a branch of `check`, for the reason
# spike/check-ledger-prose.sh gives for the same shape: `check` runs against
# every committed fixture tree, whose toy pages carry no B2 files, so a
# fail-closed reader there would go red on the two fixtures required to pass
# and take the failure of the rest away from the predicates they exist to
# prove. The live tree is the only tree with a B2 selection; acceptance runs
# this mode on it beside `check`, and `--selftest` proves the mode's own reds
# on a scratch copy the way that script does.

# The five ledgers whose names must be excluded: file, and the tab-separated
# column the name sits in (None for a one-name-per-line file). corpus.tsv is
# the A-group and its control (and the B rows again, harmlessly): without it
# the page's "the A-group and its control" rested on prose — its first review
# found borg and hg covered by nothing.
B2_LEDGERS = (
    ("spike/unknown-rate/b-targets.txt", None),
    ("spike/unknown-rate/b-exclusions.txt", 0),
    ("spike/unknown-rate/corpus.tsv", 2),
    ("spike/outcome-funnel.tsv", 1),
    ("spike/upstream-reports.tsv", 3),
)
B2_FILES = ("b2-candidates.txt", "b2-targets.txt", "b2-exclusions.txt",
            "b2-exclusion-aliases.tsv", "b2-order-key.txt", "b2-selection-record.txt")
B2_MIN = 20  # the floor #619 sets; N itself is select-b2.sh's, and the record names it


class B2Error(Exception):
    """A refusal of the B2 selection chain — raised, not printed, so --selftest can read it."""


def _b2_lines(root, rel):
    p = root / rel
    if not p.exists():
        raise B2Error(f"{rel} is missing — the B2 selection chain cannot be checked")
    return [l for l in p.read_text().splitlines() if l and not l.startswith("#")]


def b2_order(cands, key):
    """select-b2.sh's order: sha256("<package>\\t<key>") ascending, the name breaking a tie."""
    return sorted(cands, key=lambda p: (hashlib.sha256(f"{p}\t{key}".encode()).hexdigest(), p))


def b2_selection(root):
    ur = "spike/unknown-rate/"
    cands = _b2_lines(root, ur + "b2-candidates.txt")
    if len(set(cands)) != len(cands):
        raise B2Error("b2-candidates.txt lists a package twice")
    # The one figure the page states about the pool, held to the file the way
    # check-ledger-prose.sh holds the cohort counts: read out of its own
    # sentence, and an anchor that stops matching is a failure, not a skip.
    page = root / "docs/unknown-rate.md"
    if not page.exists():
        raise B2Error("docs/unknown-rate.md is missing — the pool size it states cannot be checked")
    stated = re.findall(r"is `b2-candidates\.txt` \((\d+) packages\)", page.read_text())
    if len(stated) != 1:
        raise B2Error("docs/unknown-rate.md does not state the B2 pool size exactly once in the "
                      "sentence this reads (is `b2-candidates.txt` (N packages)) — the anchor moved")
    if int(stated[0]) != len(cands):
        raise B2Error(f"docs/unknown-rate.md says the B2 pool has {stated[0]} packages and "
                      f"b2-candidates.txt lists {len(cands)}")
    targets = _b2_lines(root, ur + "b2-targets.txt")
    excl = {}
    for line in _b2_lines(root, ur + "b2-exclusions.txt"):
        f = line.split("\t")
        if len(f) != 2 or not f[0] or not f[1]:
            raise B2Error(f"b2-exclusions.txt row does not have 2 columns: {line!r}")
        if f[0] in excl:
            raise B2Error(f"b2-exclusions.txt lists {f[0]!r} twice")
        excl[f[0]] = f[1]
    keys = _b2_lines(root, ur + "b2-order-key.txt")
    if len(keys) != 1:
        raise B2Error(f"b2-order-key.txt carries {len(keys)} keys, not one")
    key = keys[0]
    record = _b2_lines(root, ur + "b2-selection-record.txt")
    m = re.match(r"generated: select-b2\.sh \(N=(\d+)\)$", record[0]) if record else None
    if not m:
        raise B2Error("b2-selection-record.txt does not open with the `generated:` line that names N")
    n = int(m.group(1))
    pool = [int(x) for l in record for x in re.findall(r"^pool after predicate: (\d+) packages$", l)]
    if len(pool) != 1:
        raise B2Error("b2-selection-record.txt does not state the pool size once")
    if pool[0] != len(cands):
        raise B2Error(f"b2-selection-record.txt says the pool has {pool[0]} packages and "
                      f"b2-candidates.txt lists {len(cands)}")
    if n < B2_MIN:
        raise B2Error(f"N={n} is below the {B2_MIN} candidates #619 asks for")
    if len(targets) != n:
        raise B2Error(f"b2-targets.txt lists {len(targets)} names and the record says N={n}")
    # The derivation itself: first N of the keyed order minus the exclusions.
    # Without this, editing b2-targets.txt keeps everything else "consistent" —
    # the same pair-edit the B-group's check in `check` closes.
    derived = [p for p in b2_order(cands, key) if p not in excl][:n]
    if derived != targets:
        raise B2Error("b2-targets.txt is not the keyed first-N derivation of b2-candidates.txt "
                      "minus b2-exclusions.txt")
    aliases = {}
    for line in _b2_lines(root, ur + "b2-exclusion-aliases.tsv"):
        f = line.split("\t")
        if len(f) != 3 or not f[0] or not f[1]:
            raise B2Error(f"b2-exclusion-aliases.tsv row does not have 3 columns: {line!r}")
        name, pkgs, _source = f
        if name in aliases:
            raise B2Error(f"b2-exclusion-aliases.tsv lists {name!r} twice")
        aliases[name] = [] if pkgs == "-" else pkgs.split(";")
        for p in aliases[name]:
            if p not in excl:
                raise B2Error(f"b2-exclusion-aliases.tsv maps {name!r} to {p!r}, a package "
                              f"b2-exclusions.txt does not carry")
    # Coverage: every name the ledgers spell is a package in the exclusions or a
    # name the alias table resolves (to packages already held above, or to `-`).
    n_names = 0
    for rel, col in B2_LEDGERS:
        for line in _b2_lines(root, rel):
            f = line.split("\t")
            if col is not None and len(f) <= col:
                raise B2Error(f"{rel} row has {len(f)} column(s), fewer than the {col + 1} its "
                              f"name sits in: {line!r}")
            # corpus.tsv's own B2 rows are the selection, not prior contact:
            # they name the thirty this check derives, and reading them as a
            # ledger would demand the list exclude itself.
            if rel.endswith("corpus.tsv") and len(f) > 1 and f[1] == "B2":
                continue
            name = (line if col is None else f[col]).strip()
            if not name:
                continue
            n_names += 1
            if name in excl or name in aliases:
                continue
            raise B2Error(f"{name!r} ({rel}) is not covered: neither a package in "
                          f"b2-exclusions.txt nor a name in b2-exclusion-aliases.tsv")
    print(f"count.py b2-selection: OK — {len(targets)} targets are the keyed first-{n} of "
          f"{len(cands)} candidates minus {len(excl)} exclusions; {n_names} ledger names "
          f"covered through {len(aliases)} aliases")


def b2_selftest(root):
    """Every refusal `b2_selection` and `_b2_lines` can raise, seen red once on a
    scratch copy mutated one way at a time — nineteen raise sites, twenty-two
    mutations (the derivation is proven twice, by a swap and by a changed key; the
    short-row refusal once per ledger read past column 0, three times), one green
    baseline: twenty-three proofs.

    Counted rather than narrated: the number of proofs that ran is asserted at the
    end, the reason check-ledger-prose.sh gives (its first cut reported fifteen and
    had run thirteen). The first cut of THIS function proved three predicates and
    called it "each refusal above"; its review counted the raise sites.
    """
    import shutil
    import tempfile
    ur = "spike/unknown-rate/"
    files = [ur + f for f in B2_FILES] + [rel for rel, _ in B2_LEDGERS] + ["docs/unknown-rate.md"]
    ran = 0

    def fresh():
        tmp = Path(tempfile.mkdtemp(prefix="b2-selftest-"))
        for rel in files:
            dst = tmp / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / rel, dst)
        return tmp

    def expect(label, mutate, want):
        nonlocal ran
        tmp = fresh()
        try:
            mutate(tmp)
            try:
                b2_selection(tmp)
            except B2Error as e:
                if want not in str(e):
                    die(f"selftest {label}: died, but not on its predicate — {e}")
                ran += 1
                return
            die(f"selftest {label}: the mutation passed — the mode is blind to it")
        finally:
            shutil.rmtree(tmp)

    tmp = fresh()
    try:
        b2_selection(tmp)
    except B2Error as e:
        die(f"selftest baseline: the unmutated copy is red — {e}")
    finally:
        shutil.rmtree(tmp)
    ran += 1

    def lines_of(tmp, rel):
        return (tmp / rel).read_text().splitlines()

    def write(tmp, rel, lines):
        (tmp / rel).write_text("\n".join(lines) + "\n")

    def append(tmp, rel, line):
        with (tmp / rel).open("a") as f:
            f.write(line + "\n")

    def first_data(tmp, rel):
        return next(l for l in lines_of(tmp, rel) if l and not l.startswith("#"))

    def edit_record(tmp, fn):
        rel = ur + "b2-selection-record.txt"
        write(tmp, rel, fn(lines_of(tmp, rel)))

    # One mutation per raise site, in the order the sites are reached.
    expect("candidate-twice",
           lambda t: append(t, ur + "b2-candidates.txt", first_data(t, ur + "b2-candidates.txt")),
           "b2-candidates.txt lists a package twice")
    expect("page-missing",
           lambda t: (t / "docs/unknown-rate.md").unlink(),
           "docs/unknown-rate.md is missing")
    expect("page-anchor-moved",
           lambda t: write(t, "docs/unknown-rate.md",
                           [l.replace("packages)", "package)") for l in lines_of(t, "docs/unknown-rate.md")]),
           "the anchor moved")
    expect("page-pool-wrong",
           lambda t: write(t, "docs/unknown-rate.md",
                           [re.sub(r"is `b2-candidates\.txt` \(\d+ packages\)", "is `b2-candidates.txt` (1 packages)", l)
                            for l in lines_of(t, "docs/unknown-rate.md")]),
           "says the B2 pool has")
    expect("exclusion-columns",
           lambda t: append(t, ur + "b2-exclusions.txt", "fx-onecolumn"),
           "b2-exclusions.txt row does not have 2 columns")
    expect("exclusion-twice",
           lambda t: append(t, ur + "b2-exclusions.txt", first_data(t, ur + "b2-exclusions.txt")),
           "b2-exclusions.txt lists")
    expect("two-keys",
           lambda t: append(t, ur + "b2-order-key.txt", "1" * 40),
           "keys, not one")
    expect("record-no-generated-line",
           lambda t: edit_record(t, lambda L: ["planted by b2_selftest"] + L[1:]),
           "does not open with the `generated:` line")
    expect("record-no-pool-line",
           lambda t: edit_record(t, lambda L: [l for l in L if not l.startswith("pool after predicate:")]),
           "does not state the pool size once")
    expect("record-pool-wrong",
           lambda t: edit_record(t, lambda L: [re.sub(r"^pool after predicate: \d+", "pool after predicate: 1", l) for l in L]),
           "says the pool has")
    expect("n-below-floor",
           lambda t: edit_record(t, lambda L: [re.sub(r"\(N=\d+\)", f"(N={B2_MIN - 1})", l) for l in L]),
           "is below the")
    expect("targets-short",
           lambda t: write(t, ur + "b2-targets.txt", lines_of(t, ur + "b2-targets.txt")[1:]),
           "names and the record says N=")

    def swap(t):
        L = lines_of(t, ur + "b2-targets.txt")
        L[0], L[1] = L[1], L[0]
        write(t, ur + "b2-targets.txt", L)

    expect("swap", swap, "not the keyed first-N derivation")
    expect("rekey",
           lambda t: write(t, ur + "b2-order-key.txt", ["0" * 40]),
           "not the keyed first-N derivation")
    expect("alias-columns",
           lambda t: append(t, ur + "b2-exclusion-aliases.tsv", "fx-tool\tfx-package"),
           "b2-exclusion-aliases.tsv row does not have 3 columns")
    expect("alias-twice",
           lambda t: append(t, ur + "b2-exclusion-aliases.tsv", first_data(t, ur + "b2-exclusion-aliases.tsv")),
           "b2-exclusion-aliases.tsv lists")
    expect("alias-dangling",
           lambda t: append(t, ur + "b2-exclusion-aliases.tsv", "fx-tool\tfx-package\tplanted by b2_selftest"),
           "does not carry")
    # Once per ledger read by a column past the first, not once for the loop: the
    # column number is data, and a proof on one ledger says nothing about the
    # others. A ledger read at column 0 cannot have a row too short for it — a
    # one-cell line still has a cell 0 — so that refusal is unreachable there and
    # the mutation would die on coverage instead; it is not planted.
    for rel, col in B2_LEDGERS:
        if not col:
            continue
        expect(f"ledger-row-short:{rel}",
               lambda t, rel=rel: append(t, rel, "planted-by-b2-selftest"),
               "fewer than the")
    expect("ledger-name-uncovered",
           lambda t: append(t, "spike/outcome-funnel.tsv",
                            "\t".join(["selftest", "fx-nowhere", "attempted", "unknown", "wall",
                                       "-", "spike/selftest", "-", "planted by b2_selftest"])),
           "is not covered")
    expect("file-missing",
           lambda t: (t / ur / "b2-targets.txt").unlink(),
           "is missing")
    if ran != 23:
        die(f"selftest: {ran} proofs ran, 23 expected")
    print(f"count.py b2-selection --selftest: {ran} ok (baseline green, 22 mutations red on their own predicate)")


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("emit", "check", "ledger-sizes", "b2-selection"):
        print(__doc__)
        sys.exit(2)
    if "--root" in sys.argv:
        root = Path(sys.argv[sys.argv.index("--root") + 1])
    else:
        root = Path(__file__).resolve().parents[2]
    if sys.argv[1] == "emit":
        sys.stdout.write(emit(root))
    elif sys.argv[1] == "ledger-sizes":
        ledger_sizes(root)
    elif sys.argv[1] == "b2-selection":
        if "--selftest" in sys.argv:
            b2_selftest(root)
        else:
            try:
                b2_selection(root)
            except B2Error as e:
                die(str(e))
    else:
        check(root)

if __name__ == "__main__":
    main()
