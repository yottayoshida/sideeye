#!/bin/sh
# Opened by ldb on a copy, as the next run would open it: checkconsistency passes, all 300 keys are
# there with the seed's values, and k1 holds either its old value or the new one.
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"
cc=$(ldb --db="$t" --try_load_options checkconsistency 2>&1)
scan=$(ldb --db="$t" --try_load_options scan 2>&1)
rm -rf "$t"
[ "$cc" = OK ] || { echo "checker(ldb): checkconsistency: $(echo "$cc" | head -2 | tr '\n' ' ')"; exit 1; }
n=$(printf '%s\n' "$scan" | grep -c ' ==> ')
[ "$n" = 300 ] || { echo "checker(ldb): $n keys, want 300"; exit 1; }
k1=$(printf '%s\n' "$scan" | sed -n 's/^k1 ==> //p')
rest=$(printf '%s\n' "$scan" | grep -v '^k1 ==> ' | md5sum | cut -d' ' -f1)
want=$(grep -v '^k1 ' /s/.rdbd-load.txt | LC_ALL=C sort | md5sum | cut -d' ' -f1)
[ "$rest" = "$want" ] || { echo "checker(ldb): the 299 keys other than k1 do not hold the seed's values"; exit 1; }
case "$k1" in changed|"$(printf '%0100d' 1)") ;; *) echo "checker(ldb): k1 = $(echo "$k1" | cut -c1-40)"; exit 1 ;; esac
