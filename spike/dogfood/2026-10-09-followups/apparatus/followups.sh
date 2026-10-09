#!/bin/sh
# Host side: every follow-up of 2026-10-09, in boxes of their own (sideeye-fu1009).
#   sh apparatus/followups.sh > transcripts/followups.txt 2>&1
#  1. the upstream fixes on the page's path (run.sh: explore, the next step once, replays, evidence):
#     nvim-0125 and nvim-nightly, pymol-debian and pymol-main;
#  2. DwarFS: a plain run of each build (plain.sh), then dwarfsck on what is left;
#  3. the four walls of 2026-10-09 user-data-4, with --observe supervised named (probe-supervised.sh).
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"
mkdir -p "$run/transcripts/explore"
echo "== 1. upstream fixes, the page's path $(date -u +%FT%TZ)"
sh "$here/explore.sh" nvim-0125 nvim-nightly pymol-debian pymol-main
echo "== 2. DwarFS, plain runs $(date -u +%FT%TZ)"
docker run --rm --network none -v "$here":/ap:ro sideeye-fu1009 sh -c '
  for v in 0158 work; do
    sh /ap/plain.sh dwarfs-$v
    ls -l /s/dwarfs
    dwarfsck-0158 -i /s/dwarfs/photos.dwarfs > /tmp/ck.txt 2>&1; echo "dwarfsck after dwarfs-$v: exit $? ($(tail -1 /tmp/ck.txt | cut -c1-100))"
  done
  echo "-- what mkdwarfs-work printed:"; sh /ap/defines/dwarfs-work/seed.sh; cd /s/dwarfs-in
  mkdwarfs-work -i /s/dwarfs/photos.dwarfs -o /s/dwarfs/photos.dwarfs --recompress -f -N 1 -l 3 2>&1 | tail -3; echo "exit $?"'
echo "== 3. the walls, --observe supervised named $(date -u +%FT%TZ)"
for t in kvantum h2cli yarn trash; do
  echo "=== $t $(date -u +%FT%TZ)"
  docker run --rm --privileged --cgroupns=private --network none -v "$here":/ap:ro -v "$run/transcripts/explore":/out sideeye-fu1009 sh /ap/probe-supervised.sh "$t"
  grep -E '^(PASS|FAIL|UNKNOWN|SETUP)' -A1 "$run/transcripts/explore/$t/probe-supervised.txt" | head -2 | cut -c1-200
done
echo "followups: done $(date -u +%FT%TZ)"
