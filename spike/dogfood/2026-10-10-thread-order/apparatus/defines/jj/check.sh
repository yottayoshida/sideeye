#!/bin/sh
# Cohort-2 jj define (P1) checker. Property (proposals.md P1): crash
# anywhere inside `jj commit`, and the repository is readable, the initial
# change's bytes survive, the description list is old-or-new (never a
# third), and the documented staleness recovery succeeds when jj reports
# the working copy stale. Reads run --ignore-working-copy so observation
# does not trigger jj's auto-snapshot; every jj output is captured with
# its rc checked (a timeout's 124 must never read as an answer).
set -u
D=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker(jj-commit): $*"; exit 1; }
run() { # name timeout cmd...
    _n=$1; _t=$2; shift 2
    timeout "$_t" "$@" > "$T/$_n" 2>"$T/$_n.err"
    _rc=$?
    [ "$_rc" -eq 0 ] || fail "$_n: '$1 ...' exited $_rc (124 = timeout): $(head -c 200 "$T/$_n.err")"
}

[ -d "$D/.jj" ] || fail "the .jj store is missing from the state dir"
[ -d "$D/.git" ] || fail "the colocated .git is missing from the state dir"

# ---- leg V: the repository is readable ----
run "leg V log" 60 jj -R "$D" --ignore-working-copy log --no-graph -T 'description.first_line() ++ "|"' -r 'all()'

# ---- leg T: the description list is old-or-new ----
# Rows, newest first: the empty working-copy commit, then the named
# commits, then the root commit's empty description — hence the leading
# and trailing empty fields (the same literals the probe pinned).
descs=$(cat "$T/leg V log")
case "$descs" in
    "|initial||")        new=0 ;;  # old: the interrupted commit rolled back
    "|probe|initial||")  new=1 ;;  # new: the commit completed
    *) fail "leg T: description list '$descs' is neither the old state nor the completed commit" ;;
esac

# ---- leg C: the initial change's bytes survive ----
run "leg C alpha" 60 jj -R "$D" --ignore-working-copy file show -r 'subject("initial")' "$D/alpha"
printf 'alpha, fixed bytes\n' > "$T/want-alpha0"
cmp -s "$T/leg C alpha" "$T/want-alpha0" || fail "leg C: the initial commit's alpha bytes changed"

# ---- leg N (new side only): the completed commit carries the real bytes ----
if [ "$new" -eq 1 ]; then
    run "leg N alpha" 60 jj -R "$D" --ignore-working-copy file show -r 'subject("probe")' "$D/alpha"
    printf 'alpha, modified fixed bytes\n' > "$T/want-alpha1"
    cmp -s "$T/leg N alpha" "$T/want-alpha1" || fail "leg N: the probe commit is neither old nor the committed bytes"
fi

# ---- leg R: the documented staleness recovery, exactly when jj reports it ----
# A plain jj command on a stale working copy refuses and names the fix;
# run one WITHOUT --ignore-working-copy and apply the documented recovery
# if it fires.
if ! timeout 60 jj -R "$D" log --no-graph -T '' -r '@' > /dev/null 2>"$T/stale.err"; then
    if grep -qi "stale" "$T/stale.err"; then
        echo "checker(jj-commit): stale working copy reported; running the documented jj workspace update-stale"
        timeout 60 jj -R "$D" workspace update-stale > /dev/null 2>&1 || fail "leg R: jj workspace update-stale failed where jj asked for it"
        timeout 60 jj -R "$D" log --no-graph -T '' -r '@' > /dev/null 2>&1 || fail "leg R: the repository is still unreadable after the documented recovery"
    else
        fail "leg R: a working-copy read failed without reporting staleness: $(head -c 200 "$T/stale.err")"
    fi
fi

exit 0
