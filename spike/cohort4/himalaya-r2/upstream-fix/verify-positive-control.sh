#!/bin/sh
# The positive control's claim, made checkable.
#
# The record says run 1 — the frozen case replayed against the stock target —
# reproduces the committed transcript with an empty diff. An empty diff after
# an unpublished normalisation is not a claim anyone can check, so the
# normalisation lives here and this script is what produces the sentence.
#
# Three things are normalised, and only three:
#   - the driver's own `### target:` / `### binary:` header lines, which
#     run-replay.sh prints and the original run did not have;
#   - the minted maildir filename, which io-maildir builds from the clock, a
#     process-local counter, the pid and the hostname, so it cannot repeat —
#     the checker is name-agnostic for exactly this reason;
#   - the per-run work directory, which differs because the two runs were
#     given different --work paths.
#
# Everything else has to match, including the verdict, both crash-point
# classes and their paths, leg D's byte counts, the oracle's operation and
# syscall-line counts, the atomicity path count and the metadata line.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
original=$here/../run1/replay-transcript.txt
mine=$here/replay-stock.txt

for f in "$original" "$mine"; do
    [ -f "$f" ] || { echo "missing: $f" >&2; exit 2; }
done

norm() {
    grep -v '^###' "$1" |
        sed -e 's|[0-9]\{10\}\.#0M[0-9]*P[0-9]*\.[0-9a-f]*|<MINTED>|g' \
            -e 's|/tmp/sideeye-[a-z-]*work|<WORK>|g'
}

# The normalisation must not be able to erase the difference it is meant to
# survive. A control: the two transcripts differ before it runs.
if cmp -s "$original" "$mine"; then
    echo "the two files are byte-identical before normalising — this script is not measuring anything" >&2
    exit 2
fi

# Both sides go to files. The first version of this piped one side in and read
# the other from a here-document, which redirected the same stdin the pipe was
# writing to: `-` and `/dev/stdin` both read the here-document, diff compared it
# with itself, and the check returned ok against a transcript whose verdict line
# had been rewritten. It was found by running the red proof, not by reading it.
t=${TMPDIR:-/tmp}/sideeye-pc-$$
mkdir -p "$t"
trap 'rm -f "$t/a" "$t/b"; rmdir "$t" 2>/dev/null || true' EXIT
norm "$original" > "$t/a"
norm "$mine" > "$t/b"

# Each side must be non-trivial. A normalisation that emptied both files would
# also produce an empty diff.
for side in a b; do
    n=$(grep -c . "$t/$side" || true)
    [ "$n" -ge 20 ] || { echo "normalised side $side has only $n lines — refusing to call that a match" >&2; exit 2; }
done

if diff -u "$t/a" "$t/b"; then
    echo "ok   the positive control reproduces the committed transcript ($(grep -c . "$t/a") lines compared; empty diff after normalising the minted name, the work path and the driver header)"
else
    echo "FAIL the positive control does not reproduce the committed transcript"
    exit 1
fi
