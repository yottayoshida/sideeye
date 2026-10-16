#!/bin/sh
# Prints, per candidate, the files under spike/ at BASE (outside this directory) that name its
# command or its binary package; exits 1 if any candidate is named. CANDIDATES.md's order and
# names are the input, and this is the predicate it states.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
self=${here#"$root"/}
BASE=5510fda3
named=0
while read -r cmd pkg; do
    case "$cmd" in ''|'#'*) continue ;; esac
    n=0
    for word in "$cmd" "$pkg"; do
        # Not `git grep -w` alone on the package: `-w` treats `-` as a boundary, so `xapian-omega`
        # would match a line naming `xapian` and `omega` apart; the fixed string keeps it whole.
        c=$(git -C "$root" grep -l -i -w -F -e "$word" "$BASE" -- spike/ ":(exclude)$self" | wc -l | tr -d ' ')
        n=$((n + c))
    done
    printf '%-24s %-28s %s\n' "$cmd" "$pkg" "$n"
    [ "$n" = 0 ] || named=1
done <<'LIST'
quilt quilt
rlog rcs
etckeeper etckeeper
aptly aptly
gdbmtool gdbmtool
stg stgit
omindex xapian-omega
yoyo python3-yoyo
xapian-compact xapian-tools
slapadd slapd
flask-migrate python3-flask-migrate
LIST
exit "$named"
