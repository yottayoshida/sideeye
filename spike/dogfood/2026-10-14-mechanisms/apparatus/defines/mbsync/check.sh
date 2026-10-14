#!/bin/sh
# CANDIDATES.md 2.4. The recovery a user runs is mbsync again, which replays its journal.
set -u
S=${SIDEEYE_STATE_DIR:?}
legs() {
    python3 - "$S" <<'PY'
import os, re, sys
s = sys.argv[1]
def side(name):
    ids, flagged = [], set()
    for sub in ("cur", "new"):
        d = os.path.join(s, name, sub)
        for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            try: m = re.search(r"^Message-ID: <([^@]+)@", open(os.path.join(d, f)).read(), re.M)
            except OSError: m = None
            if not m: continue
            ids.append(m.group(1))
            if re.search(r":2,[A-Z]*S", f): flagged.add(m.group(1))
    return ids, flagged
far, near = side("far"), side("near")
a = "ok" if set(far[0]) == set(near[0]) else "FAIL(far %s near %s)" % (sorted(far[0]), sorted(near[0]))
dup = [i for ids in (far[0], near[0]) for i in set(ids) if ids.count(i) > 1]
b = "ok" if not dup else "FAIL(twice: %s)" % sorted(set(dup))
lost = [i for i in ("one", "two", "three", "four") if i not in far[0] + near[0]]
c = "ok" if not lost else "FAIL(lost %s)" % lost
d = "ok" if "one" in far[1] and "one" in near[1] else "FAIL(flag far=%s near=%s)" % ("one" in far[1], "one" in near[1])
print("a=%s b=%s c=%s d=%s" % (a, b, c, d))
PY
}
echo "checker(mbsync) before recovery: $(legs)"
timeout 60 mbsync -c "$S/rc" ch > /tmp/mb-recovery.txt 2>&1 || echo "checker(mbsync) recovery exited $?: $(tail -c 200 /tmp/mb-recovery.txt)"
after=$(legs); echo "checker(mbsync) after recovery: $after"
case "$after" in "a=ok b=ok c=ok d=ok") exit 0 ;; *) exit 1 ;; esac
