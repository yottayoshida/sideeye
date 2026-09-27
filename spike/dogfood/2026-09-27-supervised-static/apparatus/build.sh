#!/bin/sh
# Build the box for the 2026-09-27 supervised-static run, and the engine it measures.
#
#   ASSETS=<dir with the five release files> ZIG=<dir holding a Linux zig 0.16.0> sh build.sh
#
# Two things, both before anything is measured:
#
#   1. The five release files are checked against the digests below — the values the
#      projects' own checksums files publish (checked on 2026-09-27 against
#      chezmoi_2.72.1_checksums.txt, gh_2.97.0_checksums.txt, gopass_1.17.0_SHA256SUMS,
#      lefthook_checksums.txt) and, for jj, the value spike/cohort2 pinned. A file that does
#      not match stops the build by name.
#   2. The engine is built from this checkout (ReleaseSafe, as the release workflow builds it)
#      in the image the run uses. **It is not a shipped build**: `--observe supervised` is not
#      released yet (SELECTION.md). The commit it was built from and the binary's digest are
#      printed, and the build refuses when src/, shim/ or build.zig differ from that commit.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"
ASSETS=${ASSETS:?ASSETS must name the directory holding the release files}
ZIG=${ZIG:?ZIG must name the directory holding a Linux zig 0.16.0}

CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then cp "$CA_PEM" "$here/proxy-ca.pem"; else : > "$here/proxy-ca.pem"; fi

mkdir -p "$here/assets"
while read -r sum name; do
    got=$(shasum -a 256 "$ASSETS/$name" | cut -d' ' -f1)
    [ "$got" = "$sum" ] || { echo "build: $name is $got, wanted $sum" >&2; exit 1; }
    cp "$ASSETS/$name" "$here/assets/$name"
    echo "build: $name  sha256 $sum  ok" >&2
done <<'SUMS'
73ea440ecad9c9e284429997ee6f93577bc6f7bc6fba357ef62c53ad8fb641a5 gh_2.97.0_linux_arm64.tar.gz
1e61c71d221143e4c2351c551a6ae66d36b62cce1d916cad67c40c4bd9211530 lefthook_1.13.6_Linux_arm64
75508ef41216b6d64f3145986b751729d7f92d09c6bad77d51cf2895ab35a508 chezmoi_2.72.1_linux_arm64.tar.gz
dc716451c395264e47e3f13702cdab4a7721f375a7465f6969c872f7c75092e2 gopass-1.17.0-linux-arm64.tar.gz
60d42fa2a9abaa445eff10cd2087458562aaad5a54b90309e5a3787ecc985ff2 jj-v0.44.0-aarch64-unknown-linux-musl.tar.gz
SUMS

docker build -t sideeye-217s "$here"

git -C "$root" diff --quiet HEAD -- src shim build.zig build.zig.zon \
    || { echo "build: src/, shim/ or build.zig differ from HEAD; the engine would not be the commit named" >&2; exit 1; }
docker run --rm -v "$root":/work -v "$ZIG":/zig:ro -w /work -e ZIG_GLOBAL_CACHE_DIR=/work/.zig-cache/global \
    sideeye-217s /zig/zig build -Doptimize=ReleaseSafe
echo "build: engine built from $(git -C "$root" rev-parse HEAD)" >&2
docker run --rm -v "$root":/work:ro sideeye-217s sh -c \
    'sha256sum /work/zig-out/bin/sideeye /work/zig-out/lib/libsideeye_shim.so; /work/zig-out/bin/sideeye version' >&2
