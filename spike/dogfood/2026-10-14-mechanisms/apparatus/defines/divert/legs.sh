# One broken state per leg of CANDIDATES.md 1.3, each breaking that leg alone, on the completed state.
LEGS="a b"
break_a() { mv /s/dv/root/usr/bin/tool.distrib /s/dv/root/usr/bin/tool; }
break_b() { cp /s/dv/root/usr/bin/tool.distrib /s/dv/root/usr/bin/tool; }
