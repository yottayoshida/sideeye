#!/bin/sh
# Campaign-3 Seal B artifact (khal): the green side. ADR 0016 requirement 3
# is load-bearing here: setup and check are spawned THROUGH THEIR EXEC BITS
# (./setup.sh, ./check.sh — never `sh file`), the same spawn the engine
# performs, because campaign 2's first Seal B failed exactly where a
# `sh`-spawned green could not look.
#
#   1. engine identity: version string + SHA-256 of engine and shim;
#   2. toml parse: each sealed toml fed to `sideeye explore` WITHOUT its
#      state root — the engine parses and stops at state resolution (rc 3);
#      the probed paths — the state root, the work path, and $HOME/.cache
#      (where khal's ambient cache would land if khal had run) — are each
#      asserted absent afterwards; nothing broader is claimed;
#   3. per operation: setup (exec-bit spawn, rc GATING — a failed stage
#      ABORTS that operation's remaining stages, campaign-3 R1 finding 9) →
#      the operation VERBATIM from the sealed toml (sed; asserted non-empty)
#      → status against the toml's expected_status → checker (exec-bit
#      spawn, rc 0) → the operation's documented EFFECT asserted.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh .../transcripts/green-run.sh > .../transcripts/green-run.txt 2>&1
set -u
export HOME=/tmp/blind3/home; mkdir -p "$HOME"
here=$(cd "$(dirname "$0")/.." && pwd)   # declaration/khal
ops=$here/ops
SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
fails=0

echo "===== engine identity ====="
"$SIDEEYE" version
sha256sum "$SIDEEYE" "$SHIM"

echo ""
echo "===== toml parse (state unresolved => rc 3, before setup; probed paths untouched) ====="
for op in import update new; do
    rm -rf "/tmp/blind3/hunt/$op"
    out=$("$SIDEEYE" explore --config "$ops/$op.toml" --shim "$SHIM" \
          --work "/tmp/blind3/parse-probe-$op/work" 2>&1)
    rc=$?
    printf '%s: rc=%s: %s\n' "$op" "$rc" "$out"
    [ "$rc" = 3 ] || { echo "FAIL: expected rc 3"; fails=$((fails + 1)); }
    printf '%s' "$out" | grep -q "state could not be resolved" \
        || { echo "FAIL: not the state-resolution stop"; fails=$((fails + 1)); }
    if [ -e "/tmp/blind3/hunt/$op" ] || [ -e "/tmp/blind3/parse-probe-$op" ] || [ -e "$HOME/.cache" ]; then
        echo "FAIL: the parse probe left effects at a probed path"; fails=$((fails + 1))
    fi
done

anchored() { # anchored <conf> <needle> <exact-line> — 1 if exactly one match
    QH=$(mktemp -d)
    aout=$(HOME=$QH timeout 10 /usr/local/bin/khal -c "$1" search "$2" < /dev/null 2>&1)
    arc=$?
    rm -rf "$QH"
    am=$(printf '%s\n' "$aout" | grep -Fxc "$3")
    [ "$arc" = 0 ] && [ "$am" = 1 ]
}

green_op() { # green_op <op> — returns 1 at the FIRST failed stage, so a
             # broken prerequisite never generates later contacts or effect
             # evidence (campaign-3 R1 finding 9)
    op=$1
    echo ""
    echo "===== $op ====="
    rm -rf "/tmp/blind3/hunt/$op"
    mkdir -p "/tmp/blind3/hunt/$op/state"

    ( cd "$ops" && ./setup.sh "$op" )
    src=$?
    printf 'setup rc=%s (exec-bit spawn)\n' "$src"
    [ "$src" = 0 ] || { echo "FAIL: setup failed — aborting this op"; return 1; }

    opcmd=$(sed -n 's/^operation *= *"\(.*\)"$/\1/p' "$ops/$op.toml")
    want=$(sed -n 's/^expected_status *= *"\(.*\)"$/\1/p' "$ops/$op.toml")
    [ -n "$opcmd" ] && [ -n "$want" ] \
        || { echo "FAIL: could not extract operation/expected_status from $op.toml — aborting this op"; return 1; }
    printf '$ %s\n' "$opcmd"
    opout=$(sh -c "$opcmd" < /dev/null 2>&1)
    rc=$?
    [ -n "$opout" ] && printf '%s\n' "$opout"
    printf 'operation rc=%s (toml expected_status=%s)\n' "$rc" "$want"
    [ "$rc" = "$want" ] || { echo "FAIL: operation status differs from the sealed expected_status — aborting this op"; return 1; }

    ( cd "$ops" && ./check.sh "$op" )
    crc=$?
    printf 'check rc=%s (exec-bit spawn)\n' "$crc"
    [ "$crc" = 0 ] || { echo "FAIL: checker not green on the post-operation state — aborting this op"; return 1; }

    S=/tmp/blind3/hunt/$op/state
    case $op in
        import)
            if [ -f "$S/cal/ada-fixed-uid-001.ics" ] \
               && anchored "$ops/khal-import.conf" AdaMeeting "01.09. 10:00-01.09. 11:00 AdaMeeting"; then
                echo "effect: the imported subject exists as <UID>.ics and answers its query (anchored)"
            else
                echo "FAIL: import effect absent"; return 1
            fi ;;
        update)
            if grep -q "SUMMARY:AdaMeetingMoved" "$S/cal/ada-fixed-uid-001.ics" 2>/dev/null \
               && anchored "$ops/khal-update.conf" AdaMeetingMoved "01.09. 10:00-01.09. 11:00 AdaMeetingMoved"; then
                extras=$(find "$S/cal" -type f ! -name '*.ics' | wc -l | tr -d ' ')
                echo "effect: the subject file carries the new SUMMARY and answers its query (anchored)"
                echo "observed (not asserted): $extras non-.ics leftover file(s) after the normal update"
            else
                echo "FAIL: update effect absent"; return 1
            fi ;;
        new)
            count=$(find "$S/cal" -type f -name '*.ics' ! -name 'grace-fixed-uid-001.ics' | wc -l | tr -d ' ')
            if [ "$count" = 1 ]; then
                echo "effect: exactly one new event file beside the bystander"
            else
                echo "FAIL: new effect absent (count=$count)"; return 1
            fi ;;
    esac

    ( cd "$S" && find . -type f | sort )
    return 0
}

for op_ in import update new; do
    green_op "$op_" || fails=$((fails + 1))
done

echo ""
echo "green-run fails=$fails"
[ "$fails" = 0 ]
