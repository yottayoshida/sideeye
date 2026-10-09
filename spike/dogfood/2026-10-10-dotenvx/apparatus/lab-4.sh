#!/bin/sh
# C1 without Sideeye: what dotenvx leaves when it is killed at the rename write-file-atomic ends with,
# and what `git add -A` then takes, under three setups: .gitignore naming .env.keys (what `dotenvx
# gitignore --pattern .env.keys` writes, as `dotenvx help` shows it), .gitignore holding .env* (that
# command's default pattern), and no .gitignore with `dotenvx protect` installed. 2.32.4 beside it.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-dx1010 sh /ap/lab-4.sh
#
# The first version of this script ran strace with `-e trace=none`, which turns injection off too:
# every case exited 0 with nothing killed, and the protect case's global filter leaked into the cases
# after it. Each case now has a HOME of its own, and the exit status says whether the kill landed.
export UV_THREADPOOL_SIZE=1 npm_config_update_notifier=false
run() { # <version> <setup> <command>
  v=$1; s=$2; c=$3; export PATH=/opt/dx-$v/bin:/usr/local/bin:/usr/bin:/bin
  d=/s/lab4/$v-$s-$c; export HOME=/s/lab4/home-$v-$s-$c XDG_CONFIG_HOME=
  mkdir -p "$HOME"; git init -q "$d"; cd "$d"
  git config --global user.email lab@example.invalid; git config --global user.name lab
  printf 'DB_PASSWORD=hunter2-not-a-real-secret\nAPI_TOKEN_PLACEHOLDER=plaintext-value-one\n' > .env
  case $s in keys-by-name) printf '.env.keys\n' > .gitignore;; env-star) printf '.env*\n' > .gitignore;; protect) dotenvx protect > /dev/null 2>&1;; esac
  if [ "$c" = decrypt ]; then
    dotenvx encrypt -f .env > /dev/null 2>&1
    git add .env .gitignore 2>/dev/null; git commit -qm seed
  fi
  strace -f -qq -o /dev/null -e inject=renameat,renameat2:signal=KILL:when=${N:-1} dotenvx "$c" -f .env > "../out-$v-$s-$c.txt" 2>&1; rc=$?
  echo "## $v, $s, dotenvx $c, SIGKILL at its rename #${N:-1}: exit $rc"
  for f in $(ls -A | grep -v '^\.git$'); do
    printf '   %-24s %5s bytes  %s\n' "$f" "$(wc -c < "$f")" "$(grep -c '^DOTENV_PRIVATE_KEY' "$f") private-key line(s), $(grep -c 'not-a-real-secret' "$f") plaintext secret(s)"
  done
  ga=$(git add -A 2>&1); echo "   git add -A: exit $? $(echo "$ga" | grep -v '^$' | head -2 | tr '\n' ' ' | cut -c1-200)"
  echo "   staged: $(git diff --cached --name-only | tr '\n' ' ')"
}
for v in 2.34.2 2.32.4; do for s in keys-by-name env-star protect; do run $v $s encrypt; done; done
for s in keys-by-name env-star protect; do run 2.34.2 $s decrypt; done
