#!/bin/sh
# CANDIDATES.md 1.1. The recovery a user runs is the same useradd again ("already exists" accepted);
# the legs are read before it (printed only) and after it (judged).
set -u
S=${SIDEEYE_STATE_DIR:?}; R=$S/root; E=$R/etc
legs() {
    a=ok; b=ok; c=ok; d=ok
    pwck -r -q -R "$R" > /dev/null 2>&1 || a=FAIL
    grpck -r -R "$R" > /dev/null 2>&1 || b=FAIL
    n=0
    grep -q '^alice:' "$E/passwd" 2>/dev/null && n=$((n+1))
    grep -q '^alice:' "$E/shadow" 2>/dev/null && n=$((n+1))
    grep -q '^staff:[^:]*:[^:]*:.*\balice\b' "$E/group" 2>/dev/null && n=$((n+1))
    grep -q '^staff:[^:]*:[^:]*:.*\balice\b' "$E/gshadow" 2>/dev/null && n=$((n+1))
    [ "$n" = 0 ] || [ "$n" = 4 ] || c="FAIL($n of 4)"
    for l in 'root:x:0:0:root:/:/bin/sh' 'carol:x:1001:1001::/:/bin/sh'; do grep -qxF "$l" "$E/passwd" 2>/dev/null || d=FAIL; done
    for l in 'root:*:20000:0:99999:7:::' 'carol:*:20000:0:99999:7:::'; do grep -qxF "$l" "$E/shadow" 2>/dev/null || d=FAIL; done
    echo "a=$a b=$b c=$c d=$d"
}
echo "checker(useradd) before recovery: $(legs)"
timeout 60 useradd --prefix "$R" -M -d / -G staff -p '$6$s$h' -s /bin/sh alice > /tmp/useradd-recovery.txt 2>&1
rc=$?
[ "$rc" = 0 ] || [ "$rc" = 9 ] || echo "checker(useradd) recovery exited $rc: $(tail -c 200 /tmp/useradd-recovery.txt)"
after=$(legs); echo "checker(useradd) after recovery: $after"
case "$after" in "a=ok b=ok c=ok d=ok") exit 0 ;; *) exit 1 ;; esac
