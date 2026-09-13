#!/bin/sh
# The libc-internal-call class (#39), member by member and mode by mode, against the
# shipped engine.
#
# ## What this drives, and what it deliberately does not
#
# It runs `sideeye explore --oracle` on one class member at a time, once under each
# observation mode: `--observe wrappers` (the default) and `--observe syscalls` (#541).
# An earlier design measured with `spike/cohort4/preflight.sh visibility`, and that would
# have been the wrong instrument: its `visibility-logger.c` is a SEPARATE LD_PRELOAD that
# wraps `open`, `mkdir` and friends but no member of this class, so it reports a wall
# whatever the shim does — and would have gone on reporting one after the shim stopped
# being blind. The thing measured has to be the thing that ships.
#
# Each member runs alone and writes through its own final path, so a divergence names
# the member that caused it. A single command exercising all of them cannot.
#
# ## The declared outcomes
#
# Every member carries a declared outcome PER MODE — `member:wrappers:syscalls` — and the
# check fails when the measurement disagrees IN EITHER DIRECTION: a wall that starts
# being judged is as much a change as a judged member that starts refusing.
#
#   judged     a verdict is reached, carrying the oracle's agreement: exit 0 or 1, PASS or
#              FAIL, and the report's oracle line saying it agreed on N operations —
#              `oracle: agreed on …` under a PASS, `oracle      agreed on …` under a
#              FAIL. The five creators the shim reimplements (contract v13, #39), in both
#              modes; and `dprintf` and `dprintfbig` under `--observe syscalls`, where the
#              kernel sees each `write` glibc splits them into (measured 2026-09-13, #541).
#   wall       `dprintf` and `dprintfbig` under `--observe wrappers`: glibc splits a
#              large write (measured 2026-08-31, spike/libc-internal/RESULTS.md). A
#              wrapper writing once would delete a crash point the real program has; one
#              that split would hard-code an undocumented libc internal. So the shim does
#              not replace them, and at the libc boundary they stay a wall — the negative
#              control this check did not have to invent. The decision is about the libc
#              boundary; the kernel boundary never needed a replacement.
#   inert      `tmpfile`, **on this platform only**: glibc reaches
#              `openat(AT_FDCWD, "/tmp", O_RDWR|O_EXCL|O_TMPFILE)`, which creates no
#              directory entry and ignores TMPDIR entirely, so it cannot mutate a
#              state root here. That reading does **not** carry to macOS, where
#              `tmpfile` honours TMPDIR and creates a real named file it then unlinks
#              (measured) — there it is a wall, and this script does not run there.
#
# ## The split, compared rather than pinned
#
# `dprintfbig` appends 2^20 + 1 bytes, more than the buffer glibc formats a `dprintf` into
# — a FILE's, sized from st_blksize, up to glibc 2.36, and a 2048-byte buffer of
# `dprintf`'s own since 2.37 — so it reaches the kernel as more than one `write`
# (measured: `write` 1048576 + 1 on glibc 2.36, 513 writes of up to 2048 bytes on 2.41).
# Two checks hold what the page says about it, under `--observe syscalls`:
#
#   split       `dprintfbig`'s crash points outnumber `dprintf`'s, in the same run. It
#               says the member was big enough to split at all — without it, shrinking
#               the payload back to a line would stay green (#541 review). It compares two
#               members rather than pinning a count because where glibc cuts moves with
#               the version, as the two measurements above show.
#   each write  for both `dprintf` members, the crash points equal the operations the
#               oracle agreed on: every write the kernel saw is a crash point of its own,
#               which the split alone does not say (#541 review, round two).
#
# ## What a green run does NOT mean
#
# It does not mean the class is closed: under `--observe wrappers` `dprintf` is declared
# `wall` and a green run includes it refusing. It does not mean anything about macOS —
# the oracle here is strace, `--observe syscalls` is Linux only, and the macOS side of the
# same replacements is exercised by the macOS CI leg. It says nothing about members
# nobody has named: `vdprintf`, which glibc's `dprintf` calls, is not a member of its own.
#
# Exit 0 when every member matches its declaration in both modes, 1 when one does not, 2
# when the check could not run — never read a 2 as a pass. A SETUP ERROR from the engine
# (exit 3: the run never started, which under `--observe syscalls` includes the shim's
# filter being refused, whether by the kernel or inside the target's own process) is a 2
# here, not a mismatch.
#
# Usage: sh spike/measure-libc-internal.sh              (inside the Linux container)
#        sh spike/measure-libc-internal.sh --selftest   (the reds, no container work)
set -u

ROOT=${SIDEEYE_ROOT:-/work}
# Overridable one axis at a time on purpose. The contrast this measurement rests on
# is "the same toy, two builds of the engine", and the first attempt at it pointed
# SIDEEYE_ROOT at the older build — which moved the toy source too, so every member
# came back `other` with "unknown command". The check was red for a reason that had
# nothing to do with what it measures, which is not a red at all.
SIDEEYE=${SIDEEYE:-$ROOT/zig-out/bin/sideeye}
SHIM=${SHIM:-$ROOT/zig-out/lib/libsideeye_shim.so}
ORACLE=${ORACLE:-/usr/bin/strace}
TOY_SRC=${TOY_SRC:-$ROOT/spike/toys/toy_mkstemp.c}
WORK=${WORK:-/tmp/libc-internal}

MODES='wrappers syscalls'

# member:wrappers:syscalls. The names are the subcommands of the toy, which are also
# the libc entry points; keeping them identical is what lets the drift check below
# compare this list against the toy's own dispatch without a translation table.
DECLARED='mkstemp:judged:judged
mkostemp:judged:judged
mkstemps:judged:judged
mkostemps:judged:judged
mkdtemp:judged:judged
dprintf:wall:judged
dprintfbig:wall:judged
tmpfile:inert:inert'

die_broken() { echo "BROKEN: $*" >&2; exit 2; }

# The declared outcome of one entry for one mode. An entry is exactly three non-empty
# fields; anything else is malformed and answers status 1 with no output, which the
# caller turns into BROKEN. Reading `wall:judged` whole as one outcome — what a
# two-field reader does — would report every member as a mismatch instead.
declared_for() { # $1 = entry, $2 = mode
    case "$1" in
        *:*:*:*) return 1 ;;
        *:*:*) ;;
        *) return 1 ;;
    esac
    _rest=${1#*:}
    case "$2" in
        wrappers) _v=${_rest%%:*} ;;
        syscalls) _v=${_rest#*:} ;;
        *) return 1 ;;
    esac
    [ -n "$_v" ] || return 1
    printf '%s' "$_v"
}

# How many operations a report says the oracle agreed on, or nothing. The engine spells
# the line three ways — `      oracle: agreed on …` under a PASS, `oracle      agreed on …`
# under a FAIL, and a third with seven spaces (src/main.zig) — so the line is read by its
# shape rather than by one spelling. The first version matched the PASS spelling only
# and read every FAIL as unjudged, a regression the second review caught.
agreed_count() { # $1 = report
    printf '%s\n' "$1" \
        | sed -n 's/^[[:space:]]*oracle:\{0,1\}[[:space:]][[:space:]]*agreed on \([0-9][0-9]*\) operation.*/\1/p' \
        | head -1
}

# Classify one run. Order matters: `inert` is a PASS too, and is checked first.
#
# Every branch reads the HEADLINE — the first line — rather than searching the whole
# output. Searching was the first version and it was too loose in two ways review
# named: a run printing the class refusal *beside* another one still read as `wall`,
# and a shell failure (126 could-not-execute, 127 not-found, 128+n killed) fell
# through to `other`, which is a mismatch rather than the BROKEN this file's own
# header promises for "could not run". The one exception is the oracle's agreement,
# which a verdict's report states on a line of its own.
classify() { # $1 = exit code, $2 = output
    _rc=$1
    _head=$(printf '%s\n' "$2" | head -1)
    # A shell-level failure is not a verdict about the target. `sh` reports 126 for
    # could-not-execute and 127 for not-found, and a signal shows as 128+n.
    if [ "$_rc" -ge 126 ] 2>/dev/null; then echo broken; return; fi
    # Exit 3 is the engine saying the run never started. Under `--observe syscalls` that
    # includes the shim's filter being refused — by a kernel without SECCOMP_RET_TRAP, or
    # inside the target's own process — which is this check failing to ask the question
    # on that host, not a member's answer (#541 review).
    if [ "$_rc" = 3 ]; then echo broken; return; fi
    case "$_head" in
        PASS*"performed nothing that can change the judged state"*)
            [ "$_rc" = 0 ] || { echo other; return; }
            echo inert; return ;;
    esac
    if [ "$_rc" = 2 ]; then
        # The reason has to be this one, ON THE HEADLINE. Any other exit-2 refusal is
        # a different finding wearing the same exit code, and calling it `wall` would
        # hide it.
        case "$_head" in
            'UNKNOWN  oracle_missed_operation') echo wall; return ;;
            *) echo other; return ;;
        esac
    fi
    if [ "$_rc" = 0 ] || [ "$_rc" = 1 ]; then
        case "$_head" in
            PASS*|FAIL*)
                # Every run here passes --oracle, so a verdict that does not carry the
                # oracle's agreement is not the verdict this check declares. Without this
                # a PASS the engine reached without that comparison would read as
                # `judged`, and the page's "carrying the oracle's agreement" would rest on
                # nothing (#541 review).
                if [ -n "$(agreed_count "$2")" ]; then echo judged; else echo other; fi
                return ;;
        esac
    fi
    echo other
}

# The contract differential: the five replacements must answer what the real functions
# answer, on this platform, for flags and template shapes neither the toy above nor a
# happy-path run touches. The comparison is against the SAME binary run without the
# shim, so it needs no expected-output file to go stale — and it is the only leg here
# that would notice the shim changing what a target does rather than what is recorded.
run_differential() {
    _src=${RULES_SRC:-$ROOT/spike/toys/toy_temp_rules.c}
    [ -f "$_src" ] || die_broken "rules toy not found at $_src"
    _bin=${RULES_TOY:-/tmp/toy-temp-rules}
    gcc -O0 -g -Wall -Wextra -o "$_bin" "$_src" || die_broken "$_src did not compile"
    _a="$WORK/rules-plain.txt"
    _b="$WORK/rules-shimmed.txt"
    mkdir -p "$WORK/plain" "$WORK/shimmed" || die_broken "cannot create $WORK"
    "$_bin" "$WORK/plain" > "$_a" 2> "$WORK/rules-plain.err" \
        || die_broken "the rules toy failed without the shim"
    LD_PRELOAD="$SHIM" "$_bin" "$WORK/shimmed" > "$_b" 2> "$WORK/rules-shimmed.err" \
        || die_broken "the rules toy failed under the shim"
    # Non-empty on both sides, or an empty file would equal an empty file.
    [ -s "$_a" ] || die_broken "the plain run printed nothing"
    [ -s "$_b" ] || die_broken "the shimmed run printed nothing"
    # The positive control, on stderr because the two runs are SUPPOSED to differ here.
    # Without it, deleting every temp export from the shim leaves both runs reaching
    # the real libc, agreeing, and this leg green having measured nothing.
    case "$(cat "$WORK/rules-plain.err")" in
        *"resolved mkstemp in libc"*) ;;
        *) die_broken "the plain run did not resolve mkstemp in libc: $(cat "$WORK/rules-plain.err")" ;;
    esac
    case "$(cat "$WORK/rules-shimmed.err")" in
        *"resolved mkstemp in libsideeye_shim"*) ;;
        *) die_broken "the shim was not in the way: $(cat "$WORK/rules-shimmed.err")" ;;
    esac
    if diff "$_a" "$_b" > "$WORK/rules.diff" 2>&1; then
        echo "ok   contract  the five replacements answer what libc answers ($(grep -c . "$_a") cases)"
        return 0
    fi
    echo "MISMATCH contract: the shim changed what the target does, not only what is recorded"
    sed 's/^/     | /' "$WORK/rules.diff" | head -12
    return 1
}

# One member under one mode. Prints "<outcome> <crash points> <oracle-agreed operations>",
# a field `-` where the report names none; exits 2 if the engine could not run.
measure_one() { # $1 = member, $2 = mode
    _m=$1
    _mode=$2
    rm -rf "$WORK"
    mkdir -p "$WORK/state" || die_broken "cannot create $WORK/state"
    _out=$("$SIDEEYE" explore \
        --state "$WORK/state" \
        --setup "$TOY init" \
        --operation "$TOY $_m" \
        --shim "$SHIM" \
        --work "$WORK/work" \
        --oracle "$ORACLE" \
        --observe "$_mode" 2>&1)
    _rc=$?
    printf '%s' "$_out" > "$WORK/$_m.$_mode.txt"
    _outcome=$(classify "$_rc" "$_out")
    # `broken` is not a member's answer, it is this check failing to ask the question.
    # Letting it fall through to the declaration comparison would report it as a
    # mismatch (exit 1) where the header promises exit 2.
    [ "$_outcome" = broken ] && die_broken "$_m ($_mode): the engine did not run (exit $_rc)"
    _cp=$(printf '%s\n' "$_out" \
        | sed -n 's/.*(crash points \([0-9][0-9]*\) + [0-9][0-9]* baseline).*/\1/p' | head -1)
    _ag=$(agreed_count "$_out")
    printf '%s %s %s' "$_outcome" "${_cp:--}" "${_ag:--}"
}

compare_one() { # $1 = member, $2 = mode, $3 = declared, $4 = measured; prints nothing when they agree
    [ "$3" = "$4" ] || printf 'MISMATCH %s (%s): declared %s, measured %s' "$1" "$2" "$3" "$4"
}

# Whether every argument is a count a report printed; `-` (the report named none) and
# empty are not.
counts() { # $@ = values
    for _n in "$@"; do
        case "$_n" in '' | *[!0-9]*) return 1 ;; esac
    done
}

# The split (see the header). Prints nothing when `dprintfbig` has more crash points than
# `dprintf` under --observe syscalls.
compare_split() { # $1 = dprintf's crash points, $2 = dprintfbig's
    if ! counts "$1" "$2"; then
        printf 'MISMATCH split: crash points not both measured under --observe syscalls (dprintf %s, dprintfbig %s)' "${1:-none}" "${2:-none}"
    elif [ "$2" -le "$1" ]; then
        printf 'MISMATCH split: dprintfbig has %s crash points under --observe syscalls and dprintf %s — the big payload did not become more writes' "$2" "$1"
    fi
}

# Each write a crash point (see the header). Prints nothing when a member's crash points
# equal the operations the oracle agreed on under --observe syscalls.
compare_each_write() { # $1 = member, $2 = crash points, $3 = oracle-agreed operations
    if ! counts "$2" "$3"; then
        printf 'MISMATCH each write (%s): not both measured under --observe syscalls (crash points %s, oracle agreed on %s)' "$1" "${2:-none}" "${3:-none}"
    elif [ "$2" != "$3" ]; then
        printf 'MISMATCH each write (%s): %s crash points under --observe syscalls, but the oracle agreed on %s operations' "$1" "$2" "$3"
    fi
}

# The loop is driven by a variable, and an empty one would print no failures and exit 0.
# The expectation comes from the toy's dispatch rather than from the declaration being
# counted, so an empty declaration is 0 of 16 and not 0 of 0 (#541 review).
count_ok() { # $1 = runs seen, $2 = runs expected
    [ "$2" -gt 0 ] 2>/dev/null && [ "$1" = "$2" ]
}

# The toy's own member list: its subcommands, less the two that are not class members.
toy_members() {
    sed -n 's/.*strcmp(argv\[1\], "\([a-z]*\)") == 0.*/\1/p' "$TOY_SRC" \
        | grep -vxF init | grep -vxF rotate | LC_ALL=C sort
}

selftest() {
    fails=0
    check() { # $1 = label, $2 = got, $3 = want
        if [ "$2" = "$3" ]; then
            echo "ok   $1"
        else
            echo "FAIL $1: got '$2', wanted '$3'"
            fails=$((fails + 1))
        fi
    }
    check_loud() { # $1 = label, $2 = got; a MISMATCH line of any wording
        case "$2" in
            MISMATCH*) echo "ok   $1" ;;
            *) echo "FAIL $1: got '$2', wanted a MISMATCH"; fails=$((fails + 1)) ;;
        esac
    }

    # The two report shapes, as the engine prints them: the PASS from this script's own
    # 2026-09-13 run, the FAIL from spike/cohort2/borg-r3/explore-transcript.txt (lines 117
    # and 128). The FAIL's oracle line has no colon, which is what the first version of
    # the classifier missed.
    pass_report='PASS  3/3 explored worlds satisfied the built-in atomicity invariant
      explored 3 worlds (crash points 2 + 1 baseline)
      oracle: agreed on 2 operations (70 syscall lines examined, 9 in scope of the judged state)'
    fail_report='FAIL  3 of 119 explored worlds violated an invariant
oracle      agreed on 118 operations (6547 syscall lines examined, 1046 in scope of the judged state)'

    echo "== the classifier, against its own predicate"
    check "a PASS with the oracle's agreement is judged" "$(classify 0 "$pass_report")" judged
    check "a FAIL with the oracle's agreement is judged, in the FAIL report's own spelling" \
        "$(classify 1 "$fail_report")" judged
    # The red for the line that makes "carrying the oracle's agreement" a measurement: a
    # PASS whose report does not carry the agreement is not the outcome this check declares.
    check "a verdict without the oracle's agreement is not judged" \
        "$(classify 0 'PASS  5/5 explored worlds satisfied the built-in atomicity invariant')" other
    check "the agreement is read from a PASS report" "$(agreed_count "$pass_report")" 2
    check "the agreement is read from a FAIL report" "$(agreed_count "$fail_report")" 118
    check "the agreement is not read from prose that mentions it" \
        "$(agreed_count 'the oracle agreed on nothing')" ""
    check "the class refusal is a wall" \
        "$(classify 2 'UNKNOWN  oracle_missed_operation')" wall
    # The red that matters most: a DIFFERENT exit-2 refusal must not be read as the
    # wall. Without this the check would credit any breakage as the expected wall.
    check "another refusal is not the wall" \
        "$(classify 2 'UNKNOWN  no_shim_marker')" other
    check "a refusal reason inside prose is not the wall" \
        "$(classify 2 'the oracle_missed_operation detector exists')" other
    # The two reds review asked for. Searching the whole output rather than the
    # headline read both of these as `wall`.
    check "the wall reason below another headline is not the wall" \
        "$(classify 2 'UNKNOWN  no_shim_marker
UNKNOWN  oracle_missed_operation')" other
    check "could-not-execute is BROKEN, not a mismatch" "$(classify 126 '')" broken
    check "not-found is BROKEN too" "$(classify 127 '')" broken
    check "killed by a signal is BROKEN" "$(classify 139 'PASS  5/5')" broken
    check "a SETUP ERROR is BROKEN, not a mismatch" \
        "$(classify 3 'SETUP ERROR  the kernel refused the seccomp filter')" broken
    check "the inert PASS is inert, not judged" \
        "$(classify 0 'PASS  the operation performed nothing that can change the judged state')" inert
    check "an inert line with a bad exit is neither" \
        "$(classify 2 'PASS  the operation performed nothing that can change the judged state')" other

    echo
    echo "== each mode reads its own column"
    check "wrappers reads the second field" "$(declared_for 'dprintf:wall:judged' wrappers)" wall
    check "syscalls reads the third field" "$(declared_for 'dprintf:wall:judged' syscalls)" judged
    declared_for 'dprintf:wall' wrappers > /dev/null
    check "a two-field entry is malformed" "$?" 1
    declared_for 'dprintf:wall:judged:judged' syscalls > /dev/null
    check "a four-field entry is malformed" "$?" 1
    declared_for 'dprintf::judged' wrappers > /dev/null
    check "an empty field is malformed" "$?" 1
    declared_for 'dprintf:wall:judged' kernel > /dev/null
    check "an unknown mode is malformed" "$?" 1

    echo
    echo "== the comparison, per mode, against synthetic measurements"
    # The measured side as the 2026-09-13 run recorded it: a wall at the libc boundary and
    # a verdict at the kernel's. The silent half is what catches both modes reading one
    # column — the loud half alone would pass that bug too.
    for mode in $MODES; do
        case $mode in
            wrappers) measured=wall ;;
            syscalls) measured=judged ;;
        esac
        got=$(compare_one dprintf "$mode" "$(declared_for 'dprintf:wall:judged' "$mode")" "$measured")
        check "the right column is silent ($mode)" "$got" ""
        got=$(compare_one dprintf "$mode" "$(declared_for 'dprintf:judged:wall' "$mode")" "$measured")
        check_loud "the swapped columns are loud ($mode)" "$got"
    done

    echo
    echo "== the split, both directions"
    check "more crash points for the big payload is silent" "$(compare_split 2 4)" ""
    check_loud "the same count is loud" "$(compare_split 2 2)"
    check_loud "fewer is loud" "$(compare_split 3 2)"
    check_loud "an unmeasured count is loud" "$(compare_split - 4)"
    check_loud "an empty count is loud" "$(compare_split 2 '')"

    echo
    echo "== each write a crash point, both directions"
    check "crash points equal to the agreed operations is silent" "$(compare_each_write dprintfbig 514 514)" ""
    check_loud "one crash point short is loud" "$(compare_each_write dprintfbig 513 514)"
    check_loud "one crash point over is loud" "$(compare_each_write dprintfbig 4 3)"
    check_loud "no agreement to compare with is loud" "$(compare_each_write dprintf 2 -)"

    echo
    echo "== the run count"
    count_ok 16 16
    check "a full count passes" "$?" 0
    count_ok 14 16
    check "a short count fails" "$?" 1
    count_ok 0 0
    check "nothing measured against nothing expected fails" "$?" 1

    echo
    echo "== the member list does not drift from the toy"
    # Same shape as spike/cohort4/class-drift-check.py: two copies of one list, held
    # to each other rather than to a comment asking the next person to remember.
    [ -f "$TOY_SRC" ] || die_broken "toy source not found at $TOY_SRC"
    declared_names=$(printf '%s\n' "$DECLARED" | cut -d: -f1 | LC_ALL=C sort)
    toy_names=$(toy_members)
    [ -n "$toy_names" ] || die_broken "read no subcommands out of $TOY_SRC"
    if [ "$declared_names" = "$toy_names" ]; then
        echo "ok   the toy dispatches exactly the declared members"
    else
        echo "FAIL the toy and this file disagree about the member list:"
        echo "     declared: $(printf '%s' "$declared_names" | tr '\n' ' ')"
        echo "     toy:      $(printf '%s' "$toy_names" | tr '\n' ' ')"
        fails=$((fails + 1))
    fi

    echo
    echo "== self-test failures: $fails"
    [ "$fails" = 0 ] || return 1
    return 0
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

command -v gcc >/dev/null || die_broken "gcc not found; this runs in the Linux container"
[ -x "$SIDEEYE" ] || die_broken "engine not found at $SIDEEYE"
[ -f "$SHIM" ] || die_broken "shim not found at $SHIM"
[ -x "$ORACLE" ] || die_broken "oracle not found at $ORACLE"
[ -f "$TOY_SRC" ] || die_broken "toy source not found at $TOY_SRC"

TOY=${TOY:-/tmp/toy-libc-internal}
gcc -O0 -g -Wall -Wextra -o "$TOY" "$TOY_SRC" || die_broken "$TOY_SRC did not compile"

members=$(toy_members)
[ -n "$members" ] || die_broken "read no subcommands out of $TOY_SRC"
n_members=$(printf '%s\n' "$members" | grep -c .)
n_modes=0
for mode in $MODES; do n_modes=$((n_modes + 1)); done
expected=$((n_members * n_modes))

echo "engine:  $("$SIDEEYE" --version 2>&1 | head -1)"
echo "commit:  $(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
echo "script:  $(sha256sum "$0" 2>/dev/null | cut -d' ' -f1)  spike/measure-libc-internal.sh"
echo "libc:    $(ldd --version 2>&1 | head -1)"
echo "compiler: $(gcc --version 2>&1 | head -1)"
echo "toy:     $(sha256sum "$TOY_SRC" | cut -d' ' -f1)  spike/toys/toy_mkstemp.c"
echo "arch:    $(uname -m)"
echo "modes:   $MODES"
echo

fails=0
seen=0
dprintf_cp=
dprintf_ag=
big_cp=
big_ag=
# Split on newline explicitly rather than leaning on the default IFS: this file is
# `sh`, but a reader running it under zsh would get no word splitting from a variable
# at all, and the loop would run once with the whole list as one entry. The list is
# expanded once, when the loop starts, so the body goes back to the default IFS for the
# modes.
old_ifs=$IFS
IFS='
'
for entry in $DECLARED; do
    IFS=$old_ifs
    member=${entry%%:*}
    for mode in $MODES; do
        declared=$(declared_for "$entry" "$mode") || die_broken "malformed declaration: '$entry'"
        result=$(measure_one "$member" "$mode") || exit 2
        outcome=${result%% *}
        rest=${result#* }
        cp=${rest%% *}
        agreed=${rest#* }
        seen=$((seen + 1))
        if [ "$mode" = syscalls ]; then
            case $member in
                dprintf) dprintf_cp=$cp; dprintf_ag=$agreed ;;
                dprintfbig) big_cp=$cp; big_ag=$agreed ;;
            esac
        fi
        mismatch=$(compare_one "$member" "$mode" "$declared" "$outcome")
        if [ -n "$mismatch" ]; then
            echo "$mismatch"
            sed 's/^/     | /' "$WORK/$member.$mode.txt" | head -6
            fails=$((fails + 1))
        elif [ "$outcome" = judged ]; then
            printf 'ok   %-10s %-8s %s (crash points %s, oracle agreed on %s)\n' \
                "$member" "$mode" "$outcome" "$cp" "$agreed"
        else
            printf 'ok   %-10s %-8s %s\n' "$member" "$mode" "$outcome"
        fi
    done
done
IFS=$old_ifs

echo
# A run that measured nothing must not report success.
count_ok "$seen" "$expected" \
    || die_broken "measured $seen runs, wanted $expected (the toy's $n_members members in $n_modes modes) — the declared list did not drive the loop"

split=$(compare_split "$dprintf_cp" "$big_cp")
if [ -n "$split" ]; then
    echo "$split"
    fails=$((fails + 1))
else
    echo "ok   split      dprintfbig has more crash points than dprintf under --observe syscalls ($big_cp > $dprintf_cp)"
fi

report_each_write() { # $1 = member, $2 = crash points, $3 = oracle-agreed operations
    _each=$(compare_each_write "$1" "$2" "$3")
    if [ -n "$_each" ]; then
        echo "$_each"
        return 1
    fi
    echo "ok   each write ($1): $2 crash points under --observe syscalls, the oracle agreeing on $3 operations"
}
report_each_write dprintf "$dprintf_cp" "$dprintf_ag" || fails=$((fails + 1))
report_each_write dprintfbig "$big_cp" "$big_ag" || fails=$((fails + 1))

# Last, because every measurement above wipes $WORK.
run_differential || fails=$((fails + 1))

echo
echo "measured $seen runs ($n_members members in $n_modes modes) plus the split, each write and the contract differential, $fails did not match"
[ "$fails" = 0 ] || exit 1
exit 0
