#!/bin/sh
# The contrast for the static `touch` leg (2026-09-28): does creating one empty file count as a
# recorded mutating operation, in each mode, for a dynamic and a static touch?
# Runs inside the sideeye-sv170 box, privileged with its own cgroup namespace, --network none.
# Each line: the image, the mode, preflight's exit code (read directly, not through a pipe), and
# its first line. busybox-static is not run under --observe syscalls: a static image has no
# handler for the shim's filter (2026-09-27, SIGSYS), so that cell is not a question.
SE=$(cat /install.path)
for c in "/usr/bin/touch|" "/usr/bin/touch|--observe syscalls" "/usr/bin/touch|--observe supervised" "/bin/busybox touch|" "/bin/busybox touch|--observe supervised"; do
    op=${c%%|*}; fl=${c#*|}
    rm -rf /s/tc; mkdir -p /s/tc
    # shellcheck disable=SC2086
    "$SE" preflight --state /s/tc --operation "$op /s/tc/t" --oracle /usr/bin/strace $fl > /tmp/p.txt 2>&1
    rc=$?
    echo "$op | ${fl:-default} | rc=$rc | $(head -1 /tmp/p.txt)"
done
