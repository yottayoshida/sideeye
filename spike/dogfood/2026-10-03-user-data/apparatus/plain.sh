#!/bin/sh
# Each candidate's operation, run once plainly from its seed, before any engine runs — the step
# 2026-09-28 recorded as transcripts/plain-runs.txt. Prints, per define: the operation's exit and
# whether the state root's bytes changed (a sha256 over every file, path and content).
#
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1003 sh /ap/plain.sh [name ...]
#
# The environment is the one the gate and explores give the operation: /ap/env.sh, then the
# define's own env.sh when it has one.
set -u
. /ap/env.sh
digest() { (cd "$1" 2>/dev/null && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -c1-12); }
[ $# -gt 0 ] || set -- $(ls /ap/defines)
for t in "$@"; do
    d=/ap/defines/$t
    ( [ -f "$d/env.sh" ] && . "$d/env.sh"
      state=$(sed -n 's/^state *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      cwd=$(sed -n 's/^cwd *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      op=$(sed -n 's/^operation *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      sh "$d/seed.sh" > /tmp/seed-$t.log 2>&1 || { echo "PLAIN $t seed-failed: $(tail -1 /tmp/seed-$t.log)"; exit 0; }
      before=$(digest "$state")
      cd "$cwd" && $op < /dev/null > /tmp/op-$t.log 2>&1; rc=$?
      after=$(digest "$state")
      [ "$before" = "$after" ] && ch=unchanged || ch=changed
      echo "PLAIN $t exit=$rc state=$ch  ($(tail -1 /tmp/op-$t.log | cut -c1-90))" )
done
