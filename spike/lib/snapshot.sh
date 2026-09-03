# spike/lib/snapshot.sh — the checker-snapshot drill and two rc helpers (#259).
#
# Three functions. `snap` is cohort 4's `run()` from `himalaya/checker-drills.sh`,
# which superseded cohort 2's `want NAME WANT-RC GOT-RC`: a checker drill must not
# only go red, it must go red THROUGH THE LEG UNDER TEST — a state that trips a
# different leg leaves the tested leg dead and the drill green. `run_rc` and
# `declared_exec` are new, one per bug class this harness has paid for:
#
#   snap NAME green|LEG-SUBSTRING DIR CMD [ARG...]
#       Runs CMD with SIDEEYE_STATE_DIR=DIR (stdout+stderr captured) and judges:
#       `green` must exit 0; any other second argument is a substring the red
#       output must contain — the leg's own words. Bumps FAILS like `verdict`
#       and always returns 0, so a `set -e` caller keeps going: the result is
#       read from FAILS at the end, never from the return. `snap` is a whole
#       drill (it runs the checker AND judges the colour, and prints `drill ok`
#       / `drill FAIL` itself); do not wrap it in `drill`, which is the runner
#       for probe predicates that only emit verdicts.
#
#   run_rc VAR FILE CMD [ARG...]
#       Runs CMD with stdout+stderr in FILE and stores the raw exit status in
#       VAR (a variable name; names beginning with `_rr_` are the helper's own
#       and are refused). No pipe is ever between CMD and the status: a harness that grows a
#       `| tee` or `| tail` later gets the LAST command's status, which for tee
#       is 0. Safe under `set -e`: the command runs as an `if` condition, so a
#       non-zero status does not exit the caller (spike/ runs `set -eu`
#       almost everywhere; `CMD; rc=$?` written plainly dies before the second
#       statement). Scope: the harness's own pipe. A CMD that is itself a
#       pipeline still reports its last command; POSIX sh has no pipefail.
#
#   declared_exec FILE...
#       A lint for declaration files the ENGINE execs (setup / operation /
#       check): each must be executable and start with `#!`. The engine spawns
#       argv directly, so a 644 script proven green under `sh file` in a drill
#       fails with Permission denied at the first sealed exploration (campaign
#       2, abook). Only for those files — harness scripts run by `sh file` on
#       purpose (capture.sh, CI) are not its business.
#
# `sh spike/lib/snapshot.sh --selftest` drills all three, including the pipe
# shape `run_rc` refuses to have and the wrong-leg red `snap` must catch.

FAILS=${FAILS:-0}

snap() { # NAME green|LEG-SUBSTRING DIR CMD [ARG...]
    _sn_name=$1; _sn_expect=$2; _sn_dir=$3; shift 3
    if _sn_out=$(SIDEEYE_STATE_DIR="$_sn_dir" "$@" 2>&1); then _sn_rc=0; else _sn_rc=$?; fi
    if [ "$_sn_expect" = green ]; then
        if [ "$_sn_rc" -eq 0 ]; then
            echo "drill ok   $_sn_name: checker green as required"
        else
            echo "drill FAIL $_sn_name: checker went red on a state it must accept: $_sn_out"
            FAILS=$((FAILS + 1))
        fi
        return 0
    fi
    if [ "$_sn_rc" -eq 0 ]; then
        echo "drill FAIL $_sn_name: checker stayed GREEN on damage it must catch"
        FAILS=$((FAILS + 1))
        return 0
    fi
    case "$_sn_out" in
      *"$_sn_expect"*) echo "drill ok   $_sn_name: red through the expected leg: $_sn_out" ;;
      *) echo "drill FAIL $_sn_name: red, but through the WRONG leg (wanted '$_sn_expect'): $_sn_out"
         FAILS=$((FAILS + 1)) ;;
    esac
}

run_rc() { # VAR FILE CMD [ARG...]
    _rr_var=$1; _rr_file=$2; shift 2
    case "$_rr_var" in
      _rr_*|''|[0-9]*|*[!A-Za-z0-9_]*) echo "BROKEN run_rc: '$_rr_var' is not a variable name this helper can set"; return 2 ;;
    esac
    if "$@" >"$_rr_file" 2>&1; then _rr_rc=0; else _rr_rc=$?; fi
    eval "$_rr_var=\$_rr_rc"
}

declared_exec() { # FILE...
    _de_bad=0
    for _de_f in "$@"; do
        if [ ! -f "$_de_f" ]; then
            echo "FAIL declared-exec $_de_f: no such file"; _de_bad=1
        elif [ ! -x "$_de_f" ]; then
            echo "FAIL declared-exec $_de_f: not executable — the engine spawns it directly; a drill that ran it as 'sh file' hid this"; _de_bad=1
        elif ! { IFS= read -r _de_l < "$_de_f" 2>/dev/null; case "$_de_l" in '#!'*) true ;; *) false ;; esac; }; then
            echo "FAIL declared-exec $_de_f: no #! line — executable, but the kernel has no interpreter to hand it to"; _de_bad=1
        else
            echo "ok   declared-exec $_de_f"
        fi
    done
    [ "$_de_bad" -eq 0 ]
}

# Only when this file is the one being executed, never when a cohort script that
# sources it is itself invoked with --selftest: the name must be this one AND the file
# must sit beside its library siblings, so a cohort script that happens to share the
# name does not trip it.
if [ "${0##*/}" = "snapshot.sh" ] && [ -f "$(dirname -- "$0")/check-transcript.sh" ] && [ "${1-}" = "--selftest" ]; then
    set -eu
    _st_fails=0
    _ws=$(mktemp -d "${TMPDIR:-/tmp}/snapshot-selftest-XXXXXX")
    trap 'rm -f "$_ws"/*; rmdir "$_ws" 2>/dev/null' EXIT
    st() { # label ok(yes/no) detail
        if [ "$2" = yes ]; then echo "ok   snapshot.sh: $1 — $3"; else echo "FAIL snapshot.sh: $1 — $3"; _st_fails=$((_st_fails + 1)); fi
    }

    echo "-- run_rc: the raw status of a failing command, under set -e"
    if run_rc _rr_rc "$_ws/out0" true >/dev/null; then ok=no; else ok=yes; fi
    st "run_rc refuses a name it uses itself" $ok "_rr_rc"
    rc=none
    run_rc rc "$_ws/out1" sh -c 'echo some output; exit 7'
    [ "$rc" = 7 ] && ok=yes || ok=no
    st "run_rc keeps the status" $ok "rc=$rc (wanted 7), output captured: $(cat "$_ws/out1")"
    run_rc rc "$_ws/out2" sh -c 'exit 0'
    [ "$rc" = 0 ] && ok=yes || ok=no
    st "run_rc reports success as 0" $ok "rc=$rc"
    # The shape run_rc exists to keep out: the same command behind a tee reports tee's 0.
    if sh -c 'echo x; exit 7' 2>&1 | tee "$_ws/out3" >/dev/null; then piped=0; else piped=$?; fi
    [ "$piped" = 0 ] && ok=yes || ok=no
    st "the pipe it refuses would have read 0" $ok "sh -c 'exit 7' | tee → status $piped (the bug class, shown live)"

    echo "-- snap: green, red through the right leg, red through the wrong leg, green when red is due"
    printf '#!/bin/sh\necho "leg-B: the index is torn"; exit 1\n' > "$_ws/red-B"; chmod 755 "$_ws/red-B"
    printf '#!/bin/sh\nexit 0\n' > "$_ws/green"; chmod 755 "$_ws/green"
    FAILS=0
    snap "st-green" green "$_ws" "$_ws/green" >/dev/null
    [ "$FAILS" -eq 0 ] && ok=yes || ok=no; st "green checker declared green" $ok "FAILS=$FAILS"
    snap "st-right-leg" "leg-B" "$_ws" "$_ws/red-B" >/dev/null
    [ "$FAILS" -eq 0 ] && ok=yes || ok=no; st "red through the expected leg" $ok "FAILS=$FAILS"
    snap "st-wrong-leg" "leg-A" "$_ws" "$_ws/red-B" >/dev/null
    [ "$FAILS" -eq 1 ] && ok=yes || ok=no; st "red through the WRONG leg is a failed drill" $ok "FAILS=$FAILS (wanted 1)"
    snap "st-stayed-green" "leg-B" "$_ws" "$_ws/green" >/dev/null
    [ "$FAILS" -eq 2 ] && ok=yes || ok=no; st "green where red was due is a failed drill" $ok "FAILS=$FAILS (wanted 2)"
    snap "st-red-on-good" green "$_ws" "$_ws/red-B" >/dev/null
    [ "$FAILS" -eq 3 ] && ok=yes || ok=no; st "red where green was due is a failed drill" $ok "FAILS=$FAILS (wanted 3)"

    echo "-- declared_exec: 755 with #! passes, 644 fails, no #! fails"
    printf '#!/bin/sh\nexit 0\n' > "$_ws/decl-644"; chmod 644 "$_ws/decl-644"
    printf 'exit 0\n' > "$_ws/decl-nobang"; chmod 755 "$_ws/decl-nobang"
    if declared_exec "$_ws/green" >/dev/null; then ok=yes; else ok=no; fi
    st "an executable declaration with #! passes" $ok "$_ws/green"
    if declared_exec "$_ws/decl-644" >/dev/null; then ok=no; else ok=yes; fi
    st "a 644 declaration fails" $ok "$_ws/decl-644"
    if declared_exec "$_ws/decl-nobang" >/dev/null; then ok=no; else ok=yes; fi
    st "an executable without #! fails" $ok "$_ws/decl-nobang"
    if declared_exec "$_ws/green" "$_ws/decl-644" >/dev/null; then ok=no; else ok=yes; fi
    st "one bad file among good ones fails the set" $ok "mixed list"

    echo "== snapshot.sh selftest failures: $_st_fails"
    [ "$_st_fails" -eq 0 ] || exit 1
    exit 0
fi
