#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). The ambient env is the probe's; the
# operation child inherits it from the engine.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export HOME=/tmp/cohort2/bun/ambient/home
export BUN_INSTALL_CACHE_DIR=/tmp/cohort2/bun/ambient/cache
export TMPDIR=/tmp/cohort2/bun/ambient/tmp
mkdir -p /tmp/cohort2/bun/state "$HOME" "$BUN_INSTALL_CACHE_DIR" "$TMPDIR"
cd "$here"
exec /work/zig-out/bin/sideeye explore --config bun-add.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
