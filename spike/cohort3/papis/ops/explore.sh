#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). All apparatus is configuration, papis's
# own documented switches: PAPIS_NP=0 (its parmap docstring: setting it
# to 0 disables multiprocessing on all platforms — the scout measured
# 3 threads / 14 clones / 14 pids without it, 0 / 0 / 1 with it),
# XDG config and cache at declared ambient paths, HOME fresh. The
# library's own settings (time-stamp False, use-cache False) ride the
# config setup.sh writes, as in the accepted probe.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export XDG_CONFIG_HOME=/tmp/cohort3/papis/xdg
export XDG_CACHE_HOME=/tmp/cohort3/papis/cache
export HOME=/tmp/cohort3/papis/home
export PAPIS_NP=0
mkdir -p /tmp/cohort3/papis
cd "$here"
exec /work/zig-out/bin/sideeye explore --config papis-add.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
