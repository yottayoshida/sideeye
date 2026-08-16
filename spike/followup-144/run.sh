#!/bin/sh
# The labeled follow-up run for #144 (see NOTES.md). Reads the committed
# corpus define verbatim (setup.sh as-is; op.txt expanded against this
# run's own state root, the same expansion the sweep launcher performs)
# and adds the reader-checker. Runs in the sweep's extra image
# (bogofilter-sqlite, strace, python3 present).
set -eu
SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
here=/work/spike/followup-144
defs=/work/spike/unknown-rate/defines-b/bogofilter-sqlite
OUT=${OUT:?pass OUT=<artifact dir>}

root=/tmp/followup-144
[ -e "$root" ] && { echo "state root exists: $root — fresh container required"; exit 1; }
mkdir -p "$root/state" "$OUT"
export HOME=/tmp/followup-144-home
mkdir -p "$HOME"
[ -f "$defs/env.sh" ] && . "$defs/env.sh"

op=$(head -n 1 "$defs/op.txt" | sed "s|\$TOY_STATE|$root/state|g")

set +e
"$SIDEEYE" explore \
    --state "$root/state" --setup "$defs/setup.sh" \
    --operation "$op" \
    --check "$here/check.sh" \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$root/work" --json "$OUT/report.json" \
    > "$OUT/transcript.txt" 2>&1
rc=$?
set -e
echo "followup-144 exit=$rc (0 PASS / 1 FAIL / 2 UNKNOWN / 3 SETUP ERROR)"
[ -f "$OUT/report.json" ] || { echo "no report — apparatus failure"; exit 1; }
cp /tmp/followup-144/checker.log "$OUT/checker.log"
# The pins: this run is a record, and a record that cannot go red on a
# re-run is not one. The per-world log must show the falsification gate's
# red first and then only passes — that is what backs "the checker never
# failed in any world", which the report alone cannot carry (it records
# only the earliest violating world's invariant).
python3 - "$OUT/report.json" "$OUT/checker.log" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
e = r.get("earliest", {})
print("verdict:", r.get("verdict"), "| violations:", r.get("violations"),
      "/", r.get("explored"))
print("earliest.invariant:", e.get("invariant"))
print("checker account:", r.get("checker"))
lines = [l.strip() for l in open(sys.argv[2]) if l.strip()]
print("checker.log:", len(lines), "lines;", sum(1 for l in lines if l == "ok"), "ok")
def die(m): sys.exit("PIN FAILED: " + m)
if r.get("verdict") != "FAIL": die("verdict %s" % r.get("verdict"))
if r.get("violations") != 3: die("violations %s" % r.get("violations"))
if e.get("invariant") != "built-in atomicity (L0)": die("invariant %r" % e.get("invariant"))
if not lines or not lines[0].startswith("fail:"): die("line 1 must be the falsification gate's red")
worlds = lines[1:]
if len(worlds) != r.get("explored"): die("world lines %d != explored %s" % (len(worlds), r.get("explored")))
if any(l != "ok" for l in worlds): die("a world's checker failed: %r" % [l for l in worlds if l != "ok"])
print("pins hold: gate red first, then the checker passed in every explored world")
PY
