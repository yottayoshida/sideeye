#!/bin/sh
# A-group launcher for the watson define (#84 sweep). New apparatus, labeled
# as such: unlike the other A-group members, watson's committed define
# (spike/dogfood-watson/sideeye.toml) never had a committed launcher — the
# BUILDLOG run (2026-08-12) drove it by hand with one env var (WATSON_DIR).
# The toml's paths are relative ("./state", "./check.sh") and resolve
# against the toml's own directory (ADR 0007), so this launcher stages a
# copy of the two committed files in a scratch root and runs there —
# running the committed file in place would put ./state and ./work inside
# the repository.
#
# Usage: watson.sh <tool> <artifact-dir>   (tool is always "watson"; the
# two-argument shape matches every other launcher so the sweep's
# "$launcher $args <artdir>" expansion needs no special case — R1 measured
# the one-argument version receiving "-" as its artifact dir)
#
# What is and is not checked about the staging: the manifest's define
# digest covers the CHECKOUT originals; the staged copies' hashes are
# recorded separately in staged-sha256.txt beside the report. A reader can
# compare the two records; nothing compares them automatically — the copy
# step itself is cp.
set -u
tool=${1:?tool}; art=${2:?artifact dir}
[ "$tool" = watson ] || { echo "watson.sh: only watson lives here, got: $tool" >&2; exit 3; }
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
# The staged copies' hashes go beside the report so "copied, not edited" is
# a recorded fact about what actually ran, not an inference from cp.
sha256sum "$root/sideeye.toml" "$root/check.sh" > "$art/staged-sha256.txt" || exit 3

export WATSON_DIR=$root/state
cd "$root" || exit 3
"$SIDEEYE" explore --config ./sideeye.toml \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$root/work" --json "$art/report.json" \
    > "$art/transcript.txt" 2>&1
rc=$?
echo "watson exit=$rc"
exit $rc
