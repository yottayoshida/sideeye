#!/bin/sh
# Install a pinned Sideeye release into a directory, verified against the digest GitHub
# publishes for that asset. No Zig, no source checkout of Sideeye (#620, ADR 0080).
#
#   sh install-sideeye.sh <version-tag> <install-dir>
#   sh install-sideeye.sh --selftest
#
# **stdout is the absolute path of the installed binary, and nothing else**; the running
# commentary goes to stderr. So `bin=$(sh install-sideeye.sh v1.6.0 dir)` is the whole of the
# calling convention, and a caller that wants the log still sees it. Copy this file into your
# repository beside your define — it is meant to be vendored, not curl'd: a script fetched at
# run time is a pin you do not hold.
#
# **It needs `curl`, `tar`, `python3` and a sha256 tool** (`sha256sum` or `shasum`), all of
# which GitHub-hosted runners have. It does not need Zig, a compiler, or `gh`.
#
# **The version is an argument with no default.** Following the latest release would mean a
# build you did not choose can turn your gate red, or green.
#
# **What the digest check establishes**, in the words of the page that owns this claim
# (`docs/cli.md`): that the bytes are the ones GitHub holds — not who produced them. The
# digest and the asset are the same account's word. `docs/adr/0061-every-action-is-pinned-by-commit.md`
# records why no checksum file is published beside them and why signatures are deliberately
# unbuilt rather than deferred with a date.
#
# **Why curl and not `gh`**: `docs/cli.md` shows this with `gh api`, which is right for a
# person at a terminal. `gh` needs a token even for a public read, and a copied script runs in
# jobs that may have none, so this reads the same field over plain HTTPS. A token is used when
# one is in the environment, for the rate limit, and the script says which way it went.
#
# **The shim is not passed.** A release tarball unpacks flat, binary beside shim, and Sideeye
# looks beside itself before `../lib` (#78) — so `--shim` would be path surgery for nothing.
set -eu

# Fixed, not overridable: pointing this at another host would move the asset AND the digest
# it is checked against to the same new origin, which is a verification that checks nothing.
REPO=yottayoshida/sideeye
API=https://api.github.com

die() { echo "install-sideeye: $*" >&2; exit 1; }

# --- the three pieces, each taking its inputs as arguments ---------------------------------
#
# Arguments rather than globals so `--selftest` can drive exactly what the install path runs.
# A selftest that re-implements the logic it checks proves nothing about the logic that ships.

# $1 = `uname -s`, $2 = `uname -m`. Prints the asset's platform suffix.
#
# macOS reports `arm64` where the asset is named `aarch64`; a mapping that forgets it does not
# fail loudly, it fails as "no asset for this platform", which reads like a packaging gap.
asset_suffix() {
    _os=$1
    _machine=$2
    case "$_os" in
        Linux)  _os=linux ;;
        Darwin) _os=macos ;;
        *) die "unsupported operating system: $_os (this release publishes linux and macos assets)" ;;
    esac
    case "$_machine" in
        x86_64|amd64)  _arch=x86_64 ;;
        aarch64|arm64) _arch=aarch64 ;;
        *) die "unsupported machine: $_machine (this release publishes x86_64 and aarch64 assets)" ;;
    esac
    echo "$_arch-$_os"
}

# $1 = a file holding the release JSON, $2 = the asset name. Prints the expected sha256 hex.
#
# Two failures, two messages. An asset that is not in the release is a platform this release
# does not cover; an asset with no digest is a release this script will not run unverified.
# Reporting the second as the first sends a reader looking for a packaging gap that is not there.
digest_for() {
    _json=$1
    _name=$2
    _out=$(python3 - "$_json" "$_name" <<'PY'
import json, sys
release, want = json.load(open(sys.argv[1])), sys.argv[2]
assets = release.get("assets") or []
for a in assets:
    if a.get("name") == want:
        d = (a.get("digest") or "").strip()
        if not d.startswith("sha256:") or len(d) != len("sha256:") + 64:
            print("NODIGEST", want)
            break
        print("OK", d[len("sha256:"):])
        break
else:
    print("NOASSET", " ".join(a.get("name", "?") for a in assets) or "(none)")
PY
) || die "could not read the release JSON at $_json"
    case "$_out" in
        "OK "*)        echo "${_out#OK }" ;;
        "NODIGEST "*)  die "the release published no sha256 digest for $_name; refusing to run an asset this script cannot verify" ;;
        "NOASSET "*)   die "no asset named $_name in this release. The release has: ${_out#NOASSET }" ;;
        *)             die "could not parse the release JSON at $_json" ;;
    esac
}

# The one definition of "compute a sha256": Linux ships sha256sum, macOS ships shasum, and a
# machine with neither is refused here rather than at two call sites with two wordings.
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
    else die "no sha256 tool found (looked for sha256sum and shasum)"; fi
}

# $1 = file, $2 = expected sha256 hex. Both hexes are printed on a mismatch: a message naming
# one of them leaves the reader to work out which end moved.
verify_file() {
    _file=$1
    _want=$2
    _got=$(sha256_of "$_file")
    [ "$_got" = "$_want" ] || die "digest mismatch for $_file
  published: $_want
  download:  $_got"
    echo "$_got"
}

# --- selftest ------------------------------------------------------------------------------
#
# Proves this script can go red, on every run, against synthetic input and without the network.
# The repository's rule for a new check is that it is seen red once before it is trusted
# (CLAUDE.md); a selftest is how that survives the commit that introduced it.
selftest() {
    _tmp=$(mktemp -d "${TMPDIR:-/tmp}/install-sideeye-selftest-XXXXXX")
    _fails=0
    _ok()   { echo "ok   $1"; }
    _bad()  { echo "FAIL $1"; _fails=$((_fails + 1)); }
    # A case that must succeed and print exactly $2.
    _want() {
        if _got=$( (asset_suffix $1) 2>&1 ) && [ "$_got" = "$2" ]; then _ok "$1 -> $2"
        else _bad "$1 -> $_got, wanted $2"; fi
    }
    # A case that must fail, with $2 somewhere in the message.
    _wantfail() {
        _what=$1; shift
        _pat=$1; shift
        if _got=$( ("$@") 2>&1 ); then _bad "$_what did not fail: $_got"
        elif ! printf '%s' "$_got" | grep -q "$_pat"; then _bad "$_what failed without naming '$_pat': $_got"
        else _ok "$_what fails and names '$_pat'"; fi
    }

    echo "-- the platform map, including the arm64/aarch64 spelling --"
    _want "Linux x86_64"  x86_64-linux
    _want "Linux aarch64" aarch64-linux
    _want "Darwin arm64"  aarch64-macos
    # A correct mapping, not a promise that the release carries it: v1.6.0 publishes three
    # assets and this is not one of them, so a run on an Intel Mac maps cleanly and then stops
    # at "no asset named" — which is the fail-closed path, not a mapping bug.
    _want "Darwin x86_64" x86_64-macos
    _wantfail "an unknown OS"      "unsupported operating system" asset_suffix Plan9 x86_64
    _wantfail "an unknown machine" "unsupported machine"          asset_suffix Linux s390x

    echo "-- the release JSON --"
    cat > "$_tmp/rel.json" <<'JSON'
{"assets": [
  {"name": "sideeye-vX-x86_64-linux.tar.gz", "digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111"},
  {"name": "sideeye-vX-aarch64-macos.tar.gz", "digest": null},
  {"name": "sideeye-vX-aarch64-linux.tar.gz", "digest": "sha256:short"}
]}
JSON
    if _got=$(digest_for "$_tmp/rel.json" sideeye-vX-x86_64-linux.tar.gz) &&
       [ "$_got" = "1111111111111111111111111111111111111111111111111111111111111111" ]
    then _ok "a published digest is read"; else _bad "a published digest is read: got '$_got'"; fi
    # The two failures must be distinguishable, which is the point of checking the wording:
    # a shared message would send a reader after the wrong cause.
    _wantfail "an asset the release does not have" "no asset named" \
        digest_for "$_tmp/rel.json" sideeye-vX-x86_64-macos.tar.gz
    _wantfail "an asset with a null digest" "published no sha256 digest" \
        digest_for "$_tmp/rel.json" sideeye-vX-aarch64-macos.tar.gz
    _wantfail "an asset with a malformed digest" "published no sha256 digest" \
        digest_for "$_tmp/rel.json" sideeye-vX-aarch64-linux.tar.gz

    echo "-- the digest comparison --"
    printf 'the bytes\n' > "$_tmp/blob"
    _real=$(verify_file "$_tmp/blob" "$(sha256_of "$_tmp/blob")")
    [ -n "$_real" ] && _ok "a matching digest passes" || _bad "a matching digest passes"
    printf 'the bytes, tampered\n' > "$_tmp/tampered"
    _wantfail "a tampered file" "digest mismatch" verify_file "$_tmp/tampered" "$_real"
    # …and it must print BOTH hexes, so the reader can tell which end moved.
    if _msg=$( (verify_file "$_tmp/tampered" "$_real") 2>&1 ); then
        _bad "a tampered file did not fail"
    else
        _other=$(sha256_of "$_tmp/tampered")
        if printf '%s' "$_msg" | grep -q "$_real" && printf '%s' "$_msg" | grep -q "$_other"
        then _ok "the mismatch names both digests"
        else _bad "the mismatch does not name both digests: $_msg"; fi
    fi

    # Removed by name, then the directory itself: a script that runs in someone else's CI
    # should not be able to delete more than it created, and a recursive remove of a path held
    # in a variable is the shape that goes wrong when the variable is empty.
    rm -f "$_tmp/rel.json" "$_tmp/blob" "$_tmp/tampered"
    rmdir "$_tmp" 2>/dev/null || echo "note: $_tmp is not empty and was left in place"
    if [ "$_fails" -ne 0 ]; then echo "selftest: $_fails case(s) failed"; exit 1; fi
    echo "selftest: every case behaved as documented"
}

# --- install -------------------------------------------------------------------------------

if [ "${1:-}" = "--selftest" ]; then selftest; exit 0; fi
[ $# -eq 2 ] || die "usage: install-sideeye.sh <version-tag> <install-dir>   |   install-sideeye.sh --selftest"

tag=$1
dir=$2
suffix=$(asset_suffix "$(uname -s)" "$(uname -m)")
name="sideeye-$tag-$suffix.tar.gz"
mkdir -p "$dir"
dir=$(cd "$dir" && pwd)

# A token is used when the environment has one — for the rate limit, not for access — and the
# job log says which way it went so a 403 reads as a rate limit rather than a mystery.
token=${GH_TOKEN:-${GITHUB_TOKEN:-}}
rel="$API/repos/$REPO/releases/tags/$tag"
if [ -n "$token" ]; then
    echo "install-sideeye: reading $REPO release $tag (authenticated)" >&2
    # The header goes in through `--config -`, not `-H`: a token on the command line is visible
    # to `ps` for everyone on the machine, and this script is written to be copied onto machines
    # whose other tenants are not this job.
    printf 'header = "Authorization: Bearer %s"\n' "$token" |
        curl -fsSL --config - -o "$dir/release.json" "$rel" ||
        die "could not read the release $tag from $REPO (authenticated)"
else
    echo "install-sideeye: reading $REPO release $tag (unauthenticated; shares this runner's rate limit)" >&2
    curl -fsSL -o "$dir/release.json" "$rel" ||
        die "could not read the release $tag from $REPO"
fi

want=$(digest_for "$dir/release.json" "$name")
echo "install-sideeye: $name published digest sha256:$want" >&2

dl=$(python3 - "$dir/release.json" "$name" <<'PY'
import json, sys
for a in json.load(open(sys.argv[1]))["assets"]:
    if a["name"] == sys.argv[2]:
        print(a["browser_download_url"])
        break
PY
) || die "could not read the download URL for $name out of the release JSON"
[ -n "$dl" ] || die "the release JSON holds no download URL for $name"

curl -fsSL -o "$dir/$name" "$dl" || die "could not download $dl"
got=$(verify_file "$dir/$name" "$want")
echo "install-sideeye: downloaded digest matches ($got)" >&2

tar -C "$dir" -xzf "$dir/$name"
bin="$dir/sideeye-$tag-$suffix/sideeye"
[ -x "$bin" ] || die "the tarball did not contain an executable at sideeye-$tag-$suffix/sideeye"

# The version goes into the log before anything is explored, so a report in this job can be
# read against a build later. `version` is also the first thing that would fail if the asset
# for this platform were the wrong one.
echo "install-sideeye: $("$bin" version)" >&2
echo "$bin"
