#!/bin/sh
# After a crash anywhere inside `vcpkg remove utfcpp`, vcpkg still reads its own database and knows the
# port that was not touched: `vcpkg list` exits 0 and lists nlohmann-json, whose header is still on disk.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(vcpkg-s3): $*"; exit 1; }
[ -f "$d/arm64-linux/include/nlohmann/json.hpp" ] || fail "nlohmann/json.hpp is gone"
out=$(cd /opt/vcpkg && ./vcpkg list --x-install-root="$d" 2>&1) || fail "vcpkg list exited $?: $(echo "$out" | tr '\n' ' ' | cut -c1-240)"
printf '%s' "$out" | grep -q "^nlohmann-json" || fail "vcpkg list no longer shows nlohmann-json: $(echo "$out" | tr '\n' ' ' | cut -c1-240)"
exit 0
