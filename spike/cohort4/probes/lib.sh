# Cohort-4 probe predicates (sourced, not executed).
#
# Harness continuity, the same rule cohort 3 followed: cohort 2's
# predicates are sourced IN PLACE — no fork, no copy — so conditions 1
# through 7 are the same lines that were drilled red. This file adds only
# the two conditions cohort 4 introduces (PREP.md §5), and it adds them by
# calling the already-falsified gate rather than by reimplementing it:
# there is exactly one implementation of each question in the repository.
#
#   condition 8 — shim visibility agrees with the kernel
#   condition 9 — the operation has an interior
#
# Both are engine-free: no kill, no checker, no define, so a probe that
# runs them still observes only normal execution and the provenance gate
# stays clean.
#
# Sourced from a run script the way cohort 3 did it:
#   . "$(dirname "$0")/../../cohort2/probes/lib.sh"
#   . "$(dirname "$0")/lib.sh"

_C4_HERE=${_C4_HERE:-$(CDPATH= cd -- "$(dirname -- "${0}")" && pwd)}
PREFLIGHT=${PREFLIGHT:-$_C4_HERE/../preflight.sh}

# A gate that cannot run must not read as a condition that passed. Both
# predicates below emit a FAIL verdict in that case rather than skipping,
# which is the "a 2 is never a pass" rule expressed through this harness's
# own vocabulary.
_c4_gate_ready() {
    if [ ! -f "$PREFLIGHT" ]; then
        verdict "8/9-preflight" no "gate not found at $PREFLIGHT — conditions 8 and 9 could not be measured"
        return 1
    fi
    return 0
}

# condition 8 — every state-root mutation the kernel performed also passed
# through a function an LD_PRELOAD interposer can see. A disagreement is a
# named wall at probe time, which is the whole point: cargo cost two
# defines and two explores to learn the same thing.
condition8_visibility() { # state-root -- cmd...
    _root=$1; shift
    [ "${1:-}" = "--" ] && shift
    _c4_gate_ready || return 1
    _out=${PROBE_OUT:-/tmp}/cond8
    mkdir -p "$_out" || { verdict "8-visibility" no "cannot create $_out"; return 1; }
    note "condition 8 — shim visibility vs the kernel (artifacts in $_out)"
    SIDEEYE_PREFLIGHT_OUT="$_out" sh "$PREFLIGHT" visibility "$_root" -- "$@"
    _rc=$?
    case $_rc in
        0) verdict "8-visibility" yes "every in-root mutation passed through an interposable function" ;;
        1) verdict "8-visibility" no "the kernel mutated the state root past the interposer — a named wall (see the transcript above)" ;;
        *) verdict "8-visibility" no "the gate could not measure (rc=$_rc) — not a pass" ;;
    esac
    return 0
}

# condition 9 — how many engine-reachable kill points the operation has
# inside the state root. A count of 1 is not a failure: it is a fact the
# owner should hold before the slot is frozen, because a single atomic
# mutation has no interior to crash inside (the papis shape, discovered at
# define time in cohort 3 instead of at probe time).
condition9_interior() { # state-root -- cmd...
    _root=$1; shift
    [ "${1:-}" = "--" ] && shift
    _c4_gate_ready || return 1
    _out=${PROBE_OUT:-/tmp}/cond9
    mkdir -p "$_out" || { verdict "9-interior" no "cannot create $_out"; return 1; }
    note "condition 9 — kill points inside the state root (artifacts in $_out)"
    SIDEEYE_PREFLIGHT_OUT="$_out" sh "$PREFLIGHT" interior "$_root" -- "$@"
    _rc=$?
    if [ $_rc -ne 0 ]; then
        verdict "9-interior" no "the gate could not measure (rc=$_rc) — not a pass"
        return 0
    fi
    # The count is in the gate's own output above; this verdict records that
    # it was measured and read, not what the owner decided about it.
    verdict "9-interior" yes "counted and recorded above; a count of 1 is an owner decision, not a failure"
    return 0
}
