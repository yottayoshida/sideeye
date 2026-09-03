#!/bin/sh
# The declared invariant (L2 checker), non-destruction form: undo must remove either
# nothing or exactly the interval timew's own export names as most recent — never an
# older committed interval, and it must not invent intervals. Removing nothing is
# allowed because a crash may have beaten the intent's commit.
#
# This file is the one canonical text of the checker (#65). The scripts that stage or
# replay the define copy it from here; none carries its own. The frozen v0.4 recipe,
# whose bytes the unknown-rate corpus pins, is a record rather than a consumer.
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
