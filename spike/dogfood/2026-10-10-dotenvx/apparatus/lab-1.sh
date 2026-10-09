#!/bin/sh
# A1 without Sideeye: the reproduction exactly as dotenvx/dotenvx#1012 printed it, on both versions,
# then the same kill on every write the process makes to the first file it writes, to see what
# each version leaves.  docker run --rm --network none -v <apparatus>:/ap:ro sideeye-dx1010 sh /ap/lab-1.sh
cat /versions.txt
for v in 2.32.4 2.34.2; do
  export PATH=/opt/dx-$v/bin:/usr/local/bin:/usr/bin:/bin
  d=/s/lab1-$v; rm -rf $d; mkdir -p $d; cd $d
  echo "## dotenvx $v — the issue's lines"
  printf 'DB_PASSWORD=hunter2\n' > .env
  strace -f -qq -P "$PWD/.env" -e inject=write,pwrite64:signal=KILL dotenvx encrypt -f .env > out.txt 2>&1; echo "exit $?"
  grep -v '^ *[0-9]* *+++' out.txt | head -5
  ls -la | sed 1d
  for f in .env*; do echo "--- $f: $(wc -c < "$f") bytes"; done
done
