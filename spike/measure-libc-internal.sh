#!/bin/sh
# The libc-internal-call class (#39), member by member, against the shipped engine.
#
# ## What this drives, and what it deliberately does not
#
# It runs `sideeye explore --oracle` on one class member at a time. An earlier design
# measured with `spike/cohort4/preflight.sh visibility`, and that would have been the
# wrong instrument: its `visibility-logger.c` is a SEPARATE LD_PRELOAD that wraps
# `open`, `mkdir` and friends but no member of this class, so it reports a wall
# whatever the shim does — and would have gone on reporting one after the shim stopped
# being blind. The thing measured has to be the thing that ships.
#
# Each member runs alone and writes through its own final path, so a divergence names
# the member that caused it. A single command exercising all of them cannot.
#
# ## The declared outcomes
#
# Every member carries a declared outcome and the check fails when the measurement
# disagrees IN EITHER DIRECTION — a wall that starts being judged is as much a change
# as a judged member that starts refusing.
#
#   judged     the five creators the shim reimplements (contract v13, #39). A verdict
#              is reached: exit 0 or 1, PASS or FAIL.
#   wall       `dprintf`: glibc splits a large write at 8192 bytes (measured
#              2026-08-31, spike/libc-internal/RESULTS.md). A wrapper writing once
#              would delete a crash point the real program has; one that split would
#              hard-code an undocumented libc constant. It stays a wall, and this line
#              is the standing evidence that it is still one — the negative control
#              this check did not have to invent.
#   inert      `tmpfile`, **on this platform only**: glibc reaches
#              `openat(AT_FDCWD, "/tmp", O_RDWR|O_EXCL|O_TMPFILE)`, which creates no
#              directory entry and ignores TMPDIR entirely, so it cannot mutate a
#              state root here. That reading does **not** carry to macOS, where
#              `tmpfile` honours TMPDIR and creates a real named file it then unlinks
#              (measured) — there it is a wall, and this script does not run there.
#
# ## What a green run does NOT mean
#
# It does not mean the class is closed: `dprintf` is declared `wall` and a green run
# includes it refusing. It does not mean anything about macOS — the oracle here is
# strace, and the macOS side of the same replacements is exercised by the macOS CI
# leg. It says nothing about members nobody has named.
#
# Exit 0 when every member matches its declaration, 1 when one does not, 2 when the
# check could not run — never read a 2 as a pass.
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

# member:declared-outcome. The names are the subcommands of the toy, which are also
# the libc entry points; keeping them identical is what lets the drift check below
# compare this list against the toy's own dispatch without a translation table.
DECLARED='mkstemp:judged
mkostemp:judged
mkstemps:judged
mkostemps:judged
mkdtemp:judged
dprintf:wall
tmpfile:inert'

die_broken() { echo "BROKEN: $*" >&2; exit 2; }

# Classify one run. Order matters: `inert` is a PASS too, and is checked first.
#
# Every branch reads the HEADLINE — the first line — rather than searching the whole
# output. Searching was the first version and it was too loose in two ways review
# named: a run printing the class refusal *beside* another one still read as `wall`,
# and a shell failure (126 could-not-execute, 127 not-found, 128+n killed) fell
# through to `other`, which is a mismatch rather than the BROKEN this file's own
# header promises for "could not run".
classify() { # $1 = exit code, $2 = output
    _rc=$1
    _head=$(printf '%s\n' "$2" | head -1)
    # A shell-level failure is not a verdict about the target. `sh` reports 126 for
    # could-not-execute and 127 for not-found, and a signal shows as 128+n.
    if [ "$_rc" -ge 126 ] 2>/dev/null; then echo broken; return; fi
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
            PASS*|FAIL*) echo judged; return ;;
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

measure_one() { # $1 = member; prints the outcome, or exits 2 if it could not run
    _m=$1
    rm -rf "$WORK"
    mkdir -p "$WORK/state" || die_broken "cannot create $WORK/state"
    _out=$("$SIDEEYE" explore \
        --state "$WORK/state" \
        --setup "$TOY init" \
        --operation "$TOY $_m" \
        --shim "$SHIM" \
        --work "$WORK/work" \
        --oracle "$ORACLE" 2>&1)
    _rc=$?
    printf '%s' "$_out" > "$WORK/$_m.txt"
    _outcome=$(classify "$_rc" "$_out")
    # `broken` is not a member's answer, it is this check failing to ask the question.
    # Letting it fall through to the declaration comparison would report it as a
    # mismatch (exit 1) where the header promises exit 2.
    [ "$_outcome" = broken ] && die_broken "$_m: the engine did not run (exit $_rc)"
    printf '%s' "$_outcome"
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

    echo "== the classifier, against its own predicate"
    check "a verdict is judged" \
        "$(classify 0 'PASS  5/5 explored worlds satisfied the built-in atomicity invariant')" judged
    check "a FAIL is a verdict too" "$(classify 1 'FAIL  world 3')" judged
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
    check "the inert PASS is inert, not judged" \
        "$(classify 0 'PASS  the operation performed nothing that can change the judged state')" inert
    check "an inert line with a bad exit is neither" \
        "$(classify 2 'PASS  the operation performed nothing that can change the judged state')" other

    echo
    echo "== the comparison, against a mutated declaration"
    # Declaring dprintf `judged` must go red against the measurement this file
    # records, and declaring it `wall` must not. Both directions, on the same input.
    got=$(compare_one dprintf wall wall)
    check "declaration met is silent" "$got" ""
    got=$(compare_one dprintf judged wall)
    check "declaration missed is loud" "$got" \
        "MISMATCH dprintf: declared judged, measured wall"

    echo
    echo "== the member list does not drift from the toy"
    # Same shape as spike/cohort4/class-drift-check.py: two copies of one list, held
    # to each other rather than to a comment asking the next person to remember.
    [ -f "$TOY_SRC" ] || die_broken "toy source not found at $TOY_SRC"
    declared_names=$(printf '%s\n' "$DECLARED" | cut -d: -f1 | LC_ALL=C sort)
    toy_names=$(sed -n 's/.*strcmp(argv\[1\], "\([a-z]*\)") == 0.*/\1/p' "$TOY_SRC" \
        | grep -vxF init | grep -vxF rotate | LC_ALL=C sort)
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

compare_one() { # $1 = member, $2 = declared, $3 = measured; prints nothing when they agree
    [ "$2" = "$3" ] || printf 'MISMATCH %s: declared %s, measured %s' "$1" "$2" "$3"
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

echo "engine:  $("$SIDEEYE" --version 2>&1 | head -1)"
echo "libc:    $(ldd --version 2>&1 | head -1)"
echo "compiler: $(gcc --version 2>&1 | head -1)"
echo "toy:     $(sha256sum "$TOY_SRC" | cut -d' ' -f1)  spike/toys/toy_mkstemp.c"
echo "arch:    $(uname -m)"
echo

fails=0
seen=0
# Split on newline explicitly rather than leaning on the default IFS: this file is
# `sh`, but a reader running it under zsh would get no word splitting from a variable
# at all, and the loop would run once with the whole list as one entry.
old_ifs=$IFS
IFS='
'
for entry in $DECLARED; do
    IFS=$old_ifs
    member=${entry%%:*}
    declared=${entry#*:}
    outcome=$(measure_one "$member") || exit 2
    seen=$((seen + 1))
    mismatch=$(compare_one "$member" "$declared" "$outcome")
    if [ -n "$mismatch" ]; then
        echo "$mismatch"
        sed 's/^/     | /' "$WORK/$member.txt" | head -6
        fails=$((fails + 1))
    else
        printf 'ok   %-10s %s\n' "$member" "$outcome"
    fi
done

echo
# A run that measured nothing must not report success: the loop above is driven by a
# variable, and an empty one would print no failures and exit 0.
[ "$seen" = 7 ] || die_broken "measured $seen members, wanted 7 — the declared list did not drive the loop"

# Last, because the loop above wipes $WORK between members.
run_differential || fails=$((fails + 1))

echo
echo "measured $seen members plus the contract differential, $fails did not match"
[ "$fails" = 0 ] || exit 1
exit 0
