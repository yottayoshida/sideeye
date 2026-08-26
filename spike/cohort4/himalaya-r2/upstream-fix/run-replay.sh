#!/bin/sh
# HISTORICAL AS OF trace contract v11 (2026-08-26, #244): this script replays a
# v10 case, so a current engine answers `contract_version_mismatch` before it
# reaches anything else — the freeze's promised behaviour for a saved case across
# a contract bump, not a regression. Re-running the measurement it recorded needs
# the engine of that day. Its apparatus is superseded and now collides with the
# shim as well; ../ops/himalaya-copy.toml carries the full note.
#
# Replay the frozen cohort-4 himalaya case inside the cohort image.
#
# The environment is himalaya-r2's ops/explore.sh, byte for byte in what it
# sets: HOME, XDG_CONFIG_HOME, and no-accel-copy.so in /etc/ld.so.preload so
# fs::copy's accelerated primitives are answered in userspace and never reach
# the kernel where the oracle would see a syscall it does not model. The
# seccomp profile is NOT applied, for the reason r2 exists.
#
# Only the engine subcommand differs: `replay <case>` instead of `explore`.
set -eu
ops=/work/spike/cohort4/himalaya-r2/ops
export HOME=/tmp/cohort4/himalaya/home
export XDG_CONFIG_HOME=/tmp/cohort4/himalaya/xdg
mkdir -p /tmp/cohort4/himalaya
cc -shared -fPIC -o /tmp/no-accel-copy.so "$ops/no-accel-copy.c"
echo /tmp/no-accel-copy.so > /etc/ld.so.preload
cd "$ops"
echo "### target: $(himalaya --version | head -1)"
echo "### binary: $(sha256sum /usr/local/bin/himalaya | cut -c1-16)"
echo "###"
exec /work/zig-out/bin/sideeye replay \
    /work/spike/cohort4/himalaya-r2/run1/work/cases/000001.json \
    --shim /work/zig-out/lib/libsideeye_shim.so \
    --oracle /usr/bin/strace \
    --work /tmp/sideeye-replay-work \
    "$@"
