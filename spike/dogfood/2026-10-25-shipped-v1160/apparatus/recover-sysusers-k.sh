#!/bin/sh
# For each failing crash point k (43, 44, 45 of transcripts/explore/sysusers): the run's reproduce line
# with SIDEEYE_KILL_AT=k from the seeded state, the checker, the same command run again, the checker.
set -u
d=/ap/defines/sysusers; . /ap/env.sh
SHIM=$(dirname "$(cat /install.path)")/libsideeye_shim.so
for k in 43 44 45; do
  echo "===== kill at $k"
  sh $d/seed.sh
  (cd /s/sysroot && unset SIDEEYE_KILL_GROUP && : > /tmp/trace-repro.bin && SIDEEYE_STATE_DIR=/s/sysroot SIDEEYE_STATE_DIR_ALT= SIDEEYE_TRACE_PATH=/tmp/trace-repro.bin LD_PRELOAD=$SHIM SIDEEYE_KILL_AT=$k SIDEEYE_SEQ_BASE= SIDEEYE_OBSERVE=wrappers SIDEEYE_RUN_CGROUP= SIDEEYE_KILL_CGROUP= SIDEEYE_KILL_ASIDE= 'systemd-sysusers' '--root=/s/sysroot' /s/sysaux/app.conf </dev/null) > /dev/null 2>&1
  echo "killed run exit $?"
  SIDEEYE_STATE_DIR=/s/sysroot sh $d/check.sh; echo "check exit $?"
  grep -h appsvc /s/sysroot/etc/passwd /s/sysroot/etc/shadow /s/sysroot/etc/group /s/sysroot/etc/gshadow | sed 's/^/  before re-run: /'
  systemd-sysusers --root=/s/sysroot /s/sysaux/app.conf; echo "re-run exit $?"
  SIDEEYE_STATE_DIR=/s/sysroot sh $d/check.sh; echo "check after re-run exit $?"
  for f in passwd shadow group gshadow; do echo "  after re-run $f: $(grep '^appsvc:' /s/sysroot/etc/$f || echo '(no appsvc line)')"; done
done
