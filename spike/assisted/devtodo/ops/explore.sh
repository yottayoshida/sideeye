#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run — R1: the toml alone does not carry the
# environment the operation child inherits from the engine).
set -eu
export HOME=/tmp/assisted/home
export TERM=vt100
mkdir -p /tmp/assisted/devtodo/state "$HOME"
here=$(cd "$(dirname "$0")" && pwd)
cd "$here"
exec /work/zig-out/bin/sideeye explore --config devtodo-remove.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so "$@"
