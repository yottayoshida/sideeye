#!/bin/sh
# followup-95: hnb re-posed under the argv form, with the refused spelling as
# the control. Run inside the same image the #84 B-group sweep used (hnb is
# baked in — the control reproduces the sweep's refusal on the sweep's own
# target build), with the repo at /work and this branch's Linux cross-build
# in /work/zig-out:
#
#   docker run --rm -v <repo>:/work -w /work sideeye-ur-extra:latest \
#       sh spike/followup-95/run.sh
#
# Writes artifacts/ beside itself: report-control.json, report-argv.json,
# transcript.txt, and case-argv.json when the argv run FAILs. The pinned
# expectations live at the bottom; the script exits non-zero when any pin
# fails, so a run and a judgement cannot drift apart.
set -eu

HERE=$(dirname "$0")
ROOT=${SIDEEYE_ROOT:-/work}
SIDEEYE=$ROOT/zig-out/bin/sideeye
SHIM=$ROOT/zig-out/lib/libsideeye_shim.so
ART=$HERE/artifacts
BASE=/tmp/followup-95
T=$ART/transcript.txt

mkdir -p "$ART"
: > "$T"
say() { printf '%s\n' "$*" | tee -a "$T"; }

say "== followup-95 $(date -u +%Y-%m-%dT%H:%M:%SZ)"
command -v hnb >/dev/null 2>&1 || { say "hnb is not in this image; run in the B-group sweep image (sideeye-ur-extra)"; exit 1; }
say "hnb: $(dpkg-query -W -f='${Version}' hnb)"
say "engine: $("$SIDEEYE" --version 2>&1 | head -1)"

rm -rf "$BASE"
mkdir -p "$BASE"

# The seeded state, the B-group's shape: one node, then verify non-empty.
cat > "$BASE/setup.sh" <<'EOF'
#!/bin/sh
set -eu
hnb "$TOY_STATE/notes.hnb" -ui cli -e "add seeded" save >/dev/null 2>&1
[ -s "$TOY_STATE/notes.hnb" ]
EOF
chmod 755 "$BASE/setup.sh"

# ---- control: the refused spelling, verbatim from the sweep ------------------
cat > "$BASE/op.sh" <<'EOF'
#!/bin/sh
exec hnb "$TOY_STATE/notes.hnb" -ui cli -e "add second" save
EOF
chmod 755 "$BASE/op.sh"
mkdir -p "$BASE/state-control"
cat > "$BASE/control.toml" <<EOF
[world]
state = "$BASE/state-control"
[define]
setup     = "$BASE/setup.sh"
operation = "$BASE/op.sh"
EOF
say "-- control (wrapper spelling)"
set +e
"$SIDEEYE" explore --config "$BASE/control.toml" --shim "$SHIM" \
    --work "$BASE/work-control" --oracle /usr/bin/strace \
    --json "$ART/report-control.json" >>"$T" 2>&1
rc_control=$?
set -e
say "control rc=$rc_control"

# ---- the argv form: the same question, spelled inside the contract -----------
mkdir -p "$BASE/state-argv"
cat > "$BASE/argv.toml" <<EOF
[world]
state = "$BASE/state-argv"
[define]
setup     = "$BASE/setup.sh"
operation = ["hnb", "$BASE/state-argv/notes.hnb", "-ui", "cli", "-e", "add second", "save"]
EOF
say "-- argv form"
set +e
"$SIDEEYE" explore --config "$BASE/argv.toml" --shim "$SHIM" \
    --work "$BASE/work-argv" --oracle /usr/bin/strace \
    --json "$ART/report-argv.json" >>"$T" 2>&1
rc_argv=$?
set -e
say "argv rc=$rc_argv"

# On a FAIL the saved case must replay; recorded either way in the transcript.
rc_replay=-
if [ "$rc_argv" = "1" ] && [ -s "$BASE/work-argv/cases/000001.json" ]; then
    say "-- replay of the argv-form case"
    set +e
    "$SIDEEYE" replay "$BASE/work-argv/cases/000001.json" --shim "$SHIM" \
        --work "$BASE/work-replay" >>"$T" 2>&1
    rc_replay=$?
    set -e
    say "replay rc=$rc_replay"
    cp "$BASE/work-argv/cases/000001.json" "$ART/case-argv.json"
fi

# ---- pins (declared in NOTES.md before the run) ------------------------------
python3 - "$ART/report-control.json" "$ART/report-argv.json" "$rc_control" "$rc_argv" "$rc_replay" "$ART/case-argv.json" <<'PY'
import json, sys, os
ctrl = json.load(open(sys.argv[1]))
argv = json.load(open(sys.argv[2]))
rc_ctrl, rc_argv, rc_replay, case_path = sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
bad = []
if not (rc_ctrl == "2" and ctrl.get("verdict") == "UNKNOWN" and ctrl.get("unknown_reason") == "child_process_detected"):
    bad.append(f"control: rc={rc_ctrl} verdict={ctrl.get('verdict')} reason={ctrl.get('unknown_reason')} (wanted UNKNOWN/child_process_detected)")
if argv.get("verdict") not in ("PASS", "FAIL"):
    bad.append(f"argv: verdict={argv.get('verdict')} reason={argv.get('unknown_reason')} (wanted a verdict)")
if not (isinstance(argv.get("crash_points"), int) and argv["crash_points"] > 0):
    bad.append(f"argv: crash_points={argv.get('crash_points')} (wanted > 0 — a zero-op verdict is vacuous)")
if argv.get("verdict") == "FAIL":
    if rc_replay != "1":
        bad.append(f"replay rc={rc_replay} (a FAIL's case must reproduce)")
    if not os.path.exists(case_path):
        bad.append("case-argv.json missing beside a FAIL")
    else:
        case = json.load(open(case_path))
        if case.get("case_version") != 3:
            bad.append(f"case_version={case.get('case_version')} (an argv-carrying case is version 3)")
        if not isinstance(case.get("define", {}).get("operation"), list):
            bad.append("the case's define.operation is not a JSON array")
if bad:
    print("PINS FAILED:")
    [print("  " + b) for b in bad]
    sys.exit(1)
print(f"pins hold: control refused as the sweep did; argv form reached {argv['verdict']} over {argv['crash_points']} crash points" + (f"; v3 array-carrying case replayed (rc {rc_replay})" if rc_replay != "-" else ""))
PY
