#!/bin/sh
# spike/platforms/measure.sh — one platform's measurement for the table in docs/cli.md (#697,
# ADR 0105). Runs inside the Linux being measured: a runner's own shell, a container, or a WSL2
# distribution. POSIX sh only, because the shell it runs under is the one being measured too
# (busybox ash on Alpine, dash on Ubuntu, bash on Rocky).
#
#   sh measure.sh <sideeye binary> <out dir> <label>
#
# Writes <out dir>/<label>/: env.txt (what this platform is: kernel, libc, /bin/sh, the cgroup
# this process sits in, the user, and the engine's banner), and for each observation mode the
# explore's text and JSON, with one line per mode in summary.txt. The define is define/: a file
# rewritten in place by dd, whose right answer is FAIL on every platform.
#
# `--shim` is not passed: the engine finds its shim the way an adopter's does, beside itself.
# `/s` must exist and be writable by the user this runs as; the caller makes it. Each explore
# is held to EXPLORE_TIMEOUT seconds (default 600) where `timeout` exists, so one that hangs
# leaves its leg's record and the legs after it rather than the job's whole budget.
set -u

usage="usage: measure.sh <sideeye binary> <out dir> <label>"
se=${1:?$usage}
out=${2:?$usage}/${3:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
: > "$out/summary.txt"

strace=$(command -v strace) || strace=
{
    echo "label:     $3"
    echo "uname:     $(uname -srm)"
    echo "os:        $(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"')"
    echo "libc:      $(ldd --version 2>&1 | head -2 | tr '\n' ' ')"
    echo "/bin/sh:   $(readlink -f /bin/sh 2>/dev/null || echo unknown)"
    echo "dd:        $(readlink -f "$(command -v dd)" 2>/dev/null) ($(dd --version 2>&1 | head -1))"
    echo "uid:       $(id -u)"
    echo "cgroup fs: $(stat -fc %T /sys/fs/cgroup 2>/dev/null || echo unknown)"
    echo "cgroup:    $(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null)"
    echo "strace:    ${strace:-none} ($([ -n "$strace" ] && "$strace" -V 2>&1 | head -1))"
    banner=$("$se" version 2>&1)
    echo "sideeye:   $banner (exit $?)"
} > "$out/env.txt"
[ -n "$strace" ] || { echo "measure: no strace on this platform; the oracle is required" | tee "$out/summary.txt" >&2; exit 2; }

limit=
command -v timeout > /dev/null && limit="timeout ${EXPLORE_TIMEOUT:-600}"
work=$(mktemp -d "${TMPDIR:-/tmp}/platform-measure-XXXXXX")
printf 'new contents\n' > /s/new

for mode in default syscalls supervised; do
    rm -rf /s/st && mkdir -p /s/st && printf 'old contents\n' > /s/st/a.txt
    set -- explore --config "$here/define/sideeye.toml" --oracle "$strace" \
        --work "$work/$mode" --json "$out/explore-$mode.json"
    [ "$mode" = default ] || set -- "$@" --observe "$mode"
    $limit "$se" "$@" > "$out/explore-$mode.txt" 2>&1
    rc=$?
    verdict=$(grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' "$out/explore-$mode.txt")
    printf '%s\texit %s\t%s\n' "$mode" "$rc" "${verdict:-(no verdict line)}" >> "$out/summary.txt"
done

cat "$out/summary.txt"
