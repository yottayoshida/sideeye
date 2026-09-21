#!/bin/sh
# The three controls that locate the `cwd` line, in ONE run of ONE image so that "same run" is a
# property of the script rather than a claim about file timestamps.
#
#   docker run --rm --privileged --network none -v <apparatus>:/ap:ro -v <transcripts>:/out \
#       sideeye-relpath-probe sh /ap/controls.sh
#
# Why three. Without `cwd` the engine refuses `recording_run_failed` and says only "Change the
# define" — it never names a line. A refusal that could be the shim, the observation mode, or the
# define needs the alternatives removed rather than guessed:
#
#   A  the operation alone           — is the command itself fine?
#   B  the operation + the shim only — does interposition break it?
#   C  the shipped define with the `cwd` line deleted, under the engine
#
# C is the one that names the line, and it is built by deleting exactly one line from the define
# this run shipped, so the difference between "refuses" and "reaches a verdict" is that line and
# nothing else. The generated define is printed into the transcript so a reader can see what C
# actually ran.
set -eu
SE=$(cat /install.path)
OUT=${OUT:-/out}
export LH_REPO=/tmp/lh-repo
mkdir -p /localrun "$OUT"
cp /ap/seed-state.sh /ap/verify.sh /ap/sideeye.toml /localrun/
chmod 755 /localrun/seed-state.sh /localrun/verify.sh

echo "engine: $SE"
"$SE" version

echo "=== control A: lefthook install alone, no engine, no shim ==="
sh /localrun/seed-state.sh
( cd "$LH_REPO" && lefthook install ); echo "exit=$?"

echo "=== control B: the same command with ONLY the shim preloaded ==="
sh /localrun/seed-state.sh
( cd "$LH_REPO" && LD_PRELOAD=$(dirname "$SE")/libsideeye_shim.so lefthook install ); echo "exit=$?"
echo "hooks written:"; ls "$LH_REPO/.git/hooks" | grep -v sample | tr '\n' ' '; echo

echo "=== control C: the shipped define with the cwd line deleted, under the engine ==="
grep -v '^cwd' /localrun/sideeye.toml > /localrun/no-cwd.toml
echo "--- the define control C ran (diff from the shipped one is the cwd line) ---"
grep -vE '^#|^$' /localrun/no-cwd.toml
sh /localrun/seed-state.sh
timeout 900 "$SE" explore --config /localrun/no-cwd.toml --oracle /usr/bin/strace \
    --observe syscalls --work /tmp/se-nocwd --json "$OUT/control-c.json" 2>&1 | head -6
echo "(control C ran under --observe syscalls, the same mode as the run)"
