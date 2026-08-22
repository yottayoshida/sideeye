#!/bin/sh
# Per-leg falsification of the cohort-3 rustfmt checker (every leg red
# once, separately, ATTRIBUTED — a red from the wrong leg fails the
# drill). States are fabricated with normal rustfmt runs plus targeted
# corruption — no kill, no crash, no engine. The checker and setup are
# spawned through their exec bits, never `sh file`.
set -u
OPS=$(cd "$(dirname "$0")/ops" && pwd)
R=/tmp/cohort3/rustfmt
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

echo "== rustfmt checker drills — $(rustfmt --version) — leg-V oracle: $(rustc --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
rm -rf "$R/drill-old" "$R/drill-new" "$R/drill-v" "$R/drill-empty" "$R/drill-e" "$R/drill-m"
"$OPS/setup.sh" > /dev/null 2>&1
export HOME="$R/home"

# green control, old side: the unformatted pre-state must pass
cp -a "$R/state" "$R/drill-old"
drill "green-old" pass "$R/drill-old" ""

# green control, new side: a completed format (normal execution, rc
# CHECKED — an unchecked failure would leave the old bytes and print a
# silent duplicate of green-old) must pass, and the live bytes are
# printed so the transcript itself proves the byte-match against the
# probe-measured anchor (R1: the first draft discarded the rc and
# dropped the cat line black's template carried)
cp -a "$R/state" "$R/drill-new"
rustfmt "$R/drill-new/probe.rs" > /dev/null 2>&1
frc=$?
echo "rustfmt rc=$frc (must be 0 for green-new to mean what it claims)"
[ "$frc" -eq 0 ] || { echo "drill FAIL green-new: rustfmt itself failed (rc=$frc)"; FAILS=$((FAILS+1)); }
drill "green-new" pass "$R/drill-new" ""
echo "the formatted bytes, as measured:"
cat "$R/drill-new/probe.rs"

# leg V red: a mid-token truncation (the shape a partial write leaves)
cp -a "$R/drill-new" "$R/drill-v"
head -c 30 "$R/state/probe.rs" > "$R/drill-v/probe.rs"
drill "V-red-truncated" fail "$R/drill-v" "leg V"

# leg V red, the ENGINE-REACHABLE tear: the empty file — unlike black's
# case it fails leg V here, because a bin crate without fn main does
# not compile
cp -a "$R/drill-new" "$R/drill-empty"
: > "$R/drill-empty/probe.rs"
drill "V-red-empty-file" fail "$R/drill-empty" "leg V"

# leg E red: a program rustc accepts that is neither anchor (one
# constant changed in the formatted shape)
cp -a "$R/drill-new" "$R/drill-e"
cat > "$R/drill-e/probe.rs" <<'EOF'
fn main() {
    let x = vec![1, 2, 4];
    let s: u32 = x.iter().sum();
    println!("{}", s);
}
EOF
drill "E-red-neither-anchor" fail "$R/drill-e" "leg E"

# guard red: the file is gone entirely
cp -a "$R/drill-old" "$R/drill-m"
rm "$R/drill-m/probe.rs"
drill "guard-red-missing-file" fail "$R/drill-m" "missing from the state dir"

rm -rf "$R/drill-old" "$R/drill-new" "$R/drill-v" "$R/drill-empty" "$R/drill-e" "$R/drill-m"
echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
