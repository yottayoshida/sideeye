#!/bin/sh
# The entry gate for this campaign's candidates, answered by EXIT CODE.
#
#   sh gate.sh visibility <state-root> -- <cmd> [args...]
#   sh gate.sh interior   <state-root> -- <cmd> [args...]
#   sh gate.sh threads    <state-root> -- <cmd> [args...]
#   sh gate.sh all <label> <state-root> -- <cmd> [args...]
#   sh gate.sh --selftest
#
# Exit 0 the gate is clear, 1 the gate is red, **2 the gate could not measure**.
# A 2 is never a pass and is never folded into 1 — see "the two is kept" below.
#
# ## Why this wrapper exists
#
# `spike/dogfood/README.md` already requires the measurement: *"Measure linkage and
# threads before writing the candidate table, not after."* The 2026-09-21 release-path
# run DID measure, and still admitted a statically linked target: the probe was run and
# its output read only as far as `ELF 64-bit LSB executable`, with `statically linked`
# further along the same line. The run then spent its only target slot on
# `UNKNOWN oracle_missed_operation`.
#
# What failed was the reading, not the measuring, so a rule saying "read to the end of
# the line" leaves the same path open. This wrapper changes the ANSWER's shape instead:
# a gate that returns 0, 1 or 2 cannot be skim-read.
#
# `spike/cohort4/preflight.sh` already answers one of the three questions that way.
# It is used as-is and NOT modified — cohort 4's sealed records cite it, so changing the
# instrument would change what those records mean. The other two questions are answered
# by parsing its printed count, and by counting clones.
#
# ## The two is kept
#
# `preflight.sh` exits 2 for "could not measure" and its own header says never to read a
# 2 as a pass. Collapsing 2 into 1 would turn "the apparatus is missing" into "the target
# is walled" — which is the mistake this campaign's plan nearly made about lefthook
# itself. Every 2 below is passed through unchanged.
#
# ## What a red means, per gate
#
#   visibility  A state-root mutation the kernel performed did not pass through a
#               function an LD_PRELOAD shim can interpose. The shim cannot address it,
#               so the engine cannot place a crash point on it. A real wall.
#
#   interior    Fewer than two kill points inside the state root (selection rule 15).
#               Not a wall: such a target reaches a verdict. It is a contrast case —
#               there is no world *inside* the mutation — so it does not answer the
#               question a dogfood run is spending its slot on.
#
#   threads     More than one thread id performed a state-changing call INSIDE the state
#               root. **This is a selection preference, not a prediction of refusal.**
#               Since contract v16 a run that creates threads is judged when one thread
#               wrote the judged directory, and since v18 when a creation or a join orders
#               two writers (ADR 0067); `docs/report-schema.md` states both. Whether a
#               given target clears that is the engine's decision on a real run, which
#               this gate does not make. A red here says: admitting this candidate depends
#               on a rule this gate cannot check, so in a run with one target slot, prefer
#               one that does not need it. (It counted threads *created* first; see
#               gate_threads' own header for why that was wrong.)
#
# ## The state has to be put back between gates
#
# Each gate runs the operation, so three gates run it three times. For an installer the
# second run is a different operation from the first — measured: `overcommit --install`
# writes ten hooks and then finds them already there. `gate.sh all` runs `$GATE_RESET`
# before each gate, and says so in its output when there is none.
set -u

PREFLIGHT=${PREFLIGHT:-/repo/spike/cohort4/preflight.sh}
OUT=${GATE_OUT:-/tmp/gate-out}

die_broken() { echo "BROKEN $*" >&2; exit 2; }

need_preflight() {
    [ -f "$PREFLIGHT" ] || die_broken "preflight.sh not found at $PREFLIGHT (mount the repo read-only at /repo)"
}

# --- visibility: preflight's own answer, passed through -------------------------------
gate_visibility() {
    need_preflight
    root=$1; shift
    [ "${1:-}" = "--" ] || die_broken "expected -- before the command"
    shift
    SIDEEYE_PREFLIGHT_OUT="$OUT/visibility" sh "$PREFLIGHT" visibility "$root" -- "$@"
    rc=$?
    echo "gate visibility rc=$rc"
    return $rc
}

# --- interior: preflight prints a count and always exits 0; turn it into a code --------
gate_interior() {
    need_preflight
    root=$1; shift
    [ "${1:-}" = "--" ] || die_broken "expected -- before the command"
    shift
    log="$OUT/interior.txt"
    mkdir -p "$OUT"
    SIDEEYE_PREFLIGHT_OUT="$OUT/interior" sh "$PREFLIGHT" interior "$root" -- "$@" > "$log" 2>&1
    rc=$?
    cat "$log"
    # A non-zero from preflight in this mode can only be a die_broken (the interior path
    # itself always exits 0), so it is a 2 and stays one.
    if [ "$rc" -ne 0 ]; then
        echo "gate interior rc=2 (preflight could not measure; its rc was $rc)"
        return 2
    fi
    n=$(sed -n 's/^INTERIOR kill points inside the state root: \([0-9][0-9]*\).*/\1/p' "$log" | head -1)
    if [ -z "$n" ]; then
        echo "gate interior rc=2 (preflight printed no INTERIOR count)"
        return 2
    fi
    if [ "$n" -lt 2 ]; then
        echo "gate interior rc=1 (kill points inside the state root: $n; rule 15 wants >= 2)"
        return 1
    fi
    echo "gate interior rc=0 (kill points inside the state root: $n)"
    return 0
}

# --- threads: count the thread ids that WRITE inside the state root --------------------
#
# The first version of this gate counted clones carrying CLONE_THREAD and went red at one.
# It was measured against `overcommit --install` and went red on two — both of them the
# Ruby VM's own startup threads, neither of which touches the judged directory. That is a
# proxy answering a question the engine stopped asking: since contract v16 a run that
# creates threads is judged when ONE thread wrote the judged directory, and since v18 two
# writers are judged when a creation or a join orders them (`docs/report-schema.md`,
# ADR 0067). A gate that reds on creation turns away targets the engine can judge, and
# "the interpreter starts a timer thread" would disqualify every Ruby, Python and Node
# candidate there is.
#
# So the count is taken where the engine takes its own: thread ids performing a
# state-changing call INSIDE the state root. `strace -f` prefixes every line with the id
# that made the call, which is what makes this measurable before a define exists.
#
# What it still does not do is decide the v18 ordering question — whether a creation or a
# join orders two writers. Two writers is therefore a red here and not a refusal: it says
# admission depends on something this gate cannot check, so in a run with one target slot,
# prefer a candidate that does not need it. The created count is printed beside it because
# it is the number the older rule used, and a reader comparing runs will look for it.
gate_threads() {
    root=$1; shift
    [ "${1:-}" = "--" ] || die_broken "expected -- before the command"
    shift
    command -v strace >/dev/null 2>&1 || die_broken "strace not installed - the gate cannot measure"
    mkdir -p "$OUT"
    log="$OUT/threads.txt"
    # `-y` so descriptor-based calls print the path they resolve to: a write reaches the
    # kernel as a number, and without it every fd-based write would be invisible to the
    # path filter below and the gate would answer 0 writers for a target that wrote.
    strace -f -y -o "$log" \
        -e trace=%file,write,pwrite64,writev,fsync,fdatasync,ftruncate,clone,clone3 \
        "$@" > "$OUT/threads.stdout" 2>"$OUT/threads.stderr"
    # The target's own status is not the gate's business — a candidate may legitimately
    # exit non-zero here — but strace writing nothing means nothing was measured.
    if [ ! -s "$log" ]; then
        echo "gate threads rc=2 (strace produced no output; nothing was measured)"
        return 2
    fi
    created=$(grep -c 'CLONE_THREAD' "$log" 2>/dev/null || true)
    [ -n "$created" ] || created=0
    # **The id prefix has to be there before any count is believed.** `strace -f` puts the
    # pid or tid first on every line, and this whole gate is a count of distinct first
    # fields. If that prefix is absent — no `-f`, a refused ptrace leaving only an error
    # line, a format this does not expect — every line's first field fails the numeric test
    # and the count comes out 0, which is the GREEN answer. "One writer, measured" and
    # "nothing was measured" would be the same output. So the prefix is checked first and
    # its absence is a 2.
    if [ "$(awk '$1 ~ /^[0-9]+$/' "$log" | grep -c '' || true)" = 0 ]; then
        echo "gate threads rc=2 (no line in the strace output carries a numeric id prefix; the count this gate makes is not available)"
        return 2
    fi
    # A writing line: the call mutates state, it names something INSIDE the root, and it did
    # not fail. `= -1` is dropped because an attempt the kernel refused changed nothing.
    #
    # Two things this has to get right, both of them mistakes an earlier version made.
    #
    # **The separator.** A plain substring test for the root also accepts its SIBLINGS —
    # `<root>.staging`, `<root>.tmp`, `<root>-old` — and this gate's own green leg writes
    # exactly such a sibling (`toy_single_op.c` stages at `"%s.staging"`), so the error was
    # invisible in the leg most likely to meet it.
    #
    # **Where the root is allowed to appear.** Testing the whole line for the path counts a
    # log message as a write: `write(1</dev/pts/0>, "installing /tmp/r/.git/hooks/pre-commit")`
    # passes a naive filter on every clause, and a thread that only prints becomes a writer.
    # So the position matters. Under `strace -y` a descriptor prints as `4</resolved/path>`
    # and a path argument prints as `"/the/path"`, which is the difference this uses:
    # descriptor-based calls (write, fsync, ftruncate…) are accepted only through the `<`
    # annotation, and path-taking calls through either.
    writers=$(awk -v root="$root/" '
        $1 !~ /^[0-9]+$/ { next }                       # no id prefix: not a line we count
        /= -1/           { next }                       # the kernel refused it
        {
            call = $0
            sub(/^[0-9]+[ \t]+/, "", call)
            sub(/\(.*/, "", call)
        }
        call ~ /^(write|pwrite64|writev|fsync|fdatasync|ftruncate)$/ {
            if (index($0, "<" root) > 0) print $1
            next
        }
        call ~ /^(open|openat|creat)$/ {
            if ($0 !~ /O_WRONLY|O_RDWR|O_CREAT|O_TRUNC|O_APPEND/) next
            if (index($0, "\"" root) > 0 || index($0, "<" root) > 0) print $1
            next
        }
        call ~ /^(rename|renameat|renameat2|unlink|unlinkat|mkdir|mkdirat|rmdir|link|linkat|symlink|symlinkat|truncate)$/ {
            if (index($0, "\"" root) > 0 || index($0, "<" root) > 0) print $1
        }
    ' "$log" | sort -u | grep -c '' || true)
    [ -n "$writers" ] || writers=0
    if [ "$writers" -gt 1 ]; then
        echo "gate threads rc=1 ($writers thread id(s) wrote inside the state root; $created clone(s) carrying CLONE_THREAD. See the header for what this does and does not claim)"
        return 1
    fi
    echo "gate threads rc=0 ($writers thread id(s) wrote inside the state root; $created clone(s) carrying CLONE_THREAD)"
    return 0
}

# --- all three, printed as one row ----------------------------------------------------
gate_all() {
    label=$1; root=$2; shift 2
    [ "${1:-}" = "--" ] || die_broken "expected -- before the command"
    shift
    # `OUT` is read once at the top of this file, so a `GATE_OUT=... gate_visibility`
    # prefix never reaches the function: all three gates would write into one directory
    # and each candidate would erase the last one's artifacts. Assigning OUT here, and
    # restoring it afterwards, is what actually separates them.
    base=$OUT
    OUT="$base/$label"
    mkdir -p "$OUT"
    echo "=== $label ==="
    # **Each gate runs the operation again, so the state has to be put back between them.**
    # Without this the second gate measures the operation applied to what the first one
    # left, which for an installer is a different operation: `overcommit --install` writes
    # ten hooks the first time and finds them already there the second, so an interior
    # count taken after visibility is a count of the repeat. Measured — the first version of
    # this function recorded `3 kill points` for a target the engine then explored at 31.
    # GATE_RESET is the command that rebuilds the pre-state; with none, the row still prints
    # but says what it is.
    if [ -n "${GATE_RESET:-}" ]; then
        echo "reset: $GATE_RESET"
    else
        echo "reset: NONE — interior and threads below measured the operation applied to"
        echo "       what the gate before them left, which is not the same operation."
    fi
    [ -n "${GATE_RESET:-}" ] && sh -c "$GATE_RESET" > "$OUT/reset.log" 2>&1
    gate_visibility "$root" -- "$@" > "$OUT/visibility.log" 2>&1
    v=$?
    [ -n "${GATE_RESET:-}" ] && sh -c "$GATE_RESET" > "$OUT/reset.log" 2>&1
    gate_interior "$root" -- "$@" > "$OUT/interior.log" 2>&1
    i=$?
    [ -n "${GATE_RESET:-}" ] && sh -c "$GATE_RESET" > "$OUT/reset.log" 2>&1
    gate_threads "$root" -- "$@" > "$OUT/threads.log" 2>&1
    t=$?
    tail -2 "$OUT/visibility.log"; tail -1 "$OUT/interior.log"; tail -1 "$OUT/threads.log"
    OUT=$base
    printf 'GATE %-14s visibility=%s interior=%s threads=%s\n' "$label" "$v" "$i" "$t"
    if [ "$v" = 0 ] && [ "$i" = 0 ] && [ "$t" = 0 ]; then return 0; fi
    if [ "$v" = 2 ] || [ "$i" = 2 ] || [ "$t" = 2 ]; then return 2; fi
    return 1
}

# --- selftest: every gate seen red AND green ------------------------------------------
#
# Three reds and three greens. A wrapper that always answered 0 would pass the greens and
# fail every red; one that always answered 1 would do the reverse. The visibility red is
# **lefthook**, the target the previous run admitted — not `spike/toys/toy_raw.c`, which
# is dynamically linked and issues raw syscalls (a different wall class) and whose red
# `preflight.sh --selftest` already commits to `spike/cohort4/preflight-selftest.txt`.
selftest() {
    need_preflight
    command -v cc >/dev/null 2>&1 || die_broken "cc not installed"
    command -v lefthook >/dev/null 2>&1 || die_broken "lefthook not installed - the visibility red leg needs it"
    tmp=${TMPDIR:-/tmp}/gate-selftest.$$
    mkdir -p "$tmp" || die_broken "cannot create $tmp"
    fails=0
    expect() { # name expected actual
        if [ "$2" = "$3" ]; then echo "ok   $1 (rc=$3)"; else echo "FAIL $1: expected rc=$2, got rc=$3"; fails=$((fails + 1)); fi
    }

    outer_out=$OUT   # same reason as in gate_all: OUT is read once, so each leg sets it
    here=$(cd "$(dirname "$0")" && pwd)
    cc -o "$tmp/single" "$here/toy_single_op.c" || die_broken "toy_single_op.c did not compile"
    cc -o "$tmp/multi" /repo/spike/toys/toy.c || die_broken "toy.c did not compile"

    # --- the single-op toy: visible, one kill point, no threads
    mkdir -p "$tmp/single-state"
    TOY_STATE="$tmp/single-state" "$tmp/single" init >/dev/null 2>&1 || die_broken "single init failed"
    OUT="$tmp/o1" gate_visibility "$tmp/single-state" -- env "TOY_STATE=$tmp/single-state" "$tmp/single" rotate >"$tmp/l1" 2>&1
    expect "visibility green on a libc-routed toy" 0 $?
    TOY_STATE="$tmp/single-state" "$tmp/single" init >/dev/null 2>&1
    OUT="$tmp/o2" gate_interior "$tmp/single-state" -- env "TOY_STATE=$tmp/single-state" "$tmp/single" rotate >"$tmp/l2" 2>&1
    expect "interior RED on a one-operation toy" 1 $?
    TOY_STATE="$tmp/single-state" "$tmp/single" init >/dev/null 2>&1
    OUT="$tmp/o3" gate_threads "$tmp/single-state" -- env "TOY_STATE=$tmp/single-state" "$tmp/single" rotate >"$tmp/l3" 2>&1
    expect "threads green on a toy with one writing thread" 0 $?

    # --- the repository's own toy: four kill points, so interior must be green
    mkdir -p "$tmp/multi-state"
    TOY_STATE="$tmp/multi-state" "$tmp/multi" init >/dev/null 2>&1 || die_broken "multi init failed"
    OUT="$tmp/o4" gate_interior "$tmp/multi-state" -- env "TOY_STATE=$tmp/multi-state" "$tmp/multi" rotate >"$tmp/l4" 2>&1
    expect "interior green on a four-operation toy" 0 $?

    # --- threads red: TWO threads writing inside the state root.
    #
    # Not "a process that starts a thread": an interpreter's own startup thread is one,
    # and this gate stopped counting those when it was measured against overcommit (see
    # gate_threads' header). The red this gate now claims is two writers, so that is what
    # the red leg has to be — and the green leg above is a single writer in a process that
    # creates no thread at all, which is the other end of the same range.
    mkdir -p "$tmp/thr"
    OUT="$tmp/o5" gate_threads "$tmp/thr" -- env "R=$tmp/thr" python3 -c 'import threading, os
r = os.environ["R"]
def w(n):
    with open(os.path.join(r, n), "w") as f:
        f.write(n)
ts = [threading.Thread(target=w, args=(str(i),)) for i in range(2)]
for t in ts: t.start()
for t in ts: t.join()' >"$tmp/l5" 2>&1
    expect "threads RED on two threads writing the state root" 1 $?

    # --- the root's boundary: writes to a SIBLING are not writes inside the root.
    #
    # This leg exists because the first version matched the root as a bare substring, so
    # `<root>.staging` counted as in-root — and the green leg above stages at exactly that
    # name, which made the error invisible in the one place it was already happening. Two
    # threads writing two siblings must count 0 writers; under the old match they counted 2
    # and this leg is red.
    mkdir -p "$tmp/edge" "$tmp/edge/root"
    OUT="$tmp/o7" gate_threads "$tmp/edge/root" -- env "R=$tmp/edge/root" python3 -c 'import threading, os
r = os.environ["R"]
def w(n):
    with open(r + n, "w") as f:      # r + n, NOT r + "/" + n: a sibling of the root
        f.write(n)
ts = [threading.Thread(target=w, args=(s,)) for s in (".staging", ".tmp")]
for t in ts: t.start()
for t in ts: t.join()' >"$tmp/l7" 2>&1
    expect "threads green when two threads write SIBLINGS of the root" 0 $?

    # --- a thread that only PRINTS the root's path is not a writer.
    #
    # The first version applied its `write` test to the whole line, so
    # `write(1</dev/pts/0>, "installing <root>/pre-commit")` counted — a thread that logged
    # became a writer. Two threads printing the path and writing nothing must count 0.
    mkdir -p "$tmp/log/root"
    OUT="$tmp/o8" gate_threads "$tmp/log/root" -- env "R=$tmp/log/root" python3 -u -c 'import threading, os, sys
r = os.environ["R"]
def w(n):
    sys.stdout.write("installing " + r + "/" + n + "\n"); sys.stdout.flush()
ts = [threading.Thread(target=w, args=(s,)) for s in ("a", "b")]
for t in ts: t.start()
for t in ts: t.join()' >"$tmp/l8" 2>&1
    expect "threads green when two threads only PRINT paths under the root" 0 $?

    # --- visibility red: lefthook, the target the previous run admitted
    mkdir -p "$tmp/lh-repo"
    ( cd "$tmp/lh-repo" && git init -q . && git config user.email t@example.com && git config user.name t \
      && printf 'pre-commit:\n  commands:\n    noop:\n      run: "true"\n' > lefthook.yml ) || die_broken "could not seed the lefthook repo"
    OUT="$tmp/o6" gate_visibility "$tmp/lh-repo/.git/hooks" -- env -C "$tmp/lh-repo" lefthook install >"$tmp/l6" 2>&1
    expect "visibility RED on lefthook (the 2026-09-21 release-path target)" 1 $?

    echo
    OUT=$outer_out
    echo "gate: $fails case(s) failed of 8"
    for f in 1 2 3 4 5 6 7 8; do echo "--- leg $f ---"; tail -3 "$tmp/l$f"; done
    [ "$fails" = 0 ] || return 1
    echo "gate: selftest green"
    return 0
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    visibility) shift; gate_visibility "$@"; exit $? ;;
    interior)   shift; gate_interior "$@";   exit $? ;;
    threads)    shift; gate_threads "$@";    exit $? ;;
    all)        shift; gate_all "$@";        exit $? ;;
    *)
        awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
        exit 2 ;;
esac
