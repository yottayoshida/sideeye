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
#   D2  the define blobs are byte-identical at the two points: the question that
#       preceded the answer is the question that was asked, not a tuned variant.
#       `ops/explore.sh` (the launcher: environment, not question) is not required
#       to exist at the define point (D1), but when it exists at both points it is
#       held to D2 like the rest — a launcher swapped between question and answer
#       changes the environment the operation child inherits.
#   D3  every file the scan looked at is listed with its introducing commit, so the
#       reader audits the file set instead of trusting it.
#
# Like verify-seals.sh, all of it audits the *history as pushed*. Nothing here
# proves what happened on a private disk first; the anchor ref's public order is
# the witness. And honestly: this script postdates the first cohort — for those
# five targets a run of this script is a RECORD of what the history shows, not a
# certification that the rule was followed. The rule binds claims made after
# PROTOCOL.md's mini-seal section (2026-08-15).
#
# Rename tracking is deliberate (-M/--follow): the first hand-measurement of this
# repo's own history mistook a pure rename (report.json -> report-strict.json,
# R100) for a distinct introduction. The scan that missed it is the scan this
# script must not be.
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

# Resolve the target dir to a repo-relative path.
target=$target_arg
[ -d "$repo/$target" ] || target="spike/assisted/$target_arg"
[ -d "$repo/$target" ] || { echo "verify-assisted: no target directory at $target_arg" >&2; exit 2; }

# The anchor ref: main where it exists (the pushed line), HEAD otherwise (drills).
ref=main
git -C "$repo" rev-parse --verify -q main >/dev/null 2>&1 || ref=HEAD

fails=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

echo "verify-assisted: $target"
echo "anchor: $ref ($(git -C "$repo" rev-parse --short "$ref")) — first-parent order, history as pushed"
echo "disclosure: this script postdates the first cohort; on pre-rule targets this is a record, not a certification"

# First-parent order of the anchor: line number = position, 1 = newest.
order_file=$(mktemp "${TMPDIR:-/tmp}/va-order-XXXXXX") || exit 2
trap 'rm -f "$order_file"' EXIT
git -C "$repo" rev-list --first-parent "$ref" > "$order_file" || exit 2

# Position of the first-parent commit that introduced a path (rename-tracked).
# --follow needs one path at a time. Rename hops are honored only while they stay
# INSIDE the target directory: --follow matches by content similarity, and on the
# real history it linked a small report JSON to an unrelated pre-cohort JSON
# elsewhere in the repo, dating the artifact a day before the cohort existed
# (measured; the unconstrained version of this function did exactly that). A hop
# whose old name lies outside the target is read as "this commit brought the file
# into the target" — which is the introduction the ordering claim cares about.
# A copy record (C) is an introduction wherever its source lies: the source file
# keeps existing, so the new path came into being at the copying commit — and on
# the real history git records fresh cohort files as C-from-similar-JSON
# elsewhere in the repo (C071 from a blind-hunt report was measured), so a
# C-blind walker returns nothing and the file silently falls out of the anchor.
intro_commit() {
    git -C "$repo" log --first-parent -M --follow --diff-filter=ACR --format=%H --name-status "$ref" -- "$1" 2>/dev/null |
    awk -F'\t' -v path="$1" -v tgt="$target/" '
        $1 ~ /^[0-9a-f]{40}$/ { sha = $1; next }
        $1 ~ /^R/ {
            if ($3 == path) {
                if (index($2, tgt) == 1) { path = $2; next }
                print sha; exit
            }
            next
        }
        $1 ~ /^C/ { if ($3 == path) { print sha; exit } next }
        $1 == "A" && $2 == path { print sha; exit }
    '
}
pos_of() {
    grep -n "^$1\$" "$order_file" | cut -d: -f1
}

# ---- collect the define set -----------------------------------------------------
defines=""
for f in "$repo/$target/ops/"*.toml "$repo/$target/ops/check.sh" "$repo/$target/ops/setup.sh"; do
    [ -f "$f" ] && defines="$defines ${f#"$repo"/}"
done
[ -n "$defines" ] || { echo "verify-assisted: no define files under $target/ops/" >&2; exit 2; }
launcher=""
[ -f "$repo/$target/ops/explore.sh" ] && launcher="$target/ops/explore.sh"

# ---- collect the artifact set ---------------------------------------------------
artifacts=""
for f in "$repo/$target"/report*.json "$repo/$target"/*transcript*.txt; do
    [ -f "$f" ] && artifacts="$artifacts ${f#"$repo"/}"
done
for d in "$repo/$target"/cases*; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        [ -f "$f" ] && artifacts="$artifacts ${f#"$repo"/}"
    done
done
[ -n "$artifacts" ] || { echo "verify-assisted: no report/case/transcript artifacts under $target — nothing is being claimed" >&2; exit 2; }

# ---- D3 + the two anchor commits ------------------------------------------------
# A file whose introduction cannot be resolved must stop the run (exit 2), not
# quietly leave the anchor set: the first version dropped such a file and the
# narrowed set produced a FALSE GREEN D1 on real data (devtodo — the earliest
# artifact was the one that failed to resolve).
unresolved=0
def_commit="" def_pos=0 def_carrier=""
for p in $defines $launcher; do
    c=$(intro_commit "$p")
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
    c=$(intro_commit "$p")
    [ -n "$c" ] || { bad "D3: $p has no resolvable introduction on the first-parent line of $ref"; unresolved=$((unresolved + 1)); continue; }
    n=$(pos_of "$c")
    [ -n "$n" ] || { bad "D3: introducing commit of $p is off the first-parent line"; unresolved=$((unresolved + 1)); continue; }
    echo "artifact  $p  introduced @ $(git -C "$repo" rev-parse --short "$c") (position $n)"
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
if [ "$def_commit" = "$art_commit" ]; then
    bad "D1: define and first artifact were introduced by the same commit ($(git -C "$repo" rev-parse --short "$def_commit")) — the history cannot show the question preceding the answer"
elif [ "$def_pos" -lt "$art_pos" ]; then
    bad "D1: the first artifact ($art_carrier @ $(git -C "$repo" rev-parse --short "$art_commit")) precedes the define ($def_carrier @ $(git -C "$repo" rev-parse --short "$def_commit")) on the first-parent line"
else
    ok "D1: define complete @ $(git -C "$repo" rev-parse --short "$def_commit") strictly precedes first artifact @ $(git -C "$repo" rev-parse --short "$art_commit")"
fi

# ---- D2: define blobs identical at both points ----------------------------------
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

echo ""
if [ "$fails" -eq 0 ]; then
    echo "ALL ORDER CHECKS PASSED for $target"
    exit 0
fi
echo "$fails ORDER CHECK(S) FAILED for $target"
exit 1
