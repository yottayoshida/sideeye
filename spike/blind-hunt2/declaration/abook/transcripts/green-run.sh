#!/bin/sh
# Campaign-2 Seal B artifact (abook): the green side, with the evidence the
# khard round's R1 found missing — engine identity, toml parse, and setup are
# ON the transcript, not asserted beside it.
#
#   1. engine identity: version string + SHA-256 of the engine and shim this
#      tree built (the same numbers the R3 leg will compare to the sweep
#      manifest at exploration time);
#   2. toml parse: each sealed toml is fed to `sideeye explore` WITHOUT its
#      state root existing — the engine parses the config and stops at state
#      resolution (rc=3, "--state could not be resolved"), before setup or
#      operation, with zero side effects (asserted); abook does not run;
#   3. per operation: setup → the operation VERBATIM as extracted from the
#      sealed toml (sed, printed) → exit status compared against the toml's
#      own expected_status → checker → rc 0, plus a state listing.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh .../transcripts/green-run.sh > .../transcripts/green-run.txt 2>&1
set -u
export HOME=/tmp/blind2/home; mkdir -p "$HOME"
here=$(cd "$(dirname "$0")/.." && pwd)   # declaration/abook
ops=$here/ops
SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
fails=0

echo "===== engine identity ====="
"$SIDEEYE" version
sha256sum "$SIDEEYE" "$SHIM"

echo ""
echo "===== toml parse (state unresolved => rc 3, before setup; no side effects) ====="
for op in import export refused; do
    rm -rf "/tmp/blind2/hunt/$op"
    out=$("$SIDEEYE" explore --config "$ops/$op.toml" --shim "$SHIM" \
          --work "/tmp/blind2/parse-probe-$op/work" 2>&1)
    rc=$?
    printf '%s: rc=%s: %s\n' "$op" "$rc" "$out"
    [ "$rc" = 3 ] || { echo "FAIL: expected rc 3"; fails=$((fails + 1)); }
    printf '%s' "$out" | grep -q "state could not be resolved" \
        || { echo "FAIL: not the state-resolution stop"; fails=$((fails + 1)); }
    if [ -e "/tmp/blind2/hunt/$op" ] || [ -e "/tmp/blind2/parse-probe-$op" ]; then
        echo "FAIL: the parse probe left side effects"; fails=$((fails + 1))
    fi
done

for op in import export refused; do
    echo ""
    echo "===== $op ====="
    rm -rf "/tmp/blind2/hunt/$op"
    mkdir -p "/tmp/blind2/hunt/$op/state"

    ( cd "$ops" && sh ./setup.sh "$op" )
    printf 'setup rc=%s\n' "$?"

    opcmd=$(sed -n 's/^operation *= *"\(.*\)"$/\1/p' "$ops/$op.toml")
    want=$(sed -n 's/^expected_status *= *"\(.*\)"$/\1/p' "$ops/$op.toml")
    printf '$ %s\n' "$opcmd"
    sh -c "$opcmd" < /dev/null
    rc=$?
    printf 'operation rc=%s (toml expected_status=%s)\n' "$rc" "$want"
    [ "$rc" = "$want" ] || { echo "FAIL: operation status differs from the sealed expected_status"; fails=$((fails + 1)); }

    ( cd "$ops" && sh ./check.sh "$op" )
    crc=$?
    printf 'check rc=%s\n' "$crc"
    [ "$crc" = 0 ] || { echo "FAIL: checker not green on the post-operation state"; fails=$((fails + 1)); }

    ( cd "/tmp/blind2/hunt/$op/state" && find . -type f | sort )
done

echo ""
echo "green-run fails=$fails"
[ "$fails" = 0 ]
