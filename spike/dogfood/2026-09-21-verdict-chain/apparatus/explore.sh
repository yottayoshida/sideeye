#!/bin/sh
# One explore, in the image that installed Sideeye through the vendored script (#620's path).
#
#   sh explore.sh <name>            # apparatus/ is mounted read-only at /ap, /out collects
#
# **The engine is whatever `/install.path` names.** That file is the installer's stdout,
# written at image build time. Reading it here rather than hard-coding a path is what ties
# this verdict to the adoption step: the report carries no engine version (only
# `contract_version`, which a local build shares), so a hard-coded path would let a
# hand-built binary produce a verdict this record would then attribute to the release.
#
# `--network none`: the install needed the network, the exploration does not.
set -eu
name=${1:?usage: explore.sh <name>}
SE=$(cat /install.path)
OUT=/out
R=/localrun
mkdir -p "$R" "$OUT"
cp /ap/sideeye.toml /ap/seed-state.sh /ap/verify.sh "$R/"
chmod 755 "$R/seed-state.sh" "$R/verify.sh"
cd "$R"

# The engine this record is about, named in the transcript before anything it says is used.
{ "$SE" version; echo "engine path: $SE"; } | tee "$OUT/$name.engine.txt"

export OC_REPO=/tmp/oc-repo
export OC_HOOKS=/tmp/oc-repo/.git/hooks

# The repository has to exist before the engine starts: `cwd` is resolved ahead of the
# state directory's mkdir, on purpose ("a define naming a directory that is not there must
# refuse before anything on disk has moved", src/main.zig), so a `cwd` the define's own
# setup would create can never resolve. That is #647, found by the campaign before this one
# and deliberately not repaired here — a run that fixes what it measures cannot report it.
sh /ap/seed-state.sh
# The engine's own status, not the pipeline's: `$?` after a pipe is `tee`'s, and this is a
# shell without `pipefail`. An UNKNOWN exits 2 and printing 0 beside it would be the
# record's own silent wrong answer.
set +e
timeout 1800 "$SE" explore --config "$R/sideeye.toml" \
    --oracle /usr/bin/strace --observe syscalls \
    --work /tmp/se-work --json "$OUT/$name.json" > "$OUT/$name.txt" 2>&1
rc=$?
set -e
cat "$OUT/$name.txt"
echo "explore exit: $rc"
