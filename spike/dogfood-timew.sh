#!/bin/sh
# Point sideeye at timewarrior 1.4.3 — the fifth real target, chosen for its commit tail.
#
# The operation (`timew track <fixed interval> beta :yes` against a database seeded with
# one interval) rewrites three files, each atomically on its own: month data, undo.data,
# tags.data are written to pid-named temp files and renamed into place. But the three
# renames happen in sequence at the very end — data, then undo, then tags — so a crash
# between them leaves a database whose files are individually pristine (every one is
# byte-identical to pre or post; L0 passes) while disagreeing with each other.
#
# The window that matters is after the data rename, before the undo rename: the new
# interval is committed, but undo.data still ends at the previous transaction. Measured
# by hand (2026-08-12, plain strace + file surgery, no sideeye): `timew undo` in that
# state deletes the OLD interval — long-committed data — and keeps the one whose commit
# crashed. Timewarrior's documented contract is "The undo command will undo the most
# recent change"; the checker below states exactly that and nothing else.
#
# The stale tags.data window looked harmless at first — `timew tags` recomputes from
# the interval database and ignores tags.data (measured: hand-staling it changed
# nothing in that output) — but `timew undo` turned out to be its reader: the undo
# path decrements the cached tag counts, and a count that is not there is a hard
# error. One declared contract caught both windows.
#
# Two explorations run back to back, each in its own state directory. Measured
# 2026-08-12 (timewarrior 1.4.3, aarch64 container):
#   (a) no checker        — L0 alone. PASS 20/20 worlds, oracle agreed on 19
#                           operations: every file is replaced by rename, so each one
#                           matches pre or post in every crash world. The bug is not
#                           in any single file.
#   (b) --check check.sh  — the undo contract. FAIL, 2 of 20 worlds:
#                           * crash point 14 (data renamed; undo.data, tags.data
#                             stale): `timew undo` reports success and deletes the
#                             OLD interval — committed long before the crash — while
#                             the interval whose commit crashed survives.
#                           * crash point 15 (data and undo renamed; tags.data
#                             stale): `timew undo` exits 255 ("Trying to decrement
#                             non-existent tag"), undoing nothing — undo stays
#                             unusable until tags.data is repaired by hand.
#                           The bare `timew export` is a usable falsification probe:
#                           on a garbage data file it prints "Unrecognizable line …"
#                           and exits non-zero (measured 255), so no strict wrapper
#                           is needed (unlike todoman's `todo list`).
#
# Needs `timew` on PATH and python3 (the checker compares exports with a real JSON
# parser; grep on JSON is how checkers end up agreeing with garbage). From the spike
# image:
#   apt-get update && apt-get install -y --no-install-recommends timewarrior
set -eu

SIDEEYE_REPO=${SIDEEYE_REPO:-/work}
RUN=${RUN:-/tmp/sideeye-timew}
SHIM=$SIDEEYE_REPO/zig-out/lib/libsideeye_shim.so

[ -x "$SIDEEYE_REPO/zig-out/bin/sideeye" ] || { echo "build sideeye first: zig build -Dtarget=<arch>-linux-gnu"; exit 1; }
command -v timew >/dev/null || { echo "timew not found; see the header for the install"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found; the checker needs it"; exit 1; }

# No recursive delete here. The run directory has to be new, so that nothing from a
# previous attempt can be mistaken for what this one produced — and so this script never
# has to delete anything.
[ -e "$RUN" ] && { echo "$RUN already exists. Remove it yourself, or pass RUN=<new path>."; exit 1; }
mkdir -p "$RUN"

# The checker states timewarrior's own undo contract: after any crash, `timew undo`
# must remove exactly the interval timewarrior itself reports as most recent (id 1 in
# its own export) — never an older, committed one. The checker mutates the crashed
# state (undo rewrites the database), which is safe here: the engine snapshots the
# crashed state before running the checker, and judges L0 on that snapshot.
cat > "$RUN/check.sh" <<'CHECK'
#!/bin/sh
set -eu
before=$(timew export) || exit 1
timew undo >/dev/null || exit 1
after=$(timew export) || exit 1
BEFORE="$before" AFTER="$after" python3 - <<'PY'
import json, os, sys

def keyset(doc):
    return sorted((iv["start"], iv.get("end", ""), ",".join(iv.get("tags", [])))
                  for iv in json.loads(doc))

before = json.loads(os.environ["BEFORE"])
if not before:
    print("export was empty before undo: the seeded interval is gone", file=sys.stderr)
    sys.exit(1)
newest = min(before, key=lambda iv: iv["id"])  # id 1 is timew's own "most recent"
expected = keyset(os.environ["BEFORE"])
expected.remove((newest["start"], newest.get("end", ""), ",".join(newest.get("tags", []))))
got = keyset(os.environ["AFTER"])
if got != expected:
    print("undo removed the wrong change: timew's own export named", newest,
          "as most recent, but undo left", got, "instead of", expected, file=sys.stderr)
    sys.exit(1)
PY
CHECK
chmod +x "$RUN/check.sh"

echo "timewarrior: $(timew --version)"

explore() {
    label=$1; shift
    state=$RUN/$label/state

    # TIMEWARRIORDB is the whole state: config, data, undo and tags all live under it,
    # and the checker inherits it from the engine's environment.
    export TIMEWARRIORDB=$state
    mkdir -p "$state"

    # Setup: seed one interval, in the past relative to the operation's interval, so
    # the pre snapshot holds committed data an incorrect undo could destroy. Dates are
    # fixed and the container runs in UTC; nothing in the written files depends on the
    # wall clock. `:yes` answers the database-creation prompt.
    cat > "$RUN/$label/setup.sh" <<SETUP
#!/bin/sh
set -eu
timew track 2020-01-01T10:00 - 2020-01-01T11:00 alpha :yes >/dev/null
SETUP
    chmod +x "$RUN/$label/setup.sh"

    echo ""
    echo "=== ($label) timew track <fixed interval> beta, killed before each state-changing operation ==="
    # Not guarded by `set -e`: FAIL is exit 1 and is a *result*, not a script error.
    set +e
    "$SIDEEYE_REPO/zig-out/bin/sideeye" explore \
        --state "$state" \
        --setup "$RUN/$label/setup.sh" \
        --operation "timew track 2020-01-02T10:00 - 2020-01-02T11:00 beta :yes" \
        --shim "$SHIM" \
        --work "$RUN/$label/work" \
        --json "$RUN/$label/report.json" \
        --oracle /usr/bin/strace "$@"
    rc=$?
    set -e
    echo "($label) exit=$rc  (0 PASS / 1 FAIL / 2 UNKNOWN / 3 SETUP ERROR)"
}

explore a
explore b --check "$RUN/check.sh"

echo ""
echo "reports: $RUN/a/report.json $RUN/b/report.json"
