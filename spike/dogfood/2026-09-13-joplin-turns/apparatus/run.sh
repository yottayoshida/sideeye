#!/bin/sh
# #558: twenty valid strace captures of joplin's `mknote` from one seeded pre-state, read by
# turns.py. Run in the image built from ./Dockerfile, with this directory at /ap (read-only),
# a host directory for the captures at /caps and one for the readings at /out:
#
#   docker run --rm -v <this dir>:/ap:ro -v <captures>:/caps -v <transcripts>:/out \
#     sideeye-joplin:2026-09-13 sh /ap/run.sh
#
# The captures stay on the host (about 6 MB each, not committed) so any reading can be
# redone and any mutation of turns.py tried against them. Before anything is captured the
# selftest runs, and a red selftest stops the run: readings from a reader that fails its
# own cases would say nothing.
#
# A run is valid when turns.py read it, joplin exited 0 and the note was written (a write to
# the journal). Invalid runs are kept, marked, and replaced, up to thirty attempts; fewer than
# twenty valid runs in thirty is BROKEN (exit 2) rather than a reading.
#
# JOPLIN_FLAGS is put before `--profile` on the measured command and printed below; the logger-off
# runs pass `-e JOPLIN_FLAGS='--log-level error'` (`none` is read as INFO by joplin 3.7.1, see
# logger-level.sh).
set -u
N_WANT=${N_WANT:-20}
N_MAX=${N_MAX:-30}
JOPLIN_FLAGS=${JOPLIN_FLAGS:-}
SD=/w/jp

echo "joplin: $(npm ls -g joplin 2>/dev/null | grep -o 'joplin@[^ ]*')  node: $(node --version)  flags on the measured command: '$JOPLIN_FLAGS'"
echo "$(strace -V | head -1)  libc: $(ldd --version 2>&1 | head -1)  arch: $(uname -m)"
echo "turns.py: $(sha256sum /ap/turns.py | cut -d' ' -f1)  run.sh: $(sha256sum /ap/run.sh | cut -d' ' -f1)"

python3 /ap/turns.py --selftest > /out/selftest.txt 2>&1
if [ $? != 0 ]; then
    echo "BROKEN: turns.py --selftest failed"
    cat /out/selftest.txt
    exit 2
fi
echo "selftest: $(grep -c '^ok' /out/selftest.txt) ok, 0 failing"

mkdir -p /w/seed
{ joplin --profile /w/seed mkbook TestBook && joplin --profile /w/seed use TestBook \
    && joplin --profile /w/seed mknote SeedNote; } > /out/seed.txt 2>&1 \
    || { echo "BROKEN: the seed did not build"; cat /out/seed.txt; exit 2; }
echo "seed: $(find /w/seed -maxdepth 1 | sed 's|^/w/seed||' | LC_ALL=C sort | tr '\n' ' ')"

valid=0
tried=0
while [ "$valid" -lt "$N_WANT" ] && [ "$tried" -lt "$N_MAX" ]; do
    tried=$((tried + 1))
    n=$(printf '%02d' "$tried")
    rm -rf "$SD" && cp -a /w/seed "$SD"
    # shellcheck disable=SC2086 # JOPLIN_FLAGS is a list of words on purpose
    strace -f -y -ttt -T -o "/caps/cap-$n.txt" joplin $JOPLIN_FLAGS --profile "$SD" mknote SecondNote > "/out/joplin-$n.txt" 2>&1
    jrc=$?
    python3 /ap/turns.py run "/caps/cap-$n.txt" "$SD" --joplin-rc "$jrc" > "/out/run-$n.json" 2> "/out/run-$n.err"
    trc=$?
    if [ "$trc" = 0 ] && python3 -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1]))["valid"] else 1)' "/out/run-$n.json"; then
        valid=$((valid + 1))
        echo "run $n: valid ($valid/$N_WANT)"
    else
        echo "run $n: INVALID (turns.py rc=$trc, joplin rc=$jrc) $(cat "/out/run-$n.err" 2>/dev/null | head -1)"
    fi
done
echo "tried $tried, valid $valid"
[ "$valid" -ge "$N_WANT" ] || { echo "BROKEN: fewer than $N_WANT valid runs in $N_MAX"; exit 2; }

python3 /ap/turns.py aggregate /out/run-*.json > /out/summary.txt
arc=$?
cat /out/summary.txt
exit $arc
