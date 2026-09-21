#!/bin/sh
# What `lefthook install` owes after it is killed partway.
#
# It writes the hook scripts it manages into `.git/hooks`. The contract this checks is the one a
# user would notice: **a hook file that exists must be a complete lefthook hook, not a truncated
# one** — git executes whatever is at that path on the next commit, so a half-written hook is
# worse than no hook at all.
#
# Legitimate after a crash: no hook, or fewer hooks than a finished run writes. Those are
# recoverable by running install again. A hook that exists and is cut short is not.
set -u
h=${LH_HOOKS:-/tmp/lh-repo/.git/hooks}
fail() { echo "check: $*" >&2; exit 1; }

[ -d "$h" ] || fail "the hooks directory is gone"

for f in "$h"/pre-commit "$h"/prepare-commit-msg; do
    [ -e "$f" ] || continue                       # not written yet: install had not got there
    [ -f "$f" ] || fail "${f##*/} exists and is not a regular file"
    grep -q lefthook "$f" || fail "${f##*/} exists but is not lefthook's"
    # Both ends, because a file holding only the leading comment would pass a name-only test:
    # lefthook's hooks name it again in their dispatch, at the end.
    tail -c 200 "$f" | grep -q lefthook || fail "${f##*/} is cut short before its dispatch"
    [ -x "$f" ] || fail "${f##*/} is not executable, so git would skip the hook install wrote"
done
exit 0
