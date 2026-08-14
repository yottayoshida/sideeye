#!/bin/sh
# Assisted run (#118), stow P1 checker. Property (proposals.md P1): stowing
# package B never breaks package A's installed view — A's file stays
# reachable at its target path with its exact content, through whichever
# topology (folded symlink or unfolded dir) the crash world holds, and the
# package sources are byte-conserved. Pure file inspection: stow has no
# query command, so the target binary never runs in this checker.
set -u
S=/tmp/assisted/stow/state

fail() { echo "checker(stow-unfold): $*"; exit 1; }

[ -d "$S/target" ] || fail "target dir is missing"

# ---- the bystander's installed view ----
got=$(cat "$S/target/sub/grace.txt" 2>/dev/null)
[ "$got" = "grace-content" ] || fail "A's grace.txt is not reachable at its target path (got: '${got:-unreadable}')"

# ---- package sources byte-conserved ----
[ "$(cat "$S/stowdir/A/sub/grace.txt" 2>/dev/null)" = "grace-content" ] || fail "package A's source file changed or vanished"
[ "$(cat "$S/stowdir/B/sub/ada.txt" 2>/dev/null)" = "ada-content" ] || fail "package B's source file changed or vanished"

# ---- no dangling links anywhere in the target ----
bad=$(find "$S/target" -type l ! -exec test -e {} \; -print | head -3)
[ -z "$bad" ] || fail "dangling symlink(s) in the target: $bad"

exit 0
