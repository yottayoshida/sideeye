#!/bin/sh
# Host side of this run's probes — everything that is not run.sh or modes.sh: the docker
# commands, which the first review found missing. One box per probe, no network.
#
#   sh probes-host.sh <out dir>
set -u
here=$(cd "$(dirname "$0")" && pwd); out=${1:?usage: probes-host.sh <out dir>}; mkdir -p "$out"
esc=$(printf '\033')
box() { name=$1; shift
    docker run --rm --privileged --cgroupns=private --network none -v "$here:/ap:ro" sideeye-uj170 "$@" > "$out/$name.raw" 2>&1
    rc=$?; sed "s/${esc}\[[0-9;]*m//g" "$out/$name.raw" > "$out/$name.txt"; echo "$name: docker exit $rc"; }
docker image inspect sideeye-uj170 --format 'box sideeye-uj170 {{.Id}} created {{.Created}}'
date -u +'started %Y-%m-%dT%H:%M:%SZ'
box ulimit sh /ap/ulimit.sh
box mutool-latest sh /ap/mutool-latest.sh
box write-paths sh /ap/write-paths.sh
box report-evidence-ktlint sh /ap/report-evidence.sh ktlint
box report-evidence-git-cliff sh /ap/report-evidence.sh git-cliff
box versions sh -c 'npm ls -g --depth=0 2>/dev/null | grep -E "joplin|prettier|svgo|eslint|stylelint|js-beautify|bitwarden"; dpkg-query -W -f "\${Package} \${Version}\n" mupdf-tools fontforge flac beets zstd lz4 bat ccache meson fish vim rrdtool ormolu ocrmypdf git 2>/dev/null'
