#!/bin/sh
# Host side: every define in a box of its own (run.sh), then one line per define in transcripts/summary.tsv.
#   sh apparatus/measure.sh
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"; tr="$run/transcripts"
mkdir -p "$tr"
printf 'side\ttarget\tresult\n' > "$tr/summary.tsv"
for side in none with; do
  for t in $(ls "$here/defines/$side"); do
    echo "=== $side $t $(date -u +%FT%TZ)"
    docker run --rm --privileged --cgroupns=private --network none -v "$here":/ap:ro -v "$tr":/out sideeye-uv-1010 sh /ap/run.sh "$side" "$t"
    printf '%s\t%s\t%s\n' "$side" "$t" "$(tr '\n' ';' < "$tr/$side/$t/summary.txt")" >> "$tr/summary.tsv"
  done
done
cat "$tr/summary.tsv"
