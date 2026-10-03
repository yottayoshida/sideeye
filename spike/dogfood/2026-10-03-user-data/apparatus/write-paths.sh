#!/bin/sh
# How each PASS wrote its state: the operation once under strace from its seed, with only the
# calls that touch the state root kept. For the target-classes rows, which say why a PASS
# passed (a temporary file and a rename, a new file and an unlink, ...).
#
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1003 sh /ap/write-paths.sh <name> [...]
#
# A pinned define (z.lua) runs in a box of its own, as with the gate and explore.
set -u
. /ap/env.sh
for t in "$@"; do
    ( d=/ap/defines/$t
      [ -f "$d/env.sh" ] && . "$d/env.sh"
      state=$(sed -n 's/^state *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      cwd=$(sed -n 's/^cwd *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      op=$(sed -n 's/^operation *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      sh "$d/seed.sh" > /dev/null 2>&1
      cd "$cwd" && strace -f -qq -e trace=openat,creat,write,pwrite64,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync \
          -o /tmp/st.$t $op < /dev/null > /dev/null 2>&1
      echo "=== $t ($op)"
      grep -v -E 'O_RDONLY|ENOENT|"/(usr|etc|proc|dev|sys|lib|opt|root|tmp|s/aux)/|write\(([12]),' /tmp/st.$t | sed -E 's/^[0-9]+ +//' | cut -c1-150 | head -14 )
done
