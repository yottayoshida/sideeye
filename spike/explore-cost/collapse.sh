#!/bin/sh
# How many of a run's crash points lead to the same observable outcome.
#
# The report names two crash points at most -- the earliest violating world and the
# earliest world whose violation includes the checker -- so nothing committed says what the
# other worlds produced. This re-materialises every world of one define from outside the
# engine, through the `reproduce` line the FAIL report itself prints, and groups them.
#
#   sh spike/explore-cost/collapse.sh <rundir>/<target>      # written by measure-targets.sh
#
# For k in 1..crash_points it rebuilds the pre-state with the define's `setup`, runs the
# operation under the shim with `SIDEEYE_KILL_AT=k`, and records three things about the
# world that leaves: the digest of the whole state tree, the set of paths that differ from
# the pre-state, and the checker's exit status and first line. The engine is not involved
# in the judging here; the point is to see the worlds it does not report.
#
# Two groupings are printed, because "the same outcome" has two defensible readings and
# they answer different halves of the question:
#
#   strict  -- byte-identical state trees (and the same checker result). Two worlds that
#              differ by one byte are two outcomes. This is the conservative reading the
#              measurement is asked for: what cannot be established as equivalent stays
#              distinct.
#   coarse  -- the same set of changed paths and the same checker exit and first line. This
#              is the reading a maintainer-facing consequence would take. It merges worlds
#              whose file differs only in how far a write got.
#
# The gap between the two counts is the finding, not either number alone.
#
# What this does not do: it does not judge. A world here has no L0/L1 verdict -- the
# built-in invariants live in the engine and are not reachable from a shell -- so `checker`
# is the only invariant column, and a define with no checker is grouped on state alone. It
# also cannot see a world the engine would have refused.
# The define's commands are run through `sh -c`, one line each, where the engine splits
# them on spaces and execs the result (ADR 0019). For the defines measured here the two
# agree -- none of them carries a quote, a glob or a redirection -- and a define that
# needed the argv form could not be re-materialised by this harness at all.
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

OUT=$D/collapse
wipe "$OUT"
mkdir -p "$OUT"
echo "# collapse: $(basename "$D"), $N crash points, $(uname -sm), $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo untracked)"
echo "# operation: $OP"
echo "# checker: ${CHECK:-(none)}"

digest() {  # digest <dir> -> "<tree digest> <per-path digest lines to file $2>"
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

# The pre-state: what `setup` leaves, before any operation. Every world is compared with
# this one, so a "changed path" means changed by the killed operation.
wipe "$SD"; mkdir -p "$SD"
sh -c "$SETUP" >"$OUT/setup.txt" 2>&1 || { echo "collapse.sh: setup failed, see $OUT/setup.txt" >&2; exit 2; }
pre=$(digest "$SD" "$OUT/pre.paths")
echo "# pre-state digest: $pre"
echo ""
printf '%-4s %-4s %-18s %-18s %-8s %s\n' k rc tree changed-paths checker diagnostic

k=1
while [ "$k" -le "$N" ]; do
    wipe "$SD"; mkdir -p "$SD"
    sh -c "$SETUP" >/dev/null 2>&1 || { echo "collapse.sh: setup failed at k=$k" >&2; exit 2; }
    # The operation is split on spaces and exec'd directly, which is what the engine does
    # (ADR 0019) and what macOS forces: /bin/sh is a platform binary, so running the
    # operation through `sh -c` has dyld drop DYLD_INSERT_LIBRARIES before the target
    # starts -- measured here first, as five identical worlds and an operation that exited
    # 0 because no kill ever landed.
    # shellcheck disable=SC2086
    set -- $OP
    # In a subshell whose own stderr is closed: the operation dies of SIGKILL every time,
    # which is the point, and the shell would otherwise print `Killed: 9` for each world
    # over the table being built.
    ( env "SIDEEYE_STATE_DIR=$SD" "SIDEEYE_TRACE_PATH=$OUT/trace-$k.bin" \
        "$INSERT=$SHIM" "SIDEEYE_KILL_AT=$k" "SIDEEYE_SEQ_BASE=" \
        "$@" >"$OUT/op-$k.txt" 2>&1 ) 2>/dev/null
    rc=$?
    tree=$(digest "$SD" "$OUT/w$k.paths")
    changed=$(python3 - "$OUT/pre.paths" "$OUT/w$k.paths" <<'PY'
import hashlib, sys
def read(p):
    out = {}
    with open(p, encoding="utf-8") as fh:
        for line in fh:
            rel, _, h = line.rstrip("\n").rpartition(" ")
            out[rel] = h
    return out
a, b = read(sys.argv[1]), read(sys.argv[2])
names = sorted(set(a) | set(b))
diff = [n for n in names if a.get(n) != b.get(n)]
print(hashlib.sha256("\n".join(diff).encode()).hexdigest()[:16] if diff else "(none)")
PY
    )
    if [ -n "${CHECK:-}" ]; then
        sh -c "$CHECK" >"$OUT/check-$k.txt" 2>&1
        crc=$?
        msg=$(head -1 "$OUT/check-$k.txt" | cut -c1-60)
    else
        crc="-"; msg=""
    fi
    printf '%-4s %-4s %-18s %-18s %-8s %s\n' "$k" "$rc" "$tree" "$changed" "$crc" "$msg"
    echo "$k	$rc	$tree	$changed	$crc	$msg" >> "$OUT/rows.tsv"
    k=$((k + 1))
done

echo ""
python3 - "$OUT/rows.tsv" <<'PY'
import collections, sys
rows = []
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        k, rc, tree, changed, crc, msg = (line.rstrip("\n").split("\t") + [""])[:6]
        rows.append((int(k), rc, tree, changed, crc, msg))
strict = collections.OrderedDict()
coarse = collections.OrderedDict()
for k, rc, tree, changed, crc, msg in rows:
    strict.setdefault((tree, crc), []).append(k)
    coarse.setdefault((changed, crc, msg), []).append(k)
def show(name, groups):
    print("%s: %d distinct outcome(s) over %d crash points" % (name, len(groups), len(rows)))
    for key, ks in groups.items():
        span = ",".join(str(k) for k in ks)
        print("   x%-3d k=%-24s %s" % (len(ks), span, " ".join(x for x in key if x)))
show("strict (byte-identical tree + checker result)", strict)
print()
show("coarse (same changed paths + checker exit and first line)", coarse)
PY
echo ""
echo "# per-world path digests, engine output and checker output under $OUT/"
