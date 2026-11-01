#!/bin/sh
# Box side: seed the target as its own campaign did, then explore it once in the default mode with
# the strace oracle. The define, the seed and the checker are that campaign's, mounted at /ap.
set -u
t=${1:?target}
o=/out/$t; mkdir -p "$o"
[ -f /ap/defines/$t/env.sh ] && . /ap/defines/$t/env.sh
sh /ap/defines/$t/seed.sh > "$o/seed.log" 2>&1 || { echo "$t: seed failed"; tail -3 "$o/seed.log"; exit 1; }
state=$(sed -n 's/^state *= *"\(.*\)"/\1/p' /ap/defines/$t/sideeye.toml)
echo "filesystem of $state: $(stat -f -c %T "$state")" | tee "$o/fs.txt"
getfacl -p "$state" > "$o/acl.txt" 2>&1
/eng/bin/sideeye explore --config /ap/defines/$t/sideeye.toml --shim /eng/lib/libsideeye_shim.so \
    --oracle /usr/bin/strace --work /tmp/w --json "$o/explore.json" > "$o/explore.txt" 2>&1
echo "exit $?" >> "$o/explore.txt"
python3 - "$o/explore.json" "$t" <<'PY'
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception as e: print(sys.argv[2], "no json:", e); sys.exit()
print("%s verdict=%s reason=%s oracle_verified=%s crash_points=%s" % (sys.argv[2], d.get("verdict"), d.get("unknown_reason", "-"), d.get("oracle_verified"), d.get("crash_points")))
print("%s metadata_writes=%s" % (sys.argv[2], d.get("metadata_writes")))
PY
