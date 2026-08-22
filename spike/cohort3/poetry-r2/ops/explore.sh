#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). All apparatus is configuration, poetry's
# own documented switches: no virtualenv (the probe measured 0 threads
# and 0 clones under it for this operation), cache/config at declared
# ambient paths, the null keyring by its fully-qualified name. HOME
# fresh, mirroring the probe.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export POETRY_CACHE_DIR=/tmp/cohort3/poetry-r2/pcache
export POETRY_CONFIG_DIR=/tmp/cohort3/poetry-r2/pconfig
export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
export POETRY_VIRTUALENVS_CREATE=false
export HOME=/tmp/cohort3/poetry-r2/home
mkdir -p /tmp/cohort3/poetry-r2
cd "$here"
exec /work/zig-out/bin/sideeye explore --config poetry-version.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
