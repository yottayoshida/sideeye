#!/bin/sh
# CANDIDATES.md 3.1. The recovery a user runs is the next unforced logrotate run; its exit status is
# leg c.
set -u
S=${SIDEEYE_STATE_DIR:?}
lines() {
    python3 - "$S" <<'PY'
import glob, os, sys
s = sys.argv[1]
want = ["line A%d" % i for i in (1, 2, 3)] + ["line B%d" % i for i in (1, 2, 3)] + ["line C%d" % i for i in (1, 2, 3, 4)]
seen = []
for p in glob.glob(os.path.join(s, "app.log*")):
    try: seen += open(p).read().splitlines()
    except OSError: pass
bad = [w for w in want if seen.count(w) != 1]
print("ok" if not bad else "FAIL(%s)" % ",".join("%s x%d" % (w, seen.count(w)) for w in bad))
PY
}
echo "checker(logrotate) before recovery: a=$(lines) b=$([ -f "$S/app.log" ] && echo ok || echo FAIL)"
timeout 60 logrotate -s "$S/status" /s/lr-aux/app.conf > /tmp/lr-recovery.txt 2>&1
rc=$?
c=ok; [ "$rc" = 0 ] || c="FAIL(exit $rc: $(head -c 120 /tmp/lr-recovery.txt))"
a=$(lines); b=ok; [ -f "$S/app.log" ] || b=FAIL
after="a=$a b=$b c=$c"; echo "checker(logrotate) after recovery: $after"
case "$after" in "a=ok b=ok c=ok") exit 0 ;; *) exit 1 ;; esac
