# One broken state per leg of CANDIDATES.md 1.2, each breaking that leg alone, on the completed state.
LEGS="a b c"
break_a() { sed -i '/^\/s\/ua\/opt\/ed1$/{n;s/^40$/forty/}' /s/ua/admin/editor; }
# Not alt/editor pointed elsewhere: the recovery's --install puts that link back, so it is no red.
break_b() { rm /s/ua/bin/editor && cp /s/ua/opt/ed2 /s/ua/bin/editor; }
break_c() { python3 - <<'PY'
p = "/s/ua/admin/editor"; s = open(p).read()
open(p, "w").write(s.replace("/s/ua/opt/ed1\n40\n", ""))
PY
}
