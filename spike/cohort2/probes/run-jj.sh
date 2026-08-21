#!/bin/sh
# Cohort-2 probe: Jujutsu (PROTOCOL.md "Probe plans", target 3; the plan's
# state root and pre-state were amended pre-explore in two measured steps —
# see the PROTOCOL note and probes/jj-v1.txt, probes/jj-v2.txt).
# Engine-free: normal executions only — no kill, no crash, no checker.
# State root: the repository directory (working copy + .jj + colocated .git).
set -u
. "$(dirname "$0")/lib.sh"

WS=/tmp/probe-jj
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS"

export JJ_USER=probe JJ_EMAIL=probe@example.invalid
export JJ_TIMESTAMP=2026-01-01T00:00:00+00:00 JJ_OP_TIMESTAMP=2026-01-01T00:00:00+00:00
export JJ_RANDOMNESS_SEED=42 JJ_OP_HOSTNAME=probe-host JJ_OP_USERNAME=probe-user
export JJ_TZ_OFFSET_MINS=0
export HOME="$WS/home"
mkdir -p "$HOME"

note "jj probe — $(jj --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
note "condition 7 — ambient: identity and clocks pinned entirely through the environment; HOME=<WS>/home fresh and checked empty after the runs. The pins, with values:"
env | grep '^JJ_' | sort

# ---- pre-state, built once ------------------------------------------------
mkdir -p "$WS/repo"
cd "$WS/repo"
jj git init > /dev/null 2>&1 || { echo "SETUP: jj git init failed"; exit 2; }
# The colocated .git writes a reflog line with wall-clock time on every jj
# export (probes/jj-v2.txt measured it as the single nondeterministic byte
# run). The reflog is a convenience log with a documented off switch, not
# repository state; the pre-state disables it and drops init's own lines.
git config core.logAllRefUpdates false
rm -rf .git/logs
printf 'alpha, fixed bytes\n' > alpha
touch -t 202601010000 alpha
jj commit -m initial > /dev/null 2>&1 || { echo "SETUP: initial commit failed"; exit 2; }
printf 'alpha, modified fixed bytes\n' > alpha
touch -t 202601020000 alpha
cd /
pre_log=$(cd "$WS/repo" && jj log --no-graph -T 'description.first_line() ++ "|"' -r 'all()')
pre_ops=$(cd "$WS/repo" && jj op log --no-graph -T 'id.short() ++ "\n"' | wc -l | tr -d ' ')
note "pre-state log: '$pre_log' — $pre_ops operations"

run_once() { # suffix
    sfx=$1
    cp -a "$WS/repo" "$WS/repo$sfx"
    echo "reset: repo$sfx is a fresh copy of the pre-state repo"
    ( cd "$WS/repo$sfx" && jj commit -m probe )
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/repo" "$WS/repoA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "repository dir after run A differs from pre-state"

# Exactly one new commit row and one new operation, and nothing else: the
# whole descriptions list is asserted against the expected literal.
post_log=$(cd "$WS/repoA" && jj log --no-graph -T 'description.first_line() ++ "|"' -r 'all()')
post_ops=$(cd "$WS/repoA" && jj op log --no-graph -T 'id.short() ++ "\n"' | wc -l | tr -d ' ')
# Rows, newest first: the fresh empty working-copy commit, probe, initial,
# and the root commit's empty description — hence the leading and trailing
# empty fields.
[ "$post_log" = "|probe|initial||" ] && [ "$((post_ops - pre_ops))" = 1 ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "log is exactly '|probe|initial||' (got '$post_log'), operations +$((post_ops - pre_ops)) (expected +1)"

got=$(cd "$WS/repoA" && jj file show -r @- alpha)
want='alpha, modified fixed bytes'
[ "$got" = "$want" ] && ok=yes || ok=no
verdict "4-round-trip" $ok "jj file show -r @- alpha returns the committed bytes"

note "diff -r of the two repository trees (working copy + .jj + .git):"
diff -r "$WS/repoA" "$WS/repoB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart byte-identical repository dir (diff rc=$drc)"

note "strace pass (fresh copy; raw log kept as jj.strace)"
cp -a "$WS/repo" "$WS/repoS"
( cd "$WS/repoS" && run_strace "$WS/strace.log" jj commit -m probe > /dev/null 2>&1 )
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/jj.strace" 2>/dev/null || true
note "mutating paths (all mutating syscalls, successful only, deduped):"
mutating_paths "$WS/strace.log" | sort -u | sed "s|$WS|WS|"
closure_check "$WS/strace.log" "$WS/repoS" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "condition 7 evidence — HOME after both runs (expected empty):"
find "$HOME" -type f | sed "s|$WS|WS|" | sort
echo "(no output above = HOME stayed empty)"

# ---- shim-visibility forecast ------------------------------------------------
note "forecast — linkage of the release binary (a static binary cannot load an LD_PRELOAD shim):"
ldd /usr/local/bin/jj 2>&1 | head -3

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
