#!/bin/sh
# spike/check-evidence-bundle.sh — the evidence bundle says what the run measured (#607, ADR 0071).
#
# Usage: check-evidence-bundle.sh <sideeye> <shim> <scratch-dir> [<repo-root>]
#
# Three claims, in the order they were designed, each with its own reason for not passing by
# accident:
#
#   1. THE MATRIX. Seven fixtures, and the four impact fields — pre_existing,
#      old_bytes_elsewhere, declared_scratch, checker_failed — take different values across
#      them. Asserted as a table written here before the runs, so an implementation that
#      hard-codes any single answer fails at least two rows. The check refuses a matrix with
#      a constant column: a fixture set where every row agrees is a set that tests nothing,
#      and the first draft of this check had exactly that for declared_scratch.
#
#   2. CROSS-ARTIFACT AGREEMENT. Every bundle field that names a fact the case file or the
#      report also holds must equal it. This is the claim the promise actually needs: an
#      implementation that copied Sideeye's own rendered sentence into a measured field, or
#      guessed a number, disagrees with the artifact holding the same fact. (The first draft
#      asserted something weaker — that the bundle renders with no text report present —
#      which only rules out scraping the terminal, something no implementation would do.)
#
#   3. NO RANK. No severity word appears anywhere in a rendered bundle. The other half of
#      the promise, and the half a reader would notice first if it broke.
#
# Runs on macOS and in the Linux container: the operation is a compiled image (a `#!` script
# takes no insertion on macOS), the checkers are shell scripts, and only POSIX tools are used
# besides python3, which `spike/acceptance.sh` already requires.
#
# Seen red, measured rather than predicted (2026-09-17). Every line here is a mutation that
# was actually applied and re-run, and two of them corrected what this comment first claimed:
#   - `old_bytes_elsewhere` forced to `.no` in src/evidence.zig -> claim 1 red on
#     backup/README.md. ONE row, not two: the `empty` fixture's `unknown` comes from an
#     earlier branch the mutant never reaches. The first draft said two.
#   - the `.eq` arm of `unionRels` no longer advancing `j` -> "lists a path twice" on five of
#     the seven fixtures, and the unit test in src/evidence.zig red as well.
#   - the text-side defang removed from the consequence table's path -> the `evilname`
#     fixture's forged `## Forged` heading appears in the rendered document and the section
#     assertion names it. **This is the one that had to be fixed twice.** The fixture's first
#     name was `ev\nil\033[31m.md`: hostile bytes, but its newlines land mid-sentence, so
#     removing the defang left this check GREEN. A guard tested against the accident and not
#     against its own predicate. The name forges a section now.
#   - the fixture set itself: every pinned row had `pre_existing` True until backup's second
#     row was added, and the constant-column refusal below is what said so.
#
set -eu

SIDEEYE=${1:?usage: check-evidence-bundle.sh <sideeye> <shim> <scratch-dir> [<root>]}
SHIM=${2:?}
SCRATCH=${3:?}
ROOT=${4:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
# `cc` by name, the way spike/build-toys.sh uses `gcc`: the CI runner and the container both
# have it. Overridable because a developer's shell may have `cc` shadowed — one workspace this
# runs in aliases it to something else entirely, and `sh` not reading that alias is luck
# rather than a guarantee.
CC=${CC:-cc}

fails=0
bad() { echo "     $*"; fails=$((fails + 1)); }

mkdir -p "$SCRATCH"
TOY="$SCRATCH/toy_evidence"
$CC -O0 -g -o "$TOY" "$ROOT/spike/toys/toy_evidence.c"

# The checkers. Each rejects a state whose every file has been overwritten with junk — the
# falsification gate runs before any world and refuses a checker it has not seen fail — and
# each answers a different question about the crashed one.
mkchecker() { # name, body
    printf '#!/bin/sh\n%s\n' "$2" > "$SCRATCH/$1"
    chmod 755 "$SCRATCH/$1"
}
mkchecker check-title.sh   'grep -q Rewritten "$SIDEEYE_STATE_DIR/README.md" || grep -q Original "$SIDEEYE_STATE_DIR/README.md" || { echo "FAIL: README.md holds neither generation"; exit 1; }'
mkchecker check-data.sh    'grep -q Rewritten "$SIDEEYE_STATE_DIR/DATA.txt" || grep -q Original "$SIDEEYE_STATE_DIR/DATA.txt" || { echo "FAIL: DATA.txt holds neither generation"; exit 1; }'
mkchecker check-cache.sh   'grep -q Rewritten "$SIDEEYE_STATE_DIR/cache/data" || grep -q Original "$SIDEEYE_STATE_DIR/cache/data" || { echo "FAIL: cache/data holds neither generation"; exit 1; }'
# Reads a file the operation never touches, so it is falsifiable (the probe corrupts
# everything) and green in every crashed world. The row where the checker passes.
mkchecker check-marker.sh  'grep -q ok "$SIDEEYE_STATE_DIR/MARKER.txt" || { echo "FAIL: MARKER.txt lost its marker"; exit 1; }'
# The relation no single-file invariant can see. It asks for a known generation as well as
# for agreement: the falsification probe overwrites every file with the SAME junk, so an
# equality test alone accepts the corrupted state and the gate refuses the run before any
# world (measured, first run of this fixture).
mkchecker check-evil.sh    'for f in "$SIDEEYE_STATE_DIR"/*; do grep -q Rewritten "$f" || grep -q Original "$f" || { echo "FAIL: a file holds neither generation"; exit 1; }; done'
mkchecker check-pair.sh    'a=$(cat "$SIDEEYE_STATE_DIR/a.txt"); b=$(cat "$SIDEEYE_STATE_DIR/b.txt"); case "$a" in gen1|gen2) ;; *) echo "FAIL: a.txt holds no known generation"; exit 1 ;; esac; [ "$a" = "$b" ] || { echo "FAIL: a.txt is $a but b.txt is $b"; exit 1; }'

# One fixture: set up its state, explore it, and leave the bundle path in $BUNDLE.
# Each gets its own state and work directory, so nothing carries between them.
run_fixture() { # name, mode, checker, extra-args...
    name=$1 mode=$2 checker=$3
    shift 3
    st="$SCRATCH/$name/state"
    wk="$SCRATCH/$name/work"
    mkdir -p "$st" "$wk"
    case "$name" in
        truncate|backup|marker) printf 'Original\n' > "$st/README.md" ;;
        empty)   : > "$st/README.md"; printf 'Original\n' > "$st/DATA.txt" ;;
        scratch) mkdir -p "$st/cache"; printf 'Original\n' > "$st/cache/data" ;;
        twofile) printf 'gen1\n' > "$st/a.txt"; printf 'gen1\n' > "$st/b.txt" ;;
        # A name with newlines and an ESC in it, which a Unix file name may hold.
        evilname) printf 'Original\n' > "$st/$(printf 'ev\n## Forged\n\033[31m.md')" ;;
    esac
    [ "$name" = marker ] && printf 'ok\n' > "$st/MARKER.txt"
    EV_MODE=$mode "$SIDEEYE" explore --state "$st" --operation "$TOY" \
        --check "$SCRATCH/$checker" --shim "$SHIM" --work "$wk" \
        --json "$SCRATCH/$name.report.json" "$@" > "$SCRATCH/$name.txt" 2>&1 || true
    BUNDLE="$wk/evidence/000001.json"
    CASE="$wk/cases/000001.json"
}

# name        mode      checker            extra
run_fixture truncate  truncate  check-title.sh
run_fixture backup    backup    check-title.sh
run_fixture empty     empty     check-data.sh
run_fixture scratch   scratch   check-cache.sh  --scratch cache
run_fixture marker    truncate  check-marker.sh
run_fixture twofile   twofile   check-pair.sh
run_fixture evilname  evilname  check-evil.sh

for f in truncate backup empty scratch marker twofile evilname; do
    b="$SCRATCH/$f/work/evidence/000001.json"
    if [ ! -f "$b" ]; then
        bad "fixture $f wrote no bundle; its report says:"
        sed 's/^/       | /' "$SCRATCH/$f.txt" | head -6
    fi
done
[ "$fails" -eq 0 ] || { echo "FAIL evidence bundle: $fails"; exit 1; }

# Claims 1 and 2, and the constant-column refusal, in one pass over the artifacts.
python3 - "$SCRATCH" <<'PY' || fails=$((fails + 1))
import json, sys, pathlib

scratch = pathlib.Path(sys.argv[1])
problems = []

# Written before the runs. A fixture pins one or more rows by path; a bundle that lists other
# paths as well is fine, a bundle missing a pinned one is not.
#   fixture -> [(path, pre_existing, old_bytes_elsewhere, declared_scratch, checker_failed)]
MATRIX = {
    "truncate": [("README.md",  True,  "no",             False, True)],
    "backup":   [("README.md",  True,  "yes",            False, True),
                 # The copy the operation made: it did not exist before, so it has no old
                 # bytes and the question does not arise. `not_applicable` rather than
                 # `unknown` — the run knows the answer is "none", which is not the same as
                 # not knowing it. This row is also what splits pre_existing across the set.
                 ("README.bak", False, "not_applicable", False, True)],
    "empty":    [("README.md",  True,  "unknown",        False, True)],
    "scratch":  [("cache/data", True,  "no",             True,  True)],
    "marker":   [("README.md",  True,  "no",             False, False)],
    # Both files are written atomically, so the built-in layer is green in every world and
    # this FAIL is the checker's alone. b.txt still holds its own pre-operation bytes, and
    # nothing else does — the first prediction here said `yes`, which was wrong: a.txt has
    # already moved to the new generation at this crash point, and a path is never counted
    # as a copy of itself.
    "twofile":  [("b.txt",      True,  "no",             False, True)],
    # The bundle carries the name as the target spelled it — control bytes and all. The
    # neutralising happens on the way to the terminal, not on the way into the record, so
    # this row is also the assertion that the JSON side did not quietly rewrite it.
    "evilname": [("ev\n## Forged\n\x1b[31m.md", True, "no", False, True)],
}

seen = []
for name, rows_wanted in MATRIX.items():
    b = json.loads((scratch / name / "work" / "evidence" / "000001.json").read_text())
    rows = {r["path"]: r for r in b["consequence"]}
    if len(rows) != len(b["consequence"]):
        problems.append(f"{name}: the consequence table lists a path twice")
        continue
    for path, pre, elsewhere, scratch_flag, checker_failed in rows_wanted:
        r = rows.get(path)
        if r is None:
            problems.append(f"{name}: no row for {path}; rows are {sorted(rows)}")
            continue
        got = (r["pre_existing"], r["old_bytes_elsewhere"], r["declared_scratch"], b["checker"]["failed"])
        want = (pre, elsewhere, scratch_flag, checker_failed)
        if got != want:
            problems.append(f"{name}/{path}: measured {got}, expected {want}")
        seen.append(got)

# The fixture set's own property: no column may agree across every row. A set that does is a
# set of positive examples, and an implementation that answers that column with a constant
# passes it. This fired on the first run — every pinned row had pre_existing True until the
# backup fixture's second row was added — which is the check's own seen-red.
if len(seen) == sum(len(v) for v in MATRIX.values()):
    for i, col in enumerate(["pre_existing", "old_bytes_elsewhere", "declared_scratch", "checker_failed"]):
        values = {v[i] for v in seen}
        if len(values) < 2:
            problems.append(f"the fixture set does not split {col}: every row is {values.pop()!r}")

# Claim 2: every bundle field that names a fact another artifact holds must equal it.
for name in MATRIX:
    wk = scratch / name / "work"
    b = json.loads((wk / "evidence" / "000001.json").read_text())
    c = json.loads((wk / "cases" / "000001.json").read_text())
    rep = json.loads((scratch / f"{name}.report.json").read_text())
    for field, mine, theirs, whose in [
        ("crash_point",        b["crash_point"],            c["k"],                       "case"),
        ("crash_points_total", b["crash_points_total"],      c["ops_total"],               "case"),
        ("boundary.after_op",  b["boundary"]["after_op"],    c["after_class"],             "case"),
        ("boundary.after_path", b["boundary"]["after_path"], c["after_path"],              "case"),
        ("boundary.before_op", b["boundary"]["before_op"],   c["before_class"],            "case"),
        ("boundary.before_path", b["boundary"]["before_path"], c["before_path"],           "case"),
        ("target.state_root",  b["target"]["state_root"],    c["define"]["state"],         "case"),
        ("crash_point",        b["crash_point"],             rep["earliest"]["crash_point"], "report"),
        ("invariant",          b["invariant"],               rep["earliest"]["invariant"], "report"),
        ("subject",            b["subject"],                 rep["earliest"]["subject"],   "report"),
        ("observed",           b["observed"],                rep["earliest"]["observed"],  "report"),
        ("replay",             b["replay"],                  rep["replay"],                "report"),
        ("case",               b["case"],                    rep["case"],                  "report"),
    ]:
        if mine != theirs:
            problems.append(f"{name}: bundle {field} is {mine!r} but the {whose} says {theirs!r}")
    # The report must name this bundle, so a consumer never has to derive the name.
    if b["exhibit"] != "earliest":
        problems.append(f"{name}: exhibit is {b['exhibit']!r}; these fixtures all save the overall earliest")
    if rep.get("evidence") != str(wk / "evidence" / "000001.json"):
        problems.append(f"{name}: the report's evidence field is {rep.get('evidence')!r}")
    # #606's slot, held open from version 1.
    if b["recovery"]["result"] != "not_configured":
        problems.append(f"{name}: recovery is {b['recovery']['result']!r}, expected not_configured")

for p in problems:
    print(f"     {p}")
sys.exit(1 if problems else 0)
PY

# Claim 3, on the rendered document rather than on the JSON: the rank the bundle must not
# carry is a thing a reader sees, and rendering is where one would be introduced.
for f in truncate backup empty scratch marker twofile evilname; do
    md=$("$SIDEEYE" evidence "$SCRATCH/$f/work/cases/000001.json") || {
        bad "rendering $f's bundle failed"
        continue
    }
    lower=$(printf '%s' "$md" | tr '[:upper:]' '[:lower:]')
    for word in critical severe "high severity" "data-loss" "data loss"; do
        case "$lower" in
            *"$word"*) bad "$f's rendered bundle ranks what it found: it contains '$word'" ;;
        esac
    done
    # The document's sections are EXACTLY these, in this order — not "contains each of".
    #
    # Two things at once. It is the denominator the word ban above needs: a renderer that
    # printed nothing passes a ban and fails this. And it is the real assertion about hostile
    # input, which a word ban cannot make — a file name may hold newlines and an ESC, and
    # before the text-side defang was added a crafted one rendered its own `## Severity`
    # heading into the document (measured 2026-09-17). A name that forges a section changes
    # this list; a name that merely contains the word "critical" does not, and should not,
    # because that is the target's byte and not Sideeye ranking anything. The `evilname`
    # fixture is the one whose path actually carries those bytes.
    got=$(printf '%s\n' "$md" | grep '^## ' || true)
    want='## What happened
## Consequence
## Where it was interrupted
## Built-in invariant
## Checker
## Reproducing it
## Recovery
## What this measurement did and did not establish'
    if [ "$got" != "$want" ]; then
        bad "$f's rendered bundle does not carry exactly the eight sections; it has:"
        printf '%s\n' "$got" | sed 's/^/       | /'
    fi
done

# `--help` reaches the usage banner rather than the file reader. It is checked because the
# first fix for it did not work: the mode dispatch sits ahead of the `<mode> --help` block, so
# adding the mode to that block's list changed nothing and `--help` was still read as a path.
if out=$("$SIDEEYE" evidence --help 2>&1) && printf '%s' "$out" | head -1 | grep -q '^sideeye '; then
    :
else
    bad "sideeye evidence --help did not print the usage banner; it said: $(printf '%s' "$out" | head -1)"
fi

# Reading a case that has no bundle beside it is a refusal, not a guess, and not exit 2 —
# that is UNKNOWN, a verdict this command does not produce.
if "$SIDEEYE" evidence "$SCRATCH/nonexistent-case.json" > "$SCRATCH/norefuse.txt" 2>&1; then
    bad "sideeye evidence accepted a case with no bundle beside it"
else
    rc=$?
    [ "$rc" = 3 ] || bad "sideeye evidence refused with exit $rc, want 3"
fi

if [ "$fails" -eq 0 ]; then
    echo "ok   the evidence bundle's seven fixtures split every impact field, agree with the case and the report, forge no section from a file name, and rank nothing"
    exit 0
fi
echo "FAIL evidence bundle: $fails"
exit 1
