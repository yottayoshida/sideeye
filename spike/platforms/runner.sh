#!/bin/sh
# spike/platforms/runner.sh — a GitHub Linux runner's leg of the platform probe (#697, ADR 0105),
# run by .github/workflows/spike-platforms.yml.
#
#   SIDEEYE_VERSION=v1.10.0 [LEGS=all|host] sh spike/platforms/runner.sh <out dir>
#
# The engine is the released SIDEEYE_VERSION, installed the way docs/ci-quickstart.md installs
# it (install-sideeye.sh: the asset picked by `uname`, its digest checked, GH_TOKEN used for the
# API when the environment has one). Then measure.sh, the same define, in these places:
#   host                the runner itself, as its own user, inside a cgroup delegated to that user —
#                       a runner's shell sits in one root owns, where --observe supervised is a
#                       setup error by design (spike/in-delegated-cgroup.sh). On Ubuntu 24.04 it is
#                       the release target and the control the other legs are read against; on
#                       22.04 and 26.04 it is that release's kernel and glibc (LEGS=host)
# and, with LEGS=all (the default; the 24.04 runners):
#   rocky8-privileged   Rocky Linux 8 (glibc 2.28) as root, --privileged, its own cgroup namespace
#   rocky8-defaults     the same with docker run's defaults: no --privileged
#   alpine-bare         Alpine 3.22 (musl) as shipped: whether the binary starts at all
#   alpine-gcompat      the same after gcompat and strace are added
#   centos7, debian9    glibc 2.17 and 2.24, older than the 2.28 the builds target: whether it starts
#   nixos-bare          nixos/nix: Nix, and no loader at the path the binaries name
#   nixos-nix-ld        the same with nix-ld at that path and NIX_LD naming glibc's loader
#   nixos-loader        the binary started through glibc's loader named on the command line
#   nixos-loader-shim   the same with --shim naming the shim, which that start cannot find itself
#   hardened-cli        docs/mcp.md's container flags (this runner's user, no network, read-only root,
#   hardened-mcp        /tmp a tmpfs, no capabilities, no new privileges), the state on the /work mount; explored
#                       through the CLI, then through `sideeye mcp` with the page's first call
# Images are pinned by their multi-architecture index digest; nixpkgs by its commit and the hash
# of its unpacked tree. Every leg
# runs whatever the one before it did. The exit status is non-zero when the engine could not be
# installed or a leg left no record, so a job that measured nothing does not read as one that did.
# The first five legs and their order are the 2026-10-10 record's.
set -u

out=${1:?usage: SIDEEYE_VERSION=<tag> [LEGS=all|host] runner.sh <out dir>}
V=${SIDEEYE_VERSION:?set SIDEEYE_VERSION to the release tag to measure}
LEGS=${LEGS:-all}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)

ROCKY=rockylinux:8@sha256:9794037624aaa6212aeada1d28861ef5e0a935adaf93e4ef79837119f2a2d04c
ALPINE=alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8
CENTOS7=centos:7@sha256:be65f488b7764ad3638f236b7b515b3678369a5124c47b8d32916d6487418ea4
DEBIAN9=debian:9@sha256:c5c5200ff1e9c73ffbf188b4a67eb1c91531b644856b4aefe86a58d2f0cb05be
NIX=nixos/nix@sha256:7a007c766426c1877758ddc5cb87a965ac131fc78c582ce0083d922d51ae945c
NIXPKGS=https://github.com/NixOS/nixpkgs/archive/7c8764b7c7b09b34f632464276218ef9090eaa11.tar.gz
NIXPKGS_HASH=01ybz131ld1aq6n302jq4wqpjd7d57wz9pxnjw4ly53dy6sn8s1i

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

want="host"
if [ "$LEGS" = all ]; then
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

    for leg in centos7 debian9; do
        echo "== $leg"
        img=$CENTOS7; [ "$leg" = debian9 ] && img=$DEBIAN9
        docker run --rm -v "$se_dir":/se:ro -v "$out":/out "$img" sh -c "
            mkdir -p /out/$leg
            { ldd --version 2>&1 | head -1; /se/sideeye version; echo \"exit \$?\"; } > /out/$leg/version.txt 2>&1
            cat /out/$leg/version.txt"
    done

    echo "== nixos"
    docker run --rm --privileged --cgroupns=private -v "$root":/ap:ro -v "$se_dir":/se:ro -v "$out":/out -e NIXPKGS="$NIXPKGS" -e NIXPKGS_HASH="$NIXPKGS_HASH" "$NIX" sh -c '
        set -u
        o=/out/nixos-bare; mkdir -p "$o"
        { nix --version; /se/sideeye version; echo "exit $?"; } > "$o/version.txt" 2>&1
        cat "$o/version.txt"
        got=$(nix-prefetch-url --unpack --print-path "$NIXPKGS" 2>> /out/nixos-build.txt)
        set -- $got
        [ "${1:-}" = "$NIXPKGS_HASH" ] || { echo "nixos: nixpkgs hash ${1:-none}, wanted $NIXPKGS_HASH" | tee -a /out/nixos-build.txt; exit 1; }
        pkgs=$2
        b() { nix-build "$pkgs" -A "$1" --no-out-link 2>> /out/nixos-build.txt; }
        glibc=$(b glibc); nixld=$(b nix-ld); strace=$(b strace)
        echo "glibc $glibc"; echo "nix-ld $nixld"; echo "strace $strace"
        [ -n "$glibc" ] && [ -n "$nixld" ] && [ -n "$strace" ] || { echo "nixos: nixpkgs did not build"; exit 1; }
        export PATH="$strace/bin:$PATH"
        case $(uname -m) in x86_64) ld=/lib64/ld-linux-x86-64.so.2 ;; aarch64) ld=/lib/ld-linux-aarch64.so.1 ;; esac
        mkdir -p "$(dirname "$ld")" /s
        ln -sf "$nixld/libexec/nix-ld" "$ld"
        NIX_LD=$glibc/lib/$(basename "$ld") NIX_LD_LIBRARY_PATH=$glibc/lib sh /ap/spike/platforms/measure.sh /se/sideeye /out nixos-nix-ld
        rm -f "$ld"
        printf "#!/bin/sh\nexec %s /se/sideeye \"\$@\"\n" "$glibc/lib/$(basename "$ld")" > /tmp/sideeye-via-loader
        chmod +x /tmp/sideeye-via-loader
        sh /ap/spike/platforms/measure.sh /tmp/sideeye-via-loader /out nixos-loader
        SHIM=/se/libsideeye_shim.so sh /ap/spike/platforms/measure.sh /tmp/sideeye-via-loader /out nixos-loader-shim'

    echo "== hardened"
    # The page's flags include --user (ADR 0114): the server runs as this runner's user, so it
    # writes the /work mount that user made, and nothing it leaves there is root's. Until
    # 2026-10-10 the page had no --user and this leg handed /work to root instead; a root with no
    # capability cannot write a directory another user owns, and a root that can write the mount
    # can leave a setuid-root file on the host.
    docker build -q -t sideeye-platforms-hardened -f "$here/hardened.Dockerfile" "$here" > "$out/hardened-build.txt" 2>&1
    hw=$out/hardened-work; mkdir -p "$hw/s/st"
    sed "s#/s/#/work/s/#g" "$here/define/sideeye.toml" > "$hw/sideeye.toml"
    set -- --rm --user "$(id -u):$(id -g)" --network=none --read-only --tmpfs /tmp:exec --cap-drop=ALL --security-opt no-new-privileges \
        -v "$root":/ap:ro -v "$se_dir":/se:ro -v "$hw":/work
    docker run "$@" sideeye-platforms-hardened sh -c 'S=/work/s sh /ap/spike/platforms/measure.sh /se/sideeye /work hardened-cli'
    meta='"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}'
    printf '%s\n%s\n' \
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{$meta}}" \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{$meta,\"name\":\"sideeye_explore_config\",\"arguments\":{\"config_path\":\"/work/sideeye.toml\"}}}" \
        | docker run -i "$@" -e SIDEEYE_MCP_ROOT=/work -e SIDEEYE_MCP_ORACLE=/usr/bin/strace \
            sideeye-platforms-hardened sh -c '
                printf "new contents\n" > /work/s/new
                rm -rf /work/s/st && mkdir -p /work/s/st && printf "old contents\n" > /work/s/st/a.txt
                /se/sideeye mcp > /work/mcp-response.jsonl 2> /work/mcp-stderr.txt
                echo "mcp exit $?" >> /work/mcp-stderr.txt'
    mkdir -p "$out/hardened-mcp"
    mv "$hw/mcp-response.jsonl" "$hw/mcp-stderr.txt" "$out/hardened-mcp/" 2>/dev/null
    [ -d "$hw/hardened-cli" ] && mv "$hw/hardened-cli" "$out/hardened-cli"
    want="host rocky8-privileged rocky8-defaults alpine-gcompat nixos-nix-ld nixos-loader nixos-loader-shim hardened-cli"
fi

missing=
for leg in $want; do
    [ "$(grep -cE "$(printf '\t')(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$out/$leg/summary.txt" 2>/dev/null)" = 3 ] || missing="$missing $leg"
done
if [ "$LEGS" = all ]; then
    for f in alpine-bare/version.txt centos7/version.txt debian9/version.txt nixos-bare/version.txt; do
        [ -s "$out/$f" ] || missing="$missing $f"
    done
    # The MCP leg's result is the tools/call answer carrying a verdict, not any output at all.
    grep '"id":2' "$out/hardened-mcp/mcp-response.jsonl" 2>/dev/null | grep -q '"verdict"' || missing="$missing hardened-mcp"
fi
if [ -n "$missing" ]; then
    echo "runner: no complete record from:$missing"
    exit 1
fi
