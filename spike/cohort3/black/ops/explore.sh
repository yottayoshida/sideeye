#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). No apparatus at all: the probe measured
# byte-determinism, zero threads and zero children on the stock tool;
# HOME points at a fresh ambient dir, mirroring the probe's condition-7
# declaration.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export HOME=/tmp/cohort3/black/home
mkdir -p /tmp/cohort3/black/home
cd "$here"
exec /work/zig-out/bin/sideeye explore --config black-format.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
