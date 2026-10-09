#!/bin/sh
# The findings without Sideeye, in the form a maintainer can paste: one strace line each, on 2.34.2.
# Each in a fresh HOME and repository. Every case twice: SIGKILL at the first write to the file, and
# the same write failing with ENOSPC (a full disk; no crash at all).
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-dx1010 sh /ap/lab-5.sh
export PATH=/opt/dx-2.34.2/bin:/usr/local/bin:/usr/bin:/bin UV_THREADPOOL_SIZE=1 npm_config_update_notifier=false
fresh() { # <name>
  export HOME=/s/lab5/home-$1 XDG_CONFIG_HOME=; mkdir -p "$HOME"; git init -q /s/lab5/$1; cd /s/lab5/$1
}
show() { echo "   exit $1; $2: $(wc -c < "$2") bytes: $(head -c 60 "$2" | tr '\n' '|')"; }
for how in signal=KILL error=ENOSPC; do
  echo "## B1 pre-commit hook, $how"
  fresh hook-$how
  printf '#!/bin/sh\nnpm test\n' > .git/hooks/pre-commit; chmod 755 .git/hooks/pre-commit
  dotenvx precommit --install > ../pc.txt 2>&1; echo "   precommit --install: $(grep -v '^$' ../pc.txt | head -2 | tr '\n' ' ')"
  echo "   before: $(wc -c < .git/hooks/pre-commit) bytes"
  strace -f -qq -o /dev/null -P "$PWD/.git/hooks/pre-commit" -e inject=write:$how dotenvx protect > ../out.txt 2>&1
  show $? .git/hooks/pre-commit; echo "   said: $(grep -v '^$' ../out.txt | tail -1 | cut -c1-120)"

  echo "## B2 global git attributes holding the old filter=dotenvx lines, $how"
  fresh attr-$how
  mkdir -p ~/.config/git; printf '*.png binary\n.env* filter=dotenvx\n' > ~/.config/git/attributes
  strace -f -qq -o /dev/null -P "$HOME/.config/git/attributes" -e inject=write:$how dotenvx protect > ../out.txt 2>&1
  show $? ~/.config/git/attributes; echo "   said: $(grep -v '^$' ../out.txt | tail -1 | cut -c1-120)"
  echo "   git config --global --get filter.dotenvx.required: $(git config --global --get filter.dotenvx.required)"

  echo "## B3 .git/info/attributes with the legacy local filter, $how"
  fresh info-$how
  git config filter.dotenvx.clean 'dotenvx precommit --clean %f'; git config filter.dotenvx.required true
  printf '*.psd binary\n.env* filter=dotenvx\n' > .git/info/attributes
  strace -f -qq -o /dev/null -P "$PWD/.git/info/attributes" -e inject=write:$how dotenvx protect > ../out.txt 2>&1
  show $? .git/info/attributes; echo "   said: $(grep -v '^$' ../out.txt | tail -1 | cut -c1-120)"

  echo "## B5 Envfile, spec --overwrite, $how"
  fresh spec-$how
  printf 'DB_PASSWORD=x\n' > .env.example; dotenvx spec > /dev/null 2>&1; printf '# a rule of my own\n' >> Envfile
  strace -f -qq -o /dev/null -P "$PWD/Envfile" -e inject=write:$how dotenvx spec --overwrite > ../out.txt 2>&1
  show $? Envfile; echo "   said: $(grep -v '^$' ../out.txt | tail -1 | cut -c1-120)"
done

echo "## C1 encrypt killed at its first rename, .gitignore naming .env.keys"
fresh c1
printf 'DB_PASSWORD=hunter2\n' > .env; printf '.env.keys\n' > .gitignore
strace -f -qq -o /dev/null -e inject=renameat,renameat2:signal=KILL dotenvx encrypt > ../out.txt 2>&1; echo "   exit $?"
ls -A | grep -v '^\.git$' | sed 's/^/   /'
git add -A; echo "   git status --short:"; git status --short | sed 's/^/     /'
echo "   then encrypt again: $(dotenvx encrypt 2>&1 | tail -1 | cut -c1-80)"; ls -A | grep -v '^\.git$' | tr '\n' ' '; echo

echo "## C1b the same, where it matters: .env already encrypted and committed, then .env.production"
fresh c1b
git config user.email lab@example.invalid; git config user.name lab
printf 'DB_PASSWORD=hunter2\n' > .env; printf 'PROD_DB_PASSWORD=prod\n' > .env.production; printf '.env.keys\n.env.production\n' > .gitignore
dotenvx encrypt -f .env > /dev/null 2>&1; git add .env .gitignore; git commit -qm 'encrypted .env'
strace -f -qq -o /dev/null -e inject=renameat,renameat2:signal=KILL dotenvx encrypt -f .env.production > ../out.txt 2>&1; echo "   exit $?"
ls -A | grep -v '^\.git$' | sed 's/^/   /'
git add -A; echo "   git status --short:"; git status --short | sed 's/^/     /'
k=$(git diff --cached --name-only | grep '^\.env\.keys\.'); echo "   dotenvx get DB_PASSWORD -f .env -fk $k: $(dotenvx get DB_PASSWORD -f .env -fk "$k" 2>&1)"
