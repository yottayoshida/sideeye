#!/bin/sh
set -eu
mkdir -p "/work/spike/unknown-rate/artifacts/inv-todoman/run/a/state/default"
todo new --list default seeded >/dev/null 2>&1
