#!/bin/sh
# Cohort-2 probe: BorgBackup (PROTOCOL.md "Probe plans", target 1).
# Engine-free: normal executions only — no kill, no crash, no checker.
#
# Modes:
#   ./run-borg.sh          the pinned probe (--timestamp fixed) — the real verdict
#   ./run-borg.sh control  the positive control (NO --timestamp): the same
#                          determinism check must SPLIT, proving the harness
#                          can flag nondeterminism at all. Exit 0 = split seen.
#
# The transcript pins the seven PROTOCOL conditions: (1) exit codes,
# (2) non-no-op, (3) artifact count, (4) content round-trip,
# (5) byte determinism across two runs >=2s apart, (6) state-root closure
# from strace, (7) ambient reset shown.
set -u

MODE=${1:-pinned}
WS=/tmp/probe-borg-$MODE
rm -rf "$WS"
mkdir -p "$WS"
FAILS=0
note() { echo "== $*"; }
verdict() { # name ok-bool detail
    if [ "$2" = yes ]; then echo "ok   $1: $3"; else echo "FAIL $1: $3"; FAILS=$((FAILS+1)); fi
}

note "borg probe ($MODE) — $(borg --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- pre-state, built once ------------------------------------------------
# Source tree OUTSIDE the state root, pinned bytes and mtimes.
mkdir -p "$WS/src"
printf 'alpha file, fixed bytes\n' > "$WS/src/alpha"
printf 'beta file, fixed bytes\n'  > "$WS/src/beta"
printf 'gamma file, fixed bytes\n' > "$WS/src/gamma"
touch -t 202601010000 "$WS/src/alpha" "$WS/src/beta" "$WS/src/gamma" "$WS/src"

# Ambient client state (cache, security) lives under BORG_BASE_DIR, outside
# the state root (condition 7: shown and reset per run by copying the
# post-init snapshot).
export BORG_BASE_DIR="$WS/ambient"
mkdir -p "$WS/state"
borg init --encryption=none "$WS/state/repo" || { echo "SETUP: borg init failed"; exit 2; }
note "ambient after init (condition 7 baseline):"
find "$WS/ambient" -type f | sed "s|$WS|WS|" | sort

# The state-copy path differs from the init path, which borg's security
# check flags as a relocation; the documented override for exactly this is
# BORG_RELOCATED_REPO_ACCESS_IS_OK (recorded here as apparatus, not target
# behavior).
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

run_once() { # dir-suffix -> uses stateN, ambientN
    sfx=$1
    cp -a "$WS/state" "$WS/state$sfx"
    cp -a "$WS/ambient" "$WS/ambient$sfx"
    if [ "$MODE" = control ]; then
        BORG_BASE_DIR="$WS/ambient$sfx" borg create \
            "$WS/state$sfx/repo::probe" "$WS/src"
    else
        BORG_BASE_DIR="$WS/ambient$sfx" borg create \
            --timestamp 2026-01-01T00:00:00 \
            "$WS/state$sfx/repo::probe" "$WS/src"
    fi
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
if diff -r "$WS/state/repo" "$WS/stateA/repo" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "state tree after run A differs from pre-state"

# ---- condition 3: artifact count -------------------------------------------
count=$(BORG_BASE_DIR="$WS/ambientA" borg list --short "$WS/stateA/repo" | wc -l | tr -d ' ')
[ "$count" = 1 ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "borg list shows $count archive(s), expected exactly 1"

# ---- condition 4: content round-trip ---------------------------------------
mkdir -p "$WS/extract" && cd "$WS/extract"
BORG_BASE_DIR="$WS/ambientA" borg extract "$WS/stateA/repo::probe"
if diff -r "$WS/extract$WS/src" "$WS/src" > /dev/null 2>&1; then ok=yes; else ok=no; fi
verdict "4-round-trip" $ok "extracted bytes match the source tree"
cd /

# ---- condition 5: byte determinism -----------------------------------------
note "diff -r of the two state trees:"
diff -r "$WS/stateA/repo" "$WS/stateB/repo"; drc=$?
if [ "$MODE" = control ]; then
    # The control must SPLIT.
    [ "$drc" -ne 0 ] && ok=yes || ok=no
    verdict "5-determinism-CONTROL" $ok "unpinned create must differ across runs (diff rc=$drc; 0=identical)"
else
    [ "$drc" -eq 0 ] && ok=yes || ok=no
    verdict "5-determinism" $ok "two runs >=2s apart byte-identical (diff rc=$drc)"
fi

# ---- condition 6: state-root closure (strace) -------------------------------
note "strace pass (fresh copies; mutating paths outside the state root listed)"
cp -a "$WS/state" "$WS/stateS"
cp -a "$WS/ambient" "$WS/ambientS"
if [ "$MODE" = control ]; then
    BORG_BASE_DIR="$WS/ambientS" strace -f -o "$WS/strace.log" -e trace=%file,write,clone,fork,vfork \
        borg create "$WS/stateS/repo::probe" "$WS/src" > /dev/null 2>&1
else
    BORG_BASE_DIR="$WS/ambientS" strace -f -o "$WS/strace.log" -e trace=%file,write,clone,fork,vfork \
        borg create --timestamp 2026-01-01T00:00:00 "$WS/stateS/repo::probe" "$WS/src" > /dev/null 2>&1
fi
srcrc=$?
echo "strace'd run rc=$srcrc"
note "write-opened paths (openat with O_WRONLY|O_RDWR|O_CREAT), deduped:"
grep -E 'openat\(.*O_(WRONLY|RDWR|CREAT)' "$WS/strace.log" | grep -oE '"[^"]+"' | sort -u | sed "s|$WS|WS|"
note "renames and unlinks:"
grep -E '(rename|unlink)' "$WS/strace.log" | grep -oE '"[^"]+"' | sort -u | sed "s|$WS|WS|"
note "process/thread creation (clone/fork), count:"
grep -cE '^\S+ +(clone|fork|vfork)' "$WS/strace.log" || true
note "reading (condition 6): persistent writes must be inside WS/stateS/repo; writes under WS/ambientS are the declared client cache/security (excluded: reset per run, do not feed the next invocation from a fresh copy); /tmp and /dev writes are scratch."

# ---- summary ----------------------------------------------------------------
note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
