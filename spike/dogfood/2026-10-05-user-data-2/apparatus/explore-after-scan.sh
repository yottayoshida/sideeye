#!/bin/sh
# Host side: explore each target only after its tracker's rule-14 pre-scan has ended (prescan-log.txt
# carries `prescan end <repo>`), one target at a time, so no explore runs before its scan. Reading
# the scan for a veto is done by hand from the tracker's text alone; a target vetoed after its explore
# leaves the slate with its explore kept, and SELECTION.md says so.
#   sh apparatus/explore-after-scan.sh <target>=<repo>[+<repo>] ...
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"; log="$run/transcripts/prescan-log.txt"
for pair in "$@"; do
  t=${pair%%=*}; repos=${pair#*=}
  for r in $(echo "$repos" | tr + ' '); do
    # rc=0 only: a scan that could not measure ends rc=2, is kept as .broken and re-run, and its first
    # `prescan end` line once let turbo's explore start before the re-run finished (2026-10-05).
    until grep -q "prescan end   $r .* rc=0" "$log"; do sleep 20; done
  done
  echo "scan ended for $t ($repos); exploring $(date -u +%FT%TZ)"
  sh "$here/explore.sh" "$t"
done
echo "explore-after-scan: done $(date -u +%FT%TZ)"
