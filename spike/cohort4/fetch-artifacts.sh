#!/bin/sh
# Fetch the pinned build inputs the cohort-4 image copies in (see
# Dockerfile). This runs on the HOST, not in the container, for the reason
# cohort 2 measured (spike/cohort2/fetch-artifacts.sh): the development
# machine sits behind a TLS-intercepting proxy whose CA a stock Debian
# container does not trust, so in-container pip/curl fail certificate
# verification (apt survives — it is plain HTTP). Downloads run host-side;
# every input is verified against a pin, and the Dockerfile re-verifies
# the copies.
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
#   - unison v2.54.0: the tag's COMMIT, b1a49141e7eb5334e31efcf4d08073c192d6c1ae
#     (a lightweight tag — the ref names the commit directly; read
#     2026-08-23). Same digest re-verification in the Dockerfile
#     (unison-src.digest). No crate closure: unison builds from its own
#     tree with OCaml and make, both from the image's apt layer.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
dest="$here/artifacts"
mkdir -p "$dest"

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

# One content-addressed source checkout: clone at the tag when absent,
# then verify HEAD against the pinned commit either way.
src_at_commit() { # dirname url tag commit
    dir="$dest/$1"
    if [ ! -d "$dir" ]; then
        git clone --quiet --depth 1 --branch "$3" "$2" "$dir"
    fi
    got=$(git -C "$dir" rev-parse HEAD)
    if [ "$got" != "$4" ]; then
        echo "FAIL $1: HEAD $got, wanted $4" >&2
        exit 1
    fi
    echo "ok   $1 at $got"
}

# The source-tree digest the Dockerfile re-verifies. Git metadata is
# excluded on both sides; the digest is over sorted per-file sha256
# lines, a format shasum (host) and sha256sum (image) print identically.
digest_tree() { # dirname
    (cd "$dest/$1" && find . -type f -not -path './.git/*' -print0 \
        | sort -z | xargs -0 -n 64 shasum -a 256 | shasum -a 256 | cut -d' ' -f1) \
        > "$dest/$1.digest"
    echo "ok   $1.digest $(cat "$dest/$1.digest")"
}

# rust: same artifact and pin as cohort 3; reuse its cached copy.
rust=rust-1.98.0-aarch64-unknown-linux-gnu.tar.xz
if [ ! -f "$dest/$rust" ] && [ -f "$here/../cohort3/artifacts/$rust" ]; then
    cp "$here/../cohort3/artifacts/$rust" "$dest/$rust"
fi
fetch "$rust" \
    "https://static.rust-lang.org/dist/2026-08-20/$rust" \
    ac9283184301aeed06ecc9f5aa4c1be7041e18a1b197b6cb6c5d162d98f566da

# himalaya v2.1.0 (annotated tag -> pinned commit).
src_at_commit himalaya-src https://github.com/pimalaya/himalaya.git \
    v2.1.0 ca88bee08ad2e92127b46dc6200d1e8201885156

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

digest_tree himalaya-src

# unison v2.54.0 (lightweight tag -> pinned commit). No aarch64-linux
# release asset exists upstream (measured 2026-08-23: macOS arm64 only),
# so the measured binary is a self-build — the disclosure lives in
# PROTOCOL.md's Versions section.
src_at_commit unison-src https://github.com/bcpierce00/unison.git \
    v2.54.0 b1a49141e7eb5334e31efcf4d08073c192d6c1ae

digest_tree unison-src

echo "artifacts ready in $dest"
