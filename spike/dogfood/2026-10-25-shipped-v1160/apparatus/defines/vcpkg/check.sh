#!/bin/sh
# After a crash anywhere in `vcpkg remove zlib`, the tree is still one vcpkg can read and finish:
# `vcpkg list` reads the status database and still lists bzip2 with its header in place, and running
# the same remove again (the way back) succeeds and leaves no zlib in the list or on disk.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(vcpkg): $*"; exit 1; }
cd /s/vcpkg || fail "no tree"
l=$(./vcpkg list 2>&1) || fail "vcpkg list exited $?: $(printf '%s' "$l" | tail -c 300)"
printf '%s' "$l" | grep -q '^bzip2:arm64-linux' || fail "bzip2 is no longer listed: $(printf '%s' "$l" | tail -c 300)"
[ -f "$d/arm64-linux/include/bzlib.h" ] || fail "bzip2's header is gone"
./vcpkg remove zlib > /tmp/vcpkg-rerun.txt 2>&1 || fail "re-running remove exited $?: $(tail -c 300 /tmp/vcpkg-rerun.txt)"
l=$(./vcpkg list 2>&1) || fail "vcpkg list after the re-run exited $?"
printf '%s' "$l" | grep -q '^zlib:' && fail "zlib is still listed after the re-run"
[ -e "$d/arm64-linux/include/zlib.h" ] && fail "zlib.h is still on disk after the re-run"
exit 0
