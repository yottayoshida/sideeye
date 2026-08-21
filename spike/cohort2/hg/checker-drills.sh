#!/bin/sh
# Per-leg falsification of the hg-commit checker (the cookbook rule: every
# checker leg is seen red once, separately, and the greens are controls).
# Everything here is a normal execution or a synthetic corruption of a
# copy — no kill, no crash, no engine, so no failure of the target is
# observed and the provenance gate stays clean. Exit 0 = every drill
# behaved as required.
set -u
here=$(cd "$(dirname "$0")" && pwd)
OPS="$here/ops"
FAILS=0
want() { # name want-rc got-rc
    if [ "$3" = "$2" ]; then echo "drill ok   $1 (rc=$3)"; else echo "drill FAIL $1 (rc=$3, wanted $2)"; FAILS=$((FAILS+1)); fi
}

echo "== hg-commit checker drills — $(hg version -q) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# green 1: the pre-state (the shape of a fully rolled-back world)
"$OPS/setup.sh" > /dev/null 2>&1
SIDEEYE_STATE_DIR=/tmp/cohort2/hg/repo/.hg "$OPS/check.sh"; want "green-old-state" 0 $?

# green 2: the post-state (the shape of the baseline world)
HGRCPATH=/tmp/cohort2/hg/hgrc hg -R /tmp/cohort2/hg/repo commit -m probe -d "2026-01-02 00:00:00 +0000" --user "probe <probe@example.invalid>" > /dev/null 2>&1
SIDEEYE_STATE_DIR=/tmp/cohort2/hg/repo/.hg "$OPS/check.sh"; want "green-new-state" 0 $?

# red V: the target's integrity oracle fires (truncated changelog)
cp -a /tmp/cohort2/hg/repo /tmp/drill-v
: > /tmp/drill-v/.hg/store/00changelog.i
SIDEEYE_STATE_DIR=/tmp/drill-v/.hg "$OPS/check.sh"; want "red-leg-V" 1 $?

# red C: a VALID repository whose rev-0 bytes differ — verify passes,
# conservation fails (the leg V cannot cover)
rm -rf /tmp/drill-c && hg init /tmp/drill-c
printf 'different bytes\n' > /tmp/drill-c/alpha
printf 'beta, fixed bytes\n' > /tmp/drill-c/beta
HGRCPATH=/tmp/cohort2/hg/hgrc hg -R /tmp/drill-c add /tmp/drill-c/alpha /tmp/drill-c/beta > /dev/null
HGRCPATH=/tmp/cohort2/hg/hgrc hg -R /tmp/drill-c commit -m initial -d "2026-01-01 00:00:00 +0000" --user "probe <probe@example.invalid>" > /dev/null
SIDEEYE_STATE_DIR=/tmp/drill-c/.hg "$OPS/check.sh"; want "red-leg-C" 1 $?

# red C-lf: the trailing-newline trap — one extra LF at the end of rev-0
# alpha in an otherwise valid repository (command substitution strips it;
# cmp must not)
rm -rf /tmp/drill-lf && hg init /tmp/drill-lf
printf 'alpha, fixed bytes\n\n' > /tmp/drill-lf/alpha
printf 'beta, fixed bytes\n' > /tmp/drill-lf/beta
HGRCPATH=/tmp/cohort2/hg/hgrc hg -R /tmp/drill-lf add /tmp/drill-lf/alpha /tmp/drill-lf/beta > /dev/null
HGRCPATH=/tmp/cohort2/hg/hgrc hg -R /tmp/drill-lf commit -m initial -d "2026-01-01 00:00:00 +0000" --user "probe <probe@example.invalid>" > /dev/null
SIDEEYE_STATE_DIR=/tmp/drill-lf/.hg "$OPS/check.sh"; want "red-leg-C-trailing-lf" 1 $?

# red T: a VALID repository with three changesets — neither old nor new
printf 'third\n' > /tmp/cohort2/hg/repo/alpha
HGRCPATH=/tmp/cohort2/hg/hgrc hg -R /tmp/cohort2/hg/repo commit -m third -d "2026-01-03 00:00:00 +0000" --user "probe <probe@example.invalid>" > /dev/null 2>&1
SIDEEYE_STATE_DIR=/tmp/cohort2/hg/repo/.hg "$OPS/check.sh"; want "red-leg-T" 1 $?

# red D: the third thing — the store holds the completed commit but the
# working copy still claims the old, dirty state (built with normal
# commands: update back to rev 0 and re-modify alpha)
"$OPS/setup.sh" > /dev/null 2>&1
HGRCPATH=/tmp/cohort2/hg/hgrc hg -R /tmp/cohort2/hg/repo commit -m probe -d "2026-01-02 00:00:00 +0000" --user "probe <probe@example.invalid>" > /dev/null 2>&1
HGRCPATH=/tmp/cohort2/hg/hgrc hg -R /tmp/cohort2/hg/repo update -r 0 > /dev/null 2>&1
printf 'alpha, modified fixed bytes\n' > /tmp/cohort2/hg/repo/alpha
SIDEEYE_STATE_DIR=/tmp/cohort2/hg/repo/.hg "$OPS/check.sh"; want "red-leg-D" 1 $?

# red R: an abandoned transaction hg recover cannot recover. As root every
# permission is a suggestion, so the drill drops to nobody; the journal
# itself is synthetic garbage, not the residue of any real interruption.
"$OPS/setup.sh" > /dev/null 2>&1
printf 'not a journal\n' > /tmp/cohort2/hg/repo/.hg/store/journal
chmod -R a+rX /tmp/cohort2 && chmod 555 /tmp/cohort2/hg/repo/.hg/store
su nobody -s /bin/sh -c "SIDEEYE_STATE_DIR=/tmp/cohort2/hg/repo/.hg '$OPS/check.sh'"; want "red-leg-R" 1 $?
chmod 755 /tmp/cohort2/hg/repo/.hg/store

echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
