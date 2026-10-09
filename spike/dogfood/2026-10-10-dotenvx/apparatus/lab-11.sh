#!/bin/sh
# G1 and H1 on 2.34.2 (2.32.4 beside it where the write path differs). No Sideeye.
#   G1  what a rewrite does to the file's mode, its owner, a symlink at its name, a hard link to it;
#       the commands the first pass did not run: genexample, precommit --install (new and appended),
#       set --plain, encrypt -k, encrypt with an Envfile, -fk in another directory
#   H1  encrypt, set and decrypt with the write, the fsync or the rename failing (ENOSPC, EACCES, EIO)
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-dx1010 sh /ap/lab-11.sh
export HOME=/s/lab11/home UV_THREADPOOL_SIZE=1 npm_config_update_notifier=false; mkdir -p $HOME
seed() { rm -rf "$1"; mkdir -p "$1"; cd "$1"; printf 'DB_PASSWORD=hunter2\nAPI=one\n' > .env; }
vals() { echo "DB_PASSWORD=$(dotenvx get DB_PASSWORD -f ${1:-.env} 2>/dev/null) API=$(dotenvx get API -f ${1:-.env} 2>/dev/null)"; }
for v in 2.32.4 2.34.2; do
  export PATH=/opt/dx-$v/bin:/usr/local/bin:/usr/bin:/bin
  echo "########## $v"
  echo "## G1 mode and owner: .env 0640 owned by nobody, .env.keys 0640"
  seed /s/lab11/$v-mode; chmod 640 .env; chown nobody:nogroup .env; dotenvx encrypt -f .env > /dev/null 2>&1
  chmod 640 .env.keys; dotenvx set NEW x -f .env > /dev/null 2>&1
  stat -c '   %n %a %U:%G' .env .env.keys
  echo "## G1 .env and .env.keys as symlinks into secrets/"
  seed /s/lab11/$v-link; mkdir secrets; mv .env secrets/.env; ln -s secrets/.env .env
  printf '' > secrets/.env.keys; ln -s secrets/.env.keys .env.keys; rm secrets/.env.keys
  dotenvx encrypt -f .env > /dev/null 2>&1; dotenvx set NEW x -f .env > /dev/null 2>&1
  echo "   $(ls -l .env .env.keys 2>&1 | awk '{print $1, $NF}' | tr '\n' ' ')| secrets/: $(ls -A secrets | tr '\n' ' ')| $(vals)"
  echo "## G1 a hard link to .env (a second checkout's copy, a backup tool's)"
  seed /s/lab11/$v-hard; ln .env ../$v-hard-twin; dotenvx encrypt -f .env > /dev/null 2>&1
  echo "   links now: $(stat -c %h .env); the twin: $(head -c 40 ../$v-hard-twin | tr '\n' '|')"
  echo "## G1 the other commands"
  seed /s/lab11/$v-cmds; printf 'DB_PASSWORD=x\n' > .env.example; printf '#!/bin/sh\nnpm test\n' > hook; mkdir -p .git/hooks
  dotenvx ext genexample > /dev/null 2>&1; echo "   genexample: exit $? .env.example: $(tr '\n' '|' < .env.example | cut -c1-60)"
  git init -q . 2>/dev/null; dotenvx precommit --install > /dev/null 2>&1; echo "   precommit --install (new): $(stat -c '%a %s' .git/hooks/pre-commit)"
  cp hook .git/hooks/pre-commit; dotenvx precommit --install > /dev/null 2>&1; echo "   precommit --install (appended): $(head -2 .git/hooks/pre-commit | tail -1) ... $(wc -c < .git/hooks/pre-commit) bytes"
  dotenvx encrypt -f .env > /dev/null 2>&1; dotenvx set PLAIN_ONE p1 --plain -f .env > /dev/null 2>&1; echo "   set --plain: $(grep ^PLAIN_ONE .env) | $(vals)"
  seed /s/lab11/$v-k; dotenvx encrypt -k DB_PASSWORD -f .env > /dev/null 2>&1; echo "   encrypt -k DB_PASSWORD: $(grep ^API .env) | $(vals)"
  seed /s/lab11/$v-fk; mkdir -p ../$v-keysdir; dotenvx encrypt -fk ../$v-keysdir/.env.keys -f .env > /dev/null 2>&1; echo "   -fk in another directory: $(DB=$(dotenvx get DB_PASSWORD -fk ../$v-keysdir/.env.keys -f .env 2>&1); echo DB_PASSWORD=$DB)"
  seed /s/lab11/$v-envfile; dotenvx spec > /dev/null 2>&1; dotenvx encrypt -f .env > /dev/null 2>&1; echo "   encrypt with an Envfile: $(vals)"
  [ $v = 2.32.4 ] && continue
  echo "## H1 2.34.2 with every write, fsync or rename failing (when=1+: a full disk fails them all; the first write is often node's own stderr)"
  for c in encrypt set decrypt; do for sc in write fsync renameat,renameat2; do for err in ENOSPC EACCES EIO; do
    seed /s/lab11/h-$c-$sc-$err; [ $c != encrypt ] && dotenvx encrypt -f .env > /dev/null 2>&1
    case $c in encrypt) cmd="encrypt -f .env";; set) cmd="set API two -f .env";; decrypt) cmd="decrypt -f .env";; esac
    strace -f -qq -o /dev/null -e inject=$sc:error=$err:when=1+ dotenvx $cmd > ../out.txt 2>&1; rc=$?
    r=$(vals); left=$(ls -A | grep -v '^\.env$\|^\.env\.keys$' | tr '\n' ' ')
    case "$r" in "DB_PASSWORD=hunter2 API=one"|"DB_PASSWORD=hunter2 API=two") ok=held;; *) ok=LOST;; esac
    echo "   $c, first $sc -> $err: exit $rc, $ok ($r)${left:+, left: $left}"
  done; done; done
done
