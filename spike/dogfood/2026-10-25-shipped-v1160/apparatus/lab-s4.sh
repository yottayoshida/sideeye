#!/bin/sh
# Set 4's plain runs, no Sideeye: each define's seed, its operation once as the toml spells it, in its
# cwd, under the environment run.sh gives an explore, then its checker (and the recovery's, if any).
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-sv1025-s4 sh /ap/lab-s4.sh [name ...]
set -u
[ $# -gt 0 ] || set -- paperless godot luanti navidrome firefly
cat /versions.txt
for t in "$@"; do
    echo "=== $t"
    ( . /ap/env.sh; [ -f /ap/defines/$t/env.sh ] && . /ap/defines/$t/env.sh
      sh /ap/defines/$t/seed.sh > /s/aux/seed-$t.log 2>&1 || { echo "seed failed"; tail -5 /s/aux/seed-$t.log; exit 0; }
      eval "$(python3 -c '
import sys, tomllib, shlex
d = tomllib.load(open(sys.argv[1], "rb")); df = d["define"]; r = d.get("recovery", {})
print("state=" + shlex.quote(d["world"]["state"]), "op=" + shlex.quote(df["operation"]), "cwd=" + shlex.quote(df.get("cwd", "/")),
      "check=" + shlex.quote(df.get("check", "")), "rcheck=" + shlex.quote(r.get("check", "")))' /ap/defines/$t/sideeye.toml)"
      export SIDEEYE_STATE_DIR=$state
      echo "before: $(find "$state" -type f | wc -l) files"
      ( cd "$cwd" && $op < /dev/null > /s/aux/op-$t.log 2>&1 ); echo "operation exit $?"
      tail -3 /s/aux/op-$t.log | cut -c1-200
      echo "after: $(find "$state" -type f | wc -l) files"
      [ -n "$check" ] && { $check; echo "check exit $?"; }
      [ -n "$rcheck" ] && { $rcheck; echo "recovery check exit $?"; } )
done
