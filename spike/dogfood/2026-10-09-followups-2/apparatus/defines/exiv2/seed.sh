set -eu
# 2026-09-05 userview's exiv2 define; the binary is Debian's exiv2, as 2026-09-05 measured #9482.
rm -rf /s/ex && mkdir -p /s/ex
for n in 1 2 3; do ffmpeg -loglevel error -f lavfi -i color=c=green:s=128x128 -frames:v 1 -y "/s/ex/pic$n.jpg"; done
install -m 755 /ap/defines/exiv2/check.sh /s/ex-check.sh
