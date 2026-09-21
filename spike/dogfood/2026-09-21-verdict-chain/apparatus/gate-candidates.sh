#!/bin/sh
# Every candidate's gate row, from committed scripts.
#
#   docker run --rm -v <repo>:/repo:ro -v <apparatus>:/ap:ro sideeye-vc-probe sh /ap/gate-candidates.sh
#
# This file exists because the first version of this measurement lived in a throwaway script
# under /tmp and set `GATE_RESET` to more throwaway scripts. The transcript then recorded
# `reset: sh /tmp/reset-oc.sh` — a path nothing in this repository holds, for a step whose
# whole purpose is that the reader can check the state each gate started from.
# `spike/dogfood/README.md` says the apparatus is "kept so the run can be repeated", and a
# reset that is not committed is the part of the run that cannot be.
#
# overcommit's reset is `seed-state.sh` itself: the pre-state a gate needs is exactly the
# pre-state the define's setup produces, so there is nothing second to write.
set -u
OUT=${OUT:-/out/gate}

echo "# candidate gate rows, $(date -u +%FT%TZ)"
echo "# gate.sh all <label> <state-root> -- <cmd>   (0 clear / 1 red / 2 could not measure)"
echo "# Each gate runs the operation, so GATE_RESET rebuilds the pre-state before each one."
echo

echo "########## overcommit 0.73.0 (Ruby) — the slate candidate ##########"
echo "version: $(overcommit --version | head -1)"
echo "interpreter: $(file -bL "$(command -v ruby)")"
GATE_RESET="sh /ap/seed-state.sh" GATE_OUT="$OUT" \
    sh /ap/gate.sh all overcommit /tmp/oc-repo/.git/hooks -- env -C /tmp/oc-repo overcommit --install
echo "rc=$?"

echo
echo "########## lefthook 1.13.6 (Go) — the previous run's target, not a candidate here ##########"
cat > /tmp/reset-lefthook.sh <<'RS'
set -eu
repo=/tmp/lh-repo
case "$repo" in /tmp/?*) : ;; *) echo "refusing $repo" >&2; exit 2 ;; esac
rm -rf "$repo"; mkdir -p "$repo"; cd "$repo"
git init -q .; git config user.email t@example.com; git config user.name t
printf 'pre-commit:\n  commands:\n    noop:\n      run: "true"\n' > lefthook.yml
RS
echo "version: $(lefthook version)"
echo "linkage: $(file -bL "$(command -v lefthook)")"
GATE_RESET="sh /tmp/reset-lefthook.sh" GATE_OUT="$OUT" \
    sh /ap/gate.sh all lefthook /tmp/lh-repo/.git/hooks -- env -C /tmp/lh-repo lefthook install
echo "rc=$?"

echo
echo "########## detox (C, Debian) — clears the gate, excluded on rule 1 ##########"
cat > /tmp/reset-detox.sh <<'RS'
set -eu
d=/tmp/dx
case "$d" in /tmp/?*) : ;; *) echo "refusing $d" >&2; exit 2 ;; esac
rm -rf "$d"; mkdir -p "$d/state"
printf 'x\n' > "$d/state/bad name!.txt"
printf 'y\n' > "$d/state/another  one.txt"
RS
echo "linkage: $(file -bL "$(command -v detox)")"
GATE_RESET="sh /tmp/reset-detox.sh" GATE_OUT="$OUT" \
    sh /ap/gate.sh all detox /tmp/dx/state -- detox -r /tmp/dx/state
echo "rc=$?"
