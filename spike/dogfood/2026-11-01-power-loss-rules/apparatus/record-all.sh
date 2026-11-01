#!/bin/sh
# Host side: every row of targets.tsv, then the three controls, each in a box of its own, as the
# records ran (privileged, a private cgroup namespace, no network).
#   TODO_DIR=<unpacked todo.txt-cli 2.14.0> sh record-all.sh [define ...]
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"; repo="$(cd "$run/../../.." && pwd)"
: "${TODO_DIR:?}"
mkdir -p "$run/transcripts"
box() { # <image> <apparatus dir> <define dir in the box> <name>
    docker run --rm --privileged --cgroupns=private --network none \
        -v "$2":/ap:ro -v "$here/record.sh":/rec.sh:ro -v "$here/rec-define.py":/rec-define.py:ro \
        -v "$TODO_DIR":/opt/todo:ro -v "$run/transcripts":/out "$1" sh /rec.sh "$3" "$4" </dev/null
}
want() { [ "$1" -eq 0 ] && return 0; case " $2 " in *" $3 "*) return 0 ;; esac; return 1; }
grep -v '^#' "$here/targets.tsv" | while IFS="$(printf '\t')" read -r row tool camp image def ap; do
    want $# "$*" "$def" || continue
    box "$image" "$repo/$ap" "/ap/defines/$def" "$def"
done
for c in nosync syncfile sync; do
    want $# "$*" "control-$c" || continue
    box sideeye-ud1007 "$here" "/ap/controls/$c" "control-$c"
done
