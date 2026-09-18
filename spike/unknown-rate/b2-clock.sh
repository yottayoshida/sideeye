#!/bin/sh
# Authoring clock for the B2 defines (#619): one line per event per target,
# appended to b2-clock.tsv when the author reaches that point. Self-reported —
# nothing checks it against a clock; it is published so that reach and
# authoring friction are not read as one number. It lives outside the define
# directories, whose bytes the sweep's define digest covers.
#
# Once per (target, event): a second call finds the line already there and
# leaves it — the guard lives here, not in each caller, so `final` (stamped
# by hand at the end of authoring) is held to it the same as the two the
# scripts stamp. count.py's read_clock refuses a duplicate all the same.
#
# Usage: b2-clock.sh <target> setup_started|first_accepted_recording|final
set -eu
t=${1:?target}; ev=${2:?event}
case "$ev" in
  setup_started|first_accepted_recording|final) ;;
  *) echo "b2-clock: event must be setup_started, first_accepted_recording or final" >&2; exit 2 ;;
esac
here=$(cd "$(dirname "$0")" && pwd)
clock=$here/b2-clock.tsv
if [ -f "$clock" ] && grep -q "^$t	$ev	" "$clock"; then
    grep "^$t	$ev	" "$clock"
    exit 0
fi
printf '%s\t%s\t%s\n' "$t" "$ev" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$clock"
tail -n 1 "$clock"
