#!/bin/sh
# The scale benchmark's two legs outside the grid (#621, ADR 0081 and 0082).
#
#   sh run-anchor.sh <engine> <toy-bug> <out.tsv> [oracle]
#
# The grid measures one synthetic target, which answers how cost scales but not whether that
# target resembles anything. #621 asks for two things the grid cannot produce:
#
#   * a **real-target anchor** — "the synthetic slope is the controlled result; the real target
#     checks that the toy has not omitted a dominant cost present in ordinary use";
#   * the **saved case size** "when the run is configured to produce one deterministic FAIL",
#     which the scale toy cannot give because it PASSes by construction.
#
# Both legs go through `run-cell.py`, so they are the same row, the same not-counted rule, the
# same RSS method and the same oracle requirement as every grid cell. The anchor rows leave the
# request columns empty: nobody asked timewarrior for a crash-point count — its own operation
# decides, and the reported count is what the engine says it found.
#
# The define is `spike/dogfood-timew.sh` leg (a), re-pathed the way
# `spike/explore-cost/measure-targets.sh` re-paths it: one `timew track` seeds the database,
# one `timew track` is the recorded operation, no checker, `TIMEWARRIORDB` pointed at the
# resolved state directory. **The checker-less leg is deliberate.** Every candidate in that
# script that has a checker compares against a backup file *outside* the judged state, which
# would mean either changing what is judged or declaring apparatus — neither belongs in a run
# whose whole job is to be an ordinary one.
#
# `toy-bug` is `spike/toys/toy.c` built `-DBUGGY=1`, the same pair `measure-targets.sh` uses,
# so the two records meet. It deletes the old file before renaming the new one into place, so a
# kill in that window leaves neither: the built-in atomicity form catches it with no checker and
# the report saves a case. That is where `case_bytes` comes from — every grid row has 0.
#
# **This existed only as typed commands when the figures were first published**, and blind
# review caught it. An apparatus page that demands the grid be reproducible owes the same to the
# two rows it quotes most.
#
# This is an apparatus, not a check. It is not wired into CI, for the reason
# `.github/workflows/spike-fsusage.yml` gives about itself: a measurement is run deliberately.
set -eu

engine=${1:?usage: run-anchor.sh <engine> <toy-bug> <out.tsv> [oracle]}
toybug=${2:?usage: run-anchor.sh <engine> <toy-bug> <out.tsv> [oracle]}
out=${3:?usage: run-anchor.sh <engine> <toy-bug> <out.tsv> [oracle]}
oracle=${4:-/usr/bin/strace}
here=$(cd "$(dirname "$0")" && pwd)

[ -x "$engine" ] || { echo "no engine at $engine" >&2; exit 2; }
[ -x "$toybug" ] || { echo "no toy-bug at $toybug (build it with -DBUGGY=1)" >&2; exit 2; }
[ -x "$oracle" ] || { echo "no oracle at $oracle — the anchor measures under the grid's oracle" >&2; exit 2; }
command -v timew >/dev/null || { echo "timew not on PATH; the anchor is a real target, not a stand-in" >&2; exit 2; }

# Proven able to go red before it is trusted to say green.
python3 "$here/run-cell.py" --selftest

[ -s "$out" ] || python3 "$here/run-cell.py" --header > "$out"

# The setup is a script because the define is one: it seeds the database with an earlier
# interval, so the recorded operation is an ordinary second `track` rather than a first write
# into an empty store. Mode 755 and spawned through its own exec bit — the engine spawns argv
# directly and a 644 script proven green under `sh` failed at the first sealed exploration.
setup=$(mktemp "${TMPDIR:-/tmp}/se621-timew-setup-XXXXXX")
printf '%s\n' '#!/bin/sh' 'set -eu' \
    'timew track 2020-01-01T10:00 - 2020-01-01T11:00 alpha :yes >/dev/null' > "$setup"
chmod 755 "$setup"

for rep in 1 2 3; do
    echo "anchor: timewarrior, rep $rep" >&2
    python3 "$here/run-cell.py" --engine "$engine" --oracle "$oracle" \
        --crash-points 0 --rep "$rep" --mode wrappers --checker none \
        --setup-cmd "$setup" \
        --operation-cmd "timew track 2020-01-02T10:00 - 2020-01-02T11:00 beta :yes" \
        --state-env TIMEWARRIORDB \
        --label "timewarrior (spike/dogfood-timew.sh leg a, re-pathed)" >> "$out"
done

for rep in 1 2 3; do
    echo "anchor: toy-bug, rep $rep" >&2
    python3 "$here/run-cell.py" --engine "$engine" --oracle "$oracle" \
        --crash-points 0 --rep "$rep" --mode wrappers --checker none \
        --setup-cmd "$toybug init" \
        --operation-cmd "$toybug rotate" \
        --label "toy-bug (the planted delete-before-rename bug)" >> "$out"
done

rm -f "$setup"
echo "anchor: 6 rows appended to $out" >&2
