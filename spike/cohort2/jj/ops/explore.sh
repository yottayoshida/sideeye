#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). The JJ_* pins are the probe's, verbatim;
# the operation child inherits this environment from the engine.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export JJ_USER=probe JJ_EMAIL=probe@example.invalid
export JJ_TIMESTAMP=2026-01-01T00:00:00+00:00 JJ_OP_TIMESTAMP=2026-01-01T00:00:00+00:00
export JJ_RANDOMNESS_SEED=42 JJ_OP_HOSTNAME=probe-host JJ_OP_USERNAME=probe-user
export JJ_TZ_OFFSET_MINS=0
export HOME=/tmp/cohort2/jj/home
mkdir -p /tmp/cohort2/jj/repo "$HOME"
cd "$here"
exec /work/zig-out/bin/sideeye explore --config jj-commit.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
