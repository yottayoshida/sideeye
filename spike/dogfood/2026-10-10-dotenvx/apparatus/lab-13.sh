#!/bin/sh
# The key-custody defines by hand: where the key sits after the operation, and the checker shown a
# state where every place that held a key is emptied but .env is not.  sh /ap/lab-13.sh <define>...
. /ap/env.sh; export PATH=/opt/dx-2.34.2/bin:$PATH
for t in "$@"; do ( d=/ap/defines/$t; . $d/env.sh; sh $d/seed.sh > /dev/null 2>&1
  op=$(sed -n 's/^operation = "\(.*\)"$/\1/p' $d/sideeye.toml); cd /s/kc; eval "$op" > /tmp/op.out 2>&1
  where="$(grep -c '^DOTENV_PRIVATE_KEY=.' .env.keys 2>/dev/null || echo 0) in .env.keys, $(grep -o '[0-9a-f]\{64\}' keyring.json 2>/dev/null | wc -l) in keyring, $(grep -o '[0-9a-f]\{64\}' op.json 2>/dev/null | wc -l) in op"
  export SIDEEYE_STATE_DIR=/s/kc; $d/check.sh > /dev/null 2>&1; a=$?
  for f in .env.keys keyring.json op.json; do [ -e $f ] && : > $f; done
  red=$($d/check.sh 2>&1); b=$?
  echo "$t: after the operation the key is $where; check $a; every key store emptied -> $b [$(echo $red | cut -c1-70)]" ); done
