#!/bin/sh
# Runs check.sh over every control and over the states it must accept, each in a
# fresh tree built by setup.sh. Prints one line per case: expected, got, the legs.
set -u
HERE=$(dirname "$(readlink -f "$0")")
R=$(mktemp -d)
trap 'rm -rf "$R"' EXIT
bad=0
run() {  # run <name> <expect 0|1> <build command...>
    name=$1 want=$2; shift 2
    S=$R/$name; mkdir "$S"
    export SIDEEYE_STATE_DIR=$S
    "$HERE/setup.sh" && (cd "$S" && "$@") >/dev/null 2>&1 || { echo "$name: BUILD FAILED"; bad=1; return; }
    out=$("$HERE/check.sh" 2>&1); got=$?
    [ "$got" = "$want" ] && v=as-expected || { v=WRONG; bad=1; }
    echo "$name: want $want got $got $v | $(printf '%s\n' "$out" | grep 'applied \[')"
}
run start       0 true
run completed   0 quilt push -a
# The crash state recover.sh is for: killed between `mkdir .pc` and writing .pc/.version.
run recovered   0 mkdir .pc
run order       1 "$HERE/control-order.sh"
run applied     1 "$HERE/control-applied.sh"
run unapplied   1 "$HERE/control-unapplied.sh"
run backup      1 "$HERE/control-backup.sh"
run records     1 "$HERE/control-records.sh"
# Not a control: a crash state built by hand from reading quilt's push (patch(1) has
# renamed a.txt into place, the subshell has not yet appended p1.diff to
# .pc/applied-patches). sideeye never reached it; the invariant calls it unacceptable.
run crash-window 1 sh -c 'mkdir .pc && echo 2 > .pc/.version && echo patches > .pc/.quilt_patches && echo series > .pc/.quilt_series && patch -s -p1 --backup --prefix=.pc/p1.diff/ < patches/p1.diff'
exit $bad
