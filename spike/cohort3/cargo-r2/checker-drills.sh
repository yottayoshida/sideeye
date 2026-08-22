#!/bin/sh
# Per-leg falsification of the r2 cargo checker — r1's seven drills at
# the r2 paths, plus two r2-specific conditions: this harness EXPORTS
# RUSTC at the stand-in BEFORE setup and for every drill, the way the
# engine's environment will carry it, and it commits the unset's red
# side directly — `cargo metadata` run with the stand-in still in the
# environment must die (the target-info probe asks for more than -vV),
# which is exactly what check.sh's `unset RUSTC` prevents on every
# world. Attribution as in r1: a red from the wrong leg is a drill
# failure.
set -u
OPS=$(cd "$(dirname "$0")/ops" && pwd)
C=/tmp/cohort3/cargo-r2
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

echo "== cargo r2 checker drills — $(cargo --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
rm -rf "$C/drill-old" "$C/drill-new" "$C/drill-v" "$C/drill-vl" "$C/drill-t" "$C/drill-c" "$C/drill-m"
# The env is set BEFORE setup so setup itself runs the way the engine
# will run it — under the stand-in (R1: the earlier order left setup's
# generate-lockfile measured only against the real rustc). setup writes
# the stand-in before its first cargo call, so the export dangles for
# two commands and then binds.
export CARGO_HOME="$C/home"
export RUSTC="$C/rustc-standin"
"$OPS/setup.sh" > /dev/null 2>&1
echo "setup rc=$? (ran with RUSTC=$RUSTC — engine-faithful)"
echo "harness env: RUSTC=$RUSTC for every drill below"

# green control, old side: the un-run operation's state must pass
cp -a "$C/state" "$C/drill-old"
drill "green-old" pass "$C/drill-old" ""

# green control, new side: a completed add (normal execution, under the
# stand-in exactly as the engine will run it) must pass
cp -a "$C/state" "$C/drill-new"
cargo add --offline --manifest-path "$C/drill-new/Cargo.toml" --path "$C/depcrate" > /dev/null 2>&1
drill "green-new" pass "$C/drill-new" ""
echo "the dependency entry the stand-in-mediated add recorded:"
grep '^depcrate' "$C/drill-new/Cargo.toml"

# The unset's red side, COMMITTED (R1: it was measured but only
# recorded in prose): cargo metadata with the stand-in still in the
# environment — what every checker run would hit without check.sh's
# `unset RUSTC` — must die at the stand-in.
timeout 120 cargo metadata --offline --format-version 1 \
    --manifest-path "$C/drill-new/Cargo.toml" > /dev/null 2> "$C/meta-red.err"
mrc=$?
echo "metadata-with-standin rc=$mrc (the red the checker's unset prevents):"
head -2 "$C/meta-red.err"
if [ "$mrc" -eq 0 ]; then
    echo "drill FAIL unset-red-side: metadata succeeded under the stand-in — the unset guards nothing"
    FAILS=$((FAILS+1))
else
    echo "drill ok   unset-red-side: metadata under the stand-in is red (rc=$mrc)"
fi
rm -f "$C/meta-red.err"

# leg V red: a torn manifest
cp -a "$C/drill-new" "$C/drill-v"
head -c 20 "$C/drill-v/Cargo.toml" > "$C/drill-v/Cargo.toml.t"
mv "$C/drill-v/Cargo.toml.t" "$C/drill-v/Cargo.toml"
drill "V-red-torn-manifest" fail "$C/drill-v" "leg V"

# leg V red, the LIKELY crash shape (torn-lock ruling): mid-entry tear
cp -a "$C/drill-new" "$C/drill-vl"
head -c 150 "$C/drill-vl/Cargo.lock" > "$C/drill-vl/Cargo.lock.t"
mv "$C/drill-vl/Cargo.lock.t" "$C/drill-vl/Cargo.lock"
drill "V-red-torn-lock" fail "$C/drill-vl" "leg V"

# leg T red: depcrate named twice in VALID toml
cp -a "$C/drill-new" "$C/drill-t"
printf '\n[dev-dependencies]\ndepcrate = { path = "../depcrate" }\n' >> "$C/drill-t/Cargo.toml"
drill "T-red-named-twice" fail "$C/drill-t" "leg T"

# leg C red: one mutated source byte
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
