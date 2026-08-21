#!/bin/sh
# Cohort-2 probe: KeePassXC (PROTOCOL.md "Probe plans", target 4).
# Engine-free: normal executions only — no kill, no crash, no checker.
# Pre-declared expectation: the determinism condition fails (every save is
# encrypted with fresh randomness). The probe is manual, so the database
# password travels on stdin — stdin is not the engine.
set -u
. "$(dirname "$0")/lib.sh"

WS=/tmp/probe-keepassxc
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS"

note "keepassxc probe — keepassxc-cli $(keepassxc-cli --version 2>&1 | head -1) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- pre-state, built once ------------------------------------------------
# HOME is part of the ambient (keepassxc-cli writes a config on first use),
# so it is snapshotted after setup and copied fresh per run like the state.
export HOME="$WS/home"
mkdir -p "$HOME"
mkdir -p "$WS/state"
printf 'probepw\nprobepw\n' | keepassxc-cli db-create -q --set-password "$WS/state/db.kdbx" \
    || { echo "SETUP: db-create failed"; exit 2; }
note "condition 7 — ambient: HOME=<WS>/homeX, a fresh copy of the post-setup snapshot per run. Post-setup snapshot contents:"
find "$WS/home" -type f | sed "s|$WS|WS|" | sort

run_once() { # suffix
    sfx=$1
    cp -a "$WS/state" "$WS/state$sfx"
    cp -a "$WS/home" "$WS/home$sfx"
    echo "reset: state$sfx and home$sfx are fresh copies of the post-setup snapshots"
    printf 'probepw\n' | HOME="$WS/home$sfx" keepassxc-cli add -q "$WS/state$sfx/db.kdbx" probe-entry -u probe-user
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/state" "$WS/stateA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "state after run A differs from pre-state"

# The whole root listing is asserted, not a grep for the expected name: a
# run that adds anything else fails this.
listing=$(printf 'probepw\n' | HOME="$WS/homeA" keepassxc-cli ls -q "$WS/stateA/db.kdbx" | tr '\n' ' ')
[ "$listing" = "probe-entry " ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "root listing is exactly 'probe-entry' (got: '$listing')"

uname_got=$(printf 'probepw\n' | HOME="$WS/homeA" keepassxc-cli show -q -a username "$WS/stateA/db.kdbx" probe-entry)
[ "$uname_got" = "probe-user" ] && ok=yes || ok=no
verdict "4-round-trip" $ok "show -a username returns the stored value ('$uname_got')"

note "cmp of the two databases:"
cmp "$WS/stateA/db.kdbx" "$WS/stateB/db.kdbx"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart byte-identical db.kdbx (cmp rc=$drc; the pre-declared expectation is that this fails)"

note "strace pass (fresh copies; raw log kept as keepassxc.strace)"
cp -a "$WS/state" "$WS/stateS"
cp -a "$WS/home" "$WS/homeS"
printf 'probepw\n' | HOME="$WS/homeS" run_strace "$WS/strace.log" \
    keepassxc-cli add -q "$WS/stateS/db.kdbx" probe-entry -u probe-user > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/keepassxc.strace" 2>/dev/null || true
note "mutating paths (all mutating syscalls, successful only, deduped):"
mutating_paths "$WS/strace.log" | sort -u | sed "s|$WS|WS|"
closure_check "$WS/strace.log" "$WS/stateS" "$WS/homeS" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
