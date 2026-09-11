#!/bin/sh
# #542, first of two: mlr past `epoll_ctl`. Six explorations of the same define — one, and
# the five-run determinism check followup-item4 ran — against whichever sideeye build is
# mounted at /se.
#
# Image: sideeye-reach:2026-09-07, built from spike/followup-item4/Dockerfile. This
# directory is mounted at /d and the transcripts land in /d/transcripts. State and work
# live on the container's own filesystem (#528: a macOS bind mount resolves a restored
# file's /proc/self/fd/N to " (deleted)" and refuses for nothing the target did), under
# /tmp so a run as an unprivileged --user can create them.
#
# Usage: mlr.sh <label>   — before | after: which build is mounted, written into every
# transcript name so the two are never confused.
set -u
label=${1:?usage: mlr.sh <before|after>}
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
        --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/$i" \
        --json "$OUT/mlr.$label.$i.json" > "$OUT/mlr.$label.$i.txt" 2>&1
    rc=$?
    echo "run $i rc=$rc: $(head -2 "$OUT/mlr.$label.$i.txt" | tr -s ' \n' ' ')"
done
