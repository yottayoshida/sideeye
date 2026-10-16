#!/bin/sh
# release-upload-missing.sh <tag> <dir>          upload the dir's tarballs the release lacks
# release-upload-missing.sh --selftest           against a fake gh
# release-upload-missing.sh --check-workflow <release.yml>
set -eu

upload_missing() {
    tag=$1 dir=$2 repo=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY names the repository}
    listing=$(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[] | "\(.name)\t\(.state)"')
    failed=0
    for f in "$dir"/*.tar.gz; do
        [ -f "$f" ] || { echo "release-upload-missing: no tarball in $dir" >&2; return 1; }
        name=$(basename "$f")
        state=$(printf '%s\n' "$listing" | awk -F'\t' -v n="$name" '$1 == n { print $2 }')
        case "$state" in
            # Not replaced: a rebuilt tarball has new bytes, and the formula and the MCP
            # container pin this asset's digest.
            uploaded) echo "kept $name: already on $tag, digest unchanged"; continue ;;
            "") clobber="" done_msg="uploaded $name" ;;
            *) clobber=--clobber done_msg="replaced $name: it was $state, not uploaded" ;;
        esac
        # Not `gh ... && echo`: under `set -e` a failure there is ignored, and the job ends green.
        if gh release upload "$tag" "$f" $clobber --repo "$repo"; then
            echo "$done_msg"
        else
            echo "FAIL $name did not upload to $tag" >&2
            failed=$((failed + 1))
        fi
    done
    [ "$failed" = 0 ]
}

check_workflow() {
    wf=$1
    code=$(grep -v '^[[:space:]]*#' "$wf" || true)
    if printf '%s\n' "$code" | grep -q -e '--clobber' -e 'gh release upload' -e 'gh release delete-asset'; then
        echo "FAIL $wf uploads or deletes an asset itself, not through spike/release-upload-missing.sh"; return 1
    fi
    printf '%s\n' "$code" | grep -Eq '^[[:space:]]*(-[[:space:]]+)?(run:[[:space:]]*)?sh spike/release-upload-missing\.sh "\$TAG"' ||
        { echo "FAIL $wf has no step that runs spike/release-upload-missing.sh \"\$TAG\""; return 1; }
    echo "ok   $wf uploads only through spike/release-upload-missing.sh"
}

selftest() {
    here=$(cd "$(dirname "$0")" && pwd)
    t=$(mktemp -d "${TMPDIR:-/tmp}/upload-missing.XXXXXX")
    mkdir -p "$t/bin" "$t/dist"
    cat > "$t/bin/gh" <<'GH'
#!/bin/sh
case "$1 $2" in
    "release view") printf '%s' "$FAKE_ASSETS"; [ -z "$FAKE_ASSETS" ] || echo ;;
    "release upload")
        name=$(basename "$4"); clob=no
        [ "$name" = "${FAKE_FAIL:-}" ] && exit 1
        for a in "$@"; do [ "$a" = --clobber ] && clob=yes; done
        if printf '%s\n' "$FAKE_ASSETS" | cut -f1 | grep -qx "$name" && [ "$clob" = no ]; then
            echo "asset under the same name already exists: $name" >&2; exit 1
        fi
        echo "$name $clob" >> "$FAKE_LOG" ;;
    *) exit 2 ;;
esac
GH
    chmod +x "$t/bin/gh"
    for n in x86_64-linux aarch64-linux aarch64-macos; do : > "$t/dist/sideeye-v9-$n.tar.gz"; done
    a=sideeye-v9-aarch64-linux.tar.gz m=sideeye-v9-aarch64-macos.tar.gz x=sideeye-v9-x86_64-linux.tar.gz
    fails=0 runs=0
    want() {
        runs=$((runs + 1))
        : > "$t/log"
        out=$(FAKE_FAIL=${4:-} FAKE_ASSETS=$2 FAKE_LOG="$t/log" PATH="$t/bin:$PATH" GITHUB_REPOSITORY=o/r sh "$here/release-upload-missing.sh" v9 "$t/dist" 2>&1) && rc=0 || rc=$?
        got=$(sort "$t/log" | tr '\n' ';')
        if [ -n "${4:-}" ] && [ "$rc" = 0 ]; then echo "FAIL $1: exited 0 with $4 not uploaded"; fails=$((fails + 1))
        elif [ -z "${4:-}" ] && [ "$rc" != 0 ]; then echo "FAIL $1: exited $rc: $out"; fails=$((fails + 1))
        elif [ "$got" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: uploaded [$got], wanted [$3]"; fails=$((fails + 1)); fi
    }
    tab=$(printf '\t')
    want "a fresh release takes all three" "" "$a no;$m no;$x no;"
    want "a release missing one takes only that one, without --clobber" "$a${tab}uploaded
$x${tab}uploaded" "$m no;"
    want "a complete release takes nothing" "$a${tab}uploaded
$m${tab}uploaded
$x${tab}uploaded" ""
    want "an asset that never finished uploading is replaced, alone" "$a${tab}starter
$m${tab}uploaded
$x${tab}uploaded" "$a yes;"
    want "a failed upload, first in order, fails the run after the others are tried" "" "$m no;$x no;" "$a"
    want "a failed replacement fails the run" "$a${tab}uploaded
$m${tab}starter
$x${tab}uploaded" "" "$m"
    want_wf() {
        runs=$((runs + 1))
        printf 'jobs:\n  upload:\n    steps:\n%s\n' "$3" > "$t/wf.yml"
        if check_workflow "$t/wf.yml" > /dev/null; then got=passes; else got=refused; fi
        if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: $got"; fails=$((fails + 1)); fi
    }
    want_wf "a workflow uploading with --clobber is refused" refused \
        '      - run: gh release upload "$TAG" dist/*.tar.gz --clobber'
    want_wf "a workflow calling this script passes, a comment naming --clobber aside" passes \
        '      # not --clobber
      - run: sh spike/release-upload-missing.sh "$TAG" dist'
    want_wf "a workflow naming the script but uploading itself is refused" refused \
        '      - name: sh spike/release-upload-missing.sh "$TAG" dist
        run: gh release upload "$TAG" dist/*.tar.gz'
    want_wf "a workflow naming the script in a step name only is refused" refused \
        '      - name: sh spike/release-upload-missing.sh "$TAG" dist
        run: echo nothing'
    rm -rf "$t"
    [ "$fails" = 0 ] && echo "ok   release-upload-missing selftest: $runs of $runs" || { echo "FAIL release-upload-missing selftest: $fails"; return 1; }
}

case "${1:-}" in
    --selftest) selftest ;;
    --check-workflow) check_workflow "${2:?usage: release-upload-missing.sh --check-workflow <release.yml>}" ;;
    *) upload_missing "${1:?usage: release-upload-missing.sh <tag> <dir>}" "${2:?usage: release-upload-missing.sh <tag> <dir>}" ;;
esac
