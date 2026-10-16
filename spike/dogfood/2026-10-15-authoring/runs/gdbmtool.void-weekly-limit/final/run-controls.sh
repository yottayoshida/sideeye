#!/bin/sh
# Builds each control and acceptance state in a fresh directory of its own and
# runs check.sh on it. A control passes when check.sh exits 1 with its own leg,
# and only that leg, red after the recovery; an acceptance state when check.sh
# exits 0. Exit 0 only when every one of them came out as expected.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${CONTROLS_ROOT:-/tmp/gdbm-controls}
bad=0
for b in accept-start accept-complete accept-recovered \
         control-usable control-old control-new control-nothing control-agree; do
    S=$ROOT/$b
    chmod -R u+w "$S" 2>/dev/null; rm -rf "$S"; mkdir -p "$S"
    export SIDEEYE_STATE_DIR=$S
    echo "== $b"
    "$HERE/$b.sh" || { echo "   builder failed"; bad=1; continue; }
    out=$("$HERE/check.sh" 2>&1); rc=$?
    printf '%s\n' "$out" | sed 's/^/   /'
    after=$(printf '%s\n' "$out" | sed -n 's/^checker(gdbm) after recovery: //p')
    red=$(printf '%s\n' "$after" | grep -o '[a-e]=FAIL' | cut -c1 | tr -d '\n')
    case "$b" in
        accept-*) want=""; wantrc=0 ;;
        control-usable) want=a; wantrc=1 ;;
        control-old) want=b; wantrc=1 ;;
        control-new) want=c; wantrc=1 ;;
        control-nothing) want=d; wantrc=1 ;;
        control-agree) want=e; wantrc=1 ;;
    esac
    if [ "$rc" = "$wantrc" ] && [ "$red" = "$want" ]; then
        echo "   => as expected (exit $rc, red legs: ${red:-none})"
    else
        echo "   => UNEXPECTED (exit $rc, red legs: ${red:-none}; wanted exit $wantrc, red: ${want:-none})"; bad=1
    fi
done
exit $bad
