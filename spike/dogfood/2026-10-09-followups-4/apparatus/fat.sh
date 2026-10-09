#!/bin/sh
# fat.sh umount|mount <dir> [mount options]: a fresh 32 MiB FAT filesystem at <dir>. FAT keeps no mode and
# no owner per file: the mount gives every file the same ones (fmask, dmask, uid, gid), so a target that
# checks its files' mode or owner sees the same in every world, whatever the restore rebuilds (#678).
# `quiet` makes FAT ignore the chmod and chown it cannot store, instead of failing them.
set -eu
op=$1; d=$2; opts=${3:-}
img="/tmp/fat$(echo "$d" | tr / _).img"
if grep -q " $d vfat " /proc/mounts; then umount "$d"; fi
[ "$op" = umount ] && exit 0
rm -f "$img"; truncate -s 32M "$img"; mkfs.vfat -n STATE "$img" > /dev/null
mkdir -p "$d"; mount -o "loop,quiet${opts:+,$opts}" "$img" "$d"
