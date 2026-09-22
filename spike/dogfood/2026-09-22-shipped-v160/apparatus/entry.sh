#!/bin/sh
# The entry gate for the 2026-09-22 shipped-v160 run, answered by EXIT CODE.
#
#   sh entry.sh <define-dir>        # reads <define-dir>/sideeye.toml and <define-dir>/seed.sh
#
# Runs inside the sideeye-sv box, `--network none`. Prints one row and exits with the gate's
# answer: 0 clear, 1 red, 2 could not measure — ADR 0085's three values, with 2 never folded
# into 1 — plus 3, which is not a gate answer: "the define is wrong; fix it and run the gate
# again", counted in the adoption record. What changed from that ADR's gate (amended 2026-09-22): visibility and interior are
# answered by the installed engine's own `sideeye preflight --twice --oracle`, not by the
# 2026-08-22 logger, which does not see what the v1.6.0 shim interposes (a mkstemp-based
# atomic replace read red there and is judged here). Static linkage is `file -L` on the
# operation's image, first, because a static target never loads the shim at all.
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
# Threads is the verdict-chain gate's `gate_threads`, unchanged, called through gate.sh.
# Every operation — the static probe, preflight, threads — is preceded by the define's seed.sh,
# which rebuilds the state and anything the operation needs outside it: `--twice` puts back
# only `--state`, and gate.sh reads GATE_RESET only in `all`, not in `threads`.
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

flags=$(python3 "$here/toml2flags.py" "$toml") || { row - - 2 "the define cannot be spelled as flags (argv form)"; exit 2; }
op=$(printf '%s\n' "$flags" | awk 'p{print; exit} $0=="--operation"{p=1}')
cwd=$(printf '%s\n' "$flags" | awk 'p{print; exit} $0=="--cwd"{p=1}')
state=$(printf '%s\n' "$flags" | awk 'p{print; exit} $0=="--state"{p=1}')

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
case "$finfo" in *"statically linked"*|*"static-pie"*) row 1 - 1 "statically linked: $img"; exit 1 ;; esac

# --- preflight, the installed engine's own answer
reset
set --
while IFS= read -r l; do set -- "$@" "$l"; done <<EOF
$flags
EOF
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
            "This target does something Sideeye refuses by design"*|"Check whether the operation is a shell script wrapping"*|"Re-run with --oracle <strace> on Linux, the witness"*)
                gate=1; detail="wall: $reason" ;;
            "Change the define"*|"What was read at operation is not something the loader"*|"Point --state at a smaller"*)
                gate=DEFINE; detail="define: $reason" ;;
            "Fix what the detail above names in the environment"*|"Check that --shim"*|"Use the shim and the engine"*|"Re-run once;"*|"An entry this user cannot read"*|"Wait for whatever the target left running"*)
                gate=2; detail="environment: $reason" ;;
        esac ;;
    3)
        # A substring match, and loose: a spawn failure whose detail names the operation would
        # read DEFINE, not 2. Seen here only on the two legs (badcwd, the missing oracle).
        case "$reason" in
            *"cwd could not be resolved"*|*"define"*|*"--state"*|*"operation"*) gate=DEFINE; detail="define: $reason" ;;
            *) gate=2; detail="setup: $reason" ;;
        esac ;;
esac
echo "next: $next" >> "$OUT/$name.static.txt"

# --- threads: the verdict-chain gate, over the same operation, from the same seed
trc=-
if [ "$gate" = 0 ]; then
    # Seeded here, not by gate.sh (see the header): an operation re-run on preflight's output
    # writes nothing and reads as zero writers — the first gate run read five of seven so.
    # gate.sh keeps its strace log under GATE_OUT (default /tmp/gate-out, inside the box, each
    # define overwriting the last); only its stdout, below, is kept. With no cwd declared this
    # runs in `/`, where preflight uses its own; every operation here names absolute paths, and
    # every threads answer counted at least one writer, so none ran without writing.
    reset
    set --
    for w in $op; do set -- "$@" "$w"; done
    sh "$here/gate.sh" threads "$state" -- env -C "${cwd:-/}" "$@" > "$OUT/$name.threads.txt" 2>&1
    trc=$?
    case "$trc" in 0) : ;; 1) gate=1; detail="$detail; threads: more than one writer" ;; *) gate=2; detail="$detail; threads gate could not measure" ;; esac
fi
row 0 "$prc" "$gate" "$detail; threads=$trc"
case "$gate" in 0) exit 0 ;; 1) exit 1 ;; DEFINE) exit 3 ;; *) exit 2 ;; esac
