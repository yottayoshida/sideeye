#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). The apparatus it can carry is environment:
# HOME and XDG at declared ambient paths, fresh per setup. The clock and
# pid pins the probe used are deliberately absent; the toml's Versions
# note says why, and the checker is name-agnostic in consequence.
#
# What this script CANNOT carry, and what therefore has to be in the
# invocation around it: the seccomp profile. It applies at the container
# boundary (docker --security-opt seccomp=...), and without it fs::copy
# reaches copy_file_range, which the shim does not export and the oracle
# reports as unsupported. RUNLOG.md records the full docker line.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export HOME=/tmp/cohort4/himalaya/home
export XDG_CONFIG_HOME=/tmp/cohort4/himalaya/xdg
mkdir -p /tmp/cohort4/himalaya
cd "$here"
exec /work/zig-out/bin/sideeye explore --config himalaya-copy.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
