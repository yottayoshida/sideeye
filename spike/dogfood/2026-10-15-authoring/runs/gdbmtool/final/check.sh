#!/bin/sh
# Checker for: a gdbmtool session storing k4=v4, k5=v5, k6=v6 (in that order) into a
# GDBM database that already holds k1=v1, k2=v2, k3=v3. See INVARIANT.md.
#
# Runs recover.sh first (the step a user takes after a crash), then reads the
# database through gdbmtool itself and judges five legs:
#   a  the database file exists and gdbmtool reads every record without complaint
#   b  k1=v1, k2=v2, k3=v3 are each present exactly once, with those values
#   c  each of k4, k5, k6 is absent, or present exactly once with its own value
#   d  no key other than k1..k6
#   e  the new keys present are a prefix of k4, k5, k6 (the session's order)
# b..e need a readable database; when a fails they print "-" (not judged).
# gdbmtool exits 0 even when a command fails, so "read without complaint" means
# exit 0 AND nothing on stderr.
#
# State directory: $SIDEEYE_STATE_DIR, or $1.
set -u
S=${1:-${SIDEEYE_STATE_DIR:?}}
DB=$S/db.gdbm
HERE=$(dirname "$0")
OUT=$(mktemp) ERR=$(mktemp)
trap 'rm -f "$OUT" "$ERR"' EXIT

"$HERE/recover.sh" "$S"

a=ok b=- c=- d=- e=-
if [ ! -f "$DB" ]; then
    a="FAIL(no db.gdbm)"
else
    timeout 30 gdbmtool -N -q -r "$DB" list > "$OUT" 2> "$ERR"
    rc=$?
    if [ "$rc" != 0 ] || [ -s "$ERR" ]; then
        a="FAIL(exit $rc: $(head -c 160 "$ERR" | tr '\n' ' '))"
    fi
fi

if [ "$a" = ok ]; then
    # one record per line, "KEY VALUE"; every key and value here is one word
    n() { awk -v k="$1" '$1 == k' "$OUT" | wc -l; }
    has() { [ "$(awk -v k="$1" -v v="$2" '$1 == k && $2 == v && NF == 2' "$OUT" | wc -l)" = 1 ]; }

    b=ok
    for i in 1 2 3; do
        has "k$i" "v$i" && [ "$(n "k$i")" = 1 ] || b="FAIL(k$i: $(awk -v k="k$i" '$1 == k' "$OUT" | tr '\n' '|'))"
    done

    c=ok
    for i in 4 5 6; do
        case $(n "k$i") in
            0) ;;
            1) has "k$i" "v$i" || c="FAIL(k$i: $(awk -v k="k$i" '$1 == k' "$OUT"))" ;;
            *) c="FAIL(k$i present $(n "k$i") times)" ;;
        esac
    done

    strangers=$(awk '$1 !~ /^k[1-6]$/ { print $1 }' "$OUT" | tr '\n' ' ')
    d=ok; [ -z "$strangers" ] || d="FAIL(unexpected keys: $strangers)"

    # e reads which of k4..k6 are present at all, whatever their values (c judges those)
    seen=""
    for i in 4 5 6; do [ "$(n "k$i")" = 0 ] || seen="$seen$i"; done
    case $seen in
        "" | 4 | 45 | 456) e=ok ;;
        *) e="FAIL(new keys present: $seen, not a prefix of 456)" ;;
    esac
fi

legs="a=$a b=$b c=$c d=$d e=$e"
echo "checker(gdbmtool-store3): $legs"
[ "$legs" = "a=ok b=ok c=ok d=ok e=ok" ]
