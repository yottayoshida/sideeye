#!/bin/sh
# spike/platforms/runner.sh — a GitHub Linux runner's leg of the platform probe (#697, ADR 0105),
# run by .github/workflows/spike-platforms.yml on an x86_64 and an aarch64 runner.
#
#   SIDEEYE_VERSION=v1.10.0 sh spike/platforms/runner.sh <out dir>
#
# The engine is the released SIDEEYE_VERSION, installed the way docs/ci-quickstart.md installs
# it (install-sideeye.sh: the asset picked by `uname`, its digest checked, GH_TOKEN used for the
# API when the environment has one). Then measure.sh, the same define, in five places, so each
# platform's answer is read beside the release target's own from the same run and engine:
#   host                the runner itself (Ubuntu 24.04, glibc 2.39) — the release target, and
#                       the control the other legs on this runner are read against
#                       (RUNS-RULE.md). As its own user, inside a cgroup delegated to that user:
#                       a runner's shell sits in one root owns, where --observe supervised is a
#                       setup error by design (spike/in-delegated-cgroup.sh)
#   rocky8-privileged   Rocky Linux 8 (glibc 2.28, the floor the builds target) as root, with
#                       --privileged and its own cgroup namespace
#   rocky8-defaults     the same with docker run's defaults: no --privileged
#   alpine-bare         Alpine 3.22 (musl) as shipped: whether the binary starts at all
#   alpine-gcompat      the same after gcompat and strace are added
# Images are pinned by their multi-architecture index digest. Every leg runs whatever the one
# before it did. The exit status is non-zero when the engine could not be installed or a leg
# left no record, so a job that measured nothing does not read as one that measured.
set -u

out=${1:?usage: SIDEEYE_VERSION=<tag> runner.sh <out dir>}
V=${SIDEEYE_VERSION:?set SIDEEYE_VERSION to the release tag to measure}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)

ROCKY=rockylinux:8@sha256:9794037624aaa6212aeada1d28861ef5e0a935adaf93e4ef79837119f2a2d04c
ALPINE=alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8

bin=$(sh "$root/docs/ci-quickstart/release/install-sideeye.sh" "$V" "${RUNNER_TEMP:-/tmp}/sideeye-$V" 2> "$out/install.txt") || {
    echo "runner: the engine could not be installed"; cat "$out/install.txt"; exit 1
}
se_dir=$(dirname "$bin")
{
    for f in "$bin" "$se_dir"/libsideeye_shim.so; do
        echo "== $f"
        file "$f" 2>&1
        echo "newest glibc symbol versions it asks for:"
        objdump -T "$f" 2>&1 | grep -o 'GLIBC_[0-9.]*' | sort -u -V | tail -3
    done
} > "$out/binary.txt"

if ! command -v strace > /dev/null; then
    { sudo apt-get update -qq && sudo apt-get install -y -qq strace; } > "$out/apt.txt" 2>&1
fi
sudo mkdir -p /s && sudo chown "$(id -u):$(id -g)" /s

echo "== host"
sh "$root/spike/in-delegated-cgroup.sh" sh "$here/measure.sh" "$bin" "$out" host

for how in privileged defaults; do
    echo "== rocky8-$how"
    set -- --rm -v "$root":/ap:ro -v "$se_dir":/se:ro -v "$out":/out
    [ "$how" = privileged ] && set -- "$@" --privileged --cgroupns=private
    docker run "$@" "$ROCKY" sh -c "
        dnf -q -y install strace > /out/rocky8-$how-dnf.txt 2>&1
        mkdir -p /s
        sh /ap/spike/platforms/measure.sh /se/sideeye /out rocky8-$how"
done

echo "== alpine"
docker run --rm --privileged --cgroupns=private -v "$root":/ap:ro -v "$se_dir":/se:ro -v "$out":/out "$ALPINE" sh -c '
    mkdir -p /out/alpine-bare
    { /se/sideeye version; echo "exit $?"; } > /out/alpine-bare/version.txt 2>&1
    cat /out/alpine-bare/version.txt
    apk add --no-cache gcompat strace > /out/alpine-gcompat-apk.txt 2>&1
    apk list -I 2>/dev/null | grep -E "^(musl|gcompat|strace)-" >> /out/alpine-gcompat-apk.txt
    mkdir -p /s
    sh /ap/spike/platforms/measure.sh /se/sideeye /out alpine-gcompat'

missing=
for leg in host rocky8-privileged rocky8-defaults alpine-gcompat; do
    [ "$(grep -c . "$out/$leg/summary.txt" 2>/dev/null)" = 3 ] || missing="$missing $leg"
done
[ -s "$out/alpine-bare/version.txt" ] || missing="$missing alpine-bare"
if [ -n "$missing" ]; then
    echo "runner: no complete record from:$missing"
    exit 1
fi
