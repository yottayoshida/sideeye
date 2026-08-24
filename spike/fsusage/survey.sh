#!/bin/sh
# The unprivileged half of the fs_usage survey (#286, route F1).
#
# What this half can measure without root: the exact refusal fs_usage gives an
# unprivileged caller (verbatim, because the claim sites quote sentences), the
# judge's selftest with both sabotage controls, and that the probe builds and
# self-accounts. Everything root-gated is in sudo-survey.sh, run by the CI
# runner (whose sudo needs no human) or by the owner.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
W=$(mktemp -d "$HOME/se286f1.XXXXXX") || { echo "BROKEN: mktemp failed" >&2; exit 1; }
case "$W" in "$HOME"/se286f1.*) : ;; *) echo "BROKEN: unexpected workdir '$W'" >&2; exit 1 ;; esac
FAILS=0
bad() { echo "BROKEN: $*"; FAILS=$((FAILS+1)); }

echo "== environment"
sw_vers | sed 's/^/   /'
echo "   $(uname -rm)"
echo "   invoked as uid $(id -u) (this half is deliberately unprivileged)"

echo ""
echo "== the judge, seen red before it judges anything"
python3 "$here/classify.py" --selftest > "$W/st.txt" 2>&1
strc=$?
sed 's/^/  /' "$W/st.txt"
[ "$strc" -eq 0 ] || bad "classify selftest failed (rc $strc)"

echo "-- positive control: the selftest must kill a judge that always accepts"
# Every `return 1` at any indentation, not only the eight-space ones: R2
# found the deeper branches (child control, and the BROKEN guards) untouched
# by the old pattern, so their selftest cases were never proven red.
sed -E 's/^( +)return 1$/\1return 0  # SABOTAGE/' "$here/classify.py" > "$W/ja.py"
python3 "$W/ja.py" --selftest > "$W/sa.txt" 2>&1
grep -q 'selftest cases:' "$W/sa.txt" || bad "the always-accept control did not run to completion"
n=$(grep -c 'selftest FAIL' "$W/sa.txt" || true)
echo "   always-accept judge -> $n selftest failure(s)"
[ "${n:-0}" -gt 0 ] || bad "an always-accept judge passed the selftest"

echo "-- positive control: and a judge that always rejects (one verdict body)"
python3 - "$here/classify.py" "$W/jr.py" <<'SABOTAGE'
import re
import sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^def v_p4\([^)]*\):", src, re.M)
if not m:
    sys.exit("could not locate v_p4 to sabotage")
nxt = re.search(r"^def ", src[m.end():], re.M)
if not nxt:
    sys.exit("could not find the end of v_p4")
args = m.group(0)[len("def v_p4("):-2]
open(sys.argv[2], "w", encoding="utf-8").write(
    src[:m.start()]
    + f"def v_p4({args}):\n    return 1  # SABOTAGE\n\n\n"
    + src[m.end() + nxt.start():])
SABOTAGE
python3 "$W/jr.py" --selftest > "$W/sr.txt" 2>&1
grep -q 'selftest cases:' "$W/sr.txt" || bad "the always-reject control did not run to completion"
n=$(grep -c 'selftest FAIL' "$W/sr.txt" || true)
echo "   always-reject judge -> $n selftest failure(s)"
[ "${n:-0}" -gt 0 ] || bad "an always-reject judge passed the selftest"

echo ""
echo "== the probe builds and self-accounts"
/usr/bin/cc -O0 -Wall -Wextra -o "$W/probe" "$here/probe.c" || bad "probe build failed"
mkdir -p "$W/state"
"$W/probe" --setup "$W/state" write || bad "probe setup failed"
"$W/probe" --run "$W/state" write > "$W/ops.jsonl" 2>&1
prc=$?
echo "   probe rc=$prc; account:"
sed 's/^/     /' "$W/ops.jsonl"
[ "$prc" -eq 0 ] || bad "probe run failed"

echo ""
echo "== the refusal, verbatim (fs_usage asked once, no root)"
fs_usage -w -f filesys -t 1 > "$W/refusal.txt" 2>&1
echo "   rc=$?"
sed 's/^/   | /' "$W/refusal.txt"

/bin/rm -rf "${W:?}" 2>/dev/null || /usr/bin/trash "$W" 2>/dev/null || true
echo ""
echo "== BROKEN checks: $FAILS"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
