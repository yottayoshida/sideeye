#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run — the toml alone does not carry the
# environment the operation child inherits from the engine).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# setup generates the pinned hgrc at this path (see setup.sh for why the
# bytes live there); the operation child inherits this environment.
export HGRCPATH=/tmp/cohort2/hg/hgrc
mkdir -p /tmp/cohort2/hg
cd "$here"
exec /work/zig-out/bin/sideeye explore --config hg-commit.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
