#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). The three-piece apparatus (#200,
# owner-approved) is installed here: libfaketime system-wide via
# ld.so.preload (additive with the engine's LD_PRELOAD of the sideeye
# shim), FAKETIME frozen at speed x0 (realtime only — monotonic stays
# real so nothing sleeps forever), and PYTHONPATH to the sitecustomize
# setup generates (time.monotonic and os.urandom pinned, Python-scoped).
# The operation child inherits all of it from the engine.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
FTLIB=$(find /usr/lib -name "libfaketime.so.1" | head -1)
[ -n "$FTLIB" ] || { echo "SETUP: libfaketime not in the image" >&2; exit 3; }
echo "$FTLIB" > /etc/ld.so.preload
export FAKETIME="@2026-01-01 00:00:00 x0"
export PYTHONPATH=/tmp/cohort2/borg/pylib
export BORG_BASE_DIR=/tmp/cohort2/borg/ambient
mkdir -p /tmp/cohort2/borg/state
cd "$here"
exec /work/zig-out/bin/sideeye explore --config borg-create.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
