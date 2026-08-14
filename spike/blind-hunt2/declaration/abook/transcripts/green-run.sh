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
#      resolution (rc=3, "--state could not be resolved"). The absence of the
#      state root afterwards is the evidence setup never ran (setup's mkdir
#      would have created it), and the operation runs only after setup — the
#      probed paths are the state root, the work path, and $HOME/.abook;
#      nothing broader is claimed;
#   3. per operation: setup (rc GATED) → the operation VERBATIM as extracted
#      from the sealed toml (sed; asserted non-empty) → exit status compared
#      against the toml's own expected_status → checker rc 0 → the
#      operation's documented EFFECT asserted (import: outfile exists and
#      answers the subject query; export: the vCard file exists with both
#      FN lines; refused: the store is byte-identical to its golden and the
#      refusal message was printed).
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
echo "===== toml parse (state unresolved => rc 3, before setup; probed paths untouched) ====="
for op in import export refused; do
    rm -rf "/tmp/blind2/hunt/$op"
    out=$("$SIDEEYE" explore --config "$ops/$op.toml" --shim "$SHIM" \
          --work "/tmp/blind2/parse-probe-$op/work" 2>&1)
    rc=$?
    printf '%s: rc=%s: %s\n' "$op" "$rc" "$out"
    [ "$rc" = 3 ] || { echo "FAIL: expected rc 3"; fails=$((fails + 1)); }
    printf '%s' "$out" | grep -q "state could not be resolved" \
        || { echo "FAIL: not the state-resolution stop"; fails=$((fails + 1)); }
    if [ -e "/tmp/blind2/hunt/$op" ] || [ -e "/tmp/blind2/parse-probe-$op" ] || [ -e "$HOME/.abook" ]; then
        echo "FAIL: the parse probe left effects at a probed path"; fails=$((fails + 1))
    fi
done

for op in import export refused; do
    echo ""
    echo "===== $op ====="
    rm -rf "/tmp/blind2/hunt/$op"
    mkdir -p "/tmp/blind2/hunt/$op/state"

    ( cd "$ops" && sh ./setup.sh "$op" )
    src=$?
    printf 'setup rc=%s\n' "$src"
    [ "$src" = 0 ] || { echo "FAIL: setup failed"; fails=$((fails + 1)); }

    opcmd=$(sed -n 's/^operation *= *"\(.*\)"$/\1/p' "$ops/$op.toml")
    want=$(sed -n 's/^expected_status *= *"\(.*\)"$/\1/p' "$ops/$op.toml")
    [ -n "$opcmd" ] && [ -n "$want" ] \
        || { echo "FAIL: could not extract operation/expected_status from $op.toml"; fails=$((fails + 1)); }
    printf '$ %s\n' "$opcmd"
    opout=$(sh -c "$opcmd" < /dev/null 2>&1)
    rc=$?
    [ -n "$opout" ] && printf '%s\n' "$opout"
    printf 'operation rc=%s (toml expected_status=%s)\n' "$rc" "$want"
    [ "$rc" = "$want" ] || { echo "FAIL: operation status differs from the sealed expected_status"; fails=$((fails + 1)); }

    ( cd "$ops" && sh ./check.sh "$op" )
    crc=$?
    printf 'check rc=%s\n' "$crc"
    [ "$crc" = 0 ] || { echo "FAIL: checker not green on the post-operation state"; fails=$((fails + 1)); }

    # The operation's documented EFFECT (the green side owns this;
    # crash-world invariants deliberately do not).
    S=/tmp/blind2/hunt/$op/state
    tab=$(printf '\t')
    case $op in
        import)
            aq=$(timeout 10 /usr/bin/abook --datafile "$S/book/addressbook" --mutt-query ada@example.com < /dev/null 2>&1)
            arc=$?
            am=$(printf '%s\n' "$aq" | grep -c "^ada@example.com${tab}Ada Lovelace${tab}")
            if [ "$arc" = 0 ] && [ "$am" = 1 ]; then
                echo "effect: the imported subject answers its query (anchored)"
            else
                echo "FAIL: import effect absent (rc=$arc, anchored=$am)"; fails=$((fails + 1))
            fi ;;
        export)
            fns=$(grep -c '^FN:' "$S/book/export.vcf" 2>/dev/null || echo 0)
            if [ "$fns" = 2 ]; then
                echo "effect: export.vcf exists with both FN lines"
            else
                echo "FAIL: export effect absent (FN lines=$fns)"; fails=$((fails + 1))
            fi ;;
        refused)
            if cmp -s "$ops/golden-pair.addressbook" "$S/book/addressbook" \
               && printf '%s' "$opout" | grep -q "cannot write file"; then
                echo "effect: store byte-identical to its golden and the refusal message printed"
            else
                echo "FAIL: refused effect absent"; fails=$((fails + 1))
            fi ;;
    esac

    ( cd "/tmp/blind2/hunt/$op/state" && find . -type f | sort )
done

echo ""
echo "green-run fails=$fails"
[ "$fails" = 0 ]
