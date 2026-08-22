#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). No clock or entropy apparatus: the probe
# measured byte-determinism on the stock tool. CARGO_HOME rides the
# environment into setup, operation and checker alike — the ambient
# client state the probe declared (condition 7).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export CARGO_HOME=/tmp/cohort3/cargo/home
mkdir -p /tmp/cohort3/cargo
cd "$here"
exec /work/zig-out/bin/sideeye explore --config cargo-add.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
