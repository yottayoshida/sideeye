#!/bin/sh
# spike/platforms/build.sh — building from source where no release asset exists (#697, ADR 0105;
# spike/platforms/RUNS-RULE-2026-10-10b.md), on a GitHub Linux runner.
#
#   SIDEEYE_VERSION=v1.10.0 sh spike/platforms/build.sh <out dir>
#
# Zig 0.16.0 (the version the release builds with), fetched for this runner's CPU and checked
# against ziglang.org's published shasum; -Doptimize=ReleaseSafe, as release.yml builds.
#   alpine-src-<ref>   in Alpine 3.22 (musl), the source of SIDEEYE_VERSION and of the checked-out
#                      commit ("main"): does it build, does the result explore the define
#                      (measure.sh), and what does `sideeye demo` do — on SIDEEYE_VERSION it compiles
#                      its toy with the container's cc, on main the toy is carried in the engine
#                      (ADR 0101), which on a musl host was expected to be static
#   cross-<target>     on x86_64: SIDEEYE_VERSION built for the release architectures of Debian 13 the
#                      release has no asset for — riscv64, 32-bit ARM (hard and soft float), i386,
#                      ppc64le and s390x (glibc 2.28, as the release targets are spelled). Built, not
#                      run — the owner's ruling of 2026-10-10
# The checkout must carry SIDEEYE_VERSION's tag (fetch-depth: 0).
set -u
CROSS="riscv64-linux-gnu.2.28 arm-linux-gnueabihf.2.28 x86-linux-gnu.2.28 arm-linux-gnueabi.2.28
       powerpc64le-linux-gnu.2.28 s390x-linux-gnu.2.28"

out=${1:?usage: SIDEEYE_VERSION=<tag> build.sh <out dir>}
V=${SIDEEYE_VERSION:?set SIDEEYE_VERSION to the release tag to measure}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)
t=${RUNNER_TEMP:-/tmp}/platform-build
mkdir -p "$t/src-$V" "$t/src-main" "$t/zig"
ALPINE=alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8

case $(uname -m) in
x86_64)  zarch=x86_64;  zsum=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00 ;;
aarch64) zarch=aarch64; zsum=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17 ;;
*) echo "build: no Zig pinned for $(uname -m)"; exit 2 ;;
esac
curl -fsSL -o "$t/zig.tar.xz" "https://ziglang.org/download/0.16.0/zig-$zarch-linux-0.16.0.tar.xz" || { echo "build: could not fetch Zig"; exit 1; }
[ "$(sha256sum "$t/zig.tar.xz" | cut -d' ' -f1)" = "$zsum" ] || { echo "build: Zig digest mismatch"; exit 1; }
tar -xJf "$t/zig.tar.xz" -C "$t/zig" --strip-components=1

git -C "$root" rev-parse -q --verify "$V^{commit}" > /dev/null || { echo "build: no tag $V in the checkout (fetch-depth: 0)"; exit 1; }
git -C "$root" archive "$V" | tar -x -C "$t/src-$V"
git -C "$root" archive HEAD | tar -x -C "$t/src-main"
{ echo "$V: $(git -C "$root" rev-parse "$V^{commit}")"; echo "main: $(git -C "$root" rev-parse HEAD)"; } > "$out/sources.txt"

echo "== alpine-src"
docker run --rm --privileged --cgroupns=private -v "$root":/ap:ro -v "$t/zig":/zig:ro -v "$t":/t:ro -v "$out":/out \
    -e V="$V" "$ALPINE" sh -c '
    apk add --no-cache gcc musl-dev strace file > /out/alpine-src-apk.txt 2>&1
    apk list -I 2>/dev/null | grep -E "^(musl|gcc|strace)-" >> /out/alpine-src-apk.txt
    mkdir -p /s
    for ref in "$V" main; do
        o=/out/alpine-src-$ref; mkdir -p "$o"
        cp -r /t/src-$ref /b-$ref && cd /b-$ref
        /zig/zig build -Doptimize=ReleaseSafe --prefix /b-$ref/inst > "$o/build.txt" 2>&1
        echo "exit $?" >> "$o/build.txt"
        file /b-$ref/inst/bin/sideeye /b-$ref/inst/lib/* >> "$o/build.txt" 2>&1
        [ -x /b-$ref/inst/bin/sideeye ] || continue
        sh /ap/spike/platforms/measure.sh /b-$ref/inst/bin/sideeye /out alpine-src-$ref > /dev/null
        mkdir -p /tmp/demo-$ref && cd /tmp/demo-$ref
        { /b-$ref/inst/bin/sideeye demo; echo "exit $?"; } > "$o/demo.txt" 2>&1
    done'

cross() { # <target>: build SIDEEYE_VERSION for it, into $t/cross-<target>
    o=$out/cross-$1; mkdir -p "$o"
    rm -rf "$t/b-cross" && cp -r "$t/src-$V" "$t/b-cross"
    ( cd "$t/b-cross" && "$t/zig/zig" build -Doptimize=ReleaseSafe -Dtarget="$1" --prefix "$t/cross-$1" ) > "$o/build.txt" 2>&1
    echo "exit $?" >> "$o/build.txt"
    file "$t/cross-$1/bin/sideeye" "$t/cross-$1/lib/"* >> "$o/build.txt" 2>&1
    tail -3 "$o/build.txt"
}
if [ "$(uname -m)" = x86_64 ]; then
    for target in $CROSS; do
        echo "== cross-$target"
        cross "$target"
    done
fi

# A source leg's result is its build log ending in an exit status and, where the build succeeded,
# a summary with a line per mode and the demo's exit status.
missing=
for ref in "$V" main; do
    b=$out/alpine-src-$ref
    grep -q '^exit ' "$b/build.txt" 2>/dev/null || { missing="$missing alpine-src-$ref"; continue; }
    grep -q '^exit 0' "$b/build.txt" || continue
    [ "$(grep -cE "$(printf '\t')(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$b/summary.txt" 2>/dev/null)" = 3 ] && grep -q '^exit ' "$b/demo.txt" 2>/dev/null || missing="$missing alpine-src-$ref"
done
if [ "$(uname -m)" = x86_64 ]; then
    for target in $CROSS; do
        grep -q '^exit ' "$out/cross-$target/build.txt" 2>/dev/null || missing="$missing cross-$target"
    done
fi
[ -n "$missing" ] && { echo "build: no record from:$missing"; exit 1; }
exit 0
