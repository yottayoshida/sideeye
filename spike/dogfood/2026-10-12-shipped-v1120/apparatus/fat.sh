#!/bin/sh
# fat.sh umount|mount <dir>: a fresh 32 MiB FAT filesystem at <dir>, for a target that takes another
# path where the filesystem has no O_TMPFILE and no ACL (Qt's and libglnx's named-temporary fallback,
# vim writing no ACL back). The image lives outside the state; `umount` first so a seed can rebuild.
set -eu
op=$1; d=$2; img="/tmp/fat$(echo "$d" | tr / _).img"
if grep -q " $d vfat " /proc/mounts; then umount "$d"; fi
[ "$op" = umount ] && exit 0
rm -f "$img"; truncate -s 32M "$img"; mkfs.vfat -n STATE "$img" > /dev/null
mkdir -p "$d"; mount -o loop "$img" "$d"
