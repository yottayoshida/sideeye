#!/bin/sh
# How many of a run's crash points lead to the same observable outcome.
#
# The report names two crash points at most -- the earliest violating world and the
# earliest world whose violation includes the checker -- so nothing committed says what the
# other worlds produced. This re-materialises every world of one define from outside the
# engine, with the environment the `reproduce` line a FAIL report prints (the shim inserted,
# `SIDEEYE_KILL_AT=k`), built from the define `measure-targets.sh` wrote -- so it works for
# PASS defines too, which print no such line.
#
#   sh spike/explore-cost/collapse.sh <rundir>/<target>      # written by measure-targets.sh
#
# For k in 1..crash_points it rebuilds the pre-state by running the define's `setup`, runs
# the operation killed at k, checks from the trace that the kill landed in front of
# operation k, and records the digest of the whole state tree, the paths that differ from
# the pre-state, and the checker's exit status and first line.
#
# Three groupings are printed, because "the same outcome" has more than one defensible reading:
#
#   strict  -- byte-identical state trees and the same checker exit and first line. What
#              cannot be established as equivalent stays distinct.
#   coarse  -- the same set of changed paths and the same checker exit and first line. The
#              reading a maintainer-facing consequence would take; it merges worlds whose
#              files differ only in their bytes.
#   coarse, pid-shaped temp names hidden -- as coarse, with a temporary file's name read
#              without the process id in it. A tool that names its temporaries after its
#              pid (timewarrior's `undo.data.59032-3.tmp`) gets a new name in every world,
#              because every world is a new process, and plain coarse counts each one as its
#              own outcome. The engine does not treat such paths as identity either -- the
#              case prefix hash hashes operation classes and not paths, "pid-embedded temp
#              names" being its stated reason (`src/case.zig`). The pattern is narrow on
#              purpose, `<name>.<3+ digits>-<digits>.tmp`: a random mkstemp suffix is not
#              recognised, and the plain coarse count stays the conservative one.
#
# How this differs from the engine, said here so the record can repeat it:
#
# - The pre-state is rebuilt by running `setup` again, where the engine restores a snapshot
#   (whose own report line says restore does not reproduce ownership, permissions or
#   timestamps). Setup is not guaranteed to write the same bytes twice; world 1 -- killed
#   before any counted operation -- is the check, and its tree equals the pre-state digest
#   in every define this was run on.
# - `setup` and `check` run through `sh -c`; the operation is split on spaces and exec'd
#   directly, as the engine does (ADR 0019). On macOS that difference is not optional:
#   /bin/sh is a platform binary, so an operation run through it has dyld drop the insert
#   before the target starts. That was measured here first, as five identical worlds and an
#   operation that exited 0 because no kill ever landed.
# - A `reproduce` line re-creates a crash point, not a whole world, when the run awaited a
#   writing child (the note beside it in `src/main.zig` says so). This inherits that limit.
# - It does not judge. The built-in invariants live in the engine and are not reachable from
#   a shell, so a world's L0/L1 verdict is not part of any grouping.
#
# A world whose trace does not show the kill landing at k is printed with `landed` set to
# what the trace showed instead, and is left out of every grouping, with the count said.
set -u
[ $# -ge 1 ] || { echo "usage: collapse.sh <rundir>/<target>" >&2; exit 2; }
D=$1
[ -f "$D/define.env" ] || { echo "collapse.sh: $D/define.env is missing (run measure-targets.sh first)" >&2; exit 2; }
[ -f "$D/report.json" ] || { echo "collapse.sh: $D/report.json is missing" >&2; exit 2; }
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
case "$(uname -s)" in
    Darwin) SHIM="$ROOT/zig-out/lib/libsideeye_shim.dylib"; INSERT=DYLD_INSERT_LIBRARIES ;;
    *)      SHIM="$ROOT/zig-out/lib/libsideeye_shim.so";    INSERT=LD_PRELOAD ;;
esac

# shellcheck disable=SC1091
. "$D/define.env"
[ -n "${TOY_STATE:-}" ] && export TOY_STATE
[ -n "${TIMEWARRIORDB:-}" ] && export TIMEWARRIORDB
N=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["crash_points"])' "$D/report.json")
[ "$N" -ge 1 ] || { echo "collapse.sh: the report counted $N crash points; nothing to walk" >&2; exit 2; }

# Emptying a directory without shelling out to `rm -rf`: this host's guard against
# recursive deletes intercepts that spelling, and a measurement should not be the thing
# that argues with it. The path is checked against the run directory first, which is a
# check `rm -rf` never had -- the engine's own `assertSafeRoot` is the same idea.
wipe() {
    python3 - "$1" "$D" <<'WIPE'
import os, shutil, sys
target, base = (os.path.realpath(p) for p in sys.argv[1:3])
if target != base and not target.startswith(base + os.sep):
    sys.exit('collapse.sh: refusing to remove %s -- outside %s' % (target, base))
shutil.rmtree(target, ignore_errors=True)
WIPE
}

# landed <trace> <k> -> "ok", or what the trace showed instead. The trace format is the
# contract's (`src/contract.zig`, `encodeHeader` / `encodeRecord`): an 8-byte magic and a
# little-endian u32 version, then records of u16 op, u32 seq, u32 pid, u64 tid, a
# u32-length path and a u32-length aux. The shim writes a `kill_landed` record (op 901)
# carrying the number it was killed in front of; the engine refuses a world where that
# number is not k (`kill_did_not_land`), and so does this.
landed() {
    python3 - "$1" "$2" <<'LANDED'
import struct, sys
path, k = sys.argv[1], int(sys.argv[2])
try:
    b = open(path, "rb").read()
except OSError:
    print("no-trace"); sys.exit()
if len(b) < 12 or b[:8] != b"SIDEEYE1":
    print("no-header"); sys.exit()
i, seqs = 12, []
while i + 22 <= len(b):
    op, seq, _pid, _tid, plen = struct.unpack_from("<HIIQI", b, i)
    i += 22 + plen
    if i + 4 > len(b):
        break
    i += 4 + struct.unpack_from("<I", b, i)[0]
    if op == 901:
        seqs.append(seq)
print("ok" if seqs == [k] else ("none" if not seqs else "at-" + "+".join(map(str, seqs))))
LANDED
}

digest() {  # digest <dir> <paths-file> -> tree digest; one "path digest" line per file to <paths-file>
    python3 - "$1" "$2" <<'PY'
import hashlib, os, sys
root, out = sys.argv[1], sys.argv[2]
lines = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    for fn in sorted(filenames):
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, root)
        try:
            with open(p, "rb") as fh:
                h = hashlib.sha256(fh.read()).hexdigest()[:16]
        except OSError:
            h = "unreadable"
        lines.append("%s %s" % (rel, h))
with open(out, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + ("\n" if lines else ""))
print(hashlib.sha256("\n".join(lines).encode()).hexdigest()[:16])
PY
}

OUT=$D/collapse
wipe "$OUT"
mkdir -p "$OUT"
echo "# collapse: $(basename "$D"), $N crash points, $(uname -sm), $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo untracked)"
echo "# operation: $OP"
echo "# checker: ${CHECK:-(none)}"

# The pre-state: what `setup` leaves, before any operation. Every world is compared with
# this one, so a changed path means changed by the killed operation.
wipe "$SD"; mkdir -p "$SD"
sh -c "$SETUP" >"$OUT/setup.txt" 2>&1 || { echo "collapse.sh: setup failed, see $OUT/setup.txt" >&2; exit 2; }
pre=$(digest "$SD" "$OUT/pre.paths")
echo "# pre-state digest: $pre"
echo ""
printf '%-4s %-4s %-6s %-18s %-8s %-28s %s\n' k rc landed tree checker changed diagnostic

k=1
while [ "$k" -le "$N" ]; do
    wipe "$SD"; mkdir -p "$SD"
    sh -c "$SETUP" >/dev/null 2>&1 || { echo "collapse.sh: setup failed at k=$k" >&2; exit 2; }
    # In a subshell whose own stderr is closed: the operation dies of SIGKILL every time,
    # which is the point, and the shell would otherwise print `Killed: 9` for each world.
    # shellcheck disable=SC2086
    set -- $OP
    ( env "SIDEEYE_STATE_DIR=$SD" "SIDEEYE_TRACE_PATH=$OUT/trace-$k.bin" \
        "$INSERT=$SHIM" "SIDEEYE_KILL_AT=$k" "SIDEEYE_SEQ_BASE=" \
        "$@" >"$OUT/op-$k.txt" 2>&1 ) 2>/dev/null
    rc=$?
    land=$(landed "$OUT/trace-$k.bin" "$k")
    tree=$(digest "$SD" "$OUT/w$k.paths")
    # The changed paths by name, each marked + (added), - (removed) or ~ (bytes differ).
    changed=$(python3 - "$OUT/pre.paths" "$OUT/w$k.paths" <<'PY'
import sys
def read(p):
    out = {}
    with open(p, encoding="utf-8") as fh:
        for line in fh:
            rel, _, h = line.rstrip("\n").rpartition(" ")
            out[rel] = h
    return out
a, b = read(sys.argv[1]), read(sys.argv[2])
marks = []
for n in sorted(set(a) | set(b)):
    if n not in a:
        marks.append("+" + n)
    elif n not in b:
        marks.append("-" + n)
    elif a[n] != b[n]:
        marks.append("~" + n)
print(",".join(marks) if marks else "(none)")
PY
    )
    # The same list with a pid-shaped temporary name read without its pid (see the header).
    hidden=$(printf '%s' "$changed" | sed -E 's/\.[0-9]{3,}-([0-9]+)\.tmp(,|$)/.<pid>-\1.tmp\2/g')
    if [ -n "${CHECK:-}" ]; then
        sh -c "$CHECK" >"$OUT/check-$k.txt" 2>&1
        crc=$?
        msg=$(head -1 "$OUT/check-$k.txt" | cut -c1-60)
    else
        crc="-"; msg=""
    fi
    printf '%-4s %-4s %-6s %-18s %-8s %-28s %s\n' "$k" "$rc" "$land" "$tree" "$crc" "$changed" "$msg"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$k" "$rc" "$land" "$tree" "$crc" "$changed" "$msg" "$hidden" >> "$OUT/rows.tsv"
    k=$((k + 1))
done

echo ""
python3 - "$OUT/rows.tsv" <<'PY'
import collections, sys
rows, unlanded = [], []
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        k, rc, land, tree, crc, changed, msg, hidden = (line.rstrip("\n").split("\t") + [""] * 8)[:8]
        (rows if land == "ok" else unlanded).append((int(k), tree, crc, changed, msg, land, hidden))
print("kill landed at k in %d of %d worlds" % (len(rows), len(rows) + len(unlanded)))
for k, _t, _c, _ch, _m, land, _h in unlanded:
    print("   left out of every grouping: k=%d (trace shows %s)" % (k, land))
strict = collections.OrderedDict()
coarse = collections.OrderedDict()
hidden_pid = collections.OrderedDict()
for k, tree, crc, changed, msg, _land, hidden in rows:
    strict.setdefault((tree, crc, msg), []).append(k)
    coarse.setdefault((changed, crc, msg), []).append(k)
    hidden_pid.setdefault((hidden, crc, msg), []).append(k)
def show(name, groups):
    print("%s: %d distinct outcome(s) over %d crash points" % (name, len(groups), len(rows)))
    for key, ks in groups.items():
        print("   x%-3d k=%-24s %s" % (len(ks), ",".join(str(k) for k in ks), "  ".join(x for x in key if x)))
print()
show("strict (byte-identical tree + checker exit and first line)", strict)
print()
show("coarse (same changed paths + checker exit and first line)", coarse)
print()
show("coarse, pid-shaped temp names hidden", hidden_pid)
PY
echo ""
echo "# per-world path digests, traces, engine output and checker output under $OUT/"
