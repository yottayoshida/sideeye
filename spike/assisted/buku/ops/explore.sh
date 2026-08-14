#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run — R1: the toml alone does not carry the
# environment the operation child inherits from the engine).
set -eu
export HOME=/tmp/assisted/home
export XDG_DATA_HOME=/tmp/assisted/buku/state
mkdir -p /tmp/assisted/buku/state "$HOME"
here=$(cd "$(dirname "$0")" && pwd)
cd "$here"
exec /work/zig-out/bin/sideeye explore --config buku-add.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so "$@"
