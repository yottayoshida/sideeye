#!/bin/sh
# Pick one target per semantic shape, mechanically, from pools committed beside this file (#618).
#
#   sh spike/authoring-cost/select-targets.sh            write selection.tsv
#   sh spike/authoring-cost/select-targets.sh --check    re-derive and compare, byte for byte
#
# What is mechanical here, and what is not — the distinction PROTOCOL.md refuses to blur:
#
#   * NOT mechanical: which pool a package belongs to. "This store is journaled" is a semantic
#     judgement about the target, made by us, before the runs. No package metadata this
#     repository can read answers it. That judgement is part of the authoring work the study
#     therefore does NOT measure, and the pools are committed so it can be argued with.
#   * Mechanical: the order within a pool, the exclusion, and which candidate is taken. The
#     order is sha256("<package>\t<key>") with the key in order-key.txt — the shape
#     spike/unknown-rate/select-b2.sh uses, so the alphabet does not decide.
#
# The exclusion is the predicate b2-author.sh already applies: a package is fresh when **no
# tracked file outside this selection names it** (word match). The ledgers are not enough —
# spike/unknown-rate/defines-b2/<pkg>/NOTES.md holds a written answer for thirty packages, and
# a subject who reached one would be copying rather than authoring.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
mode=${1:-write}

command -v sha256sum >/dev/null 2>&1 || { echo "select-targets: sha256sum not found" >&2; exit 2; }

basef="$here/base-commit.txt"
[ -f "$basef" ] || { echo "select-targets: $basef missing" >&2; exit 2; }
base=$(grep -v '^#' "$basef" | grep . | head -n 1)
[ -n "$base" ] || { echo "select-targets: $basef carries no commit" >&2; exit 2; }
git -C "$root" rev-parse --verify --quiet "$base^{commit}" >/dev/null ||
    { echo "select-targets: $base is not a commit in this repository" >&2; exit 2; }

keyf="$here/order-key.txt"
[ -f "$keyf" ] || { echo "select-targets: $keyf missing" >&2; exit 2; }
key=$(grep -v '^#' "$keyf" | grep . | head -n 1)
[ -n "$key" ] || { echo "select-targets: $keyf carries no key" >&2; exit 2; }

fresh() {
    # Word match over tracked files **at a fixed commit**, excluding this study's own directory.
    # Prints nothing when the package is fresh.
    #
    # The commit matters. Against the working tree this predicate eats itself: publishing the
    # study writes the four target names into CHANGELOG.md, and the next `--check` then excludes
    # its own selection (measured — `excluded dos2unix … named by CHANGELOG.md`, and the atomic
    # pool emptied). Reading `base-commit.txt` keeps the question the one that was actually
    # asked — what did the repository already say about this package when it was chosen — and
    # makes the selection re-derivable by anyone, forever.
    git -C "$root" grep -l -w -F "$1" "$base" -- . ':(exclude)spike/authoring-cost' 2>/dev/null || true
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

printf '# shape\tpackage\trank-hash\twhy-this-shape\n' > "$tmp"
for pool in "$here"/pool-*.txt; do
    shape=$(basename "$pool" .txt | sed 's/^pool-//')
    # Rank every candidate, then walk the ranked order until one survives the exclusion.
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in \#*) continue ;; esac
        pkg=$(printf '%s' "$line" | cut -f1)
        why=$(printf '%s' "$line" | cut -f2)
        h=$(printf '%s\t%s' "$pkg" "$key" | sha256sum | cut -c1-16)
        printf '%s\t%s\t%s\t%s\n' "$h" "$pkg" "$shape" "$why"
    done < "$pool" | LC_ALL=C sort | while IFS= read -r ranked; do
        h=$(printf '%s' "$ranked" | cut -f1)
        pkg=$(printf '%s' "$ranked" | cut -f2)
        shp=$(printf '%s' "$ranked" | cut -f3)
        why=$(printf '%s' "$ranked" | cut -f4-)
        hits=$(fresh "$pkg")
        if [ -z "$hits" ]; then
            printf '%s\t%s\t%s\t%s\n' "$shp" "$pkg" "$h" "$why" >> "$tmp"
            break
        fi
        printf 'excluded %s (%s): named by %s\n' "$pkg" "$shp" "$(printf '%s' "$hits" | tr '\n' ' ')" >&2
    done
    picked=$(grep -c "^$shape	" "$tmp" || true)
    [ "$picked" = "1" ] || { echo "select-targets: pool $shape yielded no fresh candidate" >&2; exit 1; }
done

rows=$(grep -cv '^#' "$tmp")
[ "$rows" -ge 1 ] || { echo "select-targets: selected nothing" >&2; exit 1; }
echo "selected $rows target(s) from $(ls "$here"/pool-*.txt | wc -l | tr -d ' ') pool(s), key ${key%%[!0-9a-f]*}" >&2

if [ "$mode" = "--check" ]; then
    if diff -u "$here/selection.tsv" "$tmp" >/dev/null 2>&1; then
        echo "ok   selection.tsv re-derives byte for byte from the pools and the key"
    else
        echo "FAIL: selection.tsv does not match what the pools and the key produce:"
        diff -u "$here/selection.tsv" "$tmp" || true
        exit 1
    fi
else
    cp "$tmp" "$here/selection.tsv"
    echo "wrote $here/selection.tsv"
fi
