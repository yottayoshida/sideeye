#!/bin/sh
# Cohort-2 probe: BorgBackup (PROTOCOL.md "Probe plans", target 1).
# Engine-free: normal executions only — no kill, no crash, no checker.
#
# Modes:
#   ./run-borg.sh          the pinned probe (--timestamp fixed) — the real verdict
#   ./run-borg.sh control  the positive control (NO --timestamp): the same
#                          determinism check must SPLIT. Exit 0 = split seen.
#
# Conditions 1-6 are machine-judged (the FAILS counter); condition 7 is the
# printed ambient evidence below. Raw strace log lands in $PROBE_OUT.
set -u
. "$(dirname "$0")/lib.sh"

MODE=${1:-pinned}
WS=/tmp/probe-borg-$MODE
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS"

note "borg probe ($MODE) — $(borg --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- pre-state, built once ------------------------------------------------
mkdir -p "$WS/src"
printf 'alpha file, fixed bytes\n' > "$WS/src/alpha"
printf 'beta file, fixed bytes\n'  > "$WS/src/beta"
printf 'gamma file, fixed bytes\n' > "$WS/src/gamma"
touch -t 202601010000 "$WS/src/alpha" "$WS/src/beta" "$WS/src/gamma" "$WS/src"

export BORG_BASE_DIR="$WS/ambient"
mkdir -p "$WS/state"
borg init --encryption=none "$WS/state/repo" || { echo "SETUP: borg init failed"; exit 2; }
# The state-copy path differs from the init path; the documented override
# for exactly this relocation check is BORG_RELOCATED_REPO_ACCESS_IS_OK
# (apparatus, not target behavior).
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

note "condition 7 — ambient: BORG_BASE_DIR=<WS>/ambientX, a fresh copy of the post-init snapshot per run (reset shown by the copy commands below); BORG_RELOCATED_REPO_ACCESS_IS_OK=yes. Post-init ambient snapshot:"
find "$WS/ambient" -type f | sed "s|$WS|WS|" | sort

run_once() { # dir-suffix
    sfx=$1
    cp -a "$WS/state" "$WS/state$sfx"
    cp -a "$WS/ambient" "$WS/ambient$sfx"
    echo "reset: state$sfx and ambient$sfx are fresh copies of the pre-state snapshots"
    if [ "$MODE" = control ]; then
        BORG_BASE_DIR="$WS/ambient$sfx" borg create \
            "$WS/state$sfx/repo::probe" "$WS/src"
    else
        BORG_BASE_DIR="$WS/ambient$sfx" borg create \
            --timestamp 2026-01-01T00:00:00 \
            "$WS/state$sfx/repo::probe" "$WS/src"
    fi
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/state/repo" "$WS/stateA/repo" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "state tree after run A differs from pre-state"

# Exactly one archive, and nothing else: the full --short listing is the
# assertion, not a grep for the expected name.
listing=$(BORG_BASE_DIR="$WS/ambientA" borg list --short "$WS/stateA/repo")
[ "$listing" = "probe" ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "borg list --short prints exactly 'probe' (got: '$listing')"

mkdir -p "$WS/extract" && cd "$WS/extract"
BORG_BASE_DIR="$WS/ambientA" borg extract "$WS/stateA/repo::probe"
if diff -r "$WS/extract$WS/src" "$WS/src" > /dev/null 2>&1; then ok=yes; else ok=no; fi
verdict "4-round-trip" $ok "extracted bytes match the source tree"
cd /

note "diff -r of the two state trees:"
diff -r "$WS/stateA/repo" "$WS/stateB/repo"; drc=$?
if [ "$MODE" = control ]; then
    [ "$drc" -ne 0 ] && ok=yes || ok=no
    verdict "5-determinism-CONTROL" $ok "unpinned create must differ across runs (diff rc=$drc; 0=identical)"
else
    [ "$drc" -eq 0 ] && ok=yes || ok=no
    verdict "5-determinism" $ok "two runs >=2s apart byte-identical (diff rc=$drc)"
fi

note "strace pass (fresh copies; raw log kept as <target>.strace)"
cp -a "$WS/state" "$WS/stateS"
cp -a "$WS/ambient" "$WS/ambientS"
if [ "$MODE" = control ]; then
    BORG_BASE_DIR="$WS/ambientS" run_strace "$WS/strace.log" \
        borg create "$WS/stateS/repo::probe" "$WS/src" > /dev/null 2>&1
else
    BORG_BASE_DIR="$WS/ambientS" run_strace "$WS/strace.log" \
        borg create --timestamp 2026-01-01T00:00:00 "$WS/stateS/repo::probe" "$WS/src" > /dev/null 2>&1
fi
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/borg-$MODE.strace" 2>/dev/null || true
note "mutating paths (all mutating syscalls, successful only, deduped):"
mutating_paths "$WS/strace.log" | sort -u | sed "s|$WS|WS|"
# Declared: persistent writes must sit under the state copy, the per-run
# ambient copy, or scratch. (libuuid attempts /var/lib/libuuid/clock.txt
# and fails ENOENT in this container — a failed call mutates nothing and
# the fail-closed accounting counts successes only, so no exclusion.)
closure_check "$WS/strace.log" "$WS/stateS" "$WS/ambientS" "$WS/extract" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
