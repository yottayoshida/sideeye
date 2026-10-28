#!/bin/sh
# After a crash every file of the project is either the bytes it was written with or the bytes one
# uninterrupted conversion gives it: a project half converted file by file is what the converter's
# own loop leaves, a file that is neither is torn.
exec python3 - "$SIDEEYE_STATE_DIR" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
def load(p): return {l.split()[1]: l.split()[0] for l in open(p)}
old, new = load("/s/aux/godot-ref/old.sha"), load("/s/aux/godot-ref/new.sha")
bad = 0; conv = 0
for name in sorted(old):
    p = os.path.join(root, name)
    if not os.path.isfile(p):
        print(f"checker(godot): {name} is missing"); bad += 1; continue
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    if h == new.get(name) and h != old[name]: conv += 1
    elif h != old[name]:
        print(f"checker(godot): {name} is neither as written nor as converted ({os.path.getsize(p)} bytes)"); bad += 1
print(f"checker(godot): {conv} of {len(old)} files converted, {bad} torn or missing")
sys.exit(1 if bad else 0)
PY
