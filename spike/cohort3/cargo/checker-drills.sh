#!/bin/sh
# Per-leg falsification of the cohort-3 cargo checker (the cohort rule:
# every leg red once, separately — one corrupted byte does not falsify
# three legs — and every red is ATTRIBUTED: the drill asserts the
# checker's message names the intended leg, so a red from the wrong leg
# is a drill failure, not a pass). States are fabricated with normal
# cargo runs plus targeted corruption — no kill, no crash, no engine.
# The checker and setup are spawned the way the engine spawns them:
# through the file's own exec bit, never `sh file`.
set -u
OPS=$(cd "$(dirname "$0")/ops" && pwd)
C=/tmp/cohort3/cargo
FAILS=0

drill() { # name want(pass|fail) state-dir expected-fragment
    name=$1; want=$2; st=$3; frag=$4
    out=$(SIDEEYE_STATE_DIR="$st" "$OPS/check.sh" 2>&1); rc=$?
    if [ "$want" = pass ] && [ "$rc" -eq 0 ]; then
        echo "drill ok   $name: checker green as required"
    elif [ "$want" = fail ] && [ "$rc" -eq 1 ]; then
        case "$out" in
            *"$frag"*) echo "drill ok   $name: checker red in the intended leg — $out" ;;
            *) echo "drill FAIL $name: red, but in the WRONG leg (wanted '$frag') — $out"; FAILS=$((FAILS+1)) ;;
        esac
    else
        echo "drill FAIL $name: rc=$rc, wanted $want — $out"
        FAILS=$((FAILS+1))
    fi
}

echo "== cargo checker drills — $(cargo --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
rm -rf "$C/drill-old" "$C/drill-new" "$C/drill-v" "$C/drill-vl" "$C/drill-t" "$C/drill-c" "$C/drill-m"
"$OPS/setup.sh" > /dev/null 2>&1
export CARGO_HOME="$C/home"

# green control, old side: the un-run operation's state must pass
cp -a "$C/state" "$C/drill-old"
drill "green-old" pass "$C/drill-old" ""

# green control, new side: a completed add (normal execution) must pass
cp -a "$C/state" "$C/drill-new"
cargo add --offline --manifest-path "$C/drill-new/Cargo.toml" --path "$C/depcrate" > /dev/null 2>&1
drill "green-new" pass "$C/drill-new" ""
echo "the dependency entry the absolute --path recorded:"
grep '^depcrate' "$C/drill-new/Cargo.toml"

# leg V red: a torn manifest — the shape an interrupted rewrite leaves
cp -a "$C/drill-new" "$C/drill-v"
head -c 20 "$C/drill-v/Cargo.toml" > "$C/drill-v/Cargo.toml.t"
mv "$C/drill-v/Cargo.toml.t" "$C/drill-v/Cargo.toml"
drill "V-red-torn-manifest" fail "$C/drill-v" "leg V"

# leg V red, the LIKELY crash shape (proposals.md, the torn-lock
# ruling): the lock is rewritten in place, so a mid-write kill leaves a
# lock torn mid-entry, and cargo's reader must refuse it (no recovery
# leg exists, by owner ruling — this drill pins the measured behavior:
# "failed to parse lock file")
cp -a "$C/drill-new" "$C/drill-vl"
head -c 150 "$C/drill-vl/Cargo.lock" > "$C/drill-vl/Cargo.lock.t"
mv "$C/drill-vl/Cargo.lock.t" "$C/drill-vl/Cargo.lock"
drill "V-red-torn-lock" fail "$C/drill-vl" "leg V"

# leg T red: depcrate named twice in VALID toml (dependencies +
# dev-dependencies) — metadata resolves, so only T can catch it
cp -a "$C/drill-new" "$C/drill-t"
printf '\n[dev-dependencies]\ndepcrate = { path = "../depcrate" }\n' >> "$C/drill-t/Cargo.toml"
drill "T-red-named-twice" fail "$C/drill-t" "leg T"

# leg C red: one mutated source byte, everything else green
cp -a "$C/drill-new" "$C/drill-c"
printf 'pub fn probe() -> u32 { 43 }\n' > "$C/drill-c/src/lib.rs"
drill "C-red-mutated-source" fail "$C/drill-c" "leg C"

# guard red: the manifest is gone entirely
cp -a "$C/drill-old" "$C/drill-m"
rm "$C/drill-m/Cargo.toml"
drill "guard-red-missing-manifest" fail "$C/drill-m" "missing from the state dir"

rm -rf "$C/drill-old" "$C/drill-new" "$C/drill-v" "$C/drill-vl" "$C/drill-t" "$C/drill-c" "$C/drill-m"
echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
