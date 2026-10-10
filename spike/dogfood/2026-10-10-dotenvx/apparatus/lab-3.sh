#!/bin/sh
# Each define by hand, no Sideeye: seed, check, the operation, check, then the judged file emptied
# and check once more — the checker has to say no to that.  sh /ap/lab-3.sh <version> <define>...
v=$1; shift
. /ap/env.sh; export PATH=/opt/dx-$v/bin:$PATH
for t in "$@"; do
  d=/ap/defines/$t; ( [ -f $d/env.sh ] && . $d/env.sh
  st=$(sed -n 's/^state = "\(.*\)"/\1/p' $d/sideeye.toml); op=$(python3 -c 'import tomllib,shlex,sys; o=tomllib.load(open(sys.argv[1],"rb"))["define"]["operation"]; print(o if isinstance(o,str) else shlex.join(o))' $d/sideeye.toml); cw=$(sed -n 's/^cwd *= "\(.*\)"/\1/p' $d/sideeye.toml)
  sh $d/seed.sh > /tmp/seed.out 2>&1 || { echo "$t $v: seed failed: $(tail -2 /tmp/seed.out)"; exit; }
  export SIDEEYE_STATE_DIR=$st
  pre=$($d/check.sh 2>&1); a=$?
  (cd $cw && eval "$op") > /tmp/op.out 2>&1; o=$?
  post=$($d/check.sh 2>&1); b=$?
  case $t in protect-hook) j=/s/repo/.git/hooks/pre-commit;; protect-global-attributes) j=/s/xdg/git/attributes;; protect-info-attributes) j=/s/repo/.git/info/attributes;; protect-remove-ignore) j=/s/xdg/git/ignore;; protect-remove-filter) j=/s/xdg/git/attributes;; lib-set-second) j=$st/.env.keys;; spec-overwrite) j=/s/proj/Envfile;; gitignore-append) j=/s/proj/.gitignore;; encrypt-second) j=$st/.env.keys;; *) j=$st/.env;; esac
  : > $j; red=$($d/check.sh 2>&1); c=$?
  echo "$t $v: check before $a, operation exit $o, check after $b, emptied $(basename $j) -> $c [$red]"
  [ $a -ne 0 ] && echo "   before: $pre"; [ $b -ne 0 ] && echo "   after: $post"; [ $o -ne 0 ] && echo "   op: $(tail -2 /tmp/op.out)"
  case $t in protect*) echo "   files after: $(ls -la $st | sed 1,3d | awk '{print $NF":"$5}' | tr '\n' ' ')";; esac )
done
