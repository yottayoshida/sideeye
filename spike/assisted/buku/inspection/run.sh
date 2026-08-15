#!/bin/sh
# The exact in-container launcher for the instrumented re-run cited by the
# Correction section of ../RUNLOG.md. Run from the cohort image with the
# repository mounted at /work and this directory mounted at /inv:
#
#   docker run --rm -v <repo>:/work -v <this dir>:/inv sideeye-assisted /inv/run.sh
#
# The environment matches ops/explore.sh, the committed launcher this
# replicates (R1 of the cohort: the toml alone does not carry the environment
# the operation child inherits from the engine).
set -eu
export HOME=/tmp/assisted/home
export XDG_DATA_HOME=/tmp/assisted/buku/state
mkdir -p /tmp/assisted/buku/state "$HOME"
rm -f /inv/worlds.log /inv/n
cd /inv
/work/zig-out/bin/sideeye version > /inv/engine-version.txt 2>&1
rc=0
/work/zig-out/bin/sideeye explore --config inv.toml \
    --shim /work/zig-out/lib/libsideeye_shim.so > /inv/explore-transcript.txt 2>&1 || rc=$?
echo "explore exit code: $rc" >> /inv/explore-transcript.txt
ls -R /tmp/sideeye-work > /inv/workdir-listing.txt 2>&1
# The engine prints its report to stdout (a report.json exists only under
# --json, deliberately not passed): the transcript above carries the verdict.
[ -f /tmp/sideeye-work/cases/000001.json ] && cp /tmp/sideeye-work/cases/000001.json /inv/case-000001.json
exit 0
