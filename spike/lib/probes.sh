# spike/lib/probes.sh — the one entry point to the probe verdict functions (#259).
#
# Source it from a cohort's probe or drill script:
#
#   . "$SIDEEYE_SPIKE/lib/probes.sh"          # or, with SIDEEYE_SPIKE unset,
#   . "$(dirname "$0")/../../lib/probes.sh"   # the file finds spike/ from $0
#
# It defines nothing of its own. The implementations stay where they were
# written and drilled red — cohort 2's `probes/lib.sh` (note, verdict,
# run_strace, closure_paths, paths_outside, closure_check, thread_counts)
# and cohort 4's `probes/lib.sh` (condition8_visibility, condition9_interior)
# — so there is still exactly one implementation of each question in the
# repository, and sealed records are not touched to give it a new home.
#
# What this file adds is location. A sourced POSIX-sh file cannot learn its
# own path, so cohort 4's lib derives its directory from `$0` and points
# `PREFLIGHT` at `../preflight.sh` relative to the *sourcing* script; read
# from another cohort, that names a file that does not exist and conditions
# 8 and 9 report `8/9-preflight` FAIL. This file pins `_C4_HERE` to cohort
# 4's real directory before sourcing, so the gate is found from anywhere.
#
# `sh spike/lib/probes.sh --selftest` sources both libraries from this
# file's own location and checks the functions and the gate are present.
# Sourcing sets FAILS=0 (cohort 2's lib does); a script that sources this
# after judging something must not expect its count to survive.

_lib_spike=${SIDEEYE_SPIKE:-}
if [ -z "$_lib_spike" ]; then
    _lib_d=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    while [ -n "$_lib_d" ]; do
        if [ -f "$_lib_d/lib/probes.sh" ]; then _lib_spike=$_lib_d; break; fi
        _lib_d=${_lib_d%/*}
    done
fi
if [ -z "$_lib_spike" ] || [ ! -f "$_lib_spike/cohort2/probes/lib.sh" ] || [ ! -f "$_lib_spike/cohort4/probes/lib.sh" ]; then
    echo "BROKEN spike/lib/probes.sh: cannot locate spike/ from \$0=$0 — set SIDEEYE_SPIKE to the spike directory" >&2
    exit 2
fi

. "$_lib_spike/cohort2/probes/lib.sh"
_C4_HERE="$_lib_spike/cohort4/probes"
. "$_lib_spike/cohort4/probes/lib.sh"

# Only when this file is the one being executed: a cohort script that sources this and is
# itself invoked with --selftest must not have the library's selftest run and exit for it.
# The name must be this one AND the file must sit beside its library siblings.
if [ "${0##*/}" = "probes.sh" ] && [ -f "$(dirname -- "$0")/check-transcript.sh" ] && [ "${1-}" = "--selftest" ]; then
    _lib_fails=0
    for _lib_fn in note verdict run_strace closure_paths paths_outside closure_check thread_counts \
                   condition8_visibility condition9_interior; do
        if command -v "$_lib_fn" >/dev/null 2>&1; then
            echo "ok   probes.sh: $_lib_fn is defined"
        else
            echo "FAIL probes.sh: $_lib_fn is not defined after sourcing"; _lib_fails=$((_lib_fails + 1))
        fi
    done
    if [ -f "$PREFLIGHT" ]; then
        echo "ok   probes.sh: PREFLIGHT points at an existing gate ($PREFLIGHT)"
    else
        echo "FAIL probes.sh: PREFLIGHT=$PREFLIGHT does not exist — the cohort-4 gate was not pinned"; _lib_fails=$((_lib_fails + 1))
    fi
    echo "== probes.sh selftest failures: $_lib_fails"
    [ "$_lib_fails" -eq 0 ] || exit 1
    exit 0
fi
