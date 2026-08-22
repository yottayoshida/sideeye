#!/bin/sh
# Cohort-3 black define (P1) setup: one unformatted Python file, bytes
# frozen in PROTOCOL.md's probe plan. Nothing else — no cache exists
# (--no-cache), no config, no ambient state beyond the launcher's fresh
# HOME.
set -eu
B=/tmp/cohort3/black
rm -rf "$B/state"
mkdir -p "$B/state" "$B/home"
cat > "$B/state/probe.py" <<'EOF'
x=[1,2,3]
def f(a,b):
    return {'k':a+b,'l':[v   for v in x]}
y = f( 1 ,2 )
EOF
