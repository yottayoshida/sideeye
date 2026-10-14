#!/bin/sh
# CANDIDATES.md 1.3. The recovery a user runs is the same dpkg-divert again.
set -u
S=${SIDEEYE_STATE_DIR:?}; B=$S/root/usr/bin
V="dpkg-divert --admindir $S/admin --instdir $S/root"
legs() {
    a=ok; b=ok
    listed=0; $V --list 2>/dev/null | grep -qxF 'local diversion of /usr/bin/tool to /usr/bin/tool.distrib' && listed=1
    moved=0; [ -e "$B/tool.distrib" ] && moved=1
    [ "$listed" = "$moved" ] || a="FAIL(listed=$listed moved=$moved)"
    n=0; for f in tool tool.distrib; do [ "$(cat "$B/$f" 2>/dev/null)" = "the original tool" ] && n=$((n+1)); done
    [ "$n" = 1 ] || b="FAIL($n names)"
    echo "a=$a b=$b"
}
echo "checker(divert) before recovery: $(legs)"
timeout 60 $V --rename --divert /usr/bin/tool.distrib --add /usr/bin/tool > /tmp/dv-recovery.txt 2>&1 || echo "checker(divert) recovery exited $?: $(tail -c 200 /tmp/dv-recovery.txt)"
after=$(legs); echo "checker(divert) after recovery: $after"
case "$after" in "a=ok b=ok") exit 0 ;; *) exit 1 ;; esac
