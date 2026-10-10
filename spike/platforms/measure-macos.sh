#!/bin/sh
# spike/platforms/measure-macos.sh — measure.sh's macOS counterpart (#697, ADR 0105), run on
# GitHub's macOS runners by .github/workflows/spike-platforms.yml; macos-26 is the control the
# older releases are read against.
#
#   sh measure-macos.sh <sideeye binary> <out dir> <label>
#
# The define is define/'s, with its paths moved under $HOME/s (macOS's root volume is
# read-only) and its dd replaced by Homebrew's GNU dd (`gdd`): /bin/dd is a system binary, and
# System Integrity Protection strips DYLD_INSERT_LIBRARIES from it, so the shim could not enter
# it — the signature of both is recorded. The oracle is fs_usage (`--oracle-fs-usage`), which
# needs root; the runners' sudo asks for no password. --observe syscalls and supervised are Linux
# only, so the default mode is the one explored. `sideeye demo` runs too: on v1.10.0 it compiles
# its toy with the runner's compiler.
set -u

usage="usage: measure-macos.sh <sideeye binary> <out dir> <label>"
se=${1:?$usage}
out=${2:?$usage}/${3:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
S=$HOME/s
mkdir -p "$out" "$S"
: > "$out/summary.txt"

dd=$(command -v gdd) || dd=
{
    echo "label:     $3"
    echo "macOS:     $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "uname:     $(uname -srm)"
    echo "dd:        ${dd:-none} ($([ -n "$dd" ] && "$dd" --version 2>&1 | head -1))"
    echo "codesign of $dd:"; [ -n "$dd" ] && codesign -dv "$dd" 2>&1 | sed 's/^/    /'
    echo "codesign of /bin/dd:"; codesign -dv /bin/dd 2>&1 | sed 's/^/    /'
    echo "user:      $(id -un) (uid $(id -u))"
    banner=$("$se" version 2>&1)
    echo "sideeye:   $banner (exit $?)"
} > "$out/env.txt"
[ -n "$dd" ] || { echo "measure-macos: gdd is not installed (brew install coreutils)" | tee "$out/summary.txt" >&2; exit 2; }
sudo -n true 2> "$out/sudo.txt" || { echo "measure-macos: sudo asks for a password; fs_usage needs root" | tee "$out/summary.txt" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/platform-measure-XXXXXX")
sed -e "s#/s/#$S/#g" -e "s#^operation = \"dd #operation = \"$dd #" "$here/define/sideeye.toml" > "$work/sideeye.toml"
printf 'new contents\n' > "$S/new"
rm -rf "$S/st" && mkdir -p "$S/st" && printf 'old contents\n' > "$S/st/a.txt"
"$se" explore --config "$work/sideeye.toml" --oracle-fs-usage --work "$work/default" \
    --json "$out/explore-default.json" > "$out/explore-default.txt" 2>&1
rc=$?
verdict=$(grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' "$out/explore-default.txt")
printf 'default\texit %s\t%s\n' "$rc" "${verdict:-(no verdict line)}" >> "$out/summary.txt"

( cd "$work" && "$se" demo ) > "$out/demo.txt" 2>&1
rc=$?
verdict=$(grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' "$out/demo.txt")
printf 'demo\texit %s\t%s\n' "$rc" "${verdict:-(no verdict line)}" >> "$out/summary.txt"

cat "$out/summary.txt"
