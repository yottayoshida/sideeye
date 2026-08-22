#!/bin/sh
# Fetch the pinned build inputs the cohort-4 image copies in (see
# Dockerfile). This runs on the HOST, not in the container, for the reason
# cohort 2 measured (spike/cohort2/fetch-artifacts.sh): the development
# machine sits behind a TLS-intercepting proxy whose CA a stock Debian
# container does not trust, so in-container pip/curl fail certificate
# verification. Downloads run host-side; every input is verified against a
# pin, and the Dockerfile re-verifies the copies.
#
# Pins:
#   - rust 1.98.0: sha256 from the Rust channel manifest — the same
#     artifact and pin as cohort 3 (spike/cohort3/fetch-artifacts.sh);
#     cohort 3's cached copy is reused when its hash matches.
#   - himalaya v2.1.0: the tag's COMMIT, ca88bee08ad2e92127b46dc6200d1e8201885156,
#     resolved from the GitHub API on 2026-08-23 (annotated tag object
#     f0886f8b8dab38697dbcc2cd7e34067cb4b3acfc dereferences to it). A git
#     commit id is content-addressed, so verifying HEAD pins the whole
#     tree. The Dockerfile re-verifies the copied tree against
#     himalaya-src.digest (computed below, git metadata excluded). The
#     crate closure comes from `cargo vendor --locked`, and its integrity
#     is enforced again at build time by cargo itself: every vendored
#     package must match the sha256 in himalaya's own committed
#     Cargo.lock, which travels inside the digest-verified tree.
#   - vdirsyncer 0.20.0: pins-wheels.txt, a uv-generated hash lock
#     (command in its header; behind this proxy uv needs --system-certs).
#     All 18 packages in the closure ship wheels at their locked versions
#     (measured 2026-08-23: `pip download --only-binary=:all:` succeeded
#     for every line), so pins-sdist.txt is empty; it exists so the cover
#     check below stays line-exact with cohort 3's.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
dest="$here/artifacts"
mkdir -p "$dest" "$dest/wheels"

# The split files must cover the lock exactly — every LINE, hashes
# included (cohort 3's check, kept verbatim; it was falsified there
# against a deleted hash line).
chk=$(mktemp -d) || exit 1
trap 'rm -f "$chk/split" "$chk/all"; rmdir "$chk" 2>/dev/null' EXIT
sort "$here/pins-wheels.txt" "$here/pins-sdist.txt" > "$chk/split"
sort "$here/pins-all.txt" > "$chk/all"
if ! cmp -s "$chk/split" "$chk/all"; then
    echo "FAIL: pins-wheels.txt + pins-sdist.txt do not cover pins-all.txt exactly (line-level, hashes included)" >&2
    diff "$chk/split" "$chk/all" >&2 || true
    exit 1
fi

sum() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"
    else shasum -a 256 "$1"; fi
}

fetch() {
    name=$1; url=$2; want=$3
    out="$dest/$name"
    if [ -f "$out" ]; then
        got=$(sum "$out" | cut -d' ' -f1)
        [ "$got" = "$want" ] && { echo "ok   $name (cached)"; return 0; }
        echo "stale $name: checksum mismatch, refetching" >&2
        rm -f "$out"
    fi
    curl -fsSL -o "$out" "$url"
    got=$(sum "$out" | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "FAIL $name: sha256 $got, wanted $want" >&2; rm -f "$out"; exit 1; }
    echo "ok   $name"
}

# rust: same artifact and pin as cohort 3; reuse its cached copy.
rust=rust-1.98.0-aarch64-unknown-linux-gnu.tar.xz
if [ ! -f "$dest/$rust" ] && [ -f "$here/../cohort3/artifacts/$rust" ]; then
    cp "$here/../cohort3/artifacts/$rust" "$dest/$rust"
fi
fetch "$rust" \
    "https://static.rust-lang.org/dist/2026-08-20/$rust" \
    ac9283184301aeed06ecc9f5aa4c1be7041e18a1b197b6cb6c5d162d98f566da

# himalaya source at the pinned tag commit (content-addressed).
himalaya_commit=ca88bee08ad2e92127b46dc6200d1e8201885156
if [ ! -d "$dest/himalaya-src" ]; then
    git clone --quiet --depth 1 --branch v2.1.0 \
        https://github.com/pimalaya/himalaya.git "$dest/himalaya-src"
fi
got=$(git -C "$dest/himalaya-src" rev-parse HEAD)
if [ "$got" != "$himalaya_commit" ]; then
    echo "FAIL himalaya-src: HEAD $got, wanted $himalaya_commit" >&2
    exit 1
fi
echo "ok   himalaya-src at $got"

# The crate closure. Skipped when present: cargo re-verifies every crate
# against Cargo.lock at build time, so a stale vendor cannot pass silently.
if [ ! -f "$dest/vendor-config.toml" ] || [ ! -d "$dest/vendor" ]; then
    (cd "$dest/himalaya-src" && cargo vendor --locked "$dest/vendor" > "$dest/vendor-config.toml")
fi
vend_n=$(ls "$dest/vendor" | wc -l | tr -d ' ')
lock_n=$(grep -c '^name = ' "$dest/himalaya-src/Cargo.lock")
if [ "$vend_n" -eq 0 ]; then
    echo "FAIL vendor: 0 crate dirs" >&2
    exit 1
fi
echo "ok   vendor: $vend_n crate dirs (Cargo.lock names $lock_n packages; the difference is himalaya itself, which is not vendored)"

# The source-tree digest the Dockerfile re-verifies. Git metadata is
# excluded on both sides; the digest is over sorted per-file sha256 lines,
# a format shasum (host) and sha256sum (image) print identically.
(cd "$dest/himalaya-src" && find . -type f -not -path './.git/*' -print0 \
    | sort -z | xargs -0 -n 64 shasum -a 256 | shasum -a 256 | cut -d' ' -f1) \
    > "$dest/himalaya-src.digest"
echo "ok   himalaya-src.digest $(cat "$dest/himalaya-src.digest")"

# Wheels: hash-verified by pip against the lock. No sdist download step:
# pins-sdist.txt is empty (see header), and the cover check above proves
# nothing was dropped to make it so.
python3 -m pip download --require-hashes --no-deps -r "$here/pins-wheels.txt" \
    --only-binary=:all: --python-version 3.13 --implementation cp \
    --platform manylinux_2_28_aarch64 --platform manylinux_2_17_aarch64 \
    --platform manylinux2014_aarch64 \
    -d "$dest/wheels"

echo "artifacts ready in $dest"
