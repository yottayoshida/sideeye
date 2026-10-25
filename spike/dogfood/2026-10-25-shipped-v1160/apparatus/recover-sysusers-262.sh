#!/bin/sh
# systemd-sysusers v262.1 (sets/3s), with no Sideeye: strace kills the process at its Nth rename (the
# kill is delivered on entry, so that rename never happens), then the checker, the same command run
# again, the checker. The renames, in order, are listed first from one uninterrupted run: the first
# four put the backups (group-, gshadow-, passwd-, shadow-) in place, the last four the new files, so
# the kills are at 5 to 8.
set -u
d=/ap/defines/sysusers; B=/opt/bin/systemd-sysusers-262
sh $d/seed.sh
echo "== the renames of an uninterrupted run"
strace -f -e trace=rename,renameat,renameat2 -o /tmp/r.txt $B --root=/s/sysroot /s/sysaux/app.conf > /dev/null 2>&1
sed -n 's/^[0-9]* *//p' /tmp/r.txt
for f in passwd shadow group gshadow; do echo "  uninterrupted $f: $(grep '^appsvc:' /s/sysroot/etc/$f)"; done
for n in 5 6 7 8; do
  echo "===== killed at rename $n"
  sh $d/seed.sh
  strace -f -o /dev/null -e trace=renameat2,renameat,rename -e inject=renameat2,renameat,rename:signal=KILL:when=$n \
      $B --root=/s/sysroot /s/sysaux/app.conf > /dev/null 2>&1
  echo "killed run exit $?"
  SIDEEYE_STATE_DIR=/s/sysroot sh $d/check.sh; echo "check exit $?"
  $B --root=/s/sysroot /s/sysaux/app.conf; echo "re-run exit $?"
  SIDEEYE_STATE_DIR=/s/sysroot sh $d/check.sh; echo "check after re-run exit $?"
  ls /s/sysroot/etc | tr "\n" " "; echo
  for f in passwd shadow group gshadow; do echo "  after re-run $f: $(grep '^appsvc:' /s/sysroot/etc/$f || echo '(no appsvc line)')"; done
done
