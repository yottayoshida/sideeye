#!/bin/sh
# Cohort-3 cargo define (spike/cohort3/cargo-r2/ops/setup.sh), paths moved under the root the
# driver exports as CARGO_ROOT, and without the RUSTC stand-in: this is the plain target. The
# project, the local dependency it will add, and a warm CARGO_HOME (generate-lockfile alone
# creates the caches — measured for r2, proposals.md there). Everything is rebuilt from scratch
# on every call, so a world starts from the same bytes.
set -eu
C=${CARGO_ROOT:?setup needs CARGO_ROOT}
rm -rf "$C/state" "$C/depcrate" "$C/home"
mkdir -p "$C/state/src" "$C/depcrate/src" "$C/home"
cat > "$C/state/Cargo.toml" <<'EOF'
[package]
name = "app"
version = "0.1.0"
edition = "2021"
EOF
printf 'pub fn probe() -> u32 { 42 }\n' > "$C/state/src/lib.rs"
cat > "$C/depcrate/Cargo.toml" <<'EOF'
[package]
name = "depcrate"
version = "0.1.0"
edition = "2021"
EOF
printf 'pub fn dep() -> u32 { 7 }\n' > "$C/depcrate/src/lib.rs"
export CARGO_HOME="$C/home"
cargo generate-lockfile --offline --manifest-path "$C/state/Cargo.toml"
