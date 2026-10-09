#!/bin/sh
# E: two dotenvx processes writing at once, both versions, ROUNDS rounds each. No crash, no Sideeye
# (Sideeye's reports list concurrent processes under `not tested`).
#   E1  `set A` and `set B` at once on one encrypted .env: both values must read back
#   E2  first `encrypt` of apps/a/.env and apps/b/.env at once, one shared .env.keys (-fk, the
#       monorepo layout): both files must decrypt
#   E3  `encrypt` of apps/b/.env while apps/a/.env is already encrypted with its key in the shared
#       .env.keys: apps/a/.env must still decrypt
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-dx1010 sh /ap/lab-8.sh
export HOME=/s/lab8/home UV_THREADPOOL_SIZE=1 npm_config_update_notifier=false; mkdir -p $HOME
ROUNDS=${ROUNDS:-20}
echo "# dotenvx concurrent: two encrypt or two set at once, $ROUNDS rounds per version (filed as dotenvx/dotenvx#1017)"
for v in 2.32.4 2.34.2; do
  export PATH=/opt/dx-$v/bin:/usr/local/bin:/usr/bin:/bin
  e1=0; e2=0; e3=0
  # the control: E2's two encrypts one after the other, and E1's two sets one after the other
  d=/s/lab8/$v-control; mkdir -p $d/apps/a $d/apps/b; cd $d
  printf 'A_SECRET=secret-a\n' > apps/a/.env; printf 'B_SECRET=secret-b\n' > apps/b/.env
  dotenvx encrypt -fk .env.keys -f apps/a/.env > /dev/null 2>&1; dotenvx encrypt -fk .env.keys -f apps/b/.env > /dev/null 2>&1
  echo "   control $v, one after the other: a='$(dotenvx get A_SECRET -fk .env.keys -f apps/a/.env 2>&1 | cut -c1-40)' b='$(dotenvx get B_SECRET -fk .env.keys -f apps/b/.env 2>&1 | cut -c1-40)'; keys: $(cut -c1-24 .env.keys | grep DOTENV | tr '\n' ' ')"
  printf 'BASE=base-value\n' > .env; dotenvx encrypt -f .env > /dev/null 2>&1; dotenvx set A value-a -f .env > /dev/null 2>&1; dotenvx set B value-b -f .env > /dev/null 2>&1
  echo "   control $v, set A then set B: A='$(dotenvx get A -f .env 2>&1)' B='$(dotenvx get B -f .env 2>&1)'"
  i=0; while [ $i -lt $ROUNDS ]; do i=$((i+1))
    d=/s/lab8/$v-e1-$i; mkdir -p $d; cd $d
    printf 'BASE=base-value\n' > .env; dotenvx encrypt -f .env > /dev/null 2>&1
    dotenvx set A value-a -f .env > /dev/null 2>&1 & dotenvx set B value-b -f .env > /dev/null 2>&1 & wait
    a=$(dotenvx get A -f .env 2>/dev/null); b=$(dotenvx get B -f .env 2>/dev/null)
    [ "$a" = value-a ] && [ "$b" = value-b ] || { e1=$((e1+1)); [ $e1 -eq 1 ] && echo "   E1 $v round $i: A='$a' B='$b'"; }

    d=/s/lab8/$v-e2-$i; mkdir -p $d/apps/a $d/apps/b; cd $d
    printf 'A_SECRET=secret-a\n' > apps/a/.env; printf 'B_SECRET=secret-b\n' > apps/b/.env
    dotenvx encrypt -fk .env.keys -f apps/a/.env > /dev/null 2>&1 & dotenvx encrypt -fk .env.keys -f apps/b/.env > /dev/null 2>&1 & wait
    a=$(dotenvx get A_SECRET -fk .env.keys -f apps/a/.env 2>/dev/null); b=$(dotenvx get B_SECRET -fk .env.keys -f apps/b/.env 2>/dev/null)
    [ "$a" = secret-a ] && [ "$b" = secret-b ] || { e2=$((e2+1)); [ $e2 -eq 1 ] && { echo "   E2 $v round $i: a='$(echo $a | cut -c1-30)' b='$(echo $b | cut -c1-30)'"; echo "      .env.keys: $(grep -c '^DOTENV_PRIVATE' .env.keys) private key line(s)"; }; }

    d=/s/lab8/$v-e3-$i; mkdir -p $d/apps/a $d/apps/b; cd $d
    printf 'A_SECRET=secret-a\n' > apps/a/.env; printf 'B_SECRET=secret-b\n' > apps/b/.env; printf 'C_SECRET=secret-c\n' > apps/c.env
    dotenvx encrypt -fk .env.keys -f apps/a/.env > /dev/null 2>&1
    dotenvx encrypt -fk .env.keys -f apps/b/.env > /dev/null 2>&1 & dotenvx encrypt -fk .env.keys -f apps/c.env > /dev/null 2>&1 & wait
    a=$(dotenvx get A_SECRET -fk .env.keys -f apps/a/.env 2>/dev/null); b=$(dotenvx get B_SECRET -fk .env.keys -f apps/b/.env 2>/dev/null); c=$(dotenvx get C_SECRET -fk .env.keys -f apps/c.env 2>/dev/null)
    [ "$a" = secret-a ] && [ "$b" = secret-b ] && [ "$c" = secret-c ] || { e3=$((e3+1)); [ $e3 -eq 1 ] && echo "   E3 $v round $i: a='$(echo $a | cut -c1-30)' b='$(echo $b | cut -c1-30)' c='$(echo $c | cut -c1-30)'"; }
  done
  echo "## $v: E1 lost a value in $e1/$ROUNDS, E2 left a file undecryptable in $e2/$ROUNDS, E3 in $e3/$ROUNDS"
done
