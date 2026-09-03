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
#       git ca-certificates cmake g++ make python3 strace timewarrior
#
# LEGS selects which legs run (default abcd — the original, full measurement).
# The CI regression job runs LEGS=abc: the FAIL/PASS pair across the fix, no
# distro package. Leg a is mandatory — b/c/d replay the case leg A records in
# this same run, so a subset without a would have nothing to replay. Leg-only
# preconditions (the distro timewarrior for leg d, the replay gate for leg c) are
# checked only when their leg is selected; an unconditional check here once made LEGS=abc die in an
# environment that had everything legs a-c need. The state-archive labels
# (state-after-leg-X) assume the default leg order; with a subset the label
# names the archive slot, not necessarily the leg that just ran.
set -eu

# ${LEGS-abcd}, not ${LEGS:-abcd}: an explicitly empty LEGS is a charset
# error below, never a silent fall-through to all four legs.
LEGS=${LEGS-abcd}
case "$LEGS" in
    *[!abcd]*|"") echo "LEGS may only contain a, b, c, d (got: '$LEGS')"; exit 1 ;;
esac
case "$LEGS" in
    *a*) : ;;
    *) echo "LEGS must include a: legs b/c/d replay the case leg A records in this run"; exit 1 ;;
esac
wants() { case "$LEGS" in *"$1"*) return 0 ;; *) return 1 ;; esac }

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
# Leg C's gate is checked up front, beside the binary, shim and patch — but only when leg C
# is selected, like the distro package for leg D: a missing file must not surface as a
# leg-C FAIL after two timewarrior builds, indistinguishable from a regression.
REPLAY_GATE=$SIDEEYE_REPO/spike/replay_gate.py
if wants c; then
    [ -f "$REPLAY_GATE" ] || { echo "replay gate not found: $REPLAY_GATE (leg C reads it)"; exit 1; }
fi
for tool in git cmake g++ make python3 strace; do
    command -v "$tool" >/dev/null || { echo "$tool not found; see the header for the install"; exit 1; }
done
if wants d; then
    command -v timew >/dev/null || { echo "distro timewarrior not found (needed for leg D); see the header"; exit 1; }
    DISTRO_TIMEW=$(command -v timew)
fi

# No recursive delete anywhere in this script: the run directory has to be new, and
# state resets move the old directory aside instead of removing it.
[ -e "$RUN" ] && { echo "$RUN already exists. Remove it yourself, or pass RUN=<new path>."; exit 1; }
mkdir -p "$RUN/bin"

# Whichever build sits at $RUN/bin/timew is what the recorded operation names.
export PATH="$RUN/bin:$PATH"

fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# --- the define, copied from its one canonical text (#65): check.sh, setup.sh and the
# operation string live in spike/loop-closure-timew/define/. This script carries none of
# them, so a refinement there is what every leg below measures. Two explicit paths, not a
# brace expansion: CI runs this file under sh ------------------------------------------
DEFINE=$SIDEEYE_REPO/spike/loop-closure-timew/define
for f in check.sh setup.sh operation; do
    [ -f "$DEFINE/$f" ] || { echo "define file not found: $DEFINE/$f"; exit 1; }
done
cp "$DEFINE/check.sh" "$RUN/check.sh"
cp "$DEFINE/setup.sh" "$RUN/setup.sh"
chmod +x "$RUN/check.sh" "$RUN/setup.sh"
OPERATION=$(cat "$DEFINE/operation")
[ -n "$OPERATION" ] || { echo "empty operation in $DEFINE/operation"; exit 1; }
# One line: this script quotes it, but the same file feeds judge.sh, which expands it
# unquoted inside its container, so a second line would ride into that command there.
# ($(cat) strips trailing newlines; an embedded one stays.)
nl=$(printf '\nx'); nl=${nl%x}
case "$OPERATION" in *"$nl"*) echo "operation must be one line: $DEFINE/operation"; exit 1 ;; esac

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
    --operation "$OPERATION" \
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

if wants b; then
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
fi

if wants c; then
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
# The gate is spike/replay_gate.py, the one text the loop-closure judge reads too (#65):
# exit 0, PASS, explored == 2, no unknown_reason, crash_points == the case's ops_total.
if python3 "$REPLAY_GATE" "$RUN/c-replay.json" "$rc_c" "$OPS_TOTAL"; then
    pass "leg C: PASS across the real fix (explored 2, landing context intact)"
else
    fail "leg C: expected a clean replay PASS (exit $rc_c). A case_no_longer_applies here is honest but does NOT meet the v0.4 acceptance"
    sed 's/^/     | /' "$RUN/c-replay.txt" | tail -12
fi
fi

if wants d; then
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
fi

echo ""
echo "for the record: $(uname -m), $(g++ --version | head -1), legs run: $LEGS"
echo "commit $PIN, patch sha256 $(sha256sum "$PATCH" | cut -d' ' -f1)"
if [ "$fails" = "0" ]; then echo "ALL REPLAY-ACROSS-FIX LEGS PASSED (legs: $LEGS)"; else echo "$fails leg(s) failed"; exit 1; fi
