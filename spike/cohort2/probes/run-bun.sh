#!/bin/sh
# Cohort-2 probe: Bun (PROTOCOL.md "Probe plans", target 5).
# Engine-free: normal executions only — no kill, no crash, no checker.
# The dependency is a local tarball outside the state root; the cache is an
# ambient directory reset per run; no registry access is expected (the
# strace pass would show any).
set -u

WS=/tmp/probe-bun
rm -rf "$WS"
mkdir -p "$WS"
FAILS=0
note() { echo "== $*"; }
verdict() {
    if [ "$2" = yes ]; then echo "ok   $1: $3"; else echo "FAIL $1: $3"; FAILS=$((FAILS+1)); fi
}

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

run_once() { # suffix
    sfx=$1
    cp -a "$WS/state" "$WS/state$sfx"
    mkdir -p "$WS/ambient$sfx/home" "$WS/ambient$sfx/cache" "$WS/ambient$sfx/tmp"
    ( cd "$WS/state$sfx" && \
      HOME="$WS/ambient$sfx/home" BUN_INSTALL_CACHE_DIR="$WS/ambient$sfx/cache" \
      TMPDIR="$WS/ambient$sfx/tmp" \
      timeout 120 bun add ../dep-1.0.0.tgz )
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
lockn=0; [ -f "$WS/stateA/bun.lock" ] && lockn=1
depn=0; [ -f "$WS/stateA/node_modules/probe-dep/package.json" ] && depn=1
lsn=$(cd "$WS/stateA" && HOME="$WS/ambientA/home" BUN_INSTALL_CACHE_DIR="$WS/ambientA/cache" bun pm ls 2>/dev/null | grep -c "probe-dep")
[ "$lockn" = 1 ] && [ "$depn" = 1 ] && [ "$lsn" = 1 ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "lockfile present=$lockn, node_modules/probe-dep present=$depn, bun pm ls names it $lsn time(s) (expected 1/1/1)"

# ---- condition 4: content round-trip ---------------------------------------
if diff "$WS/stateA/node_modules/probe-dep/package.json" "$WS/deppkg/package/package.json" > /dev/null 2>&1 \
   && diff "$WS/stateA/node_modules/probe-dep/index.js" "$WS/deppkg/package/index.js" > /dev/null 2>&1; then ok=yes; else ok=no; fi
verdict "4-round-trip" $ok "installed files byte-match the tarball's sources"

# ---- condition 5: byte determinism -----------------------------------------
note "diff -r of the two state trees:"
diff -r "$WS/stateA" "$WS/stateB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart byte-identical project tree (diff rc=$drc)"

# ---- condition 6: state-root closure (strace) -------------------------------
note "strace pass (fresh copies; mutating paths outside the state root listed)"
cp -a "$WS/state" "$WS/stateS"
mkdir -p "$WS/ambientS/home" "$WS/ambientS/cache" "$WS/ambientS/tmp"
( cd "$WS/stateS" && \
  HOME="$WS/ambientS/home" BUN_INSTALL_CACHE_DIR="$WS/ambientS/cache" TMPDIR="$WS/ambientS/tmp" \
  strace -f -yy -o "$WS/strace.log" -e trace=%file,%network,clone,fork,vfork \
  timeout 120 bun add ../dep-1.0.0.tgz > /dev/null 2>&1 )
echo "strace'd run rc=$?"
note "write-opened paths (openat with O_WRONLY|O_RDWR|O_CREAT; -yy resolves dirfd-relative opens), deduped:"
grep -E 'openat\(.*O_(WRONLY|RDWR|CREAT)' "$WS/strace.log" | grep -oE '(<[^>]*>|"[^"]+")' | sort -u | sed "s|$WS|WS|" | head -60
note "renames and unlinks (deduped, first 40):"
grep -E '(rename|unlink)' "$WS/strace.log" | grep -oE '(<[^>]*>|"[^"]+")' | sort -u | sed "s|$WS|WS|" | head -40
note "process/thread creation: total clone/fork events, then CLONE_THREAD events:"
grep -cE '^\S+ +(clone|clone3|fork|vfork)' "$WS/strace.log" || true
grep -cE 'CLONE_THREAD' "$WS/strace.log" || true
note "network syscalls (connect/socket to non-local), first 10:"
grep -E '(connect|socket)\(' "$WS/strace.log" | grep -v "AF_UNIX" | head -10
note "reading (condition 6): persistent writes must be inside WS/stateS; WS/ambientS (home/cache/tmp) is the declared ambient, reset per run; network access, if any, appears above."

# ---- condition 7: ambient --------------------------------------------------
note "ambient (condition 7): HOME/BUN_INSTALL_CACHE_DIR/TMPDIR under WS/ambientX, fresh per run; cache contents after run A (first 15):"
find "$WS/ambientA" -type f | sed "s|$WS|WS|" | sort | head -15

# ---- summary ----------------------------------------------------------------
note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
