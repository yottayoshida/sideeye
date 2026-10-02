#!/bin/sh
# Host side of the latest-release check (2026-10-02): tombi v1.7.0 and biome 2.5.15, each
# release binary mounted over the box's own at /opt/bin, the same defines and run.sh.
#
#   sh latest-host.sh <dir holding the two binaries, named tombi and biome> <out dir>
#
# tombi   tombi-cli-1.7.0-aarch64-unknown-linux-musl.tar.gz from tombi-toml/tombi's v1.7.0
# biome   biome-linux-arm64 from biomejs/biome's @biomejs/biome@2.5.15
set -u
here=$(cd "$(dirname "$0")" && pwd); bins=${1:?usage: latest-host.sh <bin dir> <out dir>}; out=${2:?}
mkdir -p "$out"
for pair in tombi:tombi-r1 biome:biome; do
    b=${pair%%:*}; t=${pair##*:}
    shasum -a 256 "$bins/$b"
    docker run --rm --privileged --cgroupns=private --network none \
        -v "$here:/ap:ro" -v "$bins/$b:/opt/bin/$b:ro" -v "$out:/out" \
        sideeye-sv170 sh -c "$b --version; sh /ap/run.sh $t" > "$out/$t.host.txt" 2>&1
    echo "$t: docker exit $? | $(head -1 "$out/$t.host.txt") | $(tr '\n' '|' < "$out/$t/summary.txt" 2>/dev/null | sed -E 's/next_step:[^|]*\|//')"
done
docker run --rm --privileged --cgroupns=private --network none \
    -v "$here:/ap:ro" -v "$bins/tombi:/opt/bin/tombi:ro" -v "$bins/biome:/opt/bin/biome:ro" \
    sideeye-sv170 sh -c 'tombi --version; biome --version; sh /ap/ulimit.sh' > "$out/ulimit.txt" 2>&1
echo "ulimit: docker exit $?"
