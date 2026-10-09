#!/bin/sh
# Copied for the 2026-10-09 follow-ups 4 waves from 2026-10-07's: the box name (sideeye-fu4-1009) and
# the next sentences v1.10.0 added (ADR 0097), each named at its row below.
# The entry gate for the 2026-09-28 shipped-v170 run, answered by EXIT CODE.
# Copied from the 2026-09-22 shipped-v160 run's entry.sh, with two changes, both named below.
#
#   sh entry.sh <define-dir>        # reads <define-dir>/sideeye.toml and <define-dir>/seed.sh
#
# Runs inside the sideeye-fu4-1009 box, `--network none`, privileged with its own cgroup namespace
# (the containment --observe supervised needs). Prints one row and exits with the gate's
# answer: 0 clear, 1 red, 2 could not measure — ADR 0085's three values, with 2 never folded
# into 1 — plus 3, which is not a gate answer: "the define is wrong; fix it and run the gate
# again", counted in the adoption record. Visibility and interior are answered by the installed
# engine's own `sideeye preflight --twice --oracle` (ADR 0085, amended 2026-09-22).
#
# preflight's exit is NOT passed through: its 2 is "refused", the gate's 2 is "could not
# measure". The refusal is read by its `next` sentence, which is a fixed string
# (src/contract.zig, NextStep.render), and mapped:
#
#   0 accepted, N >= 2 operations          -> 0
#   0 accepted, N < 2                      -> 1 interior (a contrast case, not a wall)
#   1 --twice: the two runs' bytes differ  -> 1 byte-repeatability
#   2 next names --observe syscalls        -> 0, marked FOLLOW: explore meets it and follows it once
#   2 next is a class wall / boundary      -> 1, the detector named
#   2 next is "Change the define" / not an image / narrow the state
#                                          -> DEFINE: the define is fixed and the gate re-run;
#                                             counted in adoption, never a red
#   2 next is the environment / the shim pair / retry
#                                          -> 2
#   3 SETUP ERROR                          -> DEFINE when the message is the define's, else 2
#   anything unmapped                      -> 2, loudly
#
# Change 1 — no threads question. ADR 0085's 2026-09-26 amendment drops it ("a run that copies
# the file forward removes the threads block"): after an accepted preflight the engine has asked
# its own thread rule of both recorded runs.
#
# Change 2 — static linkage is no longer a red by itself. v1.7.0 ships `--observe supervised`,
# which counts a statically linked target from outside the process (ADR 0089). A static image
# is now asked twice, and both answers are kept:
#   - first, preflight in the page's mode (no --observe), recorded as `<name>.preflight-default.txt`
#     with its reason and its `next` sentence — what a user following the page is told;
#   - then preflight --observe supervised, which is the answer mapped by the table above, the
#     row marked SUPERVISED so explore runs in that mode.
# The static answer stays in the row (static=1), so the funnel can still count static targets.
#
# Every engine invocation is preceded by the define's seed.sh, which rebuilds the state and
# anything the operation needs outside it: `--twice` puts back only `--state`.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
def=${1:?usage: entry.sh <define-dir>}
toml="$def/sideeye.toml"; seed="$def/seed.sh"
name=$(basename "$def")
SE=$(cat /install.path)
OUT=${OUT:-/out/entry}; mkdir -p "$OUT"
tx="$OUT/$name.preflight.txt"

row() { echo "ROW $name static=$1 preflight_rc=$2 gate=$3 detail=$4"; }
reset() { sh "$seed" > "$OUT/$name.seed.log" 2>&1 || { row - - 2 "seed.sh failed"; exit 2; }; }

{ "$SE" version; echo "engine path: $SE"; grep -E 'digest matches|sideeye ' /install.log; } > "$OUT/$name.engine.txt"

# 2026-10-09: a define in the argv form (an argument with a space, mcaselector's query) cannot be
# spelled as flags; since v1.9.0 `preflight --config` reads the toml as explore does (#704,
# ADR 0094), so such a define is handed over as --config, and the operation's first word and the
# cwd are read from the toml for the static question below.
argv_form=0
if flags=$(python3 "$here/toml2flags.py" "$toml" 2>/dev/null); then
    op=$(printf '%s\n' "$flags" | awk 'p{print; exit} $0=="--operation"{p=1}')
    cwd=$(printf '%s\n' "$flags" | awk 'p{print; exit} $0=="--cwd"{p=1}')
else
    argv_form=1
    op=$(python3 -c 'import sys,tomllib; d=tomllib.loads(open(sys.argv[1]).read())["define"]; o=d["operation"]; print(o[0] if isinstance(o,list) else o.split()[0])' "$toml") || { row - - 2 "the define could not be read"; exit 2; }
    cwd=$(python3 -c 'import sys,tomllib,os; d=tomllib.loads(open(sys.argv[1]).read())["define"]; c=d.get("cwd",""); print(c if (not c or os.path.isabs(c)) else os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), c)))' "$toml")
    flags=$(printf -- '--config\n%s\n' "$toml")
fi

# --- static: the operation's first word, resolved the way the engine will exec it
reset
img=${op%% *}
# A bare name is looked up on PATH, which does not depend on cwd; only a relative path with a
# slash is resolved against it. So a cwd that does not exist reaches preflight, whose answer
# for it is the one being mapped.
case "$img" in
    /*) : ;;
    */*) img="${cwd:-/}/$img" ;;
    *) img=$(command -v "$img") || { row - - 2 "operation image '${op%% *}' not found"; exit 2; } ;;
esac
finfo=$(file -bL "$img")
echo "static: $img: $finfo" > "$OUT/$name.static.txt"
static=0
case "$finfo" in *"statically linked"*|*"static-pie"*) static=1 ;; esac

set --
while IFS= read -r l; do set -- "$@" "$l"; done <<EOF
$flags
EOF

# --- static only: the page's mode first, kept as what a user is told
if [ "$static" = 1 ]; then
    reset
    "$SE" preflight "$@" --twice --oracle "${ORACLE:-/usr/bin/strace}" > "$OUT/$name.preflight-default.txt" 2>&1
    drc=$?
    dreason=$(sed -n 's/^UNKNOWN  *//p;s/^SETUP ERROR  *//p' "$OUT/$name.preflight-default.txt" | head -1)
    dnext=$(sed -n 's/^next  *//p' "$OUT/$name.preflight-default.txt" | head -1)
    { echo "default mode: rc $drc; $dreason"; echo "default next: $dnext"; } >> "$OUT/$name.static.txt"
    set -- "$@" --observe supervised
fi

# --- preflight, the installed engine's own answer (under supervised for a static image)
reset
"$SE" preflight "$@" --twice --oracle "${ORACLE:-/usr/bin/strace}" > "$tx" 2>&1
prc=$?
next=$(sed -n 's/^next  *//p' "$tx" | head -1)
reason=$(sed -n 's/^UNKNOWN  *//p;s/^SETUP ERROR  *//p' "$tx" | head -1)
gate=2; detail="unmapped preflight answer (rc $prc)"
case "$prc" in
    0)
        n=$(sed -n 's/.*recording accepted — \([0-9][0-9]*\) state-changing.*/\1/p' "$tx" | head -1)
        case "$(grep -c 'nothing to explore' "$tx")" in [1-9]*) n=0 ;; esac
        if [ -z "$n" ]; then gate=2; detail="accepted, but no operation count printed"
        elif [ "$n" -ge 2 ]; then gate=0; detail="accepted, $n operations"
        else gate=1; detail="interior: $n operation(s)"; fi ;;
    1) gate=1; detail="byte-repeatability: --twice found different bytes" ;;
    2)
        case "$next" in
            "Run explore or preflight again with --observe syscalls"*) gate=0; detail="FOLLOW --observe syscalls ($reason)" ;;
            "Run the same command again with --observe supervised"*) gate=0; detail="FOLLOW --observe supervised ($reason)" ;;
            # v1.10.0 (ADR 0097): multiple_threads_detected names the README's threads limit in
            # its own sentence ("Two threads of one process wrote ...") instead of the class wall's;
            # the second run of --twice ending differently has its own too ("The second run
            # started from the state the restore rebuilt ...", the mode bits #678 records). Both
            # are red, the detector named.
            "This target does something Sideeye refuses by design"*|"Check whether the operation is a shell script wrapping"*|"Re-run with --oracle <strace> on Linux, the witness"*|"Two threads of one process wrote the judged directory"*|"The second run started from the state the restore rebuilt"*)
                gate=1; detail="wall: $reason" ;;
            # v1.10.0 (ADR 0097): recording_run_failed on an undeclared exit status, or on a
            # signal, says to run the operation by hand and then --expect-status -- a define fix
            # where v1.9.0 said "Change the define".
            "Change the define"*|"What was read at operation is not something the loader"*|"Point --state at a smaller"*|"Add cwd = "*|"Run the operation once by hand"*|"Make the interpreter the detail above names"*)
                gate=DEFINE; detail="define: $reason" ;;
            # v1.9.0 (ADR 0091): a recording with no crash point is refused nothing_could_fail
            # where v1.8.0 accepted it saying "nothing to explore" -- the same interior answer.
            # v1.10.0 (ADR 0097): that refusal's next step says to declare a check or a marker
            # ("The built-in invariant judges only paths ..." / "No crash point changed a path ...").
            "The operation changed nothing in the state directory that the verdict judges"*|"The built-in invariant judges only paths that exist both before and after"*|"No crash point changed a path the built-in invariants judge"*)
                gate=1; detail="interior: 0 operations ($reason)" ;;
            "Fix what the detail above names in the environment"*|"Check that --shim"*|"Use the shim and the engine"*|"Re-run once;"*|"An entry this user cannot read"*|"Wait for whatever the target left running"*|"Start the exploration from a process that stays alive"*|"Nothing in the define fixes this"*)
                gate=2; detail="environment: $reason" ;;
        esac ;;
    3)
        # A substring match, and loose: a spawn failure whose detail names the operation would
        # read DEFINE, not 2.
        case "$reason" in
            *"cwd could not be resolved"*|*"define"*|*"--state"*|*"operation"*) gate=DEFINE; detail="define: $reason" ;;
            *) gate=2; detail="setup: $reason" ;;
        esac ;;
esac
echo "next: $next" >> "$OUT/$name.static.txt"
[ "$static" = 1 ] && detail="SUPERVISED; $detail"

row "$static" "$prc" "$gate" "$detail"
case "$gate" in 0) exit 0 ;; 1) exit 1 ;; DEFINE) exit 3 ;; *) exit 2 ;; esac
