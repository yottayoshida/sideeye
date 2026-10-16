#!/bin/sh
# Checker for `quilt push -a` over a tree whose patches/series names p1.diff (a.txt)
# and p2.diff (b.txt). See INVARIANT.md. Runs recover.sh, then judges five legs:
#   A order     quilt reads its own records, and what it lists as applied is a prefix
#               of what it lists in the series
#   B applied   every file of an applied patch holds that patch's result
#   C unapplied every file of an unapplied patch holds its pristine bytes
#   D backup    quilt can take back what it lists as applied: in a copy, `quilt pop -a -f`
#               succeeds, then lists nothing applied, and those patches' files are pristine
#   E records   patches/series and both patch files are the bytes the setup wrote
# Only recover.sh writes the state; every other quilt command runs in a copy, because
# quilt touches .pc/applied-patches even when it only reads.
set -u
S=${SIDEEYE_STATE_DIR:?}
HERE=$(dirname "$(readlink -f "$0")")

out=$("$HERE/recover.sh" 2>&1); rc=$?
echo "checker(quilt) recovery exited $rc: $(printf '%s' "$out" | tail -n 1)"

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
# Reference trees: the setup's (pristine) and quilt's own completed push.
mkdir "$T/ref0" "$T/ref1"
SIDEEYE_STATE_DIR=$T/ref0 "$HERE/setup.sh" || { echo "checker(quilt): setup failed in $T/ref0"; exit 1; }
SIDEEYE_STATE_DIR=$T/ref1 "$HERE/setup.sh" || { echo "checker(quilt): setup failed in $T/ref1"; exit 1; }
(cd "$T/ref1" && quilt push -a) >/dev/null 2>&1 || { echo "checker(quilt): reference push failed"; exit 1; }
cp -a "$S" "$T/tree" && cp -a "$S" "$T/pop" || { echo "checker(quilt): cannot copy the state"; exit 1; }

file_of() { case "$1" in p1.diff) echo a.txt ;; p2.diff) echo b.txt ;; *) echo "?" ;; esac; }
in_list() { printf '%s\n' "$2" | grep -qxF "$1"; }
last() { printf '%s' "$1" | tail -n 1; }

# Leg A: what quilt itself says is in the series and applied.
a=ok
series=$(cd "$T/tree" && quilt series 2>&1); src=$?
applied=$(cd "$T/tree" && quilt applied 2>&1); arc=$?
series=$(printf '%s\n' "$series" | sed 's|^patches/||')
applied=$(printf '%s\n' "$applied" | sed 's|^patches/||')
[ "$src" = 0 ] || a="FAIL(quilt series exited $src: $(last "$series"))"
if [ "$arc" = 1 ] && [ "$applied" = "No patches applied" ]; then
    applied=""
elif [ "$arc" != 0 ]; then
    [ "$a" = ok ] && a="FAIL(quilt applied exited $arc: $(last "$applied"))"
    # quilt refused to read its records; legs B-D read the record itself.
    applied=$(cat "$S/.pc/applied-patches" 2>/dev/null)
fi
if [ "$a" = ok ]; then
    n=$(printf '%s' "$applied" | grep -c .)
    prefix=$(printf '%s\n' "$series" | head -n "$n")
    [ "$n" = 0 ] || [ "$prefix" = "$applied" ] || a="FAIL(applied [$(echo $applied)] is not a prefix of series [$(echo $series)])"
fi

# Legs B and C: each file holds what its patch's applied-or-not says. The patch
# names are the fixture's; leg E judges that the series still names them.
b=ok; c=ok
for p in p1.diff p2.diff; do
    f=$(file_of "$p")
    if in_list "$p" "$applied"; then
        cmp -s "$T/ref1/$f" "$S/$f" || b="FAIL($p is applied but $f is not its result)"
    else
        cmp -s "$T/ref0/$f" "$S/$f" || c="FAIL($p is not applied but $f is not pristine)"
    fi
done

# Leg D: quilt can take back everything it lists as applied.
d=ok
if [ -n "$applied" ]; then
    pout=$(cd "$T/pop" && quilt pop -a -f 2>&1); prc=$?
    if [ "$prc" != 0 ]; then
        d="FAIL(quilt pop -a -f exited $prc: $(last "$pout"))"
    else
        left=$(cd "$T/pop" && quilt applied 2>&1)
        [ "$left" = "No patches applied" ] || d="FAIL(after pop -a -f quilt still lists: $(echo $left))"
        for p in $applied; do
            f=$(file_of "$p")
            cmp -s "$T/ref0/$f" "$T/pop/$f" || d="FAIL(popping $p did not restore pristine $f)"
        done
    fi
fi

# Leg E: the records quilt is driven by are unchanged.
e=ok
for r in patches/series patches/p1.diff patches/p2.diff; do
    cmp -s "$T/ref0/$r" "$S/$r" || e="FAIL($r differs from the setup)"
done

legs="a=$a b=$b c=$c d=$d e=$e"
echo "checker(quilt) applied [$(echo $applied)]: $legs"
case "$legs" in "a=ok b=ok c=ok d=ok e=ok") exit 0 ;; *) exit 1 ;; esac
