#!/bin/sh
# Campaign 2 Seal A artifact (ADR 0015 §3), added at the re-seal.
#
# Why it exists: the first Seal A froze invocations.tsv and two config files that
# disagreed with it — the configs still named campaign 1's state roots. The sweep's
# verdicts became uninterpretable (an apparatus contradiction wearing a target
# verdict's clothes) and the seal was voided. The pre-seal check that was supposed
# to prevent this looked at command resolution and file existence, which cannot see
# a path INSIDE a config.
#
# What it checks, per invocation row (not globally — a config belonging to one row
# must not be allowed to agree with a different row's state root; campaign-2 R1):
#
#   every absolute /tmp path appearing in a config file that ROW references must lie
#   under (or be) that row's state root, comparing normalized paths, with `..`
#   rejected outright rather than resolved.
#
# Strictly "under": a parent of the state root does NOT pass. Watching a directory
# above the observed state means the config can name state the sweep never sees,
# which is the disagreement class this check exists to refuse.
#
# Config files are discovered from the row itself: any argument of the setup or
# operation command that names a readable file inside the campaign's configs/
# directory. A row referencing no config file is vacuously consistent, and that is
# reported rather than passed over in silence.
#
# It is deliberately narrow: it does not validate config syntax or semantics, only
# the one cross-file agreement whose absence has already cost a seal.
#
# Usage: check-config-paths.sh [<campaign-dir>]   (default: this script's dir)
# Exit:  0 consistent / 1 inconsistent / 2 usage, unreadable input, or nothing to look at
set -u

[ $# -le 1 ] || {
    echo "usage: check-config-paths.sh [<campaign-dir>]" >&2
    exit 2
}
dir=${1:-$(dirname "$0")}
inv=$dir/invocations.tsv
cfg=$dir/configs

[ -r "$inv" ] || { echo "check-config-paths: cannot read $inv" >&2; exit 2; }
[ -d "$cfg" ] || { echo "check-config-paths: cannot read $cfg" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || {
    echo "check-config-paths: python3 is required" >&2
    exit 2
}

# Every failure mode below exits 2 rather than 0: a check that could not look must
# not report success (this repo's oldest lesson, and R1 found four ways this script
# could still do it).
python3 - "$inv" "$cfg" <<'PY'
import os, re, sys

inv_path, cfg_dir = sys.argv[1], sys.argv[2]

def die(msg):
    print(f"check-config-paths: {msg}", file=sys.stderr)
    sys.exit(2)

def norm(p):
    # Collapse duplicate slashes and trailing slashes without resolving symlinks.
    # `..` is not resolved but rejected: a sealed config that reaches its state
    # through a parent hop is not the plain agreement this check certifies.
    n = os.path.normpath(p)
    return n

try:
    with open(inv_path, encoding="utf-8") as f:
        raw = f.readlines()
except OSError as e:
    die(f"cannot read {inv_path}: {e}")

rows = []
for lineno, line in enumerate(raw, 1):
    line = line.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    fields = line.split("\t")
    if len(fields) != 5:
        die(f"{inv_path}:{lineno} has {len(fields)} fields, expected 5")
    name, _binary, state, setup, operation = fields
    if not state.startswith("/"):
        die(f"{inv_path}:{lineno} state root {state!r} is not absolute")
    rows.append((lineno, name, norm(state), setup, operation))

if not rows:
    die("invocations.tsv named no rows")

cfg_dir_abs = norm(os.path.abspath(cfg_dir))

def configs_of(setup, operation):
    """Config files this row references: arguments that resolve to a readable
    regular file inside the campaign's configs/ directory."""
    found = []
    for word in (setup.split() + operation.split()):
        if word == "-" or not word.startswith("/"):
            continue
        # The rows address the repo as mounted in the container (/work/...); match
        # on the trailing path so the check works from a checkout too.
        base = os.path.basename(word)
        cand = os.path.join(cfg_dir, base)
        if os.path.isfile(cand) and "/configs/" in word:
            found.append(cand)
    return found

def under(path, root):
    """True iff `path` is `root` or lies strictly beneath it."""
    return path == root or path.startswith(root.rstrip("/") + "/")

bad = 0
checked_files = 0
rows_with_configs = 0

for lineno, name, state, setup, operation in rows:
    files = configs_of(setup, operation)
    if not files:
        print(f"check-config-paths: {name}: no config file referenced (vacuously consistent)")
        continue
    rows_with_configs += 1
    for f in files:
        if not os.path.isfile(f):
            die(f"{f} is not a regular file")
        try:
            with open(f, encoding="utf-8", errors="strict") as fh:
                lines = fh.readlines()
        except (OSError, UnicodeDecodeError) as e:
            die(f"cannot read config {f}: {e}")
        checked_files += 1
        for cl, line in enumerate(lines, 1):
            for m in re.finditer(r"/tmp(?:/[^\s\"',;]*)?", line):
                p = m.group(0)
                if ".." in p.split("/"):
                    print(f"check-config-paths: {f}:{cl}: {p} contains '..'; "
                          f"sealed configs must name their state plainly", file=sys.stderr)
                    bad += 1
                    continue
                if not under(norm(p), state):
                    print(f"check-config-paths: {f}:{cl}: {p} is not under "
                          f"{name}'s state root {state}", file=sys.stderr)
                    bad += 1

if rows_with_configs == 0:
    die("no row referenced a config file; there was nothing to check")
if checked_files == 0:
    die("no config file was read")

print(f"check-config-paths: {checked_files} config file(s) across {rows_with_configs} "
      f"row(s) with configs: " + ("consistent" if bad == 0 else f"{bad} disagreement(s)"))
sys.exit(1 if bad else 0)
PY
