#!/bin/sh
# A framework Python's launcher is refused with the interpreter it hands the run to named,
# and that interpreter, named as the operation, is judged (#703). macOS only.
#
# Usage: check-framework-launcher-macos.sh <sideeye> <shim> <workdir> <launcher> <toy>
#
# <launcher> is spike/toys/pythonw-launcher.c built for this host, a stand-in for CPython's
# Mac/Tools/pythonw.c: it replaces itself with ../Resources/Python.app/Contents/MacOS/Python
# through posix_spawn with POSIX_SPAWN_SETEXEC. <toy> is spike/toys/toy.c, put where the
# interpreter goes. The layout is the one `image.frameworkPython` reads — a launcher in a
# bin directory beside the framework library `Python` and the interpreter — built under a
# Python.framework/Versions/<v> of this script's workdir.
#
# What this holds that the unit tests cannot: the shipped engine, at the recording run's
# broken self-exec chain, chooses the step and adds the detail `boundary.selfExecStep`
# builds — the call site in src/main.zig, which a unit test does not reach (review of #703).
# Three legs: the launcher is refused with the interpreter named; the interpreter, as the
# detail names it, is judged; and with the framework library taken away the same launcher
# keeps the wrapper step, so the first leg's step is the layout's doing.
set -u
SIDEEYE=${1:?usage: check-framework-launcher-macos.sh <sideeye> <shim> <workdir> <launcher> <toy>}
SHIM=${2:?shim}
WS=${3:?workdir}
LAUNCHER_BIN=${4:?launcher}
TOY=${5:?toy}
[ "$(uname -s)" = Darwin ] || { echo "FAIL: macOS only"; exit 1; }
[ -x "$SIDEEYE" ] || { echo "FAIL: no sideeye at $SIDEEYE"; exit 1; }
[ -f "$SHIM" ] || { echo "FAIL: no shim at $SHIM"; exit 1; }
[ -x "$LAUNCHER_BIN" ] || { echo "FAIL: no launcher at $LAUNCHER_BIN"; exit 1; }
[ -x "$TOY" ] || { echo "FAIL: no toy at $TOY"; exit 1; }

V=$WS/Fake/Python.framework/Versions/9.9
mkdir -p "$V/bin" "$V/Resources/Python.app/Contents/MacOS" "$WS/work" || exit 1
cp "$LAUNCHER_BIN" "$V/bin/python9.9" && cp "$TOY" "$V/Resources/Python.app/Contents/MacOS/Python" || exit 1
printf 'the framework library\n' > "$V/Python" || exit 1
LAUNCHER=$V/bin/python9.9
fails=0

# explore --json for each leg: the verdict, the reason and the step are read as data. Each
# leg has a state directory of its own, so no leg starts from what another left and nothing
# here has to delete one.
leg() { # name operation report
    TOY_STATE="$WS/state-$1" "$SIDEEYE" explore --state "$WS/state-$1" --setup "$2 init" --operation "$2 rotate" \
        --shim "$SHIM" --work "$WS/work-$1" --json "$3" --allow-unverified > "$3.out" 2>&1
    echo $?
}

r1=$(leg launcher "$LAUNCHER" "$WS/r1.json")
interp=$(python3 - "$WS/r1.json" "$r1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
rc = sys.argv[2]
want = "Make the interpreter the detail above names"
msg, step = d.get("message") or "", d.get("next_step") or ""
if rc != "2" or d.get("verdict") != "UNKNOWN" or d.get("unknown_reason") != "child_process_detected":
    sys.exit("FAIL: launcher: rc %s, %s %s — wanted 2, UNKNOWN child_process_detected" % (rc, d.get("verdict"), d.get("unknown_reason")))
if not step.startswith(want):
    sys.exit("FAIL: launcher: the step is not the one naming the interpreter: %r" % step[:120])
marker = "whose interpreter is "
if marker not in msg or "at this refusal" not in msg:
    sys.exit("FAIL: launcher: the message names no interpreter: %r" % msg[-240:])
print(msg.split(marker, 1)[1].split(";", 1)[0])
PY
) || { echo "$interp"; fails=$((fails + 1)); interp=""; }
if [ -n "$interp" ]; then
    # The interpreter named is the file the layout holds, by its resolved path.
    want=$(cd "$V/Resources/Python.app/Contents/MacOS" && pwd -P)/Python
    if [ "$interp" = "$want" ]; then
        echo "ok   the launcher is refused child_process_detected, the step and the detail naming $interp"
    else
        echo "FAIL: the detail names $interp, not $want"; fails=$((fails + 1))
    fi
    r2=$(leg interpreter "$interp" "$WS/r2.json")
    python3 - "$WS/r2.json" "$r2" <<'PY' || fails=$((fails + 1))
import json, sys
d = json.load(open(sys.argv[1]))
if d.get("verdict") not in ("PASS", "FAIL"):
    sys.exit("FAIL: the interpreter named as the operation is %s %s (rc %s), not judged"
             % (d.get("verdict"), d.get("unknown_reason"), sys.argv[2]))
print("ok   the interpreter the detail names, as the operation, is judged: %s" % d["verdict"])
PY
fi

# The control: the same launcher with the framework library taken away keeps the wrapper step.
rm -f "$V/Python"
r3=$(leg control "$LAUNCHER" "$WS/r3.json")
python3 - "$WS/r3.json" "$r3" <<'PY' || fails=$((fails + 1))
import json, sys
d = json.load(open(sys.argv[1]))
step = d.get("next_step") or ""
if d.get("unknown_reason") != "child_process_detected" or not step.startswith("Check whether the operation is a shell script"):
    sys.exit("FAIL: without the framework library: %s, step %r — wanted child_process_detected and the wrapper step"
             % (d.get("unknown_reason"), step[:80]))
if "at this refusal" in (d.get("message") or ""):
    sys.exit("FAIL: without the framework library the message still names an interpreter")
print("ok   without the framework library the same launcher keeps the wrapper step")
PY

[ "$fails" = 0 ] || { echo "FAIL: $fails leg(s)"; exit 1; }
