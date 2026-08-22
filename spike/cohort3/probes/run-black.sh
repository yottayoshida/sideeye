#!/bin/sh
# Cohort-3 probe: black (PROTOCOL.md "Probe plans", target 2).
# Engine-free: normal executions only. State root: the directory holding
# probe.py. The formatter oracle is black's own --check plus the
# determinism condition (a pre-computed formatted form would itself be
# pre-freeze contact — PROTOCOL, fixture rules). Cache: none exists,
# --no-cache. Raw strace log lands in $PROBE_OUT.
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"

WS=/tmp/probe-black
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS/pre/root"

note "black probe — $(black --version | tr '\n' ' ') — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- fixture, byte-for-byte from the frozen plan ---------------------------
cat > "$WS/pre/root/probe.py" <<'EOF'
x=[1,2,3]
def f(a,b):
    return {'k':a+b,'l':[v   for v in x]}
y = f( 1 ,2 )
EOF

export HOME="$WS/home"; mkdir -p "$HOME"
note "condition 7 — ambient: HOME=<WS>/home, fresh and shown after the runs; --no-cache means no cache directory exists to reset (the reset procedure is the absence)."

run_once() { # suffix
    cp -a "$WS/pre/root" "$WS/root$1"
    echo "reset: root$1 is a fresh copy of the pre-state"
    black --no-cache "$WS/root$1/probe.py" 2>&1
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if cmp -s "$WS/pre/root/probe.py" "$WS/rootA/probe.py"; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "probe.py's bytes changed (the fixture is not already black-formatted)"

# Exactly the expected artifacts: the root still holds exactly one file,
# probe.py — no cache files, no backups, nothing new.
listing=$(ls -A "$WS/rootA" | tr '\n' ' ')
[ "$listing" = "probe.py " ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "the state root holds exactly 'probe.py' (got: '$listing')"

black --check --no-cache "$WS/rootA/probe.py" > /dev/null 2>&1; crc=$?
[ "$crc" -eq 0 ] && ok=yes || ok=no
verdict "4-round-trip" $ok "black --check --no-cache exits 0 on the result (the tool's own oracle; rc=$crc)"
echo "the formatted bytes, as measured (recorded, not predicted):"
cat "$WS/rootA/probe.py"

note "diff -r of the two state roots:"
diff -r "$WS/rootA" "$WS/rootB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart leave byte-identical state roots (diff rc=$drc)"

note "strace pass (fresh copy; raw log kept as black.strace)"
cp -a "$WS/pre/root" "$WS/rootS"
run_strace "$WS/strace.log" black --no-cache "$WS/rootS/probe.py" > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/black.strace" 2>/dev/null || true
note "mutating paths (successful only, deduped):"
closure_paths "$WS/strace.log" "$WS/unattr-count" | sort -u | sed "s|$WS|WS|"
echo "unattributed count: $(cat "$WS/unattr-count" 2>/dev/null || echo '?')"
closure_check "$WS/strace.log" "$WS/rootS" "$WS/home" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "condition 7 evidence — HOME after all runs:"
find "$HOME" -type f | sed "s|$WS|WS|" | sort
echo "(no output above = HOME stayed empty; with --no-cache there is no cache directory anywhere — the closure pass is the proof)"

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
