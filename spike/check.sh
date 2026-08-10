#!/bin/sh
# The L2 checker: cross-examine the diagnostic command against reality.
#
# The invariant is not "the key is readable" — a target is allowed to be broken as
# long as it says so. The invariant is that `doctor`'s claim and the observable truth
# agree. Both directions are violations: claiming health while the key cannot be read,
# and claiming trouble while it can.
#
# Runs after a restart, in a fresh process, exactly as DESIGN §12 requires. Exit 0
# means the invariant holds.
#
# Environment:
#   TOY    path to the toy binary
#   TOY_STATE  state directory (passed through to the toy)

set -u

: "${TOY:?check.sh needs TOY to point at the binary under test}"

if claim=$("$TOY" doctor 2>/dev/null); then
    :
else
    claim="unhealthy"
fi

if "$TOY" load-key >/dev/null 2>&1; then
    reality="loadable"
else
    reality="unloadable"
fi

case "$claim:$reality" in
    healthy:loadable)     exit 0 ;;
    unhealthy:unloadable) exit 0 ;;
    *)
        echo "doctor says '$claim' but the key is $reality" >&2
        exit 1
        ;;
esac
