#!/bin/sh
# dotdrop's FAIL counted two violating worlds, and the report, the case and the evidence describe
# the earliest alone (review of this run). This kills the operation at each of its crash points in
# turn — the `reproduce` line's own variables, the shim mounted at /eng — and records what every
# world leaves: each dotfile's size, its `.dotdropbak`'s size, and whether that backup holds the
# bytes the seed wrote (`old` = byte-for-byte the seed's dotfile, compared with cmp). It says
# which worlds hold an empty dotfile and, for each, whether the old bytes survive in the backup.
# Output: /out/dotdrop-worlds/worlds.tsv, copied to transcripts/measure/dotdrop/worlds.tsv.
#
#   docker run --rm --privileged --network none -v <apparatus>:/ap:ro -v <engine-dir>:/eng:ro \
#     -v <out>:/out sideeye-ro684 sh /ap/worlds.sh
set -u
. /ap/env.sh
d=/ap/defines/dotdrop
o=/out/dotdrop-worlds; mkdir -p "$o"
size() { [ -e "$1" ] && wc -c < "$1" | tr -d ' ' || echo "-"; }
# The seed's own bytes, written once by the seed and kept here to compare each backup against.
sh "$d/seed.sh" > /dev/null 2>&1 || { echo "seed failed"; exit 2; }
cp /s/dotdrop/home/.bashrc "$o/seed-bashrc"; cp /s/dotdrop/home/.gitconfig "$o/seed-gitconfig"
same() { [ -e "$1" ] && cmp -s "$1" "$2" && echo old || echo "-"; }
printf 'k\trc\t.bashrc\t.bashrc.dotdropbak\tbackup=old\t.gitconfig\t.gitconfig.dotdropbak\tbackup=old\n' > "$o/worlds.tsv"
for k in $(seq 1 14); do
    sh "$d/seed.sh" > /dev/null 2>&1 || { echo "seed failed"; exit 2; }
    ( cd /s/dotdrop-in && SIDEEYE_STATE_DIR=/s/dotdrop SIDEEYE_TRACE_PATH="$o/trace-$k.bin" \
        LD_PRELOAD=/eng/lib/libsideeye_shim.so SIDEEYE_KILL_AT=$k SIDEEYE_SEQ_BASE= \
        dotdrop install -f -c /s/dotdrop-in/config.yaml -p host > /dev/null 2>&1 )
    rc=$?
    h=/s/dotdrop/home
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$k" "$rc" "$(size $h/.bashrc)" "$(size $h/.bashrc.dotdropbak)" \
        "$(same $h/.bashrc.dotdropbak "$o/seed-bashrc")" "$(size $h/.gitconfig)" "$(size $h/.gitconfig.dotdropbak)" \
        "$(same $h/.gitconfig.dotdropbak "$o/seed-gitconfig")" >> "$o/worlds.tsv"
done
rm -f "$o"/trace-*.bin
cat "$o/worlds.tsv"
