#!/bin/sh
# Host side of the #684 re-measurement. Builds the image (once), then runs one of the two steps
# in it: `survey` (plan step 4a, strace alone, before the engine changed) or `measure` (plan
# steps 4b-4c, the engine under test). The engine is mounted, not installed: <engine-dir> is a
# `zig build -Dtarget=aarch64-linux-gnu --prefix <engine-dir>` of the commit RESULTS.md names,
# and measure.sh records its digest. `sideeye version` cannot tell builds apart (it prints the
# version string the source carries), so the digest and the commit are the record.
#
#   sh host.sh survey  <out-dir>
#   sh host.sh measure <out-dir> <engine-dir> <commit>
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"
step=${1:?usage: host.sh survey|measure <out-dir> [<engine-dir> <commit>]}
out=${2:?out-dir}
mkdir -p "$out"

CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then cp "$CA_PEM" "$here/proxy-ca.pem"; else : > "$here/proxy-ca.pem"; fi
docker image inspect sideeye-ro684 > /dev/null 2>&1 || docker build -t sideeye-ro684 "$here" > "$out/build.txt" 2>&1
docker run --rm sideeye-ro684 cat /versions.txt > "$out/versions.txt"

case "$step" in
survey)
    docker run --rm --privileged --cgroupns=private --network none \
        -v "$here:/ap:ro" -v "$root/src:/src:ro" -v "$out:/out" sideeye-ro684 sh /ap/survey.sh ;;
measure)
    eng=${3:?engine-dir}; commit=${4:?commit}
    docker run --rm --privileged --cgroupns=private --network none -e ENGINE_COMMIT="$commit" \
        -v "$here:/ap:ro" -v "$eng:/eng:ro" -v "$out:/out" sideeye-ro684 sh /ap/measure.sh ;;
*) echo "host.sh: unknown step $step" >&2; exit 2 ;;
esac
