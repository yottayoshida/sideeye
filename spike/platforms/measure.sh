#!/bin/sh
# spike/platforms/measure.sh — one platform's measurement for the table in docs/cli.md (#697,
# ADR 0105). Runs inside the Linux being measured: a runner's own shell, a container, a virtual
# machine, or a WSL distribution. POSIX sh only, because the shell it runs under is the one being
# measured too (busybox ash on Alpine, dash on Ubuntu, bash on Rocky).
#
#   [S=<state root>] [SHIM=<shim>] sh measure.sh <sideeye binary> <out dir> <label>
#
# Writes <out dir>/<label>/: env.txt (what this platform is: kernel, libc, /bin/sh, dd, the user,
# ptrace's scope, the cgroup this process sits in and the cgroup filesystem, the engine's banner),
# and for each observation mode the explore's text and JSON, with one line per mode in
# summary.txt. The define is define/: a file rewritten in place by dd, whose right answer is FAIL
# on every platform.
#
# The state lives under S (default /s, which the caller makes writable). With another S, the
# define is copied into the work directory with its /s/ paths moved there; define/ itself is not
# edited, because the 2026-10-10 record names it. `--shim` is not passed unless SHIM is set: the
# engine finds its shim the way an adopter's does, beside itself. Each explore is held to EXPLORE_TIMEOUT seconds
# (default 600) where `timeout` exists, so one that hangs leaves its leg's record and the legs
# after it rather than the job's whole budget.
set -u

usage="usage: [S=<state root>] measure.sh <sideeye binary> <out dir> <label>"
se=${1:?$usage}
out=${2:?$usage}/${3:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
S=${S:-/s}
mkdir -p "$out" "$S"
: > "$out/summary.txt"

strace=$(command -v strace) || strace=
{
    echo "label:     $3"
    echo "uname:     $(uname -srm)"
    echo "os:        $(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"')"
    echo "libc:      $(ldd --version 2>&1 | head -2 | tr '\n' ' ')"
    echo "/bin/sh:   $(readlink -f /bin/sh 2>/dev/null || echo unknown)"
    echo "dd:        $(readlink -f "$(command -v dd)" 2>/dev/null) ($(dd --version 2>&1 | head -1))"
    echo "user:      $(id -un 2>/dev/null) (uid $(id -u))"
    echo "ptrace:    yama ptrace_scope $(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo absent)"
    echo "cgroup fs: $(stat -fc %T /sys/fs/cgroup 2>/dev/null || echo unknown)"
    echo "cgroup:    $(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null)"
    echo "state:     $S ($(stat -fc %T "$S" 2>/dev/null || echo unknown))"
    echo "shim:      ${SHIM:-(searched beside the engine)}"
    echo "strace:    ${strace:-none} ($([ -n "$strace" ] && "$strace" -V 2>&1 | head -1))"
    banner=$("$se" version 2>&1)
    echo "sideeye:   $banner (exit $?)"
} > "$out/env.txt"
[ -n "$strace" ] || { echo "measure: no strace on this platform; the oracle is required" | tee "$out/summary.txt" >&2; exit 2; }

limit=
command -v timeout > /dev/null && limit="timeout ${EXPLORE_TIMEOUT:-600}"
work=$(mktemp -d "${TMPDIR:-/tmp}/platform-measure-XXXXXX")
config=$here/define/sideeye.toml
if [ "$S" != /s ]; then
    sed "s#/s/#$S/#g" "$config" > "$work/sideeye.toml"
    config=$work/sideeye.toml
fi
printf 'new contents\n' > "$S/new"

for mode in default syscalls supervised; do
    rm -rf "$S/st" && mkdir -p "$S/st" && printf 'old contents\n' > "$S/st/a.txt"
    set -- explore --config "$config" --oracle "$strace" \
        --work "$work/$mode" --json "$out/explore-$mode.json"
    [ "$mode" = default ] || set -- "$@" --observe "$mode"
    [ -n "${SHIM:-}" ] && set -- "$@" --shim "$SHIM"
    $limit "$se" "$@" > "$out/explore-$mode.txt" 2>&1
    rc=$?
    verdict=$(grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' "$out/explore-$mode.txt")
    printf '%s\texit %s\t%s\n' "$mode" "$rc" "${verdict:-(no verdict line)}" >> "$out/summary.txt"
done

cat "$out/summary.txt"
