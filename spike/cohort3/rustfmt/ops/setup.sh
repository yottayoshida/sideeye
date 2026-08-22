#!/bin/sh
# Cohort-3 rustfmt define (P1) setup: one unformatted Rust file, bytes
# frozen in PROTOCOL.md's probe plan. Nothing else — rustfmt has no
# cache, no config in play, no ambient state beyond the launcher's
# fresh HOME.
set -eu
R=/tmp/cohort3/rustfmt
rm -rf "$R/state"
mkdir -p "$R/state" "$R/home"
cat > "$R/state/probe.rs" <<'EOF'
fn main(){let x=vec![1,2,3];let s:u32=x.iter().sum();println!("{}",s);}
EOF
