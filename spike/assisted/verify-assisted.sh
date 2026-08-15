#!/bin/sh
# verify-assisted.sh — machine-check that an assisted define precedes its answer
# (#130; the assisted funnel's counterpart to the campaigns' verify-seals.sh).
#
# What it checks, and what gives the check meaning:
#
#   D1  the commit that INTRODUCED the define (every file of it) precedes — and is
#       distinct from — the commit that introduced the first report/case/transcript
#       artifact, measured on the FIRST-PARENT line of the anchor ref. First-parent
#       order is the pushed history: a squash merge and a merge commit read the same
#       way, and locally splitting `git commit` cannot reorder it after the push.
#       (Commits that travel in ONE push are still ordered by this line, not by
#       push events — the rule buys ordering between pushes, not within one.)
#   D2  the define blobs are byte-identical at the two points: the question that
#       preceded the answer is the question that was asked, not a tuned variant.
#       `ops/explore.sh` (the launcher: environment, not question) is not required
#       to exist at the define point (D1), but when it exists at both points it is
#       held to D2 like the rest. When D1 already failed, D2 against the same or an
#       earlier commit would measure nothing and says so instead of printing ok.
#   D3  every file the scan looked at is listed with its introducing commit — and
#       the file SET comes from `git ls-tree` of the anchor ref, never from the
#       working tree: deleting a file from the tree without committing must not be
#       able to move an anchor (it could, in the first version; R1 measured a red
#       target turning green on an uncommitted `rm`).
#
# Introduction semantics (R1 hardened all three):
#   - The walker follows the file's history newest-first through rename hops in
#     BOTH directions and records an "existence event" every time the path came
#     into being UNDER THE TARGET: an add, a rename-in from outside, or a copy.
#     After a copy hop the chain continues into the source file, whose events lie
#     outside the target and stop counting on their own — which also defuses git's
#     similarity noise (a fresh cohort report was recorded as C071 of an unrelated
#     blind-hunt JSON; measured).
#   - A DEFINE anchors at its NEWEST existence event (a later re-introduction can
#     only make the claim harder — conservative).
#   - An ARTIFACT anchors at its OLDEST existence event: any answer that existed
#     before the define kills the claim, and taking the newest instead lets
#     delete-and-re-add or move-out-and-back launder the history (both measured
#     as false greens by R1).
#
# Like verify-seals.sh, all of it audits the *history as pushed*. Nothing here
# proves what happened on a private disk first; the anchor ref's public order is
# the witness. And honestly: this script postdates the first cohort — for those
# five targets a run of this script is a RECORD of what the history shows, not a
# certification that the rule was followed. The rule binds claims made after
# PROTOCOL.md's mini-seal section (2026-08-15).
#
# Usage: verify-assisted.sh [-C <repo>] <target-dir>
#   <target-dir> is a path like spike/assisted/buku (or just "buku").
# Exit: 0 all checks pass / 1 a check failed / 2 cannot determine.
set -u

repo=""
if [ "${1:-}" = "-C" ]; then
    repo=${2:?verify-assisted: -C needs a path}
    shift 2
fi
target_arg=${1:?usage: verify-assisted.sh [-C repo] <target-dir>}

if [ -z "$repo" ]; then
    repo=$(cd "$(dirname "$0")/../.." && pwd)
fi
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "verify-assisted: $repo is not a git repository" >&2; exit 2; }

# The anchor ref: main where it exists (the pushed line), HEAD otherwise (drills).
ref=main
git -C "$repo" rev-parse --verify -q main >/dev/null 2>&1 || ref=HEAD

# Resolve the target dir to a repo-relative path — against the ANCHOR TREE, not
# the filesystem.
target=$target_arg
if ! git -C "$repo" rev-parse -q --verify "$ref:$target" >/dev/null 2>&1; then
    target="spike/assisted/$target_arg"
fi
git -C "$repo" rev-parse -q --verify "$ref:$target" >/dev/null 2>&1 || { echo "verify-assisted: no target directory at $target_arg in $ref" >&2; exit 2; }

fails=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

echo "verify-assisted: $target"
echo "anchor: $ref ($(git -C "$repo" rev-parse --short "$ref")) — first-parent order, history as pushed"
echo "disclosure: this script postdates the first cohort; on pre-rule targets this is a record, not a certification"
if [ -n "$(git -C "$repo" status --porcelain -- "$target" 2>/dev/null)" ]; then
    echo "note: the working tree differs from $ref under $target — ignored; every anchor below is read from the committed history"
fi

# First-parent order of the anchor: line number = position, 1 = newest.
order_file=$(mktemp "${TMPDIR:-/tmp}/va-order-XXXXXX") || exit 2
trap 'rm -f "$order_file"' EXIT
git -C "$repo" rev-list --first-parent "$ref" > "$order_file" || exit 2

# Introduction of a path on the first-parent line (mode: define|artifact).
# See the header for the event semantics and why the two modes differ.
intro_commit() {
    git -C "$repo" log --first-parent -M --follow --diff-filter=ACR --format=%H --name-status "$ref" -- "$1" 2>/dev/null |
    awk -F'\t' -v path="$1" -v tgt="$target/" -v mode="$2" '
        function under(p) { return index(p, tgt) == 1 }
        function event()  { last = sha; if (mode == "define") { print sha; found = 1; exit } }
        $1 ~ /^[0-9a-f]{40}$/ { sha = $1; next }
        $1 ~ /^R/ {
            if ($3 == path) {
                if (!under($2) && under($3)) event()
                path = $2
            }
            next
        }
        $1 ~ /^C/ {
            if ($3 == path) {
                if (under($3)) event()
                path = $2
            }
            next
        }
        $1 == "A" && $2 == path { if (under($2)) event(); next }
        END { if (!found && last != "") print last }
    '
}
pos_of() {
    grep -n "^$1\$" "$order_file" | cut -d: -f1
}

# ---- collect the file sets from the ANCHOR TREE ---------------------------------
tree_file=$(mktemp "${TMPDIR:-/tmp}/va-tree-XXXXXX") || exit 2
trap 'rm -f "$order_file" "$tree_file"' EXIT
git -C "$repo" ls-tree -r --name-only "$ref" -- "$target/" > "$tree_file" || exit 2

defines=""
launcher=""
artifacts=""
while IFS= read -r p; do
    rel=${p#"$target"/}
    case "$rel" in
        ops/*.toml|ops/check.sh|ops/setup.sh) defines="$defines $p" ;;
        ops/explore.sh) launcher=$p ;;
        ops/*) ;;
        *) # artifacts match at ANY depth below the target (R1: the answer can sit
           # one directory down — inspection/, evidence/ — and a top-level-only
           # glob never sees it).
           base=${rel##*/}
           case "$base" in
               report*.json|*transcript*.txt) artifacts="$artifacts $p" ;;
               *) case "/$rel" in */cases*/*) artifacts="$artifacts $p" ;; esac ;;
           esac ;;
    esac
done < "$tree_file"
[ -n "$defines" ] || { echo "verify-assisted: no define files under $target/ops/ in $ref" >&2; exit 2; }
[ -n "$artifacts" ] || { echo "verify-assisted: no report/case/transcript artifacts under $target in $ref — nothing is being claimed" >&2; exit 2; }

# ---- D3 + the two anchor commits ------------------------------------------------
# A file whose introduction cannot be resolved must stop the run (exit 2), not
# quietly leave the anchor set: a narrowed set produced a FALSE GREEN D1 on real
# data before this guard existed.
unresolved=0
def_commit="" def_pos=0 def_carrier=""
for p in $defines $launcher; do
    c=$(intro_commit "$p" define)
    [ -n "$c" ] || { bad "D3: $p has no resolvable introduction on the first-parent line of $ref"; unresolved=$((unresolved + 1)); continue; }
    n=$(pos_of "$c")
    [ -n "$n" ] || { bad "D3: introducing commit of $p is off the first-parent line"; unresolved=$((unresolved + 1)); continue; }
    echo "define    $p  introduced @ $(git -C "$repo" rev-parse --short "$c") (position $n)"
    # The define is not complete until its LATEST part exists (smallest position).
    # The launcher is listed but does not move the define point (D1 exempts it).
    case " $defines " in *" $p "*)
        if [ "$def_pos" -eq 0 ] || [ "$n" -lt "$def_pos" ]; then def_pos=$n; def_commit=$c; def_carrier=$p; fi ;;
    esac
done
art_commit="" art_pos=0 art_carrier=""
for p in $artifacts; do
    c=$(intro_commit "$p" artifact)
    [ -n "$c" ] || { bad "D3: $p has no resolvable introduction on the first-parent line of $ref"; unresolved=$((unresolved + 1)); continue; }
    n=$(pos_of "$c")
    [ -n "$n" ] || { bad "D3: introducing commit of $p is off the first-parent line"; unresolved=$((unresolved + 1)); continue; }
    merge_note=""
    [ "$(git -C "$repo" rev-list --no-walk --count --merges "$c")" = "1" ] && merge_note=" (entered via a merge commit; side-branch author dates precede it)"
    echo "artifact  $p  introduced @ $(git -C "$repo" rev-parse --short "$c") (position $n)$merge_note"
    # The FIRST artifact is the earliest introduction (largest position).
    if [ "$n" -gt "$art_pos" ]; then art_pos=$n; art_commit=$c; art_carrier=$p; fi
done
if [ "$unresolved" -gt 0 ]; then
    echo "verify-assisted: cannot determine the order — $unresolved file(s) have no resolvable introduction; a narrowed anchor set is not an answer" >&2
    exit 2
fi
[ -n "$def_commit" ] && [ -n "$art_commit" ] || { echo "verify-assisted: could not anchor both sides" >&2; exit 2; }

# ---- D1: the define precedes the first artifact, strictly -----------------------
# rev-list is newest-first: line 1 is the newest commit, so OLDER means a LARGER
# position. "The define precedes the artifact" is def_pos > art_pos — the define's
# newest part is still older than the artifact's oldest part. (The first version
# had this comparison inverted; drill 1 caught it.)
d1_ok=0
if [ "$def_commit" = "$art_commit" ]; then
    bad "D1: define and first artifact were introduced by the same commit ($(git -C "$repo" rev-parse --short "$def_commit")) — the history cannot show the question preceding the answer"
elif [ "$def_pos" -lt "$art_pos" ]; then
    bad "D1: the first artifact ($art_carrier @ $(git -C "$repo" rev-parse --short "$art_commit")) precedes the define ($def_carrier @ $(git -C "$repo" rev-parse --short "$def_commit")) on the first-parent line"
else
    ok "D1: define complete @ $(git -C "$repo" rev-parse --short "$def_commit") strictly precedes first artifact @ $(git -C "$repo" rev-parse --short "$art_commit")"
    d1_ok=1
fi

# ---- D2: define blobs identical at both points ----------------------------------
# Meaningful only when the define point precedes the artifact point: against the
# same commit the comparison is vacuously true (the committed first-cohort
# transcript printed 20 such "ok" lines before R1 caught it), and against an
# earlier artifact commit the define did not exist yet.
if [ "$d1_ok" -eq 0 ]; then
    echo "D2: not evaluated — D1 failed, so there is no question-then-answer interval to hold the define constant over"
else
    d2_set="$defines"
    if [ -n "$launcher" ]; then
        if git -C "$repo" rev-parse -q --verify "$def_commit:$launcher" >/dev/null 2>&1; then
            d2_set="$d2_set $launcher"
        else
            echo "note: $launcher did not exist at the define point — the launcher environment is not pinned by this history"
        fi
    fi
    for p in $d2_set; do
        a=$(git -C "$repo" rev-parse -q --verify "$def_commit:$p" 2>/dev/null)
        b=$(git -C "$repo" rev-parse -q --verify "$art_commit:$p" 2>/dev/null)
        if [ -z "$a" ] || [ -z "$b" ]; then
            bad "D2: $p is missing at one of the two points (moved or deleted between question and answer)"
        elif [ "$a" != "$b" ]; then
            bad "D2: $p differs between the define commit and the first artifact commit — the question that preceded the answer is not the question that was asked"
        else
            ok "D2: $p byte-identical at both points"
        fi
    done
fi

echo ""
if [ "$fails" -eq 0 ]; then
    echo "ALL ORDER CHECKS PASSED for $target"
    exit 0
fi
echo "$fails ORDER CHECK(S) FAILED for $target"
exit 1
