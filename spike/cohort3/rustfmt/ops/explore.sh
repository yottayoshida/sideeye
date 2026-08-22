#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). No apparatus: the probe measured
# byte-determinism, zero threads and zero children on the stock tool;
# HOME points at a fresh ambient dir, mirroring the probe.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export HOME=/tmp/cohort3/rustfmt/home
mkdir -p /tmp/cohort3/rustfmt/home
cd "$here"
exec /work/zig-out/bin/sideeye explore --config rustfmt-format.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
