#!/bin/sh
# Campaign 2 Seal A artifact (ADR 0015 §3), added at the re-seal.
#
# Why it exists: the first Seal A froze invocations.tsv and two config files that
# disagreed with it — the configs still named campaign 1's state roots. The sweep
# then reported a refusal that looked like a target verdict and was our own
# apparatus. The pre-seal check that was supposed to prevent this looked at
# command resolution and file existence, which cannot see a path INSIDE a config.
#
# What it checks: every absolute /tmp path appearing in any sealed config file
# must lie under (or contain) a state root named in invocations.tsv. A config
# pointing somewhere else is either watching a directory the sweep does not, or
# writing outside the observed state — both make the sweep's verdicts mean
# something other than what the manifest will claim.
#
# It is deliberately narrow: it does not validate config syntax or semantics,
# only the one cross-file agreement whose absence has already cost a seal.
#
# Usage: check-config-paths.sh [<campaign-dir>]   (default: this script's dir)
# Exit:  0 consistent / 1 inconsistent / 2 usage or unreadable input
set -u

dir=${1:-$(dirname "$0")}
inv=$dir/invocations.tsv
cfg=$dir/configs

[ -r "$inv" ] || { echo "check-config-paths: cannot read $inv" >&2; exit 2; }
[ -d "$cfg" ] || { echo "check-config-paths: cannot read $cfg" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || {
    echo "check-config-paths: python3 is required" >&2
    exit 2
}

python3 - "$inv" "$cfg" <<'PY'
import glob, os, re, sys

inv_path, cfg_dir = sys.argv[1], sys.argv[2]

roots = []
with open(inv_path) as f:
    for lineno, line in enumerate(f, 1):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 5:
            print(f"check-config-paths: {inv_path}:{lineno} has {len(fields)} fields, expected 5",
                  file=sys.stderr)
            sys.exit(2)
        roots.append(fields[2])

if not roots:
    # An empty root set would make every config path vacuously fine — the shape
    # where a check reports success because it could not look.
    print("check-config-paths: invocations.tsv named no state roots", file=sys.stderr)
    sys.exit(2)

def agrees(path):
    for r in roots:
        if path == r or path.startswith(r.rstrip("/") + "/") or r.startswith(path.rstrip("/") + "/"):
            return True
    return False

bad = 0
scanned = 0
for f in sorted(glob.glob(os.path.join(cfg_dir, "*"))):
    if not os.path.isfile(f):
        continue
    scanned += 1
    with open(f, errors="replace") as fh:
        for lineno, line in enumerate(fh, 1):
            for m in re.finditer(r"/tmp/[^\s\"',;]+", line):
                p = m.group(0)
                if not agrees(p):
                    print(f"check-config-paths: {f}:{lineno}: {p} is under no invocation state root",
                          file=sys.stderr)
                    bad += 1

if scanned == 0:
    print("check-config-paths: no config files scanned", file=sys.stderr)
    sys.exit(2)

print(f"check-config-paths: {scanned} config file(s) against {len(roots)} state root(s): "
      + ("consistent" if bad == 0 else f"{bad} disagreement(s)"))
sys.exit(1 if bad else 0)
PY
