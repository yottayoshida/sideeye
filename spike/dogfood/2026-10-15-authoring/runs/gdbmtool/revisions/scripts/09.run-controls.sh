#!/bin/sh
# Runs check.sh over every control (each must be rejected) and over three valid
# states (each must be accepted): the starting state, the completed state, and a
# state that needs recover.sh and that recover.sh repairs. Prints a transcript.
set -u
D=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
bad=0
judge() { # expect(accept|reject) label dir
    out=$("$D/check.sh" "$3" 2>&1); rc=$?
    case "$1:$rc" in accept:0) v=as-expected ;; accept:*) v=WRONG ;; reject:0) v=WRONG ;; *) v=as-expected ;; esac
    [ "$v" = as-expected ] || bad=1
    printf '%s\t%s\texit %s\t%s\n%s\n\n' "$v" "$2" "$rc" "expected $1" "$out"
}
for c in a b c d e; do
    "$D/control-$c.sh" "$T/$c" >/dev/null 2>&1 || { echo "control-$c.sh failed to build"; bad=1; continue; }
    judge reject "control-$c" "$T/$c"
done
"$D/setup.sh" "$T/start"; judge accept valid-start "$T/start"
"$D/setup.sh" "$T/done"
gdbmtool -N -q -m "$T/done/db.gdbm" store k4 v4 \; store k5 v5 \; store k6 v6
judge accept valid-completed "$T/done"
# Recovered: the session got as far as k4, then the directory block (offset 4096)
# is damaged; reading fails, and gdbmtool recover rebuilds all four records.
"$D/setup.sh" "$T/rec"
gdbmtool -N -q -m "$T/rec/db.gdbm" store k4 v4
printf '\377' | dd of="$T/rec/db.gdbm" bs=1 seek=4096 conv=notrunc 2>/dev/null
judge accept valid-recovered "$T/rec"
rm -rf "$T"
exit $bad
