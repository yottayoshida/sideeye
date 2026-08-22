#!/bin/sh
# Cohort-3 probe: rustfmt (PROTOCOL.md "Probe plans", target 3).
# Engine-free: normal executions only. State root: the directory holding
# probe.rs. The formatter oracle is rustfmt's own --check plus the
# determinism condition (PROTOCOL, fixture rules). Raw strace log lands in
# $PROBE_OUT.
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"

WS=/tmp/probe-rustfmt
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS/pre/root"

note "rustfmt probe — $(rustfmt --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- fixture, byte-for-byte from the frozen plan ---------------------------
cat > "$WS/pre/root/probe.rs" <<'EOF'
fn main(){let x=vec![1,2,3];let s:u32=x.iter().sum();println!("{}",s);}
EOF

export HOME="$WS/home"; mkdir -p "$HOME"
note "condition 7 — ambient: HOME=<WS>/home, fresh and shown after the runs; rustfmt documents no cache, and the closure pass measures whether that holds."

run_once() { # suffix
    cp -a "$WS/pre/root" "$WS/root$1"
    echo "reset: root$1 is a fresh copy of the pre-state"
    rustfmt "$WS/root$1/probe.rs" 2>&1
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if cmp -s "$WS/pre/root/probe.rs" "$WS/rootA/probe.rs"; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "probe.rs's bytes changed (the fixture is not already rustfmt-formatted)"

listing=$(ls -A "$WS/rootA" | tr '\n' ' ')
[ "$listing" = "probe.rs " ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "the state root holds exactly 'probe.rs' (got: '$listing')"

rustfmt --check "$WS/rootA/probe.rs" > /dev/null 2>&1; crc=$?
[ "$crc" -eq 0 ] && ok=yes || ok=no
verdict "4-round-trip" $ok "rustfmt --check exits 0 on the result (the tool's own oracle; rc=$crc)"
echo "the formatted bytes, as measured (recorded, not predicted):"
cat "$WS/rootA/probe.rs"

note "diff -r of the two state roots:"
diff -r "$WS/rootA" "$WS/rootB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart leave byte-identical state roots (diff rc=$drc)"

note "strace pass (fresh copy; raw log kept as rustfmt.strace)"
cp -a "$WS/pre/root" "$WS/rootS"
run_strace "$WS/strace.log" rustfmt "$WS/rootS/probe.rs" > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/rustfmt.strace" 2>/dev/null || true
note "mutating paths (successful only, deduped):"
closure_paths "$WS/strace.log" "$WS/unattr-count" | sort -u | sed "s|$WS|WS|"
echo "unattributed count: $(cat "$WS/unattr-count" 2>/dev/null || echo '?')"
closure_check "$WS/strace.log" "$WS/rootS" "$WS/home" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "condition 7 evidence — HOME after all runs:"
find "$HOME" -type f | sed "s|$WS|WS|" | sort
echo "(no output above = HOME stayed empty)"

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
