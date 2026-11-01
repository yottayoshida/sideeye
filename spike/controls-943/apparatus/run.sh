#!/bin/sh
# Box side: the 2026-10-14 seed, then preflight on the copy that declares the controls.
set -u
. /ap/defines/alembic/env.sh
sh /ap/defines/alembic/seed.sh > /out/seed.log 2>&1 || { echo "seed failed"; tail -3 /out/seed.log; exit 1; }
/eng/bin/sideeye preflight --config /x/sideeye.toml --shim /eng/lib/libsideeye_shim.so \
    --oracle /usr/bin/strace --work /tmp/w --json /out/preflight.json > /out/preflight.txt 2>&1
echo "exit $?" >> /out/preflight.txt
python3 - /out/preflight.json <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))["controls"]
print("baseline: %s (%s)" % (c["baseline"]["word"], c["baseline"]["checker_exit"]))
for k in c["legs"]:
    print("%s: %s red=%s" % (k["leg"], k["word"], ",".join(k["red"])))
PY
