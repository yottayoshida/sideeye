#!/bin/sh
# Measures what moved on the five frozen surfaces between two revisions, and says
# which parts of that question it cannot answer (ADR 0028).
#
#   sh spike/freeze-audit/surface-drift.sh                 # snapshot commit -> HEAD
#   sh spike/freeze-audit/surface-drift.sh <base> <head>
#
# WHY THIS EXISTS. Until this sweep the audit decided "does this issue touch a
# frozen surface" by reading the issue. #324 is the counterexample: its body never
# says `unknown_reason` and never says "closed set", and its resolution added
# `trace_too_large` to that set. What moved the surface was the resolution, not the
# issue text, so no reading recovers it. The surfaces are code artifacts; code can
# be diffed.
#
# WHAT IT CAN AND CANNOT SUPPORT — three rungs, reported separately on purpose.
# The first version of this measurement called rung 2 "diffing the five surfaces"
# and an adversarial review rejected the plan for it. The refutation is in this
# window: #273 moved the exit-code surface (a `--help` that exited 3 now exits 0,
# and the declaration was rewritten to legalise it) while the `ExitCode` enum
# stayed byte-identical. An enumerated diff reports "unmoved" about that.
#
#   rung 1  blob identity      If EVERY file a surface is defined by is byte-identical
#                              across the window, the surface did not move —
#                              enumerated names AND behavioural clauses, because
#                              the behaviour lives in that file too. This is the
#                              only rung that settles a surface outright.
#   rung 2  enumerated diff    For files that changed: the named sets, with each
#                              extraction defined below. Answers "which names
#                              appeared or disappeared", nothing else.
#   rung 3  per-clause residue  The clauses of the declaration that neither rung
#                              can see, read from clause-checks.tsv. Printed:
#                              only the ones nothing asserts, plus the leftover
#                              half of the ones a check covers in part. A clause
#                              held in full is not printed, so the list shrinks
#                              as checks are written and an empty list retires
#                              this rung (#369).
#
# FOUR RULES THIS SCRIPT FOLLOWS BECAUSE THE INSTRUMENTS LIED DURING ITS WRITING,
# every one of them in the direction of "everything changed":
#
#   1. Brace the revision. `"$REV:path"` under zsh drops the path — `:s` is a
#      history modifier — and `git show` then prints the COMMIT'S DIFF, in which
#      every line of the file carries a `+`. The first closed-set measurement read
#      "29 members added" that way. Always `"${REV}:path"`, and read blobs with
#      `git cat-file -p`, which has no diff mode to fall back into.
#   2. Assert the base extraction is non-empty before reporting any difference.
#      A diff against an empty set is indistinguishable from a total rewrite. This
#      is the check that would have caught rule 1's failure on its own.
#   3. Use `-G`, never `-S`, to find value edits. `-S` counts occurrences, so
#      changing a constant's value on a line whose text is otherwise unchanged is
#      invisible: `git log -S 'contract_version: u32'` returned zero commits for a
#      window in which that constant moved twice.
#   4. Normalise before counting prose. A grep for a declaration clause reported it
#      deleted when it had only re-wrapped across a line break.
#
# ATTRIBUTION IS NOT MEASURED HERE. `-G` answers "which commits contain a diff
# matching this regex", never "which issue required this line". Commit subjects
# carry issue and PR numbers in a convention that is not uniform, so parsing them is
# not a rule: of the nine commits this sweep attributes changes to, three carry no
# trailing parenthetical, and among the rest it is sometimes the pull request and
# sometimes the issue itself. The candidate commits this script prints are the input
# to a human attribution recorded per change in surface-changes.tsv with its
# evidence.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT" || exit 1

# The window's base is the commit that installed the snapshot being replaced: the
# snapshot and the declaration it was read against are one trust root, and this
# script's whole purpose is to say what moved since then.
BASE=${1:-8feae88}
HEAD_REV=${2:-HEAD}

base_sha=$(git rev-parse --short "$BASE" 2>/dev/null) || { echo "FAIL: cannot resolve base '$BASE'" >&2; exit 1; }
head_sha=$(git rev-parse --short "$HEAD_REV" 2>/dev/null) || { echo "FAIL: cannot resolve head '$HEAD_REV'" >&2; exit 1; }

fails=0
note() { printf '%s\n' "$*"; }

blob() {  # blob <rev> <path> ; prints the blob, never a diff
    git cat-file -p "${1}:${2}" 2>/dev/null
}

exists() {
    git cat-file -e "${1}:${2}" 2>/dev/null
}

note "surface drift: ${base_sha} -> ${head_sha}"
note "  base names the commit that installed the snapshot being replaced."
note ""

# ---------------------------------------------------------------------------
# rung 1 — blob identity
# ---------------------------------------------------------------------------
note "== rung 1: blob identity (the only rung that settles a surface outright) =="
identical_paths=""
changed_paths=""
for p in src/config.zig src/main.zig src/contract.zig src/mcp.zig docs/report-schema.md docs/contract-freeze.md; do
    if ! exists "$BASE" "$p" || ! exists "$HEAD_REV" "$p"; then
        note "  FAIL  $p: absent at one end of the window"
        fails=$((fails + 1))
        continue
    fi
    b=$(git rev-parse "${BASE}:${p}")
    h=$(git rev-parse "${HEAD_REV}:${p}")
    if [ "$b" = "$h" ]; then
        note "  IDENTICAL  $p"
        identical_paths="$identical_paths $p"
    else
        note "  CHANGED    $p  ($(printf '%s' "$b" | cut -c1-7) -> $(printf '%s' "$h" | cut -c1-7))"
        changed_paths="$changed_paths $p"
    fi
done
note ""
# Surface 1 needs BOTH files identical before rung 1 can settle it, and the first
# version of this script claimed it on src/config.zig alone. The parse and the
# accepted key set live there, but the command spellings split-on-spaces rule
# (`splitArgs`) and relative-path resolution against the toml directory
# (`resolvePathAgainst`, ADR 0007) live in src/main.zig — so config.zig being
# identical says nothing about them (review P1-2, and src/main.zig DID change in
# this window).
case " $identical_paths " in
    *" src/config.zig "*)
        case " $identical_paths " in
            *" src/main.zig "*)
                note "  surface 1 (config format): SETTLED UNMOVED by rung 1."
                note "    Both files that carry it are byte-identical: src/config.zig (the accepted"
                note "    key set, the parse, the named line-numbered refusals) and src/main.zig"
                note "    (both command spellings and the split-on-spaces rule, relative-path"
                note "    resolution against the toml directory)."
                ;;
            *)
                note "  surface 1 (config format): PARTLY settled by rung 1, and NOT settled overall."
                note "    src/config.zig is byte-identical, so the accepted key set and the parse did"
                note "    not move. But src/main.zig CHANGED, and it carries the rest of surface 1:"
                note "    splitArgs (the string form's split-on-spaces rule), the argv form's verbatim"
                note "    passing, and resolvePathAgainst (relative paths against the toml's"
                note "    directory, ADR 0007). Those clauses are rung-3 residue for this window."
                ;;
        esac
        ;;
    *)  note "  surface 1 (config format): src/config.zig changed; see rung 2 and rung 3." ;;
esac
note ""

# ---------------------------------------------------------------------------
# rung 2 — enumerated diffs, each extraction defined here
# ---------------------------------------------------------------------------
note "== rung 2: enumerated diffs (which names appeared or disappeared) =="

# set_diff <label> <path> <extractor-name>
# Refuses to report a difference when the base side extracts to nothing: a diff
# against an empty set looks exactly like a total rewrite (rule 2).
set_diff() {
    label=$1; path=$2; setname=$3
    tb="$tmp/base"; th="$tmp/head"
    blob "$BASE" "$path"     | extract_surface_set "$setname" > "$tb"
    blob "$HEAD_REV" "$path" | extract_surface_set "$setname" > "$th"
    nb=$(grep -c . "$tb" || true); nh=$(grep -c . "$th" || true)
    if [ "$nb" = "0" ]; then
        note "  FAIL  $label: the base extraction is EMPTY — refusing to report a diff"
        note "        (an extractor that matches nothing at the base reports every name as new)"
        fails=$((fails + 1))
        return
    fi
    added=$(comm -13 "$tb" "$th" | tr '\n' ' ')
    removed=$(comm -23 "$tb" "$th" | tr '\n' ' ')
    if [ -z "$added" ] && [ -z "$removed" ]; then
        note "  $label: $nb -> $nh, unmoved"
    else
        note "  $label: $nb -> $nh"
        [ -n "$added" ]   && note "      added:   $added"
        [ -n "$removed" ] && note "      removed: $removed"
    fi
}

# The enumerated-set definitions live in one place, shared with
# check-freeze-audit.sh, so the report and the gate cannot disagree about what a
# surface is. A /simplify pass found the two copies before they drifted.
. "$ROOT/spike/freeze-audit/surface-sets.sh"

tmp=$(mktemp -d) || { echo "FAIL: cannot create a temp directory" >&2; exit 1; }
cleanup_tmp() { rm -f "$tmp"/* 2>/dev/null; rmdir "$tmp" 2>/dev/null; }
trap cleanup_tmp EXIT HUP INT TERM

set_diff "surface 1  config accepted keys   " src/config.zig          config_keys
set_diff "surface 2  unknown_reason closed set" src/contract.zig      unknown_reason
set_diff "surface 2  report schema fields    " docs/report-schema.md  schema_fields
set_diff "surface 3  exit codes (name=value) " src/contract.zig       exit_codes
set_diff "surface 4  contract_version        " src/contract.zig       contract_version
set_diff "surface 5  MCP tool names          " src/mcp.zig            mcp_tools
note ""

# ---------------------------------------------------------------------------
# candidate commits for attribution (input to a human judgement, not a verdict)
# ---------------------------------------------------------------------------
note "== candidate commits for each moved item =="
note "  These are candidates. The issue an item is attributed to is recorded in"
note "  surface-changes.tsv with its evidence; neither -S nor -G answers causation."
note "  -S is right for a NAME appearing (the occurrence count changes with it) and"
note "  wrong for a VALUE edit on a line whose text is otherwise unchanged, which is"
note "  rule 3 above: the two contract_version bumps below are invisible to -S."
for item in $(blob "$HEAD_REV" src/contract.zig | extract_surface_set unknown_reason > "$tmp/h2"; \
              blob "$BASE" src/contract.zig | extract_surface_set unknown_reason > "$tmp/b2"; \
              comm -13 "$tmp/b2" "$tmp/h2"); do
    c=$(git log --format='%h' --reverse -S "$item" "${BASE}..${HEAD_REV}" -- src/contract.zig | head -1)
    note "  unknown_reason/$item: ${c:-(none found)}"
done
note "  contract_version (value edit — -S returns nothing here):"
git log --oneline --reverse -G 'contract_version: u32 = ' "${BASE}..${HEAD_REV}" -- src/contract.zig \
    | sed 's/^/      /'
note ""

# ---------------------------------------------------------------------------
# the declaration itself moved — measure that too
# ---------------------------------------------------------------------------
note "== the yardstick: revisions of docs/contract-freeze.md inside the window =="
note "  The declaration every reading is taken 'strictly against' is not a fixed"
note "  yardstick. A sweep must pin the revision it read."
git log --oneline --reverse "${BASE}..${HEAD_REV}" -- docs/contract-freeze.md | sed 's/^/  /'
decl_base=$(git rev-parse --short "${BASE}:docs/contract-freeze.md")
decl_head=$(git rev-parse --short "${HEAD_REV}:docs/contract-freeze.md")
note "  declaration blob: ${decl_base} -> ${decl_head}"
note ""

# ---------------------------------------------------------------------------
# rung 3 — what neither rung above can see
# ---------------------------------------------------------------------------
note "== rung 3: what no extraction above covers, per clause =="
note "  Read from spike/freeze-audit/clause-checks.tsv. Printed here are the clauses"
note "  nothing asserts, and the part left over where something asserts only some of"
note "  it. A clause held by a check in full is NOT printed — that is the point of"
note "  the file: this list shrinks as checks are written, and an empty list is the"
note "  condition under which ADR 0028's third rung can be retired (#369)."
note ""

clause_file="$ROOT/spike/freeze-audit/clause-checks.tsv"
if [ ! -f "$clause_file" ]; then
    note "FAIL: $clause_file is missing — rung 3 has nothing to read"
    fails=$((fails + 1))
else
    # Two counts from two expressions, as elsewhere in this audit: the row count
    # comes from the file, the walked count from the loop. A narrowing applied to
    # one cannot reach the other, so a partial read shows up as a mismatch rather
    # than as a shorter clean list.
    rows=$(grep -cv '^#\|^clause_id\|^$' "$clause_file" || true)
    walked=0
    anchor_gone=0
    bad_row=0
    unpinned_n=0
    partial_n=0
    while IFS="$(printf '\t')" read -r cid csurface cclause cheld cby cgap; do
        case "$cid" in \#*|clause_id|"") continue ;; esac
        walked=$((walked + 1))

        # The anchor is checked for existence, not for meaning. That a heading is
        # still in its suite is machine-knowable; that the check under it pins the
        # clause is a reading, and stays one. Without this, a heading that was
        # renamed or deleted leaves a row quietly claiming a check that is gone —
        # the failure mode of naming a check at all instead of saying "held by
        # review", which is what this file replaced.
        if [ "$cby" != "-" ]; then
            _suite=${cby%%::*}
            _head=${cby#*::}
            if [ ! -f "$ROOT/$_suite" ]; then
                note "  ANCHOR GONE  $cid names $_suite, which does not exist"
                anchor_gone=$((anchor_gone + 1))
            elif ! grep -qF -- "$_head" "$ROOT/$_suite"; then
                note "  ANCHOR GONE  $cid names a heading no longer in $_suite:"
                note "               $_head"
                anchor_gone=$((anchor_gone + 1))
            fi
        fi

        # A held value this loop does not recognise, or a row claiming a check
        # without naming one, must fail rather than fall through. Without these
        # two the `case` below is fail-OPEN: `Unpinned` with a capital letter, or
        # `pinned` with `by` set to `-`, drops the row from the residue and skips
        # the anchor test, turning "nobody holds this" into "a check holds this"
        # with no output at all. Measured in review, one token per mutation.
        # One row can trip both tests at once (`Unpinned` is an unrecognised value AND
        # compares unequal to `unpinned`, so a row with by=- also reads as a held row
        # naming no check). The counter is per ROW because the summary line says
        # "row(s)": counting findings there made one typo report as two rows.
        _row_bad=0
        case "$cheld" in
            pinned|partial|unpinned) ;;
            *)
                note "  BAD held  $cid has held=\"$cheld\", which is not pinned/partial/unpinned"
                _row_bad=1
                ;;
        esac
        if [ "$cheld" != "unpinned" ] && [ "$cby" = "-" ]; then
            note "  BAD by    $cid is $cheld but names no check"
            _row_bad=1
        fi
        [ "$_row_bad" = "1" ] && bad_row=$((bad_row + 1))

        case "$cheld" in
            unpinned)
                unpinned_n=$((unpinned_n + 1))
                note "  surface $csurface  $cid — nothing asserts this"
                note "             \"$cclause\""
                ;;
            partial)
                partial_n=$((partial_n + 1))
                note "  surface $csurface  $cid — asserted in part"
                note "             \"$cclause\""
                note "             left over: $cgap"
                ;;
        esac
    done < "$clause_file"

    note ""
    if [ "$walked" != "$rows" ]; then
        note "FAIL: read $walked clause row(s) but the file holds $rows — the read is partial"
        fails=$((fails + 1))
    fi
    # Two counters, not one. They were one, and the summary named only the anchor
    # case, so a `held` typo was reported as "a check heading is no longer there" —
    # a diagnostic pointing at acceptance.sh when the defect is in this manifest.
    if [ "$anchor_gone" -gt 0 ]; then
        note "FAIL: $anchor_gone row(s) name a check heading that is no longer there"
        fails=$((fails + 1))
    fi
    if [ "$bad_row" -gt 0 ]; then
        note "FAIL: $bad_row malformed row(s) in spike/freeze-audit/clause-checks.tsv — held is not pinned/partial/unpinned, or a held row names no check"
        fails=$((fails + 1))
    fi
    # The retire line is the strongest claim this script makes: it says a whole rung
    # of ADR 0028 can be deleted. A malformed row increments neither residue counter,
    # so on a failing run "the residue is empty" would mean "the loop could not
    # classify these rows", which is the opposite of what the sentence says. Every
    # failure above suppresses it.
    if [ "$unpinned_n" = "0" ] && [ "$partial_n" = "0" ] \
        && [ "$anchor_gone" = "0" ] && [ "$bad_row" = "0" ] && [ "$walked" = "$rows" ]; then
        note "  residue is empty: every clause is pinned by a check."
        note "  ADR 0028's third rung has nothing left to report and can be retired (#369)."
    else
        note "  $walked clause(s) total: $unpinned_n unpinned, $partial_n partial."
        # From 0, not 1: the preamble carries a clause that spans the five surfaces,
        # and a loop starting at 1 drops it from the tally while the rows above still
        # print it — a per-surface count that does not sum to the total.
        note "  Per surface (all rows, not just the residue): $(awk -F'\t' '!/^#/ && $1!="clause_id" && NF>=4{c[$2]++; t++} END{for(i=0;i<=5;i++) if(c[i]) printf "s%d=%d ", i, c[i]; printf "(sums to %d)", t}' "$clause_file")"
        note "  Completeness of the enumeration is NOT machine-checked — a clause is one"
        note "  independently checkable assertion, which matches no boundary in the"
        note "  declaration. The clause column is verbatim, so no row can describe text"
        note "  that is not there; the reverse direction is held by review."
    fi
fi
note ""

if [ "$fails" -gt 0 ]; then
    note "FAIL: $fails extraction(s) could not be reported"
    exit 1
fi
note "ok   surface drift measured; rung 3's residue is read from clause-checks.tsv, and what it leaves unpinned is named above"
