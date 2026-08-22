#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). One piece of declared apparatus beyond
# r1's: RUSTC points at the stand-in setup generates (owner-approved,
# proposals.md here) — it reaches setup and the operation from the
# engine's environment, and the checker drops it. CARGO_HOME is the
# ambient client state the probe declared.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export CARGO_HOME=/tmp/cohort3/cargo-r2/home
export RUSTC=/tmp/cohort3/cargo-r2/rustc-standin
mkdir -p /tmp/cohort3/cargo-r2
cd "$here"
exec /work/zig-out/bin/sideeye explore --config cargo-add.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
