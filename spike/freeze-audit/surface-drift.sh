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
#   rung 3  named residue      The clauses of the declaration that neither rung
#                              can see. Printed as unmeasured. They are held by
#                              review and by spike/acceptance.sh, and mapping each
#                              clause to the check that pins it is filed, not done.
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
note "== rung 3: NOT MEASURED by anything above (read, not measured) =="
note "  Each line is a clause of docs/contract-freeze.md that no extraction here"
note "  covers. These are held by review and by spike/acceptance.sh. Mapping each"
note "  clause to the check that pins it is filed as its own issue, not done here."
note "  surface 1  the string form's split-on-spaces and no-quoting rule; the argv"
note "             form's verbatim passing; relative path resolution against the"
note "             toml's directory. These live in src/main.zig, NOT src/config.zig,"
note "             so rung 1 settles them only when src/main.zig is also identical."
note "  surface 2  field presence rules, field types, and the meaning of every"
note "             machine field. A field keeping its name while changing meaning is"
note "             exactly what surface 2 forbids and exactly what rung 2 cannot see"
note "  surface 3  which call site returns which code. #273 moved this while the"
note "             enum stayed identical — the measured proof that rung 2 is not"
note "             a measurement of surface 3"
note "  surface 4  that an old case refuses with the mismatch named and returns no"
note "             verdict. NOTE: the acceptance leg for a v7 case asserts exit 2"
note "             and a message string; it does not assert the unknown_reason value"
note "             and does not assert the absence of a verdict line, though its own"
note "             success message says 'never a verdict'. Filed."
note "  surface 5  the two input schemas and the isError derivation rule"
note ""

if [ "$fails" -gt 0 ]; then
    note "FAIL: $fails extraction(s) could not be reported"
    exit 1
fi
note "ok   surface drift measured; rung 3 residue named above is not measured by this script"
