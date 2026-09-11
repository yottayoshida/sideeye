#!/bin/sh
# What the shim takes from a target thread's memory, measured against the bound the README
# states (#555): less than 1 KiB of thread-local storage, and at most 5 KiB of stack for an
# interposed call — plus, under --observe syscalls, the kernel's own signal frame. Linux
# only: toy-stack reads /proc and the auxiliary vector, and the macOS dylib is not measured.
#
# Usage: check-shim-footprint.sh <libsideeye_shim.so> <toy-stack binary>
# Prints one `ok` / `FAIL` line per check and exits with the number of FAILs. acceptance
# calls it with the shipped shim; the same call with an older shim is how each check was
# seen red (BUILDLOG 2026-09-11).
#
# Three checks, because the bound breaks three ways, and each was measured breaking:
#   A  behaviour — a thread of the platform's minimum stack, and the depth a patterned
#      thread reaches, bare and under a recording shim in both modes. A loaded shim once
#      refused that thread outright (std's 256 KiB signal stack in its TLS); a recording
#      shim once killed it on x86_64 (twelve 4 KiB path buffers on its stack). The calls
#      measured are toy-stack's: open, write, pwritev2, close, rename, unlink, mkdir, rmdir
#      and an execve that fails. A call outside that list is held by C, one function at a
#      time, and by nothing for its whole chain.
#   B  thread-local storage — the PT_TLS segment of the built library.
#   C  the largest stack frame of any function of the shim's own, from its disassembly —
#      what A would only see on a CPU and a path it happened to exercise.
set -u
SHIM=$1
TOY=$2
# README: "at most 5 KiB of its stack for an interposed call". The plan's rule: the largest
# share measured over both CPUs and both modes, rounded up to a KiB, plus one — 3,968 bytes
# (aarch64 Debug, syscalls, over the kernel's frame) on 2026-09-11. A Debug build is the
# deep one; the release build measured under 1 KiB.
stack_limit=5120
tls_limit=1024     # README: "less than 1 KiB of thread-local storage"
# Per function. Nothing of the shim's own needs a buffer on the stack any more, and 1 KiB
# is well under the bound a whole interposed call is held to. At the time of writing the
# largest measured frame was 896 bytes (Debug, both architectures); the ones this
# replaced were 4-9 KB.
frame_limit=1024
fails=0
ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# ---- A: behaviour -------------------------------------------------------------------
tmp=$(mktemp -d "${TMPDIR:-/tmp}/shim-footprint.XXXXXX") || { fail "cannot make a scratch directory"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bare" "$tmp/wrappers" "$tmp/syscalls"

val() { printf '%s\n' "$1" | sed -n "s/^$2=\\([0-9]*\\)\$/\\1/p"; }

bare=$("$TOY" "$tmp/bare" 2>&1); rc=$?
bare_depth=$(val "$bare" depth)
if [ "$rc" = 0 ] && printf '%s\n' "$bare" | grep -qx 'shim=no' \
   && printf '%s\n' "$bare" | grep -q '^min=[0-9]* ok$' && [ -n "$bare_depth" ]; then
    ok "toy-stack runs bare: its minimum-stack thread finishes, the patterned one reaches $bare_depth bytes (control)"
else
    fail "the control is broken: toy-stack without the shim exits $rc, so nothing below measures anything"
    printf '%s\n' "$bare" | sed 's/^/     | /'
fi

# What the trace says. `announce=` is the first `shim_ready`'s aux — how the shim set
# itself up, `observe:syscalls` when the filter went up and empty in the default mode —
# and `announce=-` when there was none. Then, per op class, the records written from a
# thread other than the main one: proof the shim was loaded, armed and recording on the
# threads being measured, not merely mapped. The decoder is acceptance's
# count_op_records with the tid and the aux kept; the op numbers are contract.OpClass.
trace_facts() { python3 -c '
import struct, sys
try:
    b = open(sys.argv[1], "rb").read()
except OSError:
    b = b""
names = {1: "open", 2: "write", 3: "rename", 4: "unlink", 7: "mkdir", 8: "rmdir", 201: "exec"}
i, counts, announce = 12, {}, None
while i + 22 <= len(b):
    op, seq, pid, tid, plen = struct.unpack_from("<HIIQI", b, i); i += 22 + plen
    if i + 4 > len(b): break
    (alen,) = struct.unpack_from("<I", b, i); i += 4
    aux = b[i:i + alen]; i += alen
    if op == 900 and announce is None: announce = aux.decode(errors="replace")
    if op in names and tid != pid: counts[op] = counts.get(op, 0) + 1
print("announce=" + ("-" if announce is None else announce))
for op, name in names.items(): print("%s=%d" % (name, counts.get(op, 0)))' "$1"; }

stack_case() { # stack_case <mode>
    d=$tmp/$1
    want_announce=
    if [ "$1" = syscalls ]; then
        want_announce=observe:syscalls
        o=$(env LD_PRELOAD="$SHIM" SIDEEYE_STATE_DIR="$d" SIDEEYE_TRACE_PATH="$d.bin" SIDEEYE_OBSERVE=syscalls "$TOY" "$d" 2>&1); rc=$?
    else
        o=$(env LD_PRELOAD="$SHIM" SIDEEYE_STATE_DIR="$d" SIDEEYE_TRACE_PATH="$d.bin" "$TOY" "$d" 2>&1); rc=$?
    fi
    depth=$(val "$o" depth)
    sig=$(val "$o" sigframe)
    limit=$stack_limit
    no_frame=
    if [ "$1" = syscalls ]; then
        if [ -z "$sig" ] || [ "$sig" = 0 ]; then no_frame=1; else limit=$((stack_limit + sig)); fi
    fi
    facts=$(trace_facts "$d.bin")
    announce=$(printf '%s\n' "$facts" | sed -n 's/^announce=//p')
    short=
    for name in open write rename unlink mkdir rmdir exec; do
        n=$(val "$facts" "$name")
        [ "${n:-0}" -ge 2 ] || short="$short $name ${n:-0}"
    done
    recs=$(printf '%s\n' "$facts" | grep -v '^announce=' | tr '\n' ' ')
    # The order is the order of what can break first: a shim that is not there measures
    # nothing, and one that did not set itself up the way this row names measures the
    # other row — under syscalls the write family is counted by the trap only when the
    # filter went up, and a filter that failed to install leaves the wrappers counting,
    # which passes every line below on the wrappers' numbers (review, #555). Then a thread
    # that never started records nothing, and only then is a missing record the shim's.
    # A kernel that does not report its signal frame leaves the bound alone unmeasured, so
    # that comes last: the first version returned on it before anything else, and the
    # announcement check above never ran under that mode (review, second round).
    if ! printf '%s\n' "$o" | grep -qx 'shim=yes'; then
        fail "$1: the shim is not mapped into toy-stack, so this measured nothing"
    elif [ "$announce" != "$want_announce" ]; then
        fail "$1: the shim announced '$announce' where this mode needs '$want_announce', so this row measured another one"
    elif [ "$rc" -gt 128 ]; then
        fail "$1: toy-stack was killed by signal $((rc - 128)) under the shim and ran to the end without it — the way a thread that overruns its stack dies"
        printf '%s\n' "$o" | sed 's/^/     | /'
    elif ! printf '%s\n' "$o" | grep -q '^min=[0-9]* ok$'; then
        fail "$1: a thread of the minimum stack does not finish under the shim, and did without it: $(printf '%s\n' "$o" | grep '^min=')"
    elif [ -n "$short" ]; then
        fail "$1: the shim did not record the worker threads' work (from threads other than the main one, want 2 of each; short:$short)"
    elif [ -n "$no_frame" ]; then
        fail "$1: the kernel does not report its signal frame size (AT_MINSIGSTKSZ), so the bound cannot be checked"
    elif [ -z "$depth" ] || [ -z "$bare_depth" ]; then
        fail "$1: no depth to compare (exit $rc)"
        printf '%s\n' "$o" | sed 's/^/     | /'
    elif [ $((depth - bare_depth)) -gt "$limit" ]; then
        fail "$1: the shim spent $((depth - bare_depth)) bytes of the thread's stack over the bare run, where the bound is $limit"
    elif [ "$rc" != 0 ]; then
        fail "$1: toy-stack exits $rc under the shim"
        printf '%s\n' "$o" | sed 's/^/     | /'
    else
        ok "$1: the minimum-stack thread finishes under a recording shim, which spent $((depth - bare_depth)) of at most $limit bytes over the bare run (from worker threads: ${recs% })"
    fi
}
stack_case wrappers
stack_case syscalls

# ---- B: thread-local storage -------------------------------------------------------
ph=$(readelf -lW "$SHIM" 2>/dev/null)
if ! printf '%s\n' "$ph" | grep -q '^ *LOAD '; then
    fail "cannot read the shim's program headers (no LOAD line), so its TLS was not measured"
else
    tls_hex=$(printf '%s\n' "$ph" | awk '$1 == "TLS" { print $6; exit }')
    align=$(printf '%s\n' "$ph" | awk '$1 == "TLS" { print $NF; exit }')
    tls=$((${tls_hex:-0}))
    if [ "$tls" -ge "$tls_limit" ]; then
        fail "the shim carries $tls bytes of thread-local storage (align $align), not less than the $tls_limit the README states"
    else
        ok "the shim carries ${tls} bytes of thread-local storage${align:+ (align $align)}, under $tls_limit"
    fi
fi

# ---- C: the largest frame of the shim's own functions --------------------------------
# A function is the shim's own when any name at its address is. GNU objdump labels a
# function by its global name when it has one, so an exported wrapper prints as
# `<rename>`, not `<ops.rename>` (review, #555); nm lists both, and the address joins them.
nm --defined-only "$SHIM" >"$tmp/syms" 2>/dev/null
frames=$(objdump -d --no-show-raw-insn "$SHIM" 2>/dev/null | python3 -c '
import re, sys
# Functions of the shim itself. std'"'"'s own (debug.*, sort.*, compiler_rt.*) have large
# frames on the panic and stack-trace paths only, which end the process either way.
PREFIX = ("common.", "ops.", "syscalls.", "contract.", "shim.", "linux.", "macos.")
own = {}
for line in open(sys.argv[2]):
    f = line.split()
    if len(f) == 3 and f[1] in ("t", "T") and f[2].startswith(PREFIX):
        own[int(f[0], 16)] = f[2]
num = r"#(0x[0-9a-f]+|\d+)"
fn, n, pending, frame, aliased = None, 0, 0, {}, 0
for line in sys.stdin:
    m = re.match(r"^([0-9a-f]+) <(.+)>:$", line.strip())
    if m:
        label = m.group(2)
        fn = own.get(int(m.group(1), 16)) or (label if label.startswith(PREFIX) else None)
        n, pending = 0, 0
        if fn is not None and fn not in frame:
            frame[fn] = 0
            if not label.startswith(PREFIX): aliased += 1
        continue
    if fn is None:
        continue
    n += 1
    if n > 40:
        continue
    # x86_64: `sub $N,%rsp`, or for a frame of a page or more `mov $N,%eax`, a call to the
    # stack probe, and `sub %rax,%rsp`.
    mm = re.search(r"\bsub\s+\$0x([0-9a-f]+),%rsp", line)
    if mm:
        frame[fn] += int(mm.group(1), 16)
    mm = re.search(r"\bmov\s+\$0x([0-9a-f]+),%[er]ax", line)
    if mm:
        pending = int(mm.group(1), 16)
    if re.search(r"\bsub\s+%rax,%rsp", line):
        frame[fn] += pending
    # aarch64: `sub sp, sp, #N` (`, lsl #12` for the page part), `sub x9, sp, #N` for an
    # over-aligned frame, and the pre-indexed `stp …, [sp, #-N]!` that opens most frames.
    mm = re.search(r"\bsub\s+(sp|x\d+),\s*sp,\s*" + num + r"(,\s*lsl\s*#12)?", line)
    if mm:
        frame[fn] += int(mm.group(2), 0) * (4096 if mm.group(3) else 1)
    mm = re.search(r"\[sp,\s*#-(0x[0-9a-f]+|\d+)\]!", line)
    if mm:
        frame[fn] += int(mm.group(1), 0)
seen = sum(1 for v in frame.values() if v > 0)
big = sorted(((v, k) for k, v in frame.items() if v > int(sys.argv[1])), reverse=True)
top = max(frame.values()) if frame else 0
print(len(frame), seen, top, aliased)
for v, k in big:
    print(v, k)' "$frame_limit" "$tmp/syms")
set -- $frames
if [ "${1:-0}" -eq 0 ] || [ "${2:-0}" -eq 0 ]; then
    fail "could not read the shim's functions from its disassembly (${1:-0} named, ${2:-0} with a frame), so no frame was measured"
elif [ "${4:-0}" -eq 0 ]; then
    # Without nm's names the exported wrappers are skipped, and ReleaseSafe inlines the
    # exec carry into one of them — the check would pass on what it did not read.
    fail "no function was read under an exported name (did nm run?), so the exported wrappers were not measured"
elif [ "$(printf '%s\n' "$frames" | wc -l)" -gt 1 ]; then
    fail "functions of the shim's own take more than $frame_limit bytes of stack at once:"
    printf '%s\n' "$frames" | sed '1d; s/^/     | /'
else
    ok "no function of the shim's own takes more than $frame_limit bytes of stack at once ($1 read, $4 of them under an exported name; the largest $3)"
fi

exit "$fails"
