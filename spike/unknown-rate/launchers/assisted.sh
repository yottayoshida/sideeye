#!/bin/sh
# A-group launcher for the assisted-cohort defines (#84 sweep). The cohort
# already ships its own committed launchers (spike/assisted/<t>/ops/
# explore.sh — they exist because "the toml alone does not carry the
# environment the operation child inherits"), so this wrapper adds nothing
# but the strict-oracle flag and the report path, exactly the invocation
# REMEASURE.md records. pass is the control trial and runs the same way.
#
# Usage: assisted.sh <buku|calcurse|devtodo|stow|pass> <artifact-dir>
set -u
tool=${1:?tool}; art=${2:?artifact dir}
mkdir -p "$art" || exit 3
/work/spike/assisted/"$tool"/ops/explore.sh \
    --oracle /usr/bin/strace --json "$art/report.json" \
    > "$art/transcript.txt" 2>&1
rc=$?
echo "assisted/$tool exit=$rc"
exit $rc
