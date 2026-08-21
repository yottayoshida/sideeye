#!/bin/sh
# Cohort-2 probe: KeePassXC (PROTOCOL.md "Probe plans", target 4).
# Engine-free: normal executions only — no kill, no crash, no checker.
# Pre-declared expectation: the determinism condition fails (every save is
# encrypted with fresh randomness). The probe is manual, so the database
# password travels on stdin — stdin is not the engine.
set -u

WS=/tmp/probe-keepassxc
rm -rf "$WS"
mkdir -p "$WS"
FAILS=0
note() { echo "== $*"; }
verdict() {
    if [ "$2" = yes ]; then echo "ok   $1: $3"; else echo "FAIL $1: $3"; FAILS=$((FAILS+1)); fi
}

export HOME="$WS/home"
mkdir -p "$HOME"

note "keepassxc probe — keepassxc-cli $(keepassxc-cli --version 2>&1 | head -1) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- pre-state, built once ------------------------------------------------
mkdir -p "$WS/state"
printf 'probepw\nprobepw\n' | keepassxc-cli db-create -q --set-password "$WS/state/db.kdbx" \
    || { echo "SETUP: db-create failed"; exit 2; }
note "pre-state: one database, no entries beyond defaults"

run_once() { # suffix
    sfx=$1
    cp -a "$WS/state" "$WS/state$sfx"
    printf 'probepw\n' | keepassxc-cli add -q "$WS/state$sfx/db.kdbx" probe-entry -u probe-user
}

note "run A"
run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"
run_once B; rcB=$?

# ---- condition 1: exit codes ----------------------------------------------
[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

# ---- condition 2: non-no-op ------------------------------------------------
if diff -r "$WS/state" "$WS/stateA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "state after run A differs from pre-state"

# ---- condition 3: artifact count -------------------------------------------
count=$(printf 'probepw\n' | keepassxc-cli ls -q "$WS/stateA/db.kdbx" | grep -cx "probe-entry")
[ "$count" = 1 ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "ls shows probe-entry exactly $count time(s), expected exactly 1"

# ---- condition 4: content round-trip ---------------------------------------
uname_got=$(printf 'probepw\n' | keepassxc-cli show -q -a username "$WS/stateA/db.kdbx" probe-entry)
[ "$uname_got" = "probe-user" ] && ok=yes || ok=no
verdict "4-round-trip" $ok "show -a username returns the stored value ('$uname_got')"

# ---- condition 5: byte determinism -----------------------------------------
note "cmp of the two databases:"
cmp "$WS/stateA/db.kdbx" "$WS/stateB/db.kdbx"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart byte-identical db.kdbx (cmp rc=$drc; the pre-declared expectation is that this fails)"

# ---- condition 6: state-root closure (strace) -------------------------------
note "strace pass (fresh copy; mutating paths outside the state root listed)"
cp -a "$WS/state" "$WS/stateS"
printf 'probepw\n' | strace -f -o "$WS/strace.log" -e trace=%file,write,clone,fork,vfork \
    keepassxc-cli add -q "$WS/stateS/db.kdbx" probe-entry -u probe-user > /dev/null 2>&1
echo "strace'd run rc=$?"
note "write-opened paths (openat with O_WRONLY|O_RDWR|O_CREAT), deduped:"
grep -E 'openat\(.*O_(WRONLY|RDWR|CREAT)' "$WS/strace.log" | grep -oE '"[^"]+"' | sort -u | sed "s|$WS|WS|"
note "renames and unlinks:"
grep -E '(rename|unlink)' "$WS/strace.log" | grep -oE '"[^"]+"' | sort -u | sed "s|$WS|WS|"
note "process/thread creation (clone/fork), count:"
grep -cE '^\S+ +(clone|clone3|fork|vfork)' "$WS/strace.log" || true
note "reading (condition 6): persistent writes must be inside WS/stateS; /tmp, /dev and $HOME cache writes are scratch/ambient."

# ---- condition 7: ambient --------------------------------------------------
note "ambient (condition 7): HOME is a fresh per-probe directory; contents after the runs:"
find "$HOME" -type f | sed "s|$WS|WS|" | sort

# ---- summary ----------------------------------------------------------------
note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
