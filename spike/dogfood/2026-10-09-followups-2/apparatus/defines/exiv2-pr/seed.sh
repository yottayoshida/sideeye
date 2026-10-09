set -eu
# 2026-09-05 userview's exiv2 define; the binary is PR #9504 at 8e2fc85ae2.
rm -rf /s/ex && mkdir -p /s/ex
for n in 1 2 3; do ffmpeg -loglevel error -f lavfi -i color=c=green:s=128x128 -frames:v 1 -y "/s/ex/pic$n.jpg"; done
install -m 755 /ap/defines/exiv2-pr/check.sh /s/ex-check.sh
