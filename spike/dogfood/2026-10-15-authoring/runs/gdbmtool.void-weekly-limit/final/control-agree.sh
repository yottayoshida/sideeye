#!/bin/sh
# Leg e (agree) only: the bucket's element count is raised from 3 to 4 while its
# three elements stay, so gdbmtool's count says 4 and its list shows 3 records.
# recover.sh's check does not notice this (measured), so it is not healed.
# The bucket's address is read from gdbmtool's own directory listing; the count
# field sits 108 bytes into a bucket (4-byte av_count, padding, 6 avail
# elements of 16 bytes, 4-byte bucket_bits) on this 64-bit build.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=${SIDEEYE_STATE_DIR:?}; DB=$S/db.gdbm
"$HERE/setup.sh"
addr=$(gdbmtool -N -q -r "$DB" dir | awk '$1 == "0:" { print $3; exit }')
[ -n "$addr" ] || { echo "control-agree: no bucket address in 'dir'" >&2; exit 1; }
printf '\004' | dd of="$DB" bs=1 seek=$((addr + 108)) conv=notrunc status=none
