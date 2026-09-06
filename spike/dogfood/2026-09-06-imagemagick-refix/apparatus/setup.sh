#!/bin/sh
# 元の報告と同じ形。1 枚だけにして探索を短くする。
rm -rf /work/im
mkdir -p /work/im
/usr/bin/magick -size 128x128 xc:red /work/im/img1.png
