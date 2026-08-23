#!/bin/sh
# The exact launcher for himalaya-r2. Same environment as r1, plus the
# one thing that revision exists for: no-accel-copy.so in
# /etc/ld.so.preload, so fs::copy's accelerated primitives are answered
# in userspace and never reach the kernel where the oracle would see a
# syscall it does not model.
#
# The seccomp profile r1 used is NOT applied here and must not be: it
# made the same calls fail rather than disappear, which is what r1
# refused on. Nothing else about the run changes.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export HOME=/tmp/cohort4/himalaya/home
export XDG_CONFIG_HOME=/tmp/cohort4/himalaya/xdg
mkdir -p /tmp/cohort4/himalaya
cc -shared -fPIC -o /tmp/no-accel-copy.so "$here/no-accel-copy.c"
echo /tmp/no-accel-copy.so > /etc/ld.so.preload
cd "$here"
exec /work/zig-out/bin/sideeye explore --config himalaya-copy.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
