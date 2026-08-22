#!/bin/sh
# The exact launcher for this define (committed so a fresh checkout can
# reproduce the measured run). All apparatus is configuration, poetry's
# own documented switches: no virtualenv (the probe's thread
# off-switch), cache/config at declared ambient paths, the null keyring
# by its fully-qualified name. HOME fresh, mirroring the probe.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export POETRY_CACHE_DIR=/tmp/cohort3/poetry/pcache
export POETRY_CONFIG_DIR=/tmp/cohort3/poetry/pconfig
export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
export POETRY_VIRTUALENVS_CREATE=false
export HOME=/tmp/cohort3/poetry/home
mkdir -p /tmp/cohort3/poetry
cd "$here"
exec /work/zig-out/bin/sideeye explore --config poetry-add.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace "$@"
