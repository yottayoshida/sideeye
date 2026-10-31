#!/bin/sh
# Host side: what each run used — the engine tarball's digest, each image's id, and the version
# each box reports for the tool its rows name. Written to transcripts/versions.txt.
#   TARBALL=<sideeye-v1.17.0-aarch64-linux.tar.gz> TODO_TGZ=<todo.txt_cli-2.14.0.tar.gz> sh versions.sh
: "${TARBALL:?}" "${TODO_TGZ:?}"
echo "engine tarball  $(shasum -a 256 "$TARBALL" | cut -d' ' -f1)  $(basename "$TARBALL")"
echo "todo.txt-cli    $(shasum -a 256 "$TODO_TGZ" | cut -d' ' -f1)  $(basename "$TODO_TGZ")"
for img in sideeye-ud1003 sideeye-ud1005 sideeye-ud1007 sideeye-fu3-1009 sideeye-m1014; do
  echo "image           $img $(docker image inspect --format '{{.Id}} {{.Architecture}}' "$img")"
done
v() { printf '%-15s %s\n' "$1" "$(docker run --rm --network none --entrypoint sh "$2" -c "$3" 2>&1 | tr '\n' ' ' | sed 's/ *$//')"; }
v podman sideeye-ud1003 'podman --version'
v skopeo sideeye-ud1005 'skopeo --version'
v ntfs-3g sideeye-ud1005 'dpkg-query -W ntfs-3g'
v solvespace sideeye-ud1005 'dpkg-query -W solvespace 2>/dev/null || solvespace-cli --version 2>&1 | head -1'
v ziptool sideeye-ud1007 'ls /opt/libzip 2>/dev/null | head -3; dpkg-query -W "libzip*" 2>/dev/null'
v alacritty sideeye-ud1007 '/opt/bin/alacritty --version 2>/dev/null || alacritty --version'
v acme.sh sideeye-ud1007 '/opt/acme.sh-src/acme.sh --version | tail -1'
v zsh-z sideeye-ud1007 'grep -m1 -i "version" /opt/zsh-z/zsh-z.plugin.zsh'
v bash sideeye-ud1007 'bash --version | head -1'
v zstd sideeye-fu3-1009 'zstd --version'
v shadow-utils sideeye-m1014 'dpkg-query -W passwd'
v isync sideeye-m1014 'dpkg-query -W isync'
v dpkg sideeye-m1014 'dpkg-query -W dpkg'
