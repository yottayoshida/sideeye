#!/bin/sh
# Cohort-2 hg define (P1) checker. Property (proposals.md P1): crash
# anywhere inside `hg commit`, and the repository is already valid or
# returns to valid through the documented recovery — with the pre-existing
# changeset and both files' bytes conserved, and the whole repository
# (store AND working-copy state) either the old state or the completed
# commit, never a third thing.
#
# Documented recovery first, then assert (`hg help recover`). The engine
# snapshots and judges L0 before this runs, so recovery here cannot
# contaminate the judgement.
#
# Every hg output is captured to a file with its exit status checked
# explicitly (a timeout's 124 must never read as an answer), and byte
# comparisons go through cmp against printf-built expectations (command
# substitution strips trailing newlines, which turned real byte changes
# into false greens in review).
set -u
export HGRCPATH=/tmp/cohort2/hg/hgrc
[ -f "$HGRCPATH" ] || { echo "checker(hg-commit): the generated hgrc is missing (setup writes it)"; exit 2; }
D=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
R=$(dirname "$D")
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker(hg-commit): $*"; exit 1; }

# run NAME timeout-secs cmd... — capture stdout to $T/NAME, demand rc 0.
run() {
    _n=$1; _t=$2; shift 2
    timeout "$_t" "$@" > "$T/$_n" 2>/dev/null
    _rc=$?
    [ "$_rc" -eq 0 ] || fail "$_n: '$1 ...' exited $_rc (124 = timeout)"
}

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
printf 'alpha, fixed bytes\n' > "$T/want-alpha0"
printf 'beta, fixed bytes\n'  > "$T/want-beta0"
run "leg C alpha@0" 30 hg -R "$R" cat -r 0 "$R/alpha"
cmp -s "$T/leg C alpha@0" "$T/want-alpha0" || fail "leg C: rev 0 alpha bytes changed"
run "leg C beta@0" 30 hg -R "$R" cat -r 0 "$R/beta"
cmp -s "$T/leg C beta@0" "$T/want-beta0" || fail "leg C: rev 0 beta bytes changed"

# ---- leg T: the store is old-or-new at the contract level ----
run "leg T log" 30 hg -R "$R" log -T 'x'
revs=$(wc -c < "$T/leg T log" | tr -d ' ')
case "$revs" in
    1) new=0 ;;  # old: the interrupted commit rolled back
    2) new=1     # new: the commit completed — it must be the real one, whole
        printf 'alpha, modified fixed bytes\n' > "$T/want-alpha1"
        run "leg T alpha@1" 30 hg -R "$R" cat -r 1 "$R/alpha"
        cmp -s "$T/leg T alpha@1" "$T/want-alpha1" || fail "leg T: rev 1 alpha is neither old nor the committed bytes"
        run "leg T beta@1" 30 hg -R "$R" cat -r 1 "$R/beta"
        cmp -s "$T/leg T beta@1" "$T/want-beta0" || fail "leg T: rev 1 lost or changed beta"
        run "leg T meta" 30 hg -R "$R" log -r 1 -T '{desc}\n{author}\n{date|isodate}\n'
        printf 'probe\nprobe <probe@example.invalid>\n2026-01-02 00:00 +0000\n' > "$T/want-meta1"
        cmp -s "$T/leg T meta" "$T/want-meta1" || fail "leg T: rev 1 description/author/date are not the committed ones"
        ;;
    *) fail "leg T: $revs changesets visible; the contract allows exactly the old state (1) or the completed commit (2)" ;;
esac

# ---- leg D: the working copy agrees with the store's side of the line ----
# Old means parent rev 0 with alpha still modified; new means parent rev 1
# and a clean status. A store that committed while the working copy still
# claims the old, dirty state is the third thing the property forbids: the
# next commit would silently duplicate the change.
# --cwd pins status paths to the repository root (hg prints them relative
# to the caller's cwd otherwise, and the checker inherits the engine's).
run "leg D parent" 30 hg --cwd "$R" parents -T '{rev}'
parent=$(cat "$T/leg D parent")
run "leg D status" 30 hg --cwd "$R" status
if [ "$new" -eq 0 ]; then
    [ "$parent" = "0" ] || fail "leg D: store rolled back but the working copy parent is '$parent', not 0"
    printf 'M alpha\n' > "$T/want-status"
    cmp -s "$T/leg D status" "$T/want-status" || fail "leg D: store rolled back but the working copy is not the old dirty state"
else
    [ "$parent" = "1" ] || fail "leg D: store holds the completed commit but the working copy parent is '$parent', not 1"
    [ -s "$T/leg D status" ] && fail "leg D: store holds the completed commit but the working copy is not clean"
fi

exit 0
