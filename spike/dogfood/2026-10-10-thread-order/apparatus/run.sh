#!/bin/sh
# One target, end to end (#687): the released engine's own refusal, and the capture of the run it
# refused. Run in the box (privileged, its own cgroup namespace, no network — --observe supervised
# needs the cgroup, ADR 0089):
#
#   docker run --rm --privileged --cgroupns=private --network none \
#       -v <apparatus>:/ap:ro -v <out>:/out sideeye-to-1010 sh /ap/run.sh <target>
#
# Each attempt seeds the state and runs `preflight --config <define> --observe supervised
# --oracle /usr/bin/strace`, the recording run only. The oracle is strace over that same run
# (`strace -f -y -e trace=%file,%desc,%process,...` — the engine's own arguments), so a refused
# attempt leaves, in its work directory, a capture of the very run the engine refused, with every
# thread's creation and exit. The capture is copied out per attempt: the engine removes it at the
# start of its next recording. Attempts stop at five refusals, or after fifteen.
set -u
t=${1:?usage: run.sh <target>}
d=/ap/defines/$t
SE=$(cat /install.path)
. /ap/env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"
o=/out/$t; mkdir -p "$o"
{ "$SE" version; echo "engine path: $SE"; grep -E 'digest matches|sideeye ' /install.log; cat /versions.txt; } > "$o/engine.txt"

refused=0; i=0
printf 'attempt\texit\tverdict\n' > "$o/attempts.tsv"
while [ "$i" -lt 15 ] && [ "$refused" -lt 5 ]; do
    i=$((i + 1))
    sh "$d/seed.sh" > "$o/seed-$i.log" 2>&1 || { echo "seed failed on attempt $i" >&2; exit 2; }
    "$SE" preflight --config "$d/sideeye.toml" --observe supervised --oracle /usr/bin/strace \
        --work "$o/work-$i" > "$o/preflight-$i.txt" 2>&1
    rc=$?
    verdict=$(grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR|OK|READY)' "$o/preflight-$i.txt" || echo '-')
    printf '%s\t%s\t%s\n' "$i" "$rc" "$verdict" >> "$o/attempts.tsv"
    if grep -q '^UNKNOWN  multiple_threads_detected$' "$o/preflight-$i.txt"; then
        refused=$((refused + 1))
        cp "$o/work-$i/oracle.txt" "$o/oracle-$i.txt" 2>/dev/null || echo "attempt $i: refused, and no oracle.txt in its work directory" >> "$o/attempts.tsv"
    fi
done
echo "$t: $refused refused of $i attempts"
