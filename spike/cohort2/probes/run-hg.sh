#!/bin/sh
# Cohort-2 probe: Mercurial (PROTOCOL.md "Probe plans", target 2).
# Engine-free: normal executions only — no kill, no crash, no checker.
# State root: the WHOLE .hg (a store-only root would leave dirstate pointing
# at a commit the restored store no longer has).
set -u

WS=/tmp/probe-hg
rm -rf "$WS"
mkdir -p "$WS"
FAILS=0
note() { echo "== $*"; }
verdict() {
    if [ "$2" = yes ]; then echo "ok   $1: $3"; else echo "FAIL $1: $3"; FAILS=$((FAILS+1)); fi
}

note "hg probe — $(hg version -q) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Fixed identity/config via HGRCPATH (condition 7: the ambient config is one
# pinned file; no $HOME state is consulted).
cat > "$WS/hgrc" <<'EOF'
[ui]
username = probe <probe@example.invalid>
EOF
export HGRCPATH="$WS/hgrc"
export HOME="$WS/home"
mkdir -p "$HOME"

# ---- pre-state, built once ------------------------------------------------
hg init "$WS/repo"
printf 'alpha, fixed bytes\n' > "$WS/repo/alpha"
printf 'beta, fixed bytes\n'  > "$WS/repo/beta"
touch -t 202601010000 "$WS/repo/alpha" "$WS/repo/beta"
hg -R "$WS/repo" add "$WS/repo/alpha" "$WS/repo/beta"
hg -R "$WS/repo" commit -m initial -d "2026-01-01 00:00:00 +0000"
printf 'alpha, modified fixed bytes\n' > "$WS/repo/alpha"
touch -t 202601020000 "$WS/repo/alpha"
note "pre-state: 1 changeset, alpha modified in the working copy"
hg -R "$WS/repo" log -T '{rev}:{node|short} {desc}\n'

run_once() { # suffix
    sfx=$1
    cp -a "$WS/repo" "$WS/repo$sfx"
    hg -R "$WS/repo$sfx" commit -m probe -d "2026-01-02 00:00:00 +0000"
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
if diff -r "$WS/repo/.hg" "$WS/repoA/.hg" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok ".hg after run A differs from pre-state .hg"

# ---- condition 3: artifact count -------------------------------------------
count=$(hg -R "$WS/repoA" log -T 'x' | wc -c | tr -d ' ')
[ "$count" = 2 ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "changeset count after commit: $count, expected exactly 2"

# ---- condition 4: content round-trip ---------------------------------------
got=$(hg -R "$WS/repoA" cat -r tip "$WS/repoA/alpha")
want='alpha, modified fixed bytes'
[ "$got" = "$want" ] && ok=yes || ok=no
verdict "4-round-trip" $ok "hg cat -r tip alpha returns the committed bytes"

# ---- condition 5: byte determinism -----------------------------------------
note "diff -r of the two .hg trees:"
diff -r "$WS/repoA/.hg" "$WS/repoB/.hg"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart byte-identical .hg (diff rc=$drc)"

# ---- condition 6: state-root closure (strace) -------------------------------
note "strace pass (fresh copy; mutating paths outside .hg listed)"
cp -a "$WS/repo" "$WS/repoS"
strace -f -o "$WS/strace.log" -e trace=%file,write,clone,fork,vfork \
    hg -R "$WS/repoS" commit -m probe -d "2026-01-02 00:00:00 +0000" > /dev/null 2>&1
echo "strace'd run rc=$?"
note "write-opened paths (openat with O_WRONLY|O_RDWR|O_CREAT), deduped:"
grep -E 'openat\(.*O_(WRONLY|RDWR|CREAT)' "$WS/strace.log" | grep -oE '"[^"]+"' | sort -u | sed "s|$WS|WS|"
note "renames and unlinks:"
grep -E '(rename|unlink)' "$WS/strace.log" | grep -oE '"[^"]+"' | sort -u | sed "s|$WS|WS|"
note "process/thread creation (clone/fork), count:"
grep -cE '^\S+ +(clone|fork|vfork)' "$WS/strace.log" || true
note "reading (condition 6): persistent writes must be inside WS/repoS/.hg; the working-copy file writes (if any) are the operation's own tree; /tmp and /dev writes are scratch."

# ---- shim-visibility forecast: the commit-path thread ----------------------
# The strace pass above shows one short-lived CLONE_THREAD during commit
# (created at C level around the mmap-ed rev-branch-cache; invisible to
# Python-level threading hooks). The engine refuses any thread the shim
# observes, so this forecast matters. Measured split, with control:
note "thread forecast: CLONE_THREAD count with storage.revbranchcache.mmap=no, then default (control)"
cp -a "$WS/repo" "$WS/repoT1"
t1=$(strace -f -e trace=clone,clone3 hg -R "$WS/repoT1" --config storage.revbranchcache.mmap=no commit -m probe -d "2026-01-02 00:00:00 +0000" 2>&1 >/dev/null | grep -c CLONE_THREAD)
cp -a "$WS/repo" "$WS/repoT2"
t2=$(strace -f -e trace=clone,clone3 hg -R "$WS/repoT2" commit -m probe -d "2026-01-02 00:00:00 +0000" 2>&1 >/dev/null | grep -c CLONE_THREAD)
echo "mmap=no: $t1 CLONE_THREAD lines / default (control): $t2"
[ "$t1" -eq 0 ] && [ "$t2" -gt 0 ] && ok=yes || ok=no
verdict "forecast-thread-free" $ok "storage.revbranchcache.mmap=no removes the commit thread; the default shows it (control)"

# ---- summary ----------------------------------------------------------------
note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
