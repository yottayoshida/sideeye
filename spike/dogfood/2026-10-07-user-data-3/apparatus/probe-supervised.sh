#!/bin/sh
# Off the page's path: a target whose default explore was refused with a next step that does not name
# --observe supervised, explored once more with supervised named — as 2026-10-05 measured aliyun-cli
# (its transcripts/probe-aliyun-supervised.txt). The page's-path result in summary.txt is what counts;
# this one is recorded beside it. Run inside the box, from the host:
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro \
#     -v <transcripts/explore>:/out sideeye-ud1007 sh /ap/probe-supervised.sh <target>
set -u
t=${1:?usage: probe-supervised.sh <target>}
d=/ap/defines/$t
SE=$(cat /install.path)
. /ap/env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"
o=/out/$t; mkdir -p "$o"
seed() { sh "$d/seed.sh" > "$o/seed-probe.log" 2>&1 || { echo "seed failed" >&2; exit 2; }; }
seed
"$SE" explore --config "$d/sideeye.toml" --oracle /usr/bin/strace --observe supervised \
    --work "$o/work-probe-supervised" --json "$o/probe-supervised.json" > "$o/probe-supervised.txt" 2>&1
rc=$?
echo "probe supervised exit $rc"
if [ "$rc" = 1 ]; then
    case_json=$(ls "$o/work-probe-supervised/cases/"*.json 2>/dev/null | head -1)
    [ -n "$case_json" ] && "$SE" evidence "$case_json" > "$o/probe-supervised.evidence.md" 2>&1
fi
