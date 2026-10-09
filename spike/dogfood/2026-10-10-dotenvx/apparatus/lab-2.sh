#!/bin/sh
# What `dotenvx get` prints and exits with in the states a checker meets: a value, a missing key,
# a missing private key, an empty file, a missing file. Both versions.
. /ap/env.sh; export UV_THREADPOOL_SIZE=1
for v in 2.32.4 2.34.2; do
  export PATH=/opt/dx-$v/bin:/usr/local/bin:/usr/bin:/bin
  d=/s/lab2-$v; rm -rf $d; mkdir -p $d; cd $d
  printf 'DB_PASSWORD=hunter2-not-a-real-secret\nAPI_TOKEN_PLACEHOLDER=plaintext-value-one\n' > .env
  dotenvx encrypt -f .env > /dev/null 2>&1
  g() { out=$(dotenvx get "$@" 2>err); echo "  get $* -> [$out] exit $? stderr: $(head -1 err | cut -c1-110)"; }
  echo "## $v"; g DB_PASSWORD -f .env; g NOPE -f .env
  mv .env.keys keys.bak; g DB_PASSWORD -f .env; mv keys.bak .env.keys
  : > empty.env; g DB_PASSWORD -f empty.env; g DB_PASSWORD -f missing.env
  echo "  spec: $(dotenvx spec --stdout -f .env 2>&1 | head -3 | tr '\n' '|')"
done
