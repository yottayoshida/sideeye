#!/bin/sh
# The positive control's claim, made checkable.
#
# The record says run 1 — the frozen case replayed against the stock target —
# reproduces the committed transcript with an empty diff. An empty diff after
# an unpublished normalisation is not a claim anyone can check, so the
# normalisation lives here and this script is what produces the sentence.
#
# Three things are normalised, and only three:
#   - the driver's own header block, which run-replay.sh prints and the original
#     run did not have: three lines at the top of the file, `### target:`,
#     `### binary:` and a bare `###`. Removed BY POSITION, after asserting the
#     block is there. An earlier version removed every line beginning `###`
#     wherever it sat, which is a wider operation than the sentence above
#     describes: a `###` line appearing later in either transcript would have
#     been deleted from both sides and the diff would have stayed empty (#318);
#   - the minted maildir filename, which io-maildir builds from the clock, a
#     process-local counter, the pid and the hostname, so it cannot repeat —
#     the checker is name-agnostic for exactly this reason;
#   - the per-run work directory, which differs because the two runs were
#     given different --work paths.
#
# Everything else has to match, including the verdict, both crash-point
# classes and their paths, leg D's byte counts, the oracle's operation and
# syscall-line counts, the atomicity path count and the metadata line.
# `--selftest` is the red proof, and it lives here rather than in the workflow for
# the reason every other check in this repository keeps its own (`check-adr-status.sh`,
# `check-upstream-ledger.sh`, `check-fsusage-coverage.py`): a proof that only exists
# inside a CI step is one nobody runs while changing the thing it proves. The first
# draft of this one was written into ci.yml and had to be extracted from the YAML to
# be run at all.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
original=$here/../run1/replay-transcript.txt
mine=$here/replay-stock.txt

case "${1-}" in
    "") ;;
    --selftest) selftest=1 ;;
    *) echo "usage: $0 [--selftest]" >&2; exit 2 ;;
esac

for f in "$original" "$mine"; do
    [ -f "$f" ] || { echo "missing: $f" >&2; exit 2; }
done

# Two mutations, because one of them proves nothing this script added.
#
#   verdict          a judgment line, which no normalisation touches. This is the proof
#                    the script always deserved — and the normaliser it replaced catches
#                    it too, so on its own it leaves the new guarantee unmeasured.
#   later-hash-line  a `###` line further down. This falsifies the predicate the header
#                    states — three lines, by position, and only those — rather than the
#                    accident that motivated it: the old `grep -v '^###'` deleted such a
#                    line from both sides and reported an empty diff.
#
# Both demand exit 1 with the word FAIL, not merely a non-zero exit: this script exits 2
# for BROKEN, and a proof that accepts 2 reads a jammed instrument as a detection.
if [ "${selftest-}" = 1 ]; then
    w=$(mktemp -d)
    trap 'rm -rf "$w"' EXIT
    mkdir -p "$w/run1" "$w/upstream-fix"
    cp "$original" "$w/run1/replay-transcript.txt"
    cp "$0" "$w/upstream-fix/verify-positive-control.sh"

    prove() {
        name=$1 expect=$2
        # Written without `sed -i`: the in-place flag needs an argument on BSD sed and
        # refuses one on GNU sed, and a proof that runs on only one of them is half a
        # proof.
        cp "$mine" "$w/upstream-fix/replay-stock.txt"
        case $name in
            verdict)
                sed 's/^FAIL  1 of 2 explored worlds/FAIL  2 of 2 explored worlds/' \
                    "$w/upstream-fix/replay-stock.txt" > "$w/m"
                mv "$w/m" "$w/upstream-fix/replay-stock.txt" ;;
            later-hash-line)
                printf '### smuggled: a header-shaped line the driver never printed\n' \
                    >> "$w/upstream-fix/replay-stock.txt" ;;
        esac
        grep -q "$expect" "$w/upstream-fix/replay-stock.txt" \
            || { echo "$name: the mutation did not apply — this would have measured nothing" >&2; exit 2; }
        set +e
        out=$(sh "$w/upstream-fix/verify-positive-control.sh" 2>&1); rc=$?
        set -e
        printf '%s\n' "$out" | sed "s/^/     $name | /"
        [ "$rc" = 1 ] || { echo "$name: wanted exit 1 (FAIL), got $rc" >&2; exit 1; }
        printf '%s\n' "$out" | grep -q '^FAIL the positive control does not reproduce' \
            || { echo "$name: exit 1 without the FAIL sentence — not the failure this proves" >&2; exit 1; }
        echo "ok   $name is caught, with exit 1 and the FAIL sentence"
    }

    prove verdict         '^FAIL  2 of 2 explored worlds'
    prove later-hash-line '^### smuggled: '
    exit 0
fi

# The driver's header block: three lines, at the top, in this order.
# run-replay.sh:26-28 prints them and nothing else in either transcript does.
driver_header_lines=3

# The digest line is pinned to its length as well as its alphabet: run-replay.sh
# builds it with `cut -c1-16`, so exactly sixteen hex characters after a
# twelve-character prefix, and `### binary: a` is a line the driver cannot have
# produced. Written as a length test rather than an `{16}` interval, which is an
# ERE extension some awks lower to a literal brace.
has_driver_header() {
    head -n "$driver_header_lines" "$1" | awk '
        NR == 1 && /^### target: ./                                   { n++ }
        NR == 2 && /^### binary: [0-9a-f]+$/ && length($0) == 12 + 16 { n++ }
        NR == 3 && $0 == "###"                                        { n++ }
        END { exit(n == 3 ? 0 : 1) }
    '
}

# Which side carries the block is part of what this script compares, so it is
# asserted rather than discovered. Getting it backwards would mean the "original"
# was produced by the driver too, which is a different measurement.
if ! has_driver_header "$mine"; then
    echo "$mine does not open with the driver's three-line header — the normalisation this script declares does not apply to it" >&2
    exit 2
fi
if has_driver_header "$original"; then
    echo "$original opens with the driver's header, which the committed original does not have — these are not the two things this script compares" >&2
    exit 2
fi

strip_driver_header() {
    if has_driver_header "$1"; then
        tail -n "+$((driver_header_lines + 1))" "$1"
    else
        cat "$1"
    fi
}

norm() {
    strip_driver_header "$1" |
        sed -e 's|[0-9]\{10\}\.#0M[0-9]*P[0-9]*\.[0-9a-f]*|<MINTED>|g' \
            -e 's|/tmp/sideeye-[a-z-]*work|<WORK>|g'
}

# The normalisation must not be able to erase the difference it is meant to
# survive. A control: the two transcripts differ before it runs.
#
# Taken with the driver header already off, and that is the whole point of where
# it sits. The raw files cannot be byte-identical any more — the assertions above
# require the block on one side and forbid it on the other — so a raw `cmp` here
# would be a control that can no longer fail, which is not a control. What is
# still worth asserting is that the two `sed` expressions have something to do:
# the minted name and the work path differ between the two runs, and if they ever
# stopped differing this script would be comparing a file with itself.
#
# `$original` is asserted above to carry no header, so stripping it is a no-op and
# only one side needs to go through the filter. Compared byte for byte rather than
# by digest: a control that answers "the same" on a hash collision is a worse
# control than the one it replaced.
if strip_driver_header "$mine" | cmp -s - "$original"; then
    echo "the two transcripts are identical once the driver header is off — the remaining normalisation would have nothing to survive, so this script is not measuring anything" >&2
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
