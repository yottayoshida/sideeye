#!/bin/sh
# Cohort-3 black define (P1) checker. Property (proposals.md P1): crash
# anywhere inside the in-place rewrite, and the source survives as a
# program — the file parses as Python (leg V) and its AST equals the
# frozen pre-operation program's (leg E, black's own --safe contract
# applied across a crash). NO recovery leg: black documents no crash
# recovery and the source is the primary data (the cargo precedent's
# principle, proposals.md "The torn-file reading"). The engine snapshots
# and judges L0 before this runs. Both the old bytes and the formatted
# output are green on both legs (drilled); a torn intermediate is red.
set -u
S=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}

fail() { echo "checker(black-format): $*"; exit 1; }

[ -f "$S/probe.py" ] || fail "probe.py is missing from the state dir"

python3 - "$S/probe.py" <<'EOF'
import ast, sys

FROZEN = """x=[1,2,3]
def f(a,b):
    return {'k':a+b,'l':[v   for v in x]}
y = f( 1 ,2 )
"""

path = sys.argv[1]
data = open(path, "rb").read()
try:
    got = ast.parse(data.decode("utf-8"))
except (SyntaxError, ValueError, UnicodeDecodeError) as e:
    print(f"checker(black-format): leg V: the crashed file no longer parses as Python: {e}")
    sys.exit(1)
want = ast.parse(FROZEN)
if ast.dump(got) != ast.dump(want):
    print("checker(black-format): leg E: the file parses but is a DIFFERENT program from the frozen source")
    sys.exit(1)
sys.exit(0)
EOF
rc=$?
[ "$rc" -eq 0 ] || exit 1
exit 0
