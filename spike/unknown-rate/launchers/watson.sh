#!/bin/sh
# A-group launcher for the watson define (#84 sweep). New apparatus, labeled
# as such: unlike the other A-group members, watson's committed define
# (spike/dogfood-watson/sideeye.toml) never had a committed launcher — the
# BUILDLOG run (2026-08-12) drove it by hand with one env var (WATSON_DIR).
# The toml's paths are relative ("./state", "./check.sh") and the engine
# resolves them against the working directory, so this launcher stages a
# byte-verbatim copy of the two committed files in a scratch root and runs
# there. The sweep manifest hashes the staged copies against HEAD's bytes —
# "copied, not edited" is checked, not asserted.
#
# Usage: watson.sh <artifact-dir>
set -u
art=${1:?artifact dir}
SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
src=/work/spike/dogfood-watson
root=/tmp/bwatson

if [ -e "$root" ]; then
    echo "watson.sh: scratch root already exists: $root — fresh container required" >&2
    exit 3
fi
mkdir -p "$root/state" "$art" || exit 3
cp "$src/sideeye.toml" "$src/check.sh" "$root/" || exit 3
chmod 755 "$root/check.sh"

export WATSON_DIR=$root/state
cd "$root" || exit 3
"$SIDEEYE" explore --config ./sideeye.toml \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$root/work" --json "$art/report.json" \
    > "$art/transcript.txt" 2>&1
rc=$?
echo "watson exit=$rc"
exit $rc
