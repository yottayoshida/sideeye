#!/bin/sh
# ADR 0109's cost reading: what restoring permission bits adds to every world. One explore over a
# state of 2,000 small files (toy-fixed, five worlds, --allow-unverified), on the engine before
# #678 (/old) and after (/new), three pairs alternated. Wall clock, in the sideeye-spike container:
#
#   docker run --rm --network none -v <repo>:/work -v <old zig-out>:/old:ro -v <new zig-out>:/new:ro \
#       sideeye-spike sh -c 'sh /work/spike/build-toys.sh >/dev/null && sh /work/<this file>'
set -u
OUT=/work/spike/out
run() { # <engine dir> <label>
    rm -rf /tmp/c && mkdir -p /tmp/c/state/many
    i=0; while [ $i -lt 2000 ]; do printf 'x%d\n' $i > /tmp/c/state/many/f$i; i=$((i+1)); done
    s=$(date +%s.%N)
    "$1/bin/sideeye" explore --state /tmp/c/state --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
        --shim "$1/lib/libsideeye_shim.so" --work /tmp/c/work --allow-unverified > /tmp/c/out.txt 2>&1
    rc=$?; e=$(date +%s.%N)
    echo "$2 rc=$rc $(head -1 /tmp/c/out.txt | cut -c1-48) seconds=$(python3 -c "print(round($e-$s,2))")"
}
echo "before engine sha256: $(sha256sum /old/bin/sideeye | cut -c1-64)"
echo "after engine sha256: $(sha256sum /new/bin/sideeye | cut -c1-64)"
for k in 1 2 3; do run /old before; run /new after; done
