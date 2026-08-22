#!/bin/sh
# Cohort-3 cargo define (P1) setup: the application state (manifest, one
# source file, a lockfile generated offline) plus the outside-root path
# dependency and a warmed ambient CARGO_HOME. Fixture bytes are the probe
# plan's, frozen in PROTOCOL.md. The dep sits as the state root's
# sibling; an absolute --path records the relative entry
# `depcrate = { version = "0.1.0", path = "../depcrate" }` — measured
# 2026-08-22, printed by the green-new drill in checker-drills.txt.
set -eu
C=/tmp/cohort3/cargo
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
# Warm the ambient caches once so every world's operation meets the same
# CARGO_HOME (.global-cache and .package-cache exist before world 1). The
# rustc version probe itself is NOT cached across invocations — measured
# in the probe's forecast — so each world still vforks rustc -vV alike.
cargo metadata --offline --format-version 1 --manifest-path "$C/state/Cargo.toml" > /dev/null
