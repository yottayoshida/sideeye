#!/bin/sh
# CANDIDATES.md 1.2. The recovery a user runs is the same --install again.
set -u
S=${SIDEEYE_STATE_DIR:?}
U="update-alternatives --altdir $S/alt --admindir $S/admin --log $S/log"
legs() {
    a=ok; b=ok; c=ok
    $U --query editor > /dev/null 2>&1 || a=FAIL
    b=$(python3 - "$S" <<'PY'
import os, sys
s = sys.argv[1]
try:
    lines = open(os.path.join(s, "admin/editor")).read().split("\n")
    mode, i, alts = lines[0], lines.index("", 1) + 1, {}
    while i + 1 < len(lines) and lines[i]:
        try: alts[lines[i]] = int(lines[i + 1])
        except ValueError: pass
        i += 2
    if os.readlink(os.path.join(s, "bin/editor")) != os.path.join(s, "alt/editor"):
        print("FAIL(bin/editor does not point into alt)"); sys.exit()
    target = os.readlink(os.path.join(s, "alt/editor"))
    want = max(alts, key=alts.get) if mode == "auto" else None
    ok = target == want if mode == "auto" else target in alts
    print("ok" if ok and os.path.exists(target) else "FAIL(%s -> %s, admin says %s)" % (mode, target, want))
except Exception as e:
    print("FAIL(%s)" % type(e).__name__)
PY
)
    grep -qxF "$S/opt/ed1" "$S/admin/editor" 2>/dev/null || c=FAIL
    echo "a=$a b=$b c=$c"
}
echo "checker(alternatives) before recovery: $(legs)"
timeout 60 $U --install "$S/bin/editor" editor "$S/opt/ed2" 50 > /tmp/ua-recovery.txt 2>&1 || echo "checker(alternatives) recovery exited $?: $(tail -c 200 /tmp/ua-recovery.txt)"
after=$(legs); echo "checker(alternatives) after recovery: $after"
case "$after" in "a=ok b=ok c=ok") exit 0 ;; *) exit 1 ;; esac
