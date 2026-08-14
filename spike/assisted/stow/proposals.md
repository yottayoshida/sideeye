# stow — scout proposals (assisted, #118)

T0: 20260814T141235Z. Sources: `stow --help` (pinned 2.3.1), fold/unfold
behavior probes. No external service needed.

## P1 — stow B into a folded tree (IMPLEMENTED)

- argv: `stow -d <stowdir> -t <target> -S B`, with the target's shared
  subdirectory currently folded onto package A (one symlink to A's dir).
- **why**: the unfold is stow's own multi-step maintenance — delete the
  fold symlink, create the real directory, re-point A's files one by one,
  add B's. A crash in the middle is where the OTHER package's installed
  view breaks.
- **what property**: *stowing B never breaks A* — A's file stays reachable
  at its target path with exact content in every crash world, package
  sources are conserved, and no dangling symlink is left in the target.
- **where from**: the help text (`-R, --restow (like stow -D followed by
  stow -S)` admits multi-phase mutation; tree folding is stow's documented
  core mechanism), and the probes (fold observed: `sub -> ../stowdir/A/sub`;
  unfold observed: real dir with per-file links; whole-tree determinism
  over the same pre-state measured).

## P2 — `stow -D` unstow (recorded, not implemented first)

- **why/what**: unstow removes links and re-folds; interrupting it must not
  damage the surviving package. Deferred: P1's unfold is the sharper
  multi-step window.

## P3 — `stow -R` restow (recorded, not implemented)

- **why/what**: documented as "-D followed by -S" — the phrasing itself
  admits a window where the package is absent; the meaningful conserved
  entity is again the OTHER package. Deferred as a variant of P1/P2.
