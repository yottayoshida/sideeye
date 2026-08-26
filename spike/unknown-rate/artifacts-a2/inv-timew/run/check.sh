#!/bin/sh
set -eu
before=$(timew export) || exit 1
timew undo >/dev/null || exit 1
after=$(timew export) || exit 1
BEFORE="$before" AFTER="$after" python3 - <<'PY'
import json, os, sys

def key(iv):
    return (iv["start"], iv.get("end", ""), ",".join(iv.get("tags", [])))

before = json.loads(os.environ["BEFORE"])
after = json.loads(os.environ["AFTER"])
if not before:
    print("export was empty before undo: the seeded interval is gone", file=sys.stderr)
    sys.exit(1)
newest = min(before, key=lambda iv: iv["id"])  # id 1 is timew's own "most recent"
b = sorted(key(iv) for iv in before)
a = sorted(key(iv) for iv in after)
added = [k for k in a if k not in b]
removed = [k for k in b if k not in a]
if added:
    print("undo added intervals:", added, file=sys.stderr)
    sys.exit(1)
if removed not in ([], [key(newest)]):
    print("undo removed the wrong change: timew's own export named", key(newest),
          "as most recent, but undo removed", removed, file=sys.stderr)
    sys.exit(1)
PY
