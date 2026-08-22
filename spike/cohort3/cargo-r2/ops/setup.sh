#!/bin/sh
# Cohort-3 cargo define r2 setup: identical to r1's except the paths and
# three apparatus deltas — it GENERATES the RUSTC stand-in (the bytes
# that decide the question live inside D2-held files) before any cargo
# runs, the rm -rf list gains the stand-in's path (a stale copy must not
# survive a re-run), and the cache-warm metadata call is gone (metadata
# needs more than the stand-in's -vV contract; generate-lockfile alone
# creates the caches — measured, proposals.md here).
set -eu
C=/tmp/cohort3/cargo-r2
rm -rf "$C/state" "$C/depcrate" "$C/home" "$C/rustc-standin"
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
# The stand-in: -vV prints the measured bytes of the image's real
# `rustc -vV` (2026-08-22), inline — no reads outside itself; anything
# else fails loudly with the argv named. cargo add asks for -vV only
# (measured); cargo metadata asks for more and is deliberately NOT
# served — the checker unsets RUSTC and uses the real rustc.
cat > "$C/rustc-standin" <<'EOF'
#!/bin/sh
case " $* " in
    *" -vV "*) cat <<'VV'
rustc 1.98.0 (88d9e12ae 2026-08-18)
binary: rustc
commit-hash: 88d9e12ae178fab0fb5cc050a94da85685d449ea
commit-date: 2026-08-18
host: aarch64-unknown-linux-gnu
release: 1.98.0
LLVM version: 22.1.8
VV
    ;;
    *) echo "rustc-standin: unsupported argv: $*" >&2; exit 90 ;;
esac
EOF
chmod 755 "$C/rustc-standin"
export CARGO_HOME="$C/home"
cargo generate-lockfile --offline --manifest-path "$C/state/Cargo.toml"
