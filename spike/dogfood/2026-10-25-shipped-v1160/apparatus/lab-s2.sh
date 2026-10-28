#!/bin/sh
# Set 2, each define once with no Sideeye: seed, the checker on the seeded state, the operation, the
# checker on what it left. Run in the set's box (sideeye-sv1025-s2), --network none.
#   docker run --rm --privileged --network none -v <apparatus>:/ap:ro sideeye-sv1025-s2 sh /ap/lab-s2.sh [name ...]
set -u
[ $# -gt 0 ] || set -- gogs symfony-secrets nextcloud-occ docusaurus drizzle-kit
for t in "$@"; do
  ( d=/ap/defines/$t; . /ap/env.sh; [ -f $d/env.sh ] && . $d/env.sh
    echo "=== $t"
    sh $d/seed.sh > /tmp/seed-$t.log 2>&1 || { echo "seed rc=$?"; tail -5 /tmp/seed-$t.log; exit 0; }
    op=$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["define"]["operation"])' $d/sideeye.toml)
    cwd=$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["define"].get("cwd","/"))' $d/sideeye.toml)
    st=$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["world"]["state"])' $d/sideeye.toml)
    ck=$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["define"].get("check",""))' $d/sideeye.toml)
    echo "state before: $(find $st -type f | wc -l) files, $(du -sk $st | cut -f1) KiB"
    [ -n "$ck" ] && { SIDEEYE_STATE_DIR=$st $ck; echo "check on seed rc=$?"; }
    ( cd $cwd && sh -c "$op" < /dev/null ) > /tmp/op-$t.log 2>&1; echo "operation rc=$?"; tail -3 /tmp/op-$t.log
    echo "state after: $(find $st -type f | wc -l) files"; find $st -maxdepth 2 | head -15
    [ -n "$ck" ] && { SIDEEYE_STATE_DIR=$st $ck; echo "check after rc=$?"; } )
done
