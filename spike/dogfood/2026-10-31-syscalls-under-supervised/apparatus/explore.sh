#!/bin/sh
# Host side: every row of targets.tsv, under syscalls and then supervised, each in a box of
# its own. The same released engine runs both modes, so the two columns differ by mode only.
#   SE_DIR=<unpacked sideeye-v1.17.0-aarch64-linux> TODO_DIR=<unpacked todo.txt-cli 2.14.0> sh explore.sh [name ...]
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"; spike="$(cd "$run/../.." && pwd)"
: "${SE_DIR:?}" "${TODO_DIR:?}"
grep -v '^#' "$here/targets.tsv" | while IFS="$(printf '\t')" read -r row name image ap def; do
  [ $# -gt 0 ] && case " $* " in *" $name "*) ;; *) continue ;; esac
  case "$ap" in apparatus/*) apdir="$run/$ap" ;; *) apdir="$spike/$ap" ;; esac
  for mode in syscalls supervised; do
    docker run --rm --privileged --cgroupns=private --network none \
      -v "$apdir":/ap:ro -v "$here":/run2:ro -v "$SE_DIR":/se:ro -v "$TODO_DIR":/opt/todo:ro \
      -v "$run/transcripts":/out "$image" sh /run2/run.sh "$name" "$def" "$mode" </dev/null
  done
done
