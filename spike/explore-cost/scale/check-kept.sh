#!/bin/sh
# The scale benchmark's cheap deterministic checker (#621, ADR 0081).
#
# It reads the one judged file and rejects anything but the byte the setup wrote. That is
# almost no work — the point of this leg is the fixed cost of *having* a checker, not the cost
# of a demanding one — but it is work that **can fail**, and that matters: Sideeye refuses a
# checker its falsification probe cannot break, and `/bin/true` as the cheap checker produced
# `UNKNOWN / checker_not_falsified` and no measurement at all (pilot cell 6). A checker that
# always passes is not a cheap checker; it is no checker, and the engine says so.
#
# `TOY_STATE` is what Sideeye exports to its children pointed at the resolved `[world] state`.
set -eu
state=${TOY_STATE:-./state}
kept="$state/keep.json"

[ -f "$kept" ] || { echo "check-kept: $kept is missing" >&2; exit 1; }
read -r line < "$kept" || { echo "check-kept: $kept could not be read" >&2; exit 1; }
[ "$line" = "kept" ] || { echo "check-kept: $kept holds '$line', wanted 'kept'" >&2; exit 1; }
exit 0
