#!/bin/sh
# The #84 sweep: runs every corpus.tsv trial fresh, one container per
# invocation, and writes the manifest the published tables are recomputed
# from. Host-side (drives docker); the launchers under launchers/ run
# inside. This is an OPEN measurement — no seals, no blindness claims; what
# it borrows from the campaign discipline is only the honesty machinery:
# fresh roots, refuse-don't-overwrite, apparatus identity recorded per
# trial, raw exit codes read before any pipe.
#
# Usage: sweep.sh            (refuses if artifacts/ already exists)
#
# Manifest columns (tab-separated, artifacts/manifest.tsv):
#   trial_id group tool class judge image_id launcher_argv define_digest
#   report_path launcher_rc
# define_digest = sha256 over the sorted "sha256  path" lines of every file
# the corpus row's `defines` column names, computed from the CLEAN worktree
# this sweep ran (count.py recomputes it from the checkout and must agree).
set -u

here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/../.." && pwd)
ARTS=$here/artifacts

if [ -e "$ARTS" ]; then
    echo "sweep: $ARTS already exists — a sweep never overwrites its predecessor" >&2
    exit 2
fi

# The defines are hashed from this worktree; an unclean tree would make
# "verbatim" unprovable. artifacts/ itself is created below, after this check.
if [ -n "$(cd "$ROOT" && git status --porcelain)" ]; then
    echo "sweep: worktree not clean — the define digests would not match any commit" >&2
    exit 2
fi

echo "sweep: building the Linux engine + shim"
(cd "$ROOT" && zig build -Dtarget=aarch64-linux-gnu) || exit 2

echo "sweep: building the three images"
docker build -q -t sideeye-ur-campaign -f "$ROOT/spike/Dockerfile" "$ROOT/spike" || exit 2
docker build -q -t sideeye-ur-assisted -f "$ROOT/spike/assisted/Dockerfile" "$ROOT/spike/assisted" || exit 2
docker build -q -t sideeye-ur-extra -f "$here/Dockerfile" "$here" || exit 2

# This mkdir is load-bearing for the ro mounts below: the artifacts dir is
# the nested rw mountpoint inside the read-only /work bind, and docker
# cannot create a missing mountpoint on a read-only rootfs (measured — the
# smoke without this dir failed with EROFS at container create).
mkdir -p "$ARTS"

# Apparatus identity, recorded from inside a container (the binary is a
# Linux cross-build; the host cannot even run it).
docker run --rm -v "$ROOT":/work:ro sideeye-ur-extra sh -c '
  /work/zig-out/bin/sideeye 2>&1 | head -1
  sha256sum /work/zig-out/bin/sideeye /work/zig-out/lib/libsideeye_shim.so
' > "$ARTS/apparatus.txt" 2>&1 || { echo "sweep: engine identity capture failed" >&2; exit 2; }
grep -q "^sideeye " "$ARTS/apparatus.txt" || {
    echo "sweep: the engine did not print its banner — wrong-platform build?" >&2; exit 2; }
{ echo "head: $(cd "$ROOT" && git rev-parse HEAD)"
  docker images --no-trunc --format '{{.Repository}} {{.ID}}' \
      | grep -E '^sideeye-ur-' ; } >> "$ARTS/apparatus.txt"

image_for() {
    case "$1" in
      campaign.sh) echo sideeye-ur-campaign ;;
      assisted.sh) echo sideeye-ur-assisted ;;
      watson.sh|dogfood.sh|bgroup.sh) echo sideeye-ur-extra ;;
      *) return 1 ;;
    esac
}

digest_for() {
    # $1 = ;-separated repo-relative paths (file or directory). A path that
    # does not exist is an apparatus error, never an empty digest — an empty
    # hash would read as "hashed and clean". The caller must capture with
    # `d=$(digest_for …) || exit 2`: a bare command substitution inside
    # printf would swallow the failure (R1 measured the sweep finishing
    # rc=0 over an empty digest column).
    out=$(cd "$ROOT" && for p in $(printf '%s' "$1" | tr ';' ' '); do
        [ -e "$p" ] || { echo "MISSING:$p"; exit 9; }
        if [ -d "$p" ]; then find "$p" -type f -exec sha256sum {} +
        else sha256sum "$p"; fi
    done)
    case "$out" in ""|MISSING:*|*"MISSING:"*)
        echo "sweep: define path missing while hashing: $1" >&2; return 1 ;;
    esac
    printf '%s\n' "$out" | sort | sha256sum | cut -d' ' -f1
}

manifest=$ARTS/manifest.tsv
: > "$manifest"
ran=""   # invocation dedup: dogfood runs once, registers two trials

# No pipeline around this loop: a `grep | while` subshell would swallow both
# the dedup state and any `exit` (measured class in this workspace — pipes
# hide failures).
corpus_stripped=$ARTS/corpus-stripped.tsv
grep -v '^#' "$here/corpus.tsv" > "$corpus_stripped"
while IFS="$(printf '\t')" read -r id group tool class judge launcher args artdir rpath defines; do
    [ -n "$id" ] || continue
    if [ "$launcher" = "-" ]; then
        # Funnel wall: no engine run; the row still reaches the manifest so
        # the funnel table's denominator is asserted, not implied.
        d=$(digest_for "$defines") || exit 2
        printf '%s\t%s\t%s\t%s\t%s\t-\twall:%s\t%s\t-\t-\n' \
            "$id" "$group" "$tool" "$class" "$judge" "$args" "$d" >> "$manifest"
        continue
    fi
    img=$(image_for "$launcher") || { echo "sweep: no image for $launcher" >&2; exit 2; }
    imgid=$(docker images --no-trunc --format '{{.ID}}' "$img" | head -1)
    [ -n "$imgid" ] || { echo "sweep: no image id for $img — build failed upstream?" >&2; exit 2; }
    inv="$launcher $args"
    case " $ran " in *" $inv "*) already=1 ;; *) already=0 ;; esac
    if [ "$already" = 0 ]; then
        ran="$ran $inv"
        echo "sweep: $id — $launcher $args"
        # The repo mounts read-only: the trials drive real Debian packages
        # under crash injection as root, and nothing they do may write into
        # the checkout. Only the artifacts tree is writable (R1 measured a
        # launcher-arg bug creating a directory in the repo root — the ro
        # mount turns that whole class into a loud failure).
        docker run --rm -v "$ROOT":/work:ro \
            -v "$ARTS":/work/spike/unknown-rate/artifacts \
            "$img" \
            /work/spike/unknown-rate/launchers/"$launcher" $args \
            /work/spike/unknown-rate/artifacts/"$artdir"
        lrc=$?
        echo "$lrc" > "$ARTS/$artdir/launcher-rc"
    else
        lrc=$(cat "$ARTS/$artdir/launcher-rc" 2>/dev/null || echo '?')
    fi
    if [ ! -f "$ARTS/$artdir/$rpath" ]; then
        # Fail-closed, the campaign runners' rule: a refusal is a result and
        # still writes a report; a MISSING report is an apparatus failure.
        echo "sweep: $id produced no report at $artdir/$rpath (launcher rc=$lrc)" >&2
        exit 2
    fi
    d=$(digest_for "$defines") || exit 2
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$group" "$tool" "$class" "$judge" "$imgid" "$launcher $args" \
        "$d" "$artdir/$rpath" "$lrc" >> "$manifest"
done < "$corpus_stripped"
rm -f "$corpus_stripped"

rows=$(grep -cv '^#' "$here/corpus.tsv")
mrows=$(wc -l < "$manifest" | tr -d ' ')
echo "sweep: corpus rows=$rows manifest rows=$mrows"
[ "$rows" = "$mrows" ] || { echo "sweep: manifest row count differs from corpus — incomplete sweep" >&2; exit 2; }
echo "sweep: done — artifacts under $ARTS"
