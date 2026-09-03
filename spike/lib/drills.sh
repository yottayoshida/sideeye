# spike/lib/drills.sh — the drill runner every cohort rewrote (#259).
#
# A drill runs a predicate against an input that must (red) or must not
# (green) make it emit a FAIL verdict. Cohorts 2 and 4 each wrote this as a
# checkpoint: the caller saved `_before=$FAILS`, called the predicate, then
# called `expect_red NAME` / `expect NAME colour`, which compared FAILS to
# `_before`. The bookkeeping lived in the caller, and a caller that forgot
# the `_before=$FAILS` line before one drill kept the previous value: a
# drill whose predicate stayed green then read "went red as required",
# silently, because FAILS was already above the stale mark.
#
# Here the runner runs the predicate itself and measures the delta, so
# there is no line to forget:
#
#   drill NAME red|green CMD [ARG...]
#
# Contract, two lines:
#   * Environment for the predicate goes BEFORE `drill`, as a prefix —
#     `PROBE_OUT=$WS/libc drill "8a" green condition8_visibility "$root" -- cmd`
#     — the way cohort 4 already calls its predicates. An assignment word
#     passed as an argument is not an assignment (`"$@"` runs it as a
#     command, rc 127), and `env` cannot run a shell function.
#   * A drill that is several statements (cohort 2's shape: set up, compute,
#     then `verdict`) is wrapped in a function by the caller and the function
#     is passed as CMD. The runner does not eval text.
#
# One consequence of the prefix form, measured in dash and bash: an assignment
# before a function call PERSISTS in the caller's shell after the call (POSIX
# leaves it unspecified; both shells keep it). A drill that reads PROBE_OUT
# therefore sees the previous drill's value unless its own line sets it, which
# is why cohort 4's run-drills.sh sets PROBE_OUT on every call. Set what each
# drill needs on that drill's own line; do not rely on a prefix having been
# cleared.
#
# `drill_summary` prints the count and exits non-zero when any drill failed.
# The predicates come from probes.sh (`verdict` bumps FAILS); this file only
# reads FAILS and never defines it.
#
# `sh spike/lib/drills.sh --selftest` runs the runner against synthetic
# predicates, including the one that used to slip: a green predicate
# declared red must be reported as a failed drill.

DRILL_FAILS=${DRILL_FAILS:-0}

drill() { # NAME red|green CMD [ARG...]
    _dr_name=$1; _dr_want=$2; shift 2
    _dr_before=${FAILS:-0}
    "$@"
    _dr_after=${FAILS:-0}
    case "$_dr_want" in
      red)
        if [ "$_dr_after" -gt "$_dr_before" ]; then
            echo "drill ok   $_dr_name went red as required"
        else
            echo "drill FAIL $_dr_name stayed green against a violating input"
            DRILL_FAILS=$((DRILL_FAILS + 1))
        fi ;;
      green)
        if [ "$_dr_after" -eq "$_dr_before" ]; then
            echo "drill ok   $_dr_name stayed green as required"
        else
            echo "drill FAIL $_dr_name went red against a conforming input"
            DRILL_FAILS=$((DRILL_FAILS + 1))
        fi ;;
      *)
        echo "drill BROKEN $_dr_name: the colour must be red or green, got '$_dr_want'"
        DRILL_FAILS=$((DRILL_FAILS + 1)) ;;
    esac
}

drill_summary() {
    echo "== drill failures: $DRILL_FAILS"
    [ "$DRILL_FAILS" -eq 0 ]
}

# Only when this file is the one being executed, never when a cohort script that
# sources it is itself invoked with --selftest: the name must be this one AND the file
# must sit beside its library siblings, so a cohort script that happens to share the
# name does not trip it.
if [ "${0##*/}" = "drills.sh" ] && [ -f "$(dirname -- "$0")/check-transcript.sh" ] && [ "${1-}" = "--selftest" ]; then
    set -u
    FAILS=0
    _st_fails=0
    # Synthetic predicates in the shape of `verdict`: red bumps FAILS, green does not.
    goes_red() { FAILS=$((FAILS + 1)); }
    stays_green() { :; }
    sees_env() { [ "${DRILL_ST_ENV:-}" = yes ] || FAILS=$((FAILS + 1)); }
    expect_drill_fails() { # label want-count
        if [ "$DRILL_FAILS" -eq "$2" ]; then echo "ok   drills.sh: $1 (DRILL_FAILS=$DRILL_FAILS)"
        else echo "FAIL drills.sh: $1 — DRILL_FAILS=$DRILL_FAILS, wanted $2"; _st_fails=$((_st_fails + 1)); fi
    }

    echo "-- selftest 1: a red predicate declared red is a passing drill"
    drill "st-1" red goes_red
    expect_drill_fails "red/red counts no failure" 0

    echo "-- selftest 2: a green predicate declared green is a passing drill"
    drill "st-2" green stays_green
    expect_drill_fails "green/green counts no failure" 0

    echo "-- selftest 3: a green predicate declared red is a FAILED drill (the slip the runner exists to catch)"
    drill "st-3" red stays_green
    expect_drill_fails "green declared red is counted" 1

    echo "-- selftest 4: a red predicate declared green is a FAILED drill"
    drill "st-4" green goes_red
    expect_drill_fails "red declared green is counted" 2

    echo "-- selftest 5: an environment prefix before drill reaches the predicate"
    DRILL_ST_ENV=yes drill "st-5" green sees_env
    expect_drill_fails "the prefix was visible inside the predicate" 2

    echo "-- selftest 6: a stale FAILS above zero does not make a green predicate read red"
    FAILS=7
    drill "st-6" red stays_green
    expect_drill_fails "the delta, not the absolute count, decides" 3

    echo "-- selftest 7: an unknown colour is BROKEN and counted"
    drill "st-7" purple stays_green
    expect_drill_fails "a colour typo cannot pass" 4

    echo "== drills.sh selftest failures: $_st_fails (DRILL_FAILS ended at $DRILL_FAILS, by design)"
    [ "$_st_fails" -eq 0 ] || exit 1
    exit 0
fi
