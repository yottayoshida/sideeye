#!/bin/sh
# The v0.4 regression-case-stability measurement (PRD v0.4): a saved counterexample
# must work across a REAL code change — the fix — not only across the synthetic
# context changes the v0.3 acceptance pins.
#
# Four legs, one saved case:
#   A  build timewarrior at the pinned upstream commit, explore with the undo-contract
#      checker -> FAIL, and the counterexample is saved as a case file
#   B  replay that case against the same build -> FAIL again ("the case reproduced")
#   C  apply spike/timew-undo-ordering.patch in a SEPARATE checkout, rebuild, install
#      over the same PATH name -> replay the same case -> PASS required: explored==2,
#      no unknown_reason, crash_points equal to the case's ops_total. A
#      case_no_longer_applies here would be an honest refusal but NOT the acceptance —
#      the paths-only-warn rule (ADR 0009) exists precisely so a fix that reorders
#      same-class operations keeps the case addressable
#   D  negative control: the distro 1.4.3 package at the same PATH name -> the replay
#      must refuse (UNKNOWN case_no_longer_applies), never answer a verdict about a
#      recording with a different operation count. The expectation that the counts
#      differ (19 vs 24 at the time of writing) is a prediction, not a premise; if
#      this leg refuses for another named reason, record what actually happened
#
# Verdicts are judged from the --json reports with a real JSON parser (grep passes on
# truncated documents). Two wiring facts this depends on: the case stores the
# operation as the PATH name `timew`, so $RUN/bin at the head of PATH is the lever
# that swaps builds; and TIMEWARRIORDB is not part of the case's identity (env is not
# captured), so it must be re-exported here. The state is reset between legs by
# MOVING it aside, never deleting — the case pins the absolute state path, and the
# setup is additive (seeding a used database would change the recording).
#
# Needs (Linux container): git, cmake, g++, make, python3, strace, network for the
# clone, and the `timewarrior` distro package for leg D. From the spike image:
#   apt-get update && apt-get install -y --no-install-recommends \
#       git ca-certificates cmake g++ make timewarrior
set -eu

SIDEEYE_REPO=${SIDEEYE_REPO:-/work}
RUN=${RUN:-/tmp/sideeye-timew-replay}
SIDEEYE=$SIDEEYE_REPO/zig-out/bin/sideeye
SHIM=$SIDEEYE_REPO/zig-out/lib/libsideeye_shim.so
PATCH=$SIDEEYE_REPO/spike/timew-undo-ordering.patch
# Full 40-hex pin, verified with `git rev-parse HEAD` after checkout: an abbreviated
# hash is a lookup convenience, not a content address, and the claim that a MITM'd
# transport cannot alter what was measured rests on the full hash matching.
PIN=${PIN:-db7751cb12aa3b1d52161a9e2457be8539644e56}
TIMEW_GIT=${TIMEW_GIT:-https://github.com/GothenburgBitFactory/timewarrior.git}

[ "$(uname -s)" = "Linux" ] || { echo "Linux container only (strace oracle, disposable installs)"; exit 1; }
[ -x "$SIDEEYE" ] || { echo "build sideeye first: zig build -Dtarget=<arch>-linux-gnu"; exit 1; }
[ -f "$SHIM" ] || { echo "shim not found: $SHIM"; exit 1; }
[ -f "$PATCH" ] || { echo "patch not found: $PATCH"; exit 1; }
for tool in git cmake g++ make python3 strace; do
    command -v "$tool" >/dev/null || { echo "$tool not found; see the header for the install"; exit 1; }
done
command -v timew >/dev/null || { echo "distro timewarrior not found (needed for leg D); see the header"; exit 1; }
DISTRO_TIMEW=$(command -v timew)

# No recursive delete anywhere in this script: the run directory has to be new, and
# state resets move the old directory aside instead of removing it.
[ -e "$RUN" ] && { echo "$RUN already exists. Remove it yourself, or pass RUN=<new path>."; exit 1; }
mkdir -p "$RUN/bin"

# Whichever build sits at $RUN/bin/timew is what the recorded operation names.
export PATH="$RUN/bin:$PATH"

fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# --- the define, copied from spike/dogfood-timew.sh (the original recipe keeps the
# full reasoning; the copy keeps this script one self-contained measurement) --------
cat > "$RUN/check.sh" <<'CHECK'
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
CHECK
chmod +x "$RUN/check.sh"

cat > "$RUN/setup.sh" <<'SETUP'
#!/bin/sh
set -eu
timew track 2020-01-01T10:00 - 2020-01-01T11:00 alpha :yes >/dev/null
SETUP
chmod +x "$RUN/setup.sh"

STATE=$RUN/state
export TIMEWARRIORDB=$STATE

reset_state() {
    [ -e "$STATE" ] && mv "$STATE" "$RUN/state-after-leg-$1"
    mkdir -p "$STATE"
}

build_timew() { # $1 = src dir, $2 = build dir, $3 = label
    ( cd "$1" && git submodule update --init --quiet )
    cmake -S "$1" -B "$2" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$2" -j"$(nproc)" >/dev/null
    [ -x "$2/src/timew" ] || { echo "build produced no $2/src/timew"; exit 1; }
    cp "$2/src/timew" "$RUN/bin/timew"
    echo "($3) timew: $(timew --version)"
}

echo "=========== leg A: pinned upstream build; explore saves the case ==========="
git clone --quiet "$TIMEW_GIT" "$RUN/src-unpatched"
( cd "$RUN/src-unpatched" && git checkout --quiet "$PIN" )
# The content pin, enforced: what was checked out is byte-for-byte the commit the
# measurement names, whatever the transport did.
got=$(cd "$RUN/src-unpatched" && git rev-parse HEAD)
[ "$got" = "$PIN" ] || { echo "checkout mismatch: wanted $PIN, got $got"; exit 1; }
build_timew "$RUN/src-unpatched" "$RUN/build-unpatched" A
reset_state before-A
set +e
"$SIDEEYE" explore \
    --state "$STATE" --setup "$RUN/setup.sh" \
    --operation "timew track 2020-01-02T10:00 - 2020-01-02T11:00 beta :yes" \
    --check "$RUN/check.sh" \
    --shim "$SHIM" --work "$RUN/work" \
    --json "$RUN/a-explore.json" --oracle /usr/bin/strace > "$RUN/a-explore.txt" 2>&1
rc_a=$?
set -e
CASE=$RUN/work/cases/000001.json
if python3 -c '
# Explicit checks, not assert: assert vanishes under PYTHONOPTIMIZE, and a judgement
# that an environment variable can silence is not a judgement.
import json, sys
r = json.load(open(sys.argv[1])); c = json.load(open(sys.argv[2]))
if r["verdict"] != "FAIL": sys.exit("verdict: %s" % r["verdict"])
if c.get("schema") != "sideeye/case" or c.get("ops_total", 0) <= 0: sys.exit("bad case")
' "$RUN/a-explore.json" "$CASE" 2>/dev/null && [ "$rc_a" = "1" ]; then
    pass "leg A: FAIL (exit 1), case saved"
else
    fail "leg A: expected exit 1 + verdict FAIL + a saved case (got exit $rc_a)"
    echo "leg A did not produce the counterexample; the later legs would measure nothing."
    sed 's/^/     | /' "$RUN/a-explore.txt" | tail -12
    exit 1
fi
OPS_TOTAL=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["ops_total"])' "$CASE")
K=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["k"])' "$CASE")
echo "case: k=$K of $OPS_TOTAL operations"

echo "=========== leg B: replay against the same build (must reproduce) ==========="
reset_state A
set +e
"$SIDEEYE" replay "$CASE" --shim "$SHIM" --work "$RUN/work-b" \
    --json "$RUN/b-replay.json" --oracle /usr/bin/strace > "$RUN/b-replay.txt" 2>&1
rc_b=$?
set -e
if python3 -c '
import json, sys
r = json.load(open(sys.argv[1]))
if r["verdict"] != "FAIL": sys.exit("verdict: %s (%s)" % (r["verdict"], r.get("unknown_reason")))
' "$RUN/b-replay.json" 2>/dev/null \
    && grep -q "the case reproduced" "$RUN/b-replay.txt" && [ "$rc_b" = "1" ]; then
    pass "leg B: the case reproduced (FAIL, exit 1)"
else
    fail "leg B: expected FAIL + 'the case reproduced' (got exit $rc_b)"
    sed 's/^/     | /' "$RUN/b-replay.txt" | tail -12
fi

echo "=========== leg C: the fix, rebuilt in a separate checkout, same name ==========="
git clone --quiet "$RUN/src-unpatched" "$RUN/src-patched"
( cd "$RUN/src-patched" && git checkout --quiet "$PIN" && git apply "$PATCH" )
build_timew "$RUN/src-patched" "$RUN/build-patched" C
reset_state B
set +e
"$SIDEEYE" replay "$CASE" --shim "$SHIM" --work "$RUN/work-c" \
    --json "$RUN/c-replay.json" --oracle /usr/bin/strace > "$RUN/c-replay.txt" 2>&1
rc_c=$?
set -e
if OPS_TOTAL="$OPS_TOTAL" python3 -c '
import json, os, sys
r = json.load(open(sys.argv[1]))
if r["verdict"] != "PASS":
    sys.exit("verdict: %s (%s) %s" % (r["verdict"], r.get("unknown_reason"), r.get("message", "")))
if r["explored"] != 2: sys.exit("explored: %s" % r["explored"])
if "unknown_reason" in r: sys.exit("unknown_reason present: %s" % r["unknown_reason"])
if r["crash_points"] != int(os.environ["OPS_TOTAL"]):
    sys.exit("crash_points %s != case ops_total %s" % (r["crash_points"], os.environ["OPS_TOTAL"]))
' "$RUN/c-replay.json" && [ "$rc_c" = "0" ]; then
    pass "leg C: PASS across the real fix (explored 2, landing context intact)"
else
    fail "leg C: expected a clean replay PASS (exit $rc_c). A case_no_longer_applies here is honest but does NOT meet the v0.4 acceptance"
    sed 's/^/     | /' "$RUN/c-replay.txt" | tail -12
fi

echo "=========== leg D: negative control — a different recording must refuse ==========="
cp "$DISTRO_TIMEW" "$RUN/bin/timew"
echo "(D) timew: $(timew --version)"
reset_state C
set +e
"$SIDEEYE" replay "$CASE" --shim "$SHIM" --work "$RUN/work-d" \
    --json "$RUN/d-replay.json" --oracle /usr/bin/strace > "$RUN/d-replay.txt" 2>&1
rc_d=$?
set -e
if python3 -c '
import json, sys
r = json.load(open(sys.argv[1]))
if r["verdict"] != "UNKNOWN": sys.exit("verdict: %s" % r["verdict"])
if r.get("unknown_reason") != "case_no_longer_applies":
    sys.exit("unknown_reason: %s" % r.get("unknown_reason"))
# The refusal must be for the predicted reason CLASS — a changed operation count —
# not merely any context mismatch (the count is distro-dependent; no number is pinned).
if "the case was recorded over" not in r.get("message", ""):
    sys.exit("refusal message does not name an operation-count mismatch: %s" % r.get("message"))
' "$RUN/d-replay.json" && [ "$rc_d" = "2" ]; then
    pass "leg D: refused (case_no_longer_applies, exit 2) — no verdict about the wrong recording"
else
    fail "leg D: expected UNKNOWN case_no_longer_applies (got exit $rc_d) — record what actually happened"
    sed 's/^/     | /' "$RUN/d-replay.txt" | tail -12
fi

echo ""
echo "for the record: $(uname -m), $(g++ --version | head -1)"
echo "commit $PIN, patch sha256 $(sha256sum "$PATCH" | cut -d' ' -f1)"
if [ "$fails" = "0" ]; then echo "ALL REPLAY-ACROSS-FIX LEGS PASSED"; else echo "$fails leg(s) failed"; exit 1; fi
