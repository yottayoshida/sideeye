#!/bin/sh
# The seal of the authoring-cost study (#618, ADR 0077), checked on every push.
#
# What a seal has to survive is not "was it written first" but "can it be shown, later, that
# run N was graded by the answer key that existed when it ran". A list of hashes cannot show
# that: after a run, an inconvenient card can be edited and a new row appended, and a checker
# that only recomputes the current hash stays green. So three things are required together:
#
#   1. the manifest recomputed from the live files equals the LAST row of ledger.md;
#   2. every hash in that ledger has its pre-image under manifests/<hash>/ — the files as they
#      were, not a promise that they existed;
#   3. every published run names a hash the ledger holds.
#
# ledger.md is append-only **by the tool that writes it**: spike/ledger-append.sh proves each
# addition still extends HEAD's copy, and the campaign ledgers were broken by hand twice before
# that tool existed. **This script does not re-prove it**, and an earlier version of this
# comment claimed it did. What is left open, stated rather than implied: a row and its
# pre-image can be removed together and re-sealed, and a run's `meta.json` names its manifest
# by self-report. The seal makes those edits visible in the history rather than impossible —
# it is discipline with a mechanical floor, not a proof.
#
# It prints what it scanned. A check that walks nothing must not be able to pass: the same hole
# spike/check-sealed-campaigns.sh closes by refusing when it finds no campaign at all.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

# --selftest: prove the seal can FAIL, on a copy, without touching the tree.
#
# The negative test used to live in the CI job, where it edited a tracked file and put it back.
# Nobody could run it before pushing, and a restore that did not happen would have left an
# edited answer key behind. `audit.py --selftest` is the shape this repository already uses.
if [ "${1:-}" = "--selftest" ]; then
    tmp=$(mktemp -d) || exit 2
    # No deletion anywhere in here. The first version made its negative cases by removing files,
    # and the developer sandbox this repository is written in blocks recursive deletes: the
    # removal silently did not happen, the seal passed, and the selftest reported that the SEAL
    # was broken. A test that cannot tell "the setup failed" from "the thing under test failed"
    # is worse than no test. Every case below is made by adding.
    trap 'rm -rf "$tmp" 2>/dev/null || true' EXIT
    cp -R "$here/." "$tmp/copy" || exit 2
    sh "$tmp/copy/check-sealed.sh" >/dev/null 2>&1 ||
        { echo "FAIL selftest: an untouched copy of the seal does not pass"; exit 1; }
    printf '\n an edit that no ledger row accounts for\n' >> "$tmp/copy/grade-rubric.md"
    if out=$(sh "$tmp/copy/check-sealed.sh" 2>&1); then
        echo "FAIL selftest: an edited answer key passed the seal"
        exit 1
    fi
    printf '%s\n' "$out" | grep -q 'a sealed file changed without an amendment row' ||
        { echo "FAIL selftest: the refusal does not name what happened: $out"; exit 1; }
    # And the other half: a ledger row whose pre-image was never written must not pass. Made by
    # appending a row rather than by removing a directory, for the reason above.
    cp -R "$here/." "$tmp/copy2" || exit 2
    printf '%s\t2026-01-01\ta row whose pre-image nobody wrote\n' \
        "0000000000000000000000000000000000000000000000000000000000000000" >> "$tmp/copy2/ledger.md"
    if out2=$(sh "$tmp/copy2/check-sealed.sh" 2>&1); then
        echo "FAIL selftest: a ledger row with no pre-image passed the seal"
        exit 1
    fi
    printf '%s\n' "$out2" | grep -q 'no pre-image for' ||
        { echo "FAIL selftest: the refusal does not name the missing pre-image: $out2"; exit 1; }
    echo "ok   check-sealed selftest: 3 case(s) — an untouched copy passes, an edited answer key and a missing pre-image do not"
    exit 0
fi

# The sealed set of ONE directory, in the order the manifest hashes it. The directory is an
# argument, and that is load-bearing: an earlier version listed the cards from the live tree even
# while hashing a pre-image, so adding a fifth card made every past manifest hash something it
# never contained and the whole history went red — with no way back, because the only repair
# would have been editing the pre-images, which is the one thing a seal exists to forbid. A
# manifest describes the directory it was taken from.
sealed_list() {
    dir=$1
    printf '%s\n' PROTOCOL.md prompt.md grade-rubric.md selection.tsv
    if [ -d "$dir/cards" ]; then
        ls "$dir/cards" 2>/dev/null | sed 's|^|cards/|' | LC_ALL=C sort
    fi
}

# One hash over the sealed files' names AND contents: a rename is a change. It takes the
# directory to hash so the live files and a pre-image are measured by the SAME procedure — the
# first version walked the pre-image with `find | sort` instead, which put `cards/` before
# `grade-rubric.md` and produced a different hash for identical bytes.
manifest_of() {
    dir=$1
    for f in $(sealed_list "$dir"); do
        [ -f "$dir/$f" ] || { echo "missing:$f"; continue; }
        printf '%s  %s\n' "$(shasum -a 256 "$dir/$f" | cut -d' ' -f1)" "$f"
    done | shasum -a 256 | cut -d' ' -f1
}

[ -f "$here/ledger.md" ] || { echo "FAIL: no ledger.md — nothing is sealed"; exit 1; }

# `manifest_of` already prints `missing:<file>` for anything absent, so the hash itself carries
# the answer; a second walk of the same list would only be able to disagree with it.
live="$(manifest_of "$here")"
case "$live" in *missing:*) fail "sealed file(s) absent: $live" ;; esac

# The ledger: hash<TAB>date<TAB>reason. Comments and blanks are ignored.
rows=$(grep -cv '^\(#\|$\)' "$here/ledger.md" 2>/dev/null || echo 0)
[ "$rows" -gt 0 ] || fail "ledger.md holds no rows"

last=$(grep -v '^\(#\|$\)' "$here/ledger.md" | tail -1 | cut -f1)
[ "$last" = "$live" ] || fail "the live files hash to $live but the ledger's last row is $last — a sealed file changed without an amendment row"

pre_images=0
for h in $(grep -v '^\(#\|$\)' "$here/ledger.md" | cut -f1); do
    if [ -d "$here/manifests/$h" ]; then
        pre_images=$((pre_images + 1))
        # The pre-image must BE the thing it claims, measured the way the live files are.
        inner=$(manifest_of "$here/manifests/$h")
        [ "$inner" = "$h" ] || fail "manifests/$h does not hash to its own name ($inner)"
    else
        fail "no pre-image for $h — the answer key that graded its runs cannot be read back"
    fi
done

runs=0
if [ -d "$here/runs" ]; then
    for meta in "$here"/runs/*/meta.json; do
        [ -f "$meta" ] || continue
        runs=$((runs + 1))
        named=$(sed -n 's/.*"manifest"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$meta" | head -1)
        [ -n "$named" ] || { fail "$(basename "$(dirname "$meta")")/meta.json names no manifest"; continue; }
        grep -q "^$named	" "$here/ledger.md" ||
            fail "$(basename "$(dirname "$meta")") ran under $named, which the ledger does not hold"
    done
fi

# Scanned nothing is a failure, not a pass. (The row count is already fatal above; what this
# adds is the pre-image side, which an empty manifests/ would otherwise pass in silence.)
[ "$pre_images" -gt 0 ] || fail "scanned $rows ledger row(s) and $pre_images pre-image(s) — a seal that checks nothing is not a seal"

echo "scanned: $rows ledger row(s), $pre_images pre-image(s), $runs published run(s); live manifest $live"
[ "$fails" = "0" ] || exit 1
echo "ok   the live answer key is the ledger's last row, every hash has its pre-image, and every run names one"
