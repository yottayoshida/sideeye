#!/bin/sh
# Cohort-2 probe: Bun (PROTOCOL.md "Probe plans", target 5).
# Engine-free: normal executions only — no kill, no crash, no checker.
# The dependency is a local tarball outside the state root; the cache is an
# ambient directory reset per run; the network-independence companion
# transcript (bun-network-independence.txt) shows the same add succeeding
# under docker --network=none.
set -u
. "$(dirname "$0")/lib.sh"

WS=/tmp/probe-bun
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS"

note "bun probe — bun $(bun --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- dependency tarball, OUTSIDE the state root -----------------------------
mkdir -p "$WS/deppkg/package"
cat > "$WS/deppkg/package/package.json" <<'EOF'
{ "name": "probe-dep", "version": "1.0.0", "main": "index.js" }
EOF
printf 'module.exports = "probe-dep";\n' > "$WS/deppkg/package/index.js"
touch -t 202601010000 "$WS/deppkg/package/package.json" "$WS/deppkg/package/index.js" "$WS/deppkg/package"
tar -czf "$WS/dep-1.0.0.tgz" -C "$WS/deppkg" package
touch -t 202601010000 "$WS/dep-1.0.0.tgz"

# ---- pre-state, built once ------------------------------------------------
mkdir -p "$WS/state"
cat > "$WS/state/package.json" <<'EOF'
{ "name": "probe-proj", "version": "1.0.0" }
EOF
touch -t 202601010000 "$WS/state/package.json" "$WS/state"
note "condition 7 — ambient: HOME, BUN_INSTALL_CACHE_DIR and TMPDIR under <WS>/ambientX, created fresh per run (reset shown by the mkdir below; nothing pre-exists)."

run_once() { # suffix
    sfx=$1
    cp -a "$WS/state" "$WS/state$sfx"
    mkdir -p "$WS/ambient$sfx/home" "$WS/ambient$sfx/cache" "$WS/ambient$sfx/tmp"
    echo "reset: state$sfx copied from pre-state; ambient$sfx created empty"
    ( cd "$WS/state$sfx" && \
      HOME="$WS/ambient$sfx/home" BUN_INSTALL_CACHE_DIR="$WS/ambient$sfx/cache" \
      TMPDIR="$WS/ambient$sfx/tmp" \
      timeout 120 bun add ../dep-1.0.0.tgz )
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/state" "$WS/stateA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "state after run A differs from pre-state"

# Exactly the expected artifacts and nothing else: node_modules holds
# probe-dep (plus bun's .bin/.cache bookkeeping dirs at most), the lockfile
# exists, and the full bun pm ls tree names exactly one dependency.
nm=$(ls "$WS/stateA/node_modules" | grep -v '^\.' | tr '\n' ' ')
lockn=0; [ -f "$WS/stateA/bun.lock" ] && lockn=1
# bun pm ls shows local-tarball deps as name@<specifier-path>; the whole
# dependency block must be that single row.
lstree=$(cd "$WS/stateA" && HOME="$WS/ambientA/home" BUN_INSTALL_CACHE_DIR="$WS/ambientA/cache" bun pm ls 2>/dev/null | sed -n '2,$p' | tr '\n' ' ')
[ "$nm" = "probe-dep " ] && [ "$lockn" = 1 ] && [ "$lstree" = "└── probe-dep@../dep-1.0.0.tgz " ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "node_modules is exactly 'probe-dep' (got: '$nm'), lockfile present=$lockn, bun pm ls is exactly one dep row (got: '$lstree')"

if diff "$WS/stateA/node_modules/probe-dep/package.json" "$WS/deppkg/package/package.json" > /dev/null 2>&1 \
   && diff "$WS/stateA/node_modules/probe-dep/index.js" "$WS/deppkg/package/index.js" > /dev/null 2>&1; then ok=yes; else ok=no; fi
verdict "4-round-trip" $ok "installed files byte-match the tarball's sources"

note "diff -r of the two state trees:"
diff -r "$WS/stateA" "$WS/stateB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart byte-identical project tree (diff rc=$drc)"

note "strace pass (fresh copies; raw log kept as bun.strace)"
cp -a "$WS/state" "$WS/stateS"
mkdir -p "$WS/ambientS/home" "$WS/ambientS/cache" "$WS/ambientS/tmp"
( cd "$WS/stateS" && \
  HOME="$WS/ambientS/home" BUN_INSTALL_CACHE_DIR="$WS/ambientS/cache" TMPDIR="$WS/ambientS/tmp" \
  run_strace "$WS/strace.log" timeout 120 bun add ../dep-1.0.0.tgz > /dev/null 2>&1 )
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/bun.strace" 2>/dev/null || true
note "mutating paths (all mutating syscalls, successful only, deduped):"
mutating_paths "$WS/strace.log" | sort -u | sed "s|$WS|WS|" | head -60
closure_check "$WS/strace.log" "$WS/stateS" "$WS/ambientS" "$WS/dep-1.0.0.tgz" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"
note "network syscalls (socket/connect, non-AF_UNIX), first 10 — the companion transcript shows the add succeeding with no network at all:"
grep -E '(connect|socket)\(' "$WS/strace.log" | grep -v "AF_UNIX" | head -10

# ---- shim-visibility forecast ------------------------------------------------
note "forecast — linkage of the release binary (the shim needs dynamic loading):"
ldd /usr/local/bin/bun 2>&1 | head -4

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
