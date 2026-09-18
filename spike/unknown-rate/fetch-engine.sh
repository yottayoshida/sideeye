#!/bin/sh
# Fetch the released Sideeye build a generation is pinned to and stage it in
# the zig-out layout (#619, ADR 0073). Reads the generation's row — tag, asset,
# sha256 as GitHub publishes it — from engine-pins.tsv (the one reader of that
# file on the host; sweep.sh takes the tag and asset back from this script's
# output rather than reading the row a second time by another key), downloads
# the asset once, refuses on a digest mismatch, and unpacks it to
# engine/<asset>/zig-out/{bin/sideeye,lib/libsideeye_shim.so}, which sweep.sh
# mounts read-only at /work/zig-out in place of a build of the checkout. The
# directory is keyed by the asset's name, not the tag: two generations may pin
# one tag's two assets (an aarch64 and an x86_64 build), and a tag-keyed
# directory would hand the second the first's binary with the pin check
# still passing. Run on the HOST (gh needs the network; the container has none).
#
# Idempotent: an asset already on disk is re-verified, not re-downloaded, and an
# already-staged tree is not unpacked again. The staged directory is ignored by
# git; the pin is the committed record.
#
# Usage: fetch-engine.sh <generation>
#   prints one line on stdout:  <engine dir>\t<tag>\t<asset>\t<sha256>
set -u

gen=${1:-}
[ -n "$gen" ] || { echo "fetch-engine: usage: fetch-engine.sh <generation>" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
pins=$here/engine-pins.tsv
[ -f "$pins" ] || { echo "fetch-engine: $pins missing" >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { echo "fetch-engine: sha256sum not found (select-b2.sh and sweep.sh need it too)" >&2; exit 2; }

row=$(awk -F'\t' -v g="$gen" '!/^#/ && NF == 4 && $1 == g {print; exit}' "$pins")
[ -n "$row" ] || { echo "fetch-engine: no pin for generation $gen in engine-pins.tsv" >&2; exit 2; }
tag=$(printf '%s\n' "$row" | cut -f2)
asset=$(printf '%s\n' "$row" | cut -f3)
psha=$(printf '%s\n' "$row" | cut -f4)
case "$psha" in ''|*[!0-9a-f]*) echo "fetch-engine: pin sha256 for $gen is not lowercase hex" >&2; exit 2 ;; esac
[ "${#psha}" -eq 64 ] || { echo "fetch-engine: pin sha256 for $gen is not 64 hex chars" >&2; exit 2; }

engdir=$here/engine/${asset%.tar.gz}
mkdir -p "$engdir" || exit 2
tarball=$engdir/$asset

if [ ! -f "$tarball" ]; then
    command -v gh >/dev/null 2>&1 || { echo "fetch-engine: gh not found" >&2; exit 2; }
    gh release download "$tag" -R yottayoshida/sideeye -p "$asset" -D "$engdir" >/dev/null 2>&1 \
        || { echo "fetch-engine: gh release download $tag $asset failed" >&2; exit 2; }
fi
got=$(sha256sum "$tarball" | cut -d' ' -f1)
[ "$got" = "$psha" ] || {
    echo "fetch-engine: $asset sha256 $got does not match the pin $psha — not staging it" >&2
    exit 2
}

# The archive is flat: <name>/sideeye and <name>/libsideeye_shim.so beside two
# licence files (measured on v1.5.0). The two the sweep needs are extracted
# straight into the zig-out layout — no scratch directory, so nothing here has
# to be removed afterwards (a recursive rm on the host is a guarded operation
# on this workspace, and the first draft died on it).
bin=$engdir/zig-out/bin/sideeye
lib=$engdir/zig-out/lib/libsideeye_shim.so
if [ ! -f "$bin" ] || [ ! -f "$lib" ]; then
    members=$(tar -tzf "$tarball") || { echo "fetch-engine: tar cannot list $asset" >&2; exit 2; }
    top=$(printf '%s\n' "$members" | head -n 1 | cut -d/ -f1)
    [ -n "$top" ] || { echo "fetch-engine: $asset lists no members" >&2; exit 2; }
    printf '%s\n' "$members" | grep -qx "$top/sideeye" && printf '%s\n' "$members" | grep -qx "$top/libsideeye_shim.so" \
        || { echo "fetch-engine: $asset does not carry $top/sideeye and $top/libsideeye_shim.so" >&2; exit 2; }
    mkdir -p "$engdir/zig-out/bin" "$engdir/zig-out/lib" || exit 2
    tar -xzf "$tarball" -C "$engdir/zig-out/bin" --strip-components=1 "$top/sideeye" "$top/libsideeye_shim.so" \
        && mv "$engdir/zig-out/bin/libsideeye_shim.so" "$lib" \
        && chmod 755 "$bin" || { echo "fetch-engine: tar failed on $asset" >&2; exit 2; }
fi
[ -f "$bin" ] && [ -f "$lib" ] || { echo "fetch-engine: staging left no engine at $engdir/zig-out" >&2; exit 2; }
printf '%s\t%s\t%s\t%s\n' "$engdir" "$tag" "$asset" "$psha"
