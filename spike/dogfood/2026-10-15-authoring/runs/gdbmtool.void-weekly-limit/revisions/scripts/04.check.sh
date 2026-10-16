#!/bin/sh
# The invariant of INVARIANT.md, judged after the recovery a user would run
# (recover.sh), and read through gdbmtool itself:
#   a  usable    recover.sh succeeds and the database opens read-write again
#   b  old       k1 k2 k3 are each listed exactly once, with v1 v2 v3
#   c  new       n1 n2 n3 are each listed at most once, and only with w1 w2 w3
#   d  nothing   no key outside k1..k3, n1..n3 is listed
#   e  agree     gdbmtool's own count equals the number of records it lists
# Which of n1..n3 survived, and in which order, is printed and not judged.
# gdbmtool exits 0 even when it cannot open or read the database, so every read
# also requires an empty stderr.
set -u
S=${SIDEEYE_STATE_DIR:?}; DB=$S/db.gdbm
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

# number from "There are N items" / "There is 1 item"; empty when stderr said anything
count_of() {
    gdbmtool -N -q "$@" "$DB" count >"$T/c.out" 2>"$T/c.err"
    [ -s "$T/c.err" ] && return 0
    sed -n 's/^There \(is\|are\) \([0-9][0-9]*\) items\{0,1\} in the database\.$/\2/p' "$T/c.out"
}

legs() {  # $1: recover.sh's exit status, or "-" when it has not run
    a=ok; b=ok; c=ok; d=ok; e=ok
    # before the recovery nothing is opened for writing: the user's recovery comes first
    case "$1" in
        -) a=- ;;
        0) [ -n "$(count_of)" ] || a="FAIL(read-write open: $(head -c 120 "$T/c.err"))" ;;
        *) a="FAIL(recover exited $1)" ;;
    esac

    gdbmtool -N -q -r "$DB" list >"$T/l.out" 2>"$T/l.err"
    if [ -s "$T/l.err" ]; then
        b="FAIL(list: $(head -c 120 "$T/l.err"))"
    else
        for kv in "k1 v1" "k2 v2" "k3 v3"; do
            k=${kv% *}
            n=$(awk -v k="$k" '$1 == k' "$T/l.out" | wc -l)
            [ "$n" -eq 1 ] && grep -qxF "$kv" "$T/l.out" || b="FAIL($k listed $n time(s): $(grep "^$k " "$T/l.out" | tr '\n' ' '))"
        done
    fi
    for kv in "n1 w1" "n2 w2" "n3 w3"; do
        k=${kv% *}
        n=$(awk -v k="$k" '$1 == k' "$T/l.out" | wc -l)
        case "$n" in
            0) ;;
            1) grep -qxF "$kv" "$T/l.out" || c="FAIL($k holds: $(grep "^$k " "$T/l.out"))" ;;
            *) c="FAIL($k listed $n times)" ;;
        esac
    done
    other=$(awk '$1 !~ /^(k1|k2|k3|n1|n2|n3)$/ { print $1 }' "$T/l.out" | tr '\n' ' ')
    [ -z "$other" ] || d="FAIL(other keys: $other)"

    listed=$(wc -l < "$T/l.out" | tr -d ' ')
    counted=$(count_of -r)
    [ "$counted" = "$listed" ] || e="FAIL(count says '${counted:-unreadable}', list has $listed)"

    new=$(awk '$1 ~ /^n[123]$/ { print $1 }' "$T/l.out" | sort | tr -d '\n')
    echo "a=$a b=$b c=$c d=$d e=$e (new keys present: ${new:-none})"
}

echo "checker(gdbm) before recovery: $(legs -)"
"$HERE/recover.sh"
rc=$?
after=$(legs "$rc")
echo "checker(gdbm) after recovery: $after"
case "$after" in "a=ok b=ok c=ok d=ok e=ok "*) exit 0 ;; *) exit 1 ;; esac
