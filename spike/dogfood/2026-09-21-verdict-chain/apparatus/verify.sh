#!/bin/sh
# What `overcommit --install` owes after it is killed partway.
#
# It copies one Ruby entrypoint into `.git/hooks` under ten names — measured: ten regular
# files of 3,682 bytes, one distinct md5 between them. The contract this checks is the one
# a user would notice: **a hook file that exists must be a complete overcommit hook, and
# executable**. Git runs whatever is at that path on the next commit, so a hook cut off
# mid-file is worse than no hook at all, and a complete hook without its exec bit is a
# hook git silently skips.
#
# Legitimate after a crash: no hook, or fewer hooks than a finished run writes. Those are
# recoverable by running install again. A hook that exists and is cut short is not.
#
# Both ends are checked, because a file holding only the leading comment would pass a
# name-only test: the entrypoint names itself in its header and again in its last lines
# (the `EX_SOFTWARE` rescue), so the tail is what says the copy reached its end.
set -u
h=${OC_HOOKS:-/tmp/oc-repo/.git/hooks}
fail() { echo "check: $*" >&2; exit 1; }

[ -d "$h" ] || fail "the hooks directory is gone"

for f in "$h"/commit-msg "$h"/overcommit-hook "$h"/post-checkout "$h"/post-commit \
         "$h"/post-merge "$h"/post-rewrite "$h"/pre-commit "$h"/pre-push \
         "$h"/pre-rebase "$h"/prepare-commit-msg; do
    [ -e "$f" ] || continue                       # not written yet: install had not got there
    [ -f "$f" ] || fail "${f##*/} exists and is not a regular file"
    head -c 200 "$f" | grep -q 'Overcommit' || fail "${f##*/} exists but is not overcommit's"
    tail -c 200 "$f" | grep -q 'EX_SOFTWARE' || fail "${f##*/} is cut short before its rescue block"
    [ -x "$f" ] || fail "${f##*/} is not executable, so git would skip the hook install wrote"
done
exit 0
