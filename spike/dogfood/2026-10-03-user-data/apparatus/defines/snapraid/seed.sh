set -eu
rm -rf /s/snapraid /s/snapraid-in && mkdir -p /s/snapraid/d1 /s/snapraid/parity /s/snapraid/content /s/snapraid-in
printf 'parity /s/snapraid/parity/snapraid.parity\ncontent /s/snapraid/content/snapraid.content\ncontent /s/snapraid/d1/snapraid.content\ndata d1 /s/snapraid/d1/\nblocksize 64\n' > /s/snapraid-in/snapraid.conf
head -c 200000 /dev/zero | tr '\0' 'a' > /s/snapraid/d1/photo1.raw
head -c 150000 /dev/zero | tr '\0' 'b' > /s/snapraid/d1/photo2.raw
snapraid -c /s/snapraid-in/snapraid.conf sync > /dev/null 2>&1
head -c 120000 /dev/zero | tr '\0' 'c' > /s/snapraid/d1/photo3.raw
