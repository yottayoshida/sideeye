#!/bin/sh
# A-group launcher for the cohort defines (#239). Each cohort target ships
# its own committed ops/explore.sh — those exist because the toml alone does
# not carry the environment the operation child inherits (pinned HGRCPATH, a
# sitecustomize on PYTHONPATH, a preloaded library) — so this wrapper adds
# the report path and nothing else, the same shape assisted.sh has for the
# same reason.
#
# The strict-oracle flag is NOT added here: all eight committed explore.sh
# scripts already pass --oracle /usr/bin/strace themselves, and all eight
# forward "$@" — read from the eight committed files on 2026-08-26, not
# measured from a run of them. Passing it again would hand the engine a
# duplicate argument, and silently relying on the wrapper instead would hide
# a define that stopped passing it.
#
# Usage: cohort.sh <cohort2|cohort3|cohort4> <target-dir> <artifact-dir>
set -u
cohort=${1:?cohort}; target=${2:?target dir}; art=${3:?artifact dir}
mkdir -p "$art" || exit 3
/work/spike/"$cohort"/"$target"/ops/explore.sh \
    --json "$art/report.json" \
    > "$art/transcript.txt" 2>&1
rc=$?
echo "$cohort/$target exit=$rc"
exit $rc
