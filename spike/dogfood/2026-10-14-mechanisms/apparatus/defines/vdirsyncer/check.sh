#!/bin/sh
# CANDIDATES.md 2.5. The recovery a user runs is vdirsyncer sync again.
set -u
S=${SIDEEYE_STATE_DIR:?}
export VDIRSYNCER_CONFIG=$S/config HOME=$S/home
legs() {
    python3 - "$S" <<'PY'
import os, re, sys
s = sys.argv[1]
def side(name):
    d = os.path.join(s, name, "cal"); uids = []
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if not f.endswith(".ics"): continue
        try: m = re.search(r"^UID:(.*?)\r?$", open(os.path.join(d, f)).read(), re.M)
        except OSError: m = None
        if m: uids.append(m.group(1))
    return uids
a, b = side("a"), side("b")
la = "ok" if set(a) == set(b) else "FAIL(a %s b %s)" % (sorted(a), sorted(b))
dup = [u for side_ in (a, b) for u in set(side_) if side_.count(u) > 1]
lb = "ok" if not dup else "FAIL(twice: %s)" % sorted(set(dup))
lost = [u for u in ("one", "two", "three", "four") if u not in a + b]
lc = "ok" if not lost else "FAIL(lost %s)" % lost
print("a=%s b=%s c=%s" % (la, lb, lc))
PY
}
echo "checker(vdirsyncer) before recovery: $(legs)"
timeout 120 vdirsyncer sync > /tmp/vd-recovery.txt 2>&1 || echo "checker(vdirsyncer) recovery exited $?: $(tail -c 200 /tmp/vd-recovery.txt)"
after=$(legs); echo "checker(vdirsyncer) after recovery: $after"
case "$after" in "a=ok b=ok c=ok") exit 0 ;; *) exit 1 ;; esac
