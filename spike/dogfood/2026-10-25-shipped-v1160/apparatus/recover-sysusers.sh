#!/bin/sh
# sysusers' documented recovery is to run again (systemd-sysusers.service runs it at every boot): the
# FAIL case's crash state, left by `replay --leave-crash-state`, then the same command once more, then
# the run's checker. Also each of the three failing crash points by SIDEEYE_KILL_AT, through the case.
set -u
SE=$(cat /install.path); d=/ap/defines/sysusers
. /ap/env.sh
c=/out/sysusers/work-explore/cases/000001.json
sh $d/seed.sh
"$SE" replay "$c" --oracle /usr/bin/strace --leave-crash-state --work /tmp/rec > /tmp/rec.txt 2>&1; echo "replay --leave-crash-state exit $?"
grep -E "^FAIL|left|crash state" /tmp/rec.txt | head -3
echo "-- crash state:"; SIDEEYE_STATE_DIR=/s/sysroot sh $d/check.sh; echo "check exit $?"
grep appsvc /s/sysroot/etc/passwd /s/sysroot/etc/shadow /s/sysroot/etc/group /s/sysroot/etc/gshadow
systemd-sysusers --root=/s/sysroot /s/sysaux/app.conf; echo "re-run exit $?"
echo "-- after the re-run:"; SIDEEYE_STATE_DIR=/s/sysroot sh $d/check.sh; echo "check exit $?"
grep appsvc /s/sysroot/etc/passwd /s/sysroot/etc/shadow /s/sysroot/etc/group /s/sysroot/etc/gshadow
