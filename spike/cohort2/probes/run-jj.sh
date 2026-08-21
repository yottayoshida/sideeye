#!/bin/sh
# Cohort-2 probe: Jujutsu (PROTOCOL.md "Probe plans", target 3).
# Engine-free: normal executions only — no kill, no crash, no checker.
# Reproducibility env (names read from the jj binary itself, per the frozen
# plan's plumbing allowance): JJ_TIMESTAMP, JJ_OP_TIMESTAMP,
# JJ_RANDOMNESS_SEED, JJ_OP_HOSTNAME, JJ_OP_USERNAME, JJ_TZ_OFFSET_MINS,
# JJ_USER, JJ_EMAIL.
set -u

WS=/tmp/probe-jj
rm -rf "$WS"
mkdir -p "$WS"
FAILS=0
note() { echo "== $*"; }
verdict() {
    if [ "$2" = yes ]; then echo "ok   $1: $3"; else echo "FAIL $1: $3"; FAILS=$((FAILS+1)); fi
}

export JJ_USER=probe JJ_EMAIL=probe@example.invalid
export JJ_TIMESTAMP=2026-01-01T00:00:00+00:00 JJ_OP_TIMESTAMP=2026-01-01T00:00:00+00:00
export JJ_RANDOMNESS_SEED=42 JJ_OP_HOSTNAME=probe-host JJ_OP_USERNAME=probe-user
export JJ_TZ_OFFSET_MINS=0
export HOME="$WS/home"
mkdir -p "$HOME"

note "jj probe — $(jj --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- pre-state, built once ------------------------------------------------
mkdir -p "$WS/repo"
cd "$WS/repo"
jj git init > /dev/null 2>&1 || { echo "SETUP: jj git init failed"; exit 2; }
# The colocated .git writes a reflog line with wall-clock time on every jj
# export ("export from jj", measured in probes/jj-v2.txt as the single
# nondeterministic byte run). The reflog is a local convenience log with a
# documented off switch, not repository state; the pre-state disables it
# and drops the lines init already wrote.
git config core.logAllRefUpdates false
rm -rf .git/logs
printf 'alpha, fixed bytes\n' > alpha
touch -t 202601010000 alpha
jj commit -m initial > /dev/null 2>&1 || { echo "SETUP: initial commit failed"; exit 2; }
printf 'alpha, modified fixed bytes\n' > alpha
touch -t 202601020000 alpha
cd /
pre_commits=$(cd "$WS/repo" && jj log --no-graph -T 'commit_id.short() ++ "\n"' -r 'all()' | wc -l | tr -d ' ')
pre_ops=$(cd "$WS/repo" && jj op log --no-graph -T 'id.short() ++ "\n"' | wc -l | tr -d ' ')
note "pre-state: $pre_commits commits (incl. root and working copy), $pre_ops operations"

run_once() { # suffix
    sfx=$1
    cp -a "$WS/repo" "$WS/repo$sfx"
    ( cd "$WS/repo$sfx" && jj commit -m probe )
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
# State root (amended pre-explore, see PROTOCOL): the whole repository
# directory — working copy, .jj and the colocated .git together.
if diff -r "$WS/repo" "$WS/repoA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "repository dir after run A differs from pre-state"

# ---- condition 3: artifact count -------------------------------------------
# jj commit finishes the working-copy commit AND opens a fresh empty one, so
# the log grows by exactly one row per commit; the op log grows by one
# operation (the snapshot rides the same op). Read both.
post_commits=$(cd "$WS/repoA" && jj log --no-graph -T 'commit_id.short() ++ "\n"' -r 'all()' | wc -l | tr -d ' ')
post_ops=$(cd "$WS/repoA" && jj op log --no-graph -T 'id.short() ++ "\n"' | wc -l | tr -d ' ')
dc=$((post_commits - pre_commits)); dop=$((post_ops - pre_ops))
[ "$dc" = 1 ] && [ "$dop" = 1 ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "commits +$dc (expected +1), operations +$dop (expected +1)"

# ---- condition 4: content round-trip ---------------------------------------
got=$(cd "$WS/repoA" && jj file show -r @- alpha)
want='alpha, modified fixed bytes'
[ "$got" = "$want" ] && ok=yes || ok=no
verdict "4-round-trip" $ok "jj file show -r @- alpha returns the committed bytes"

# ---- condition 5: byte determinism -----------------------------------------
note "diff -r of the two repository trees (working copy + .jj + .git):"
diff -r "$WS/repoA" "$WS/repoB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart byte-identical repository dir (diff rc=$drc)"

# ---- condition 6: state-root closure (strace) -------------------------------
note "strace pass (fresh copy; mutating paths outside .jj listed)"
cp -a "$WS/repo" "$WS/repoS"
( cd "$WS/repoS" && strace -f -o "$WS/strace.log" -e trace=%file,write,clone,fork,vfork \
    jj commit -m probe > /dev/null 2>&1 )
echo "strace'd run rc=$?"
note "write-opened paths (openat with O_WRONLY|O_RDWR|O_CREAT), deduped:"
grep -E 'openat\(.*O_(WRONLY|RDWR|CREAT)' "$WS/strace.log" | grep -oE '"[^"]+"' | sort -u | sed "s|$WS|WS|"
note "renames and unlinks:"
grep -E '(rename|unlink)' "$WS/strace.log" | grep -oE '"[^"]+"' | sort -u | sed "s|$WS|WS|"
note "process/thread creation (clone/fork), count:"
grep -cE '^\S+ +(clone|clone3|fork|vfork)' "$WS/strace.log" || true
note "reading (condition 6): persistent writes must be inside WS/repoS (the repository dir: working copy + .jj + colocated .git); /tmp and /dev writes are scratch."

# ---- condition 7: ambient --------------------------------------------------
note "ambient consulted (condition 7): identity and clocks are pinned entirely through JJ_* environment (printed above); HOME is a fresh per-probe directory, contents after the runs:"
find "$HOME" -type f | sed "s|$WS|WS|" | sort

# ---- summary ----------------------------------------------------------------
note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
