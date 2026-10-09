set -eu
rm -rf /s/dwarfs /s/dwarfs-in && mkdir -p /s/dwarfs /s/dwarfs-in/src
i=0; while [ $i -lt 40 ]; do head -c 4000 /dev/zero | tr '\0' "$(printf '\\%03o' $((65 + i % 26)))" > /s/dwarfs-in/src/img$i.raw; i=$((i+1)); done
mkdwarfs-work -i /s/dwarfs-in/src -o /s/dwarfs/photos.dwarfs -N 1 -l 1 > /dev/null 2>&1
