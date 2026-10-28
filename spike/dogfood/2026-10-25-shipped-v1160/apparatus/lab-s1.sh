#!/bin/sh
# Set 1's plain runs, no Sideeye: each define's seed, its operation in its cwd, then its checker on
# the state the operation left — so a red gate is never a define that does not run.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-sv1025-s1 sh /ap/lab-s1.sh [name ...]
set -u
[ $# -gt 0 ] || set -- etcdutl dolt tursodb diesel grafana
for t in "$@"; do
  (
    . /ap/env.sh; [ -f /ap/defines/$t/env.sh ] && . /ap/defines/$t/env.sh
    d=/ap/defines/$t
    eval "$(python3 - "$d/sideeye.toml" <<'PY'
import shlex, sys, tomllib
c = tomllib.load(open(sys.argv[1], "rb"))
op = c["define"]["operation"]
print("state=" + shlex.quote(c["world"]["state"]))
print("cwd=" + shlex.quote(c["define"].get("cwd", "/")))
print("check=" + shlex.quote(c["define"].get("check", "")))
print("op=" + shlex.quote(op if isinstance(op, str) else " ".join(shlex.quote(a) for a in op)))
PY
)"
    echo "=== $t"
    sh "$d/seed.sh" > /tmp/seed-$t.log 2>&1 || { echo "seed failed:"; tail -5 /tmp/seed-$t.log; exit 0; }
    echo "seed ok"
    SIDEEYE_STATE_DIR=$state sh -c "$check" && echo "check before: accepts" || echo "check before: REJECTS"
    (cd "$cwd" && eval "$op") > /tmp/op-$t.log 2>&1; echo "operation exit $?"; tail -3 /tmp/op-$t.log | cut -c1-200
    SIDEEYE_STATE_DIR=$state sh -c "$check" && echo "check after: accepts" || echo "check after: REJECTS"
    echo "state after:"; find "$state" -type f -exec ls -l {} + | awk '{print "  " $5, $9}' | head -20
  )
done
