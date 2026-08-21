#!/bin/sh
# Cohort-2 hg define (P1) checker. Property (proposals.md P1): crash
# anywhere inside `hg commit`, and the repository is already valid or
# returns to valid through the documented recovery — with the pre-existing
# changeset and both files' bytes conserved, and the tip either the old
# state or the completed commit, never a third thing.
#
# Documented recovery first, then assert (`hg help recover`: "recover from
# an interrupted commit or pull"). The engine snapshots and judges L0
# before this runs, so recovery here cannot contaminate the judgement.
set -u
export HGRCPATH=/tmp/cohort2/hg/hgrc
[ -f "$HGRCPATH" ] || { echo "checker(hg-commit): the generated hgrc is missing (setup writes it)"; exit 2; }
D=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
R=$(dirname "$D")

fail() { echo "checker(hg-commit): $*"; exit 1; }

[ -d "$D" ] || fail "state dir is missing"
[ -d "$D/store" ] || fail "store is missing from the state dir"

# ---- leg R: the documented recovery, exactly when hg documents it ----
if [ -e "$D/store/journal" ]; then
    echo "checker(hg-commit): abandoned transaction present; running the documented hg recover"
    timeout 60 hg -R "$R" recover > /dev/null 2>&1 || fail "leg R: hg recover failed on an abandoned transaction"
fi

# ---- leg V: the target's own integrity oracle ----
timeout 120 hg -R "$R" verify > /dev/null 2>&1 || fail "leg V: hg verify failed after crash (and recovery, when one ran)"

# ---- leg C: conservation of the pre-existing changeset's bytes ----
a0=$(timeout 30 hg -R "$R" cat -r 0 "$R/alpha" 2>/dev/null) || fail "leg C: cannot read alpha at rev 0"
[ "$a0" = "alpha, fixed bytes" ] || fail "leg C: rev 0 alpha bytes changed: '$a0'"
b0=$(timeout 30 hg -R "$R" cat -r 0 "$R/beta" 2>/dev/null) || fail "leg C: cannot read beta at rev 0"
[ "$b0" = "beta, fixed bytes" ] || fail "leg C: rev 0 beta bytes changed: '$b0'"

# ---- leg T: the tip is old-or-new at the contract level ----
revs=$(timeout 30 hg -R "$R" log -T 'x' 2>/dev/null | wc -c | tr -d ' ') || fail "leg T: hg log failed"
case "$revs" in
    1) : ;;  # old: the interrupted commit rolled back
    2)       # new: the commit completed — its content must be the real one
        a1=$(timeout 30 hg -R "$R" cat -r 1 "$R/alpha" 2>/dev/null) || fail "leg T: cannot read alpha at rev 1"
        [ "$a1" = "alpha, modified fixed bytes" ] || fail "leg T: rev 1 alpha is neither old nor the committed bytes: '$a1'"
        d1=$(timeout 30 hg -R "$R" log -r 1 -T '{desc}' 2>/dev/null)
        [ "$d1" = "probe" ] || fail "leg T: rev 1 description is not the committed one: '$d1'"
        ;;
    *) fail "leg T: $revs changesets visible; the contract allows exactly the old state (1) or the completed commit (2)" ;;
esac

exit 0
