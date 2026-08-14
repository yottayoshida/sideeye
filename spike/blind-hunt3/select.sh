#!/bin/sh
# Seal A artifact (ADR 0012 decision 2). The selection predicate, with no discretion in
# it: walk the sealed priority order and take the FIRST candidate that both
#
#   * preflight accepted (exit 0), and
#   * resolves to an absolute path inside the container image,
#
# then stop. Exactly one. Not "the most promising", not "one or two" — a count with
# slack lets the campaign decide when to stop after seeing how the first one went.
#
# Operation counts and atomicity classifications are deliberately absent from this
# predicate. They are in the sealed reports, and they are exactly the signals that would
# turn "the first that works" into "the one that looked breakable".
#
# The optional burned list holds targets removed by breach handling (ADR 0012): a
# reviewer named a target's internals, or the experimenter touched a forbidden source,
# BEFORE Seal B. Burned names are skipped, never reordered around. After Seal B there
# is no reselection — a burned selected target ends the campaign.
#
# Usage: select.sh <sweep-manifest.json> <candidates-priority-list> [<burned-list>]
# Exit:  0 selected (name on stdout) / 3 none qualified / 2 usage or parse error
set -u

[ $# -ge 2 ] && [ $# -le 3 ] || {
    echo "usage: select.sh <sweep-manifest.json> <priority-list> [<burned-list>]" >&2
    exit 2
}
manifest=$1
priority=$2
burned=${3:-}
[ -r "$manifest" ] || { echo "select: cannot read $manifest" >&2; exit 2; }
[ -r "$priority" ] || { echo "select: cannot read $priority" >&2; exit 2; }
[ -z "$burned" ] || [ -r "$burned" ] || { echo "select: cannot read $burned" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 || {
    echo "select: python3 is required (grep on a JSON document is how a truncated one reads as complete)" >&2
    exit 2
}

python3 - "$manifest" "$priority" "$burned" <<'PY'
import json, sys

manifest_path, priority_path, burned_path = sys.argv[1], sys.argv[2], sys.argv[3]

# A malformed manifest is a parse error (exit 2), never "none qualified": the two mean
# different things to the campaign, and a JSON traceback's default exit 1 was neither.
try:
    with open(manifest_path) as f:
        manifest = json.load(f)
    rows = []
    for c in manifest["candidates"]:
        name, code, resolved = c["name"], c["exit"], c["resolved"]
        # Shape-checked here, not discovered later: a non-string name would raise in
        # the walk below and exit 1 — outside the contract, which says parse errors
        # are 2 and only "none qualified" is 3.
        if not (isinstance(name, str) and isinstance(code, int) and isinstance(resolved, str)):
            raise TypeError(f"candidate fields have wrong types: {c!r}")
        rows.append((name, code, resolved))
except (json.JSONDecodeError, KeyError, TypeError) as e:
    print(f"select: manifest does not parse as a sweep manifest: {e}", file=sys.stderr)
    sys.exit(2)

def read_names(path):
    names = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                names.append(line)
    return names

order = read_names(priority_path)
burned = set(read_names(burned_path)) if burned_path else set()

# A name may appear once. Last-wins on a duplicate would let a second sweep of the same
# candidate silently replace its first verdict — the retry the protocol forbids.
seen = {}
for name, code, resolved in rows:
    if name in seen:
        print(f"select: manifest lists {name} twice; one verdict per candidate", file=sys.stderr)
        sys.exit(2)
    seen[name] = (code, resolved)

# No candidate outside the sealed order may appear in the manifest. An appended name
# is a candidate added after the seal — the walk below would never pick it, but its
# presence in a committed manifest would lend it a legitimacy the seal never granted
# (campaign-2 R1 finding, carried: the original accepted extras silently).
unknown = sorted(n for n in seen if n not in order)
if unknown:
    print("select: manifest lists candidates outside the sealed order: " + ", ".join(unknown),
          file=sys.stderr)
    sys.exit(2)

# Every non-burned candidate in the sealed order must appear in the manifest. A sweep
# that skipped one silently would let the walk fall through to a lower-priority target —
# the selection being made by an omission rather than by the predicate.
missing = [n for n in order if n not in seen and n not in burned]
if missing:
    print("select: swept manifest is missing sealed candidates: " + ", ".join(missing),
          file=sys.stderr)
    sys.exit(2)

for name in order:
    if name in burned:
        continue
    code, resolved = seen[name]
    if code == 0 and resolved == "yes":
        print(name)
        sys.exit(0)

print("select: no candidate satisfied the predicate; the refusal ledger is the result",
      file=sys.stderr)
sys.exit(3)
PY
