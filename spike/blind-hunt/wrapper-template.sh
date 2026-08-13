#!/bin/sh
# Seal A artifact (ADR 0012 decision 4): the falsification-wrapper template.
#
# Sideeye refuses to trust a checker it has not seen fail: before exploring, it corrupts
# the state and requires the check to reject it (checker_not_falsified otherwise). Some
# targets answer garbage with exit 0 — todoman printed a traceback about every entry and
# still exited 0, the "could not read" read as "nothing wrong" shape. This template is
# the sanctioned adapter for that case, fixed BEFORE any target's behavior over corrupt
# state has been seen.
#
# The shape — and the only shape — a Seal B wrapper may take:
#
#   1. Run one of the target's own query commands.
#   2. Require it to exit 0 AND require of its output a property taken from the
#      documentation (a `source: doc` citation in the checker header), stated
#      POSITIVELY: "the output contains/matches what the docs promise", never
#      "the output does not contain <text I saw when it broke>".
#
# Rule 2's direction is the whole point. A positive doc-derived requirement can be
# written before ever seeing a failure; a negative requirement is a fingerprint of an
# observed failure, and a wrapper carrying one is sighted by construction.
#
# Instantiation happens at Seal B. Any edit after Seal B marks the checker sighted
# (ADR 0012 breach handling) — corrupt output is on screen during exploration, and a
# wrapper adjusted while looking at it is an invariant being redesigned.
#
# Template (replace the three <...> holes; delete nothing else):

: <<'TEMPLATE'
#!/bin/sh
# checker wrapper for <target>
# source: doc — <citation for why this output property is promised>
set -u

out=$(<target query command> 2>&1)
rc=$?

# The query itself must succeed after a crash + restart.
[ "$rc" -eq 0 ] || { echo "wrapper: query exited $rc" >&2; exit 1; }

# And its output must show the documented property — positively stated.
case "$out" in
    <doc-promised pattern>) exit 0 ;;
    *) echo "wrapper: query output lacks the documented property" >&2; exit 1 ;;
esac
TEMPLATE
