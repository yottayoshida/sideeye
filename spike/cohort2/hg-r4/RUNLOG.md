# Mercurial (cohort 2, target 1) — run log and ruling

## Timeline (all 2026-08-21, each step's evidence committed where named)

1. **r1** — SETUP ERROR at state resolution before any target execution
   (`../hg/explore-r1-transcript.txt`): the launcher had not pre-created
   the state root.
2. **r2** — `UNKNOWN unsupported_syscall_observed: sendfile`
   (`../hg-r2/explore-r2-transcript.txt`): CPython's shutil fast-copies
   the transaction backups. Owner-approved workaround: a setup-generated
   sitecustomize flips `shutil._USE_CP_SENDFILE` off; declared, with the
   stock-reproduction condition.
3. **r3** — `UNKNOWN unsupported_syscall_observed: utimensat`
   (`../hg-r3/explore-r3-transcript.txt`), which ripened the decision the
   oracle had reserved: the timestamp family joined the metadata
   exclusion (#190, its own PR and tests). Re-run under the new engine:
   101 crash worlds all green through the checker, then
   `baseline_run_failed` — restore flattens modes and hg caches the
   filesystem's exec answer as the exec bit of `wcache/checkisexec`, so
   restored worlds re-probed and shifted every operation index.
4. **r4** — setup removes `wcache` from the pre-state; the explore
   reaches a verdict (`explore-transcript.txt`, `report.json`,
   `cases/000001.json`). A second run reproduced the identical verdict
   and counts (deterministic, as the probe promised).

## The verdict, read under the protocol's frozen claim rule

**FAIL, 73 of 107 explored worlds; every violation is L0-only.**

- **Mercurial's documented contract held in all 107 worlds.** The
  checker — documented recovery first, then `hg verify`, conservation of
  the pre-existing changeset's bytes, tip old-or-new, working copy
  coherent — ran in every world and failed in none. The recover leg fired
  in 62 worlds (an abandoned transaction was present) and succeeded in
  all 62. The transcript carries zero checker `leg` failures; the single
  red `leg V` line is the falsification gate's own proof, labeled
  `falsify:`.
- **The L0 violations are the multi-write shape**: files hg legitimately
  writes more than once per commit (the earliest case is `dirstate` at
  crash point 16, caught between its pre-transaction rewrite and the
  final one — "holding neither the old nor the new content" because it
  held a valid *intermediate*). This is the checker-cookbook's #35 class,
  and the protocol froze its reading before any explore ran: **an
  L0-only FAIL is a precision-limit observation, recorded, never
  claimed.**
- **Criterion-1 candidate: none.** The saved case's violated invariant
  is L0, not the declared checker. 73/107 is exactly the number the
  claim rule exists to resist.

## Apparatus notes carried by this run

- The report's `metadata` line shows the #190 machinery working:
  `fchmodat x10, utimensat x2` observed and excluded.
- `oracle agreed on 106 operations (6015 syscall lines examined, 756 in
  scope)`, `oracle_verified: true`, `processes single process` — the
  probe's forecasts (thread off-switch, closure) held under the engine.
- The measured hg is not entirely stock: `revbranchcache.mmap=no`
  (documented config) and the declared sendfile sitecustomize. Any future
  claim from this target must reproduce against stock hg first; none is
  being made.
