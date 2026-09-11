#!/bin/sh
# #542, second of two: mlr under `--observe syscalls`, with the widened trap set.
#
# The define is the one the first change left refusing. After that change mlr reached its
# real wall — `oracle_missed_operation` at the `openat` of `mlr-in-place-*`, six runs of
# six — because mlr is Go and issues its file syscalls without passing through libc, so no
# interposed wrapper sees any of them. This script runs the SAME define in the SAME image
# with the trap set widened from the write family to every kill point, and the question it
# answers is the one #542 asks: how many writers does mlr have.
#
# Six runs, not one: the first change's transcripts were six, so the two are comparable
# run for run, and a count that moves between runs is the thing a single run would hide.
#
# Image: sideeye-reach:2026-09-07, built from spike/followup-item4/Dockerfile. This
# directory is mounted at /d and the transcripts land in /d/transcripts. State and work
# live on the container's own filesystem (#528: a macOS bind mount resolves a restored
# file's /proc/self/fd/N to " (deleted)" and refuses for nothing the target did), under
# /tmp so a run as an unprivileged --user can create them.
#
# Usage: mlr.sh <label> [mode]   — label goes into every transcript name so builds are
# never confused; mode defaults to `syscalls` and may be `wrappers` for the comparison.
set -u
label=${1:?usage: mlr.sh <label> [syscalls|wrappers]}
mode=${2:-syscalls}
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/tmp/localrun
OUT=/d/transcripts
mkdir -p "$OUT" "$R/ap"
"$SE" version
mlr --version

cat > "$R/ap/setup.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"; printf 'a,b\n1,2\n3,4\n' > "$SD/f.csv"
EOX
cat > "$R/ap/check.sh" <<'EOX'
#!/bin/sh
[ -f "$SD/f.csv" ] || { echo "f.csv is gone"; exit 1; }
[ "$(wc -l < "$SD/f.csv")" -ge 3 ] || { echo "f.csv lost rows ($(wc -l < "$SD/f.csv") lines)"; exit 1; }
exit 0
EOX
chmod 755 "$R/ap/setup.sh" "$R/ap/check.sh"

for i in 1 2 3 4 5 6; do
    SD=$R/st/$i/mlr
    export SD
    mkdir -p "$SD" "$R/wk/$i"
    "$SE" explore --state "$SD" --setup "$R/ap/setup.sh" \
        --operation "mlr -I --csv put \$c=1 $SD/f.csv" --check "$R/ap/check.sh" \
        --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" --work "$R/wk/$i" \
        --json "$OUT/mlr.$label.$mode.$i.json" > "$OUT/mlr.$label.$mode.$i.txt" 2>&1
    rc=$?
    echo "run $i rc=$rc: $(head -2 "$OUT/mlr.$label.$mode.$i.txt" | tr -s ' \n' ' ')"
done
