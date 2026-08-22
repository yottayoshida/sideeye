#!/bin/sh
# Cohort-3 probe: cargo (PROTOCOL.md "Probe plans", target 1).
# Engine-free: normal executions only — no kill, no crash, no checker.
# State root: the application directory. Conditions 1-6 machine-judged;
# condition 7 is the printed ambient evidence. Raw strace log lands in
# $PROBE_OUT. Predicates come from cohort 2's lib.sh, sourced in place
# (PROTOCOL: harness continuity).
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"

WS=/tmp/probe-cargo
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS"

note "cargo probe — $(cargo --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- fixtures, byte-for-byte from the frozen plan --------------------------
mkdir -p "$WS/pre/app/src" "$WS/depcrate/src"
cat > "$WS/pre/app/Cargo.toml" <<'EOF'
[package]
name = "app"
version = "0.1.0"
edition = "2021"
EOF
printf 'pub fn probe() -> u32 { 42 }\n' > "$WS/pre/app/src/lib.rs"
cat > "$WS/depcrate/Cargo.toml" <<'EOF'
[package]
name = "depcrate"
version = "0.1.0"
edition = "2021"
EOF
printf 'pub fn dep() -> u32 { 7 }\n' > "$WS/depcrate/src/lib.rs"

export HOME="$WS/home"; mkdir -p "$HOME"
note "condition 7 — ambient: CARGO_HOME is created FRESH PER RUN at <WS>/cargo-home-<run> (the reset), HOME=<WS>/home fresh and shown after the runs. The dep crate fixture lives outside the state root at <WS>/depcrate and is never mutated (asserted below)."

# Pre-state completion: the lockfile, generated offline in the pre-state
# copy itself (the plan freezes "a Cargo.lock generated at setup").
CARGO_HOME="$WS/cargo-home-setup" cargo generate-lockfile --offline --manifest-path "$WS/pre/app/Cargo.toml" > /dev/null 2>&1
echo "setup: cargo generate-lockfile --offline rc=$?"
ls "$WS/pre/app"

run_once() { # suffix
    sfx=$1
    cp -a "$WS/pre/app" "$WS/app$sfx"
    mkdir -p "$WS/cargo-home-$sfx"
    echo "reset: app$sfx is a fresh copy of the pre-state; cargo-home-$sfx is fresh"
    ( cd "$WS/app$sfx" && CARGO_HOME="$WS/cargo-home-$sfx" cargo add --offline --path ../depcrate ) 2>&1
}

# The relative path ../depcrate resolves against the app dir; both runs and
# the strace run sit directly under $WS so the recorded relative path is
# the same string everywhere (the cohort-2 borg argv lesson, applied).

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/pre/app" "$WS/appA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "the state root after run A differs from the pre-state"

# Exactly one depcrate entry in the manifest, and cargo metadata lists it.
n=$(grep -c '^depcrate' "$WS/appA/Cargo.toml")
meta=$(cd "$WS/appA" && CARGO_HOME="$WS/cargo-home-A" cargo metadata --offline --format-version 1 2>/dev/null | grep -c '"name":"depcrate"')
[ "$n" = 1 ] && [ "$meta" -ge 1 ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "Cargo.toml names depcrate exactly once (got $n); cargo metadata --offline lists it ($meta occurrence(s))"
echo "the manifest's dependency section after run A:"
sed -n '/\[dependencies\]/,$p' "$WS/appA/Cargo.toml"

# Round-trip: metadata reads back the dependency that was put in — name,
# version and the fixture path — and the fixture itself is unmutated.
mline=$(cd "$WS/appA" && CARGO_HOME="$WS/cargo-home-A" cargo metadata --offline --format-version 1 2>/dev/null | tr ',' '\n' | grep -m1 '"id":.*depcrate')
printf 'pub fn dep() -> u32 { 7 }\n' | cmp -s - "$WS/depcrate/src/lib.rs" && fix=intact || fix=changed
[ -n "$mline" ] && [ "$fix" = intact ] && ok=yes || ok=no
verdict "4-round-trip" $ok "metadata resolves depcrate ($mline); fixture bytes $fix"

# Whether Cargo.lock changed is measured and recorded, not expected
# (PROTOCOL: the cargo-add manual promises manifest editing only).
if cmp -s "$WS/pre/app/Cargo.lock" "$WS/appA/Cargo.lock"; then
    echo "measured: Cargo.lock is byte-identical to the pre-state (cargo add did not update it)"
else
    echo "measured: Cargo.lock changed (cargo add updated it)"
fi

note "diff -r of the two state roots:"
diff -r "$WS/appA" "$WS/appB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart leave byte-identical state roots (diff rc=$drc)"

note "strace pass (fresh copy; raw log kept as cargo.strace)"
cp -a "$WS/pre/app" "$WS/appS"
mkdir -p "$WS/cargo-home-S"
( cd "$WS/appS" && CARGO_HOME="$WS/cargo-home-S" run_strace "$WS/strace.log" cargo add --offline --path ../depcrate ) > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/cargo.strace" 2>/dev/null || true
note "mutating paths (successful only, deduped):"
closure_paths "$WS/strace.log" "$WS/unattr-count" | sort -u | sed "s|$WS|WS|"
echo "unattributed count: $(cat "$WS/unattr-count" 2>/dev/null || echo '?')"
# Declared: the state root, the per-run CARGO_HOME (client state, condition
# 7), HOME (shown empty below) and /tmp scratch.
closure_check "$WS/strace.log" "$WS/appS" "$WS/cargo-home-S" "$WS/home" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "condition 7 evidence — the fixture is unmutated (both files) and HOME after all runs:"
printf 'pub fn dep() -> u32 { 7 }\n' | cmp -s - "$WS/depcrate/src/lib.rs" && echo "depcrate/src/lib.rs: unchanged" || echo "depcrate/src/lib.rs: CHANGED"
printf '[package]\nname = "depcrate"\nversion = "0.1.0"\nedition = "2021"\n' | cmp -s - "$WS/depcrate/Cargo.toml" && echo "depcrate/Cargo.toml: unchanged" || echo "depcrate/Cargo.toml: CHANGED"
find "$HOME" -type f | sed "s|$WS|WS|" | sort
echo "(files above, if any, are what cargo left in HOME; CARGO_HOME contents:)"
find "$WS/cargo-home-A" -type f | sed "s|$WS|WS|" | sort | head -20

# ---- shim-visibility forecast: the rustc version probe ---------------------
# The engine refuses observed threads. The strace above shows one vfork
# child (`rustc -vV`) which spawns its own internal thread — cargo itself
# stays single-threaded. This section measures whether a warm CARGO_HOME
# removes the child, each state from a FRESH pre-state copy (an earlier
# ad-hoc reading claimed the warm run made zero clones — that run's add
# was a no-op on an already-edited manifest, which short-circuits before
# the resolver; measuring the operation means a fresh pre-state).
note "clone/execve forecast per CARGO_HOME state (cold = fresh dir, warm = the cold run's dir reused; fresh pre-state each):"
mkdir -p "$WS/ch-forecast"
for state in cold warm; do
    cp -a "$WS/pre/app" "$WS/appF"
    ( cd "$WS/appF" && CARGO_HOME="$WS/ch-forecast" strace -f -o "$WS/forecast.log" -e trace=clone,clone3,execve cargo add --offline --path ../depcrate ) > /dev/null 2>&1
    clones=$(grep -c 'clone' "$WS/forecast.log")
    children=$(grep 'execve' "$WS/forecast.log" | grep -v ENOENT | grep -v 'resumed' | grep -cv '"cargo"')
    echo "  $state: $clones clone line(s), $children non-cargo execve call(s) (unfinished/resumed pairs counted once)"
    grep 'execve' "$WS/forecast.log" | grep -v ENOENT | grep -v '"cargo"' | sed 's/^/    /' | head -3
    rm -rf "$WS/appF" "$WS/forecast.log"
done
echo "reading: the rustc -vV child appears in BOTH states — a warm CARGO_HOME does not remove the version probe, so every fresh add carries one vfork child whose internal thread the shim will observe. Whether that refuses is the engine's decision at explore; any workaround (cargo's documented RUSTC override) is apparatus with its own gate, not assumed here."

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
