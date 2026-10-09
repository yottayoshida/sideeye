#!/bin/sh
# Lab 2: dotenvx encrypt without Sideeye — strace kills it at its first write to .env (after the open that
# empties it), as the report will tell a maintainer to do. Then what .env and dotenvx get hold.
#   docker run --rm --network none --cap-add SYS_PTRACE -v <apparatus>:/ap:ro sideeye-fu3-1009 sh /ap/lab-2.sh
set -u
export HOME=/tmp/home; mkdir -p "$HOME"
rm -rf /t && mkdir -p /t && cd /t
printf 'DB_PASSWORD=hunter2\n' > .env
ls -l .env
strace -f -qq -o /tmp/dx.strace -P "$PWD/.env" -e trace=openat,write,pwrite64 -e inject=write,pwrite64:signal=KILL \
  dotenvx encrypt -f .env; echo "dotenvx exit $?"
grep -v ENOENT /tmp/dx.strace | grep -E "/t/.env|killed" | tail -4 | cut -c1-150
ls -la /t
dotenvx get DB_PASSWORD -f .env 2>&1 | tail -1 | cut -c1-120
echo "## not killed"
rm -rf /t && mkdir -p /t && cd /t && printf 'DB_PASSWORD=hunter2\n' > .env
dotenvx encrypt -f .env > /dev/null 2>&1; echo "exit $?"; ls -la /t; dotenvx get DB_PASSWORD -f .env 2>&1 | tail -1
