#!/bin/sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"; dogfood="$(dirname "$(dirname "$here")")"
log="$(dirname "$here")/transcripts/build"; mkdir -p "$log"

box_of() {
    case "$1" in
        2026-09-28-shipped-v170) echo sideeye-sv170 ;;
        2026-10-02-unjudged-on-v170) echo sideeye-uj170 ;;
        2026-10-03-user-data) echo sideeye-ud1003 ;;
        2026-10-05-user-data-2) echo sideeye-ud1005 ;;
        2026-10-07-user-data-3) echo sideeye-ud1007 ;;
        2026-10-09-followups-3) echo sideeye-fu3-1009 ;;
        2026-10-09-followups-4) echo sideeye-fu4-1009 ;;
        2026-10-14-mechanisms) echo sideeye-m1014 ;;
        *) return 1 ;;
    esac
}

[ $# -gt 0 ] || set -- 2026-10-14-mechanisms 2026-10-03-user-data 2026-10-05-user-data-2 2026-10-07-user-data-3 \
    2026-10-09-followups-4 2026-10-09-followups-3 2026-09-28-shipped-v170 2026-10-02-unjudged-on-v170
for c in "$@"; do
    box=$(box_of "$c") || { echo "unknown campaign $c" >&2; exit 2; }
    ap="$dogfood/$c/apparatus"
    echo "=== $c -> $box $(date -u +%FT%TZ)"
    # Not through build.sh where there is none: 2026-10-02's box is a layer on the 2026-09-28 one.
    if [ -f "$ap/build.sh" ]; then
        sh "$ap/build.sh" > "$log/$c.base.txt" 2>&1
        rc=$?
        # Not left as build.sh leaves it: it vendors today's installer over that campaign's record.
        git -C "$dogfood" checkout -- "$c/apparatus/install-sideeye.sh"
    else
        docker build -t "$box" "$ap" > "$log/$c.base.txt" 2>&1
        rc=$?
    fi
    echo "base exit $rc"
    # Not `continue`: a <box>-v1150 left from an earlier build would then be measured as if rebuilt.
    [ "$rc" = 0 ] || exit 1
    [ "$c" = 2026-09-28-shipped-v170 ] && continue
    docker build -f "$here/v1150.Dockerfile" --build-arg "BOX=$box" -t "$box-v1150" "$here" > "$log/$c.v1150.txt" 2>&1 || exit 1
    docker run --rm "$box-v1150" sh -c 'cat /install.path; "$(cat /install.path)" version; grep -E "digest matches|sideeye " /install.log' > "$log/$c.engine.txt" 2>&1
    cat "$log/$c.engine.txt"
done
