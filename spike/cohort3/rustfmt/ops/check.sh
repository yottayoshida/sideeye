#!/bin/sh
# Cohort-3 rustfmt define (P1) checker. Property (proposals.md P1):
# crash anywhere inside the in-place rewrite, and the source survives
# as a program — rustc's own front end accepts it (leg V), and the
# bytes are one of the two known-good states: the frozen pre-operation
# source or the probe-measured formatted output (leg E). NO recovery
# leg (proposals.md, "The torn-file reading"). The engine snapshots and
# judges L0 before this runs. Every leg's rc is checked (a timeout's
# 124 must never read as an answer).
set -u
S=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker(rustfmt-format): $*"; exit 1; }

[ -f "$S/probe.rs" ] || fail "probe.rs is missing from the state dir"

# ---- leg V: the language's own front end accepts the crashed file ---------
timeout 120 rustc --edition 2021 --crate-type bin --emit=metadata \
    --out-dir "$T" "$S/probe.rs" > "$T/rustc.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "leg V: rustc rejected the crashed file (rc=$rc, 124 = timeout): $(head -c 200 "$T/rustc.out")"

# ---- leg E: the bytes are exactly old or exactly the measured new ---------
cat > "$T/old" <<'EOF'
fn main(){let x=vec![1,2,3];let s:u32=x.iter().sum();println!("{}",s);}
EOF
cat > "$T/new" <<'EOF'
fn main() {
    let x = vec![1, 2, 3];
    let s: u32 = x.iter().sum();
    println!("{}", s);
}
EOF
if cmp -s "$S/probe.rs" "$T/old" || cmp -s "$S/probe.rs" "$T/new"; then
    exit 0
fi
fail "leg E: the file compiles but is neither the frozen source nor the probe-measured formatted output"
