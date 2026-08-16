#!/bin/sh
# The reader-checker for the #144 follow-up: bogofilter's own tools must
# still be able to read the wordlist. bogoutil opens the db through the
# sqlite backend (bogoutil-sqlite by name — the bare `bogoutil`
# alternatives symlink resolves to the BDB variant, which cannot read a
# sqlite wordlist and made the checker red on VALID state; the baseline
# world caught that on the first run); the classification run uses it for
# a real query. Exit
# codes 0/1/2 from bogofilter are spam/ham/unsure — all three mean "the
# reader works"; a missing db, a failed dump, or an error status means it
# does not. The falsification gate corrupts the store before the run and
# requires this script to go red then.
# Every run appends one line to a log OUTSIDE the judged state (a log
# inside $TOY_STATE would join the L0 comparison): the engine only records
# the earliest violating world's invariant, so this log is what turns
# "the checker never failed" from an inference into a committed record —
# one line per checker invocation, in engine order (the falsification
# gate's red first, then every world).
LOG=/tmp/followup-144/checker.log
note() { echo "$1" >> "$LOG"; }
set -eu
db=$TOY_STATE/wordlist.db
[ -f "$db" ] || { note "fail: wordlist.db missing"; echo "wordlist.db missing" >&2; exit 1; }
bogoutil-sqlite -d "$db" >/dev/null || { note "fail: bogoutil cannot dump"; echo "bogoutil cannot dump the wordlist" >&2; exit 1; }
set +e
bogofilter-sqlite -d "$TOY_STATE" -I "$TOY_STATE/ham.eml"
rc=$?
set -e
case "$rc" in
    0|1|2) note "ok"; exit 0 ;;
    *) note "fail: classify status $rc"; echo "bogofilter-sqlite classify failed with status $rc" >&2; exit 1 ;;
esac
