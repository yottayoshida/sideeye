#!/bin/sh
# Assisted run (#118), stow P1 setup: two packages sharing one target
# subdirectory; A stowed first, so the target's `sub` is a FOLDED tree (one
# symlink to A's dir). The operation (stow B) must unfold it — the
# multi-step window under test.
set -eu
S=/tmp/assisted/stow/state
mkdir -p "$S/stowdir/A/sub" "$S/stowdir/B/sub" "$S/target"
echo "grace-content" > "$S/stowdir/A/sub/grace.txt"
echo "ada-content"   > "$S/stowdir/B/sub/ada.txt"
stow -d "$S/stowdir" -t "$S/target" -S A
