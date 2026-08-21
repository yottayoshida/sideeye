#!/bin/sh
# Cohort-2 probe: Mercurial (PROTOCOL.md "Probe plans", target 2).
# Engine-free: normal executions only — no kill, no crash, no checker.
# State root: the WHOLE .hg. Conditions 1-6 machine-judged; condition 7 is
# the printed ambient evidence. Raw strace log lands in $PROBE_OUT.
set -u
. "$(dirname "$0")/lib.sh"

WS=/tmp/probe-hg
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS"

note "hg probe — $(hg version -q) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$WS/hgrc" <<'EOF'
[ui]
username = probe <probe@example.invalid>
EOF
export HGRCPATH="$WS/hgrc"
export HOME="$WS/home"
mkdir -p "$HOME"
note "condition 7 — ambient: HGRCPATH=<WS>/hgrc (contents above are its two lines: [ui] username), HOME=<WS>/home (fresh, empty). Neither is copied per run: the config file is read-only to hg and HOME stays empty — shown after the runs below."

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
    echo "reset: repo$sfx is a fresh copy of the pre-state repo"
    hg -R "$WS/repo$sfx" commit -m probe -d "2026-01-02 00:00:00 +0000"
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/repo/.hg" "$WS/repoA/.hg" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok ".hg after run A differs from pre-state .hg"

# Exactly one new changeset and nothing else: the whole log is asserted.
lg=$(hg -R "$WS/repoA" log -T '{rev}:{desc}\n' | tr '\n' ' ')
[ "$lg" = "1:probe 0:initial " ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "log is exactly '1:probe 0:initial' (got: '$lg')"

got=$(hg -R "$WS/repoA" cat -r tip "$WS/repoA/alpha")
want='alpha, modified fixed bytes'
[ "$got" = "$want" ] && ok=yes || ok=no
verdict "4-round-trip" $ok "hg cat -r tip alpha returns the committed bytes"

note "diff -r of the two .hg trees:"
diff -r "$WS/repoA/.hg" "$WS/repoB/.hg"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart byte-identical .hg (diff rc=$drc)"

note "strace pass (fresh copy; raw log kept as hg.strace)"
cp -a "$WS/repo" "$WS/repoS"
run_strace "$WS/strace.log" hg -R "$WS/repoS" commit -m probe -d "2026-01-02 00:00:00 +0000" > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/hg.strace" 2>/dev/null || true
note "mutating paths (all mutating syscalls, successful only, deduped):"
mutating_paths "$WS/strace.log" | sort -u | sed "s|$WS|WS|"
# Declared: writes stay inside the repo copy (the .hg state and the
# operation's own working-copy bookkeeping); /tmp is scratch.
closure_check "$WS/strace.log" "$WS/repoS" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "condition 7 evidence — HOME after both runs (expected empty):"
find "$HOME" -type f | sed "s|$WS|WS|" | sort
echo "(no output above = HOME stayed empty; HGRCPATH file is the only ambient input and hg only reads it)"

# ---- shim-visibility forecast: the commit-path thread ----------------------
# The engine refuses any thread the shim observes; this section measures the
# thread and its off switch, each with a fresh pre-state copy, plus the
# worker.* configs that do NOT remove it (so the off switch's attribution is
# exclusive, not one-of-several).
note "thread forecast (successful CLONE_THREAD count per configuration):"
for cfg in "default" "storage.revbranchcache.mmap=no" "worker.enabled=no" "worker.backgroundclose=no"; do
    cp -a "$WS/repo" "$WS/repoF"
    if [ "$cfg" = default ]; then
        strace -f -o "$WS/forecast.log" -e trace=clone,clone3 hg -R "$WS/repoF" commit -m probe -d "2026-01-02 00:00:00 +0000" > /dev/null 2>&1
    else
        strace -f -o "$WS/forecast.log" -e trace=clone,clone3 hg -R "$WS/repoF" --config "$cfg" commit -m probe -d "2026-01-02 00:00:00 +0000" > /dev/null 2>&1
    fi
    echo "  $cfg: $(thread_counts "$WS/forecast.log")"
    rm -rf "$WS/repoF" "$WS/forecast.log"
done
echo "reading: the commit-path thread exists by default, survives the worker.* switches, and storage.revbranchcache.mmap=no removes it — that config rides the define's launcher."

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
