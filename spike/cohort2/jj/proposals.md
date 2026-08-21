# Jujutsu — scout proposals (cohort 2, #183)

Sources: jj's tutorial and architecture docs (the selection scout's named
sources), `jj help commit`, `jj help workspace`, and the cohort-2 probe
(`../probes/jj.txt` and its two amendment transcripts). Assisted; no
exploration has run and no failure of the target has been observed.

**Standing forecast, declared before the explore**: the release binary is
statically linked (`ldd`: "not a dynamic executable", in the probe
transcript) — an `LD_PRELOAD` shim cannot load into it, so the expected
outcome is a `no_shim_marker`-class refusal at recording. The define
exists so that outcome is measured through the mini-seal rather than
assumed; whether a dynamically-linked jj is worth building as apparatus
is a separate decision this define does not make.

## P1 — `jj commit` (IMPLEMENTED)

- argv: `jj -R /tmp/cohort2/jj/repo commit -m probe` (string form fits)
- **why**: `jj commit` finishes the working-copy commit and opens a new
  one in a single transaction across three stores — the colocated git
  object store, jj's own op store/index, and the working-copy state. The
  architecture docs present the operation log as the repo's history of
  views, with transactions committed atomically; a kill inside that
  multi-store window is the exact class this cohort measures.
- **what property**: crash anywhere inside `jj commit`, and the
  repository is readable, the snapshotted initial change survives with
  its bytes, the visible description list is the old state or the new one
  (never a third), and the documented staleness recovery
  (`jj workspace update-stale`) succeeds when jj reports the working copy
  stale.
- **where from**: the tutorial's operation-log/undo section; the
  architecture doc's transaction description; `jj help workspace`
  (`update-stale`: "update a workspace that has become stale"); the
  probe's determinism and closure conditions (byte-identical repos,
  writes closed over the repo dir).

## P2 — `jj new` (recorded, not implemented)

- **why**: the other view-changing transaction. **what property**: same
  old-or-new over the op log. **where from**: the tutorial. Deferred: P1
  covers the same machinery with content at stake.

## P3 — `jj undo` (recorded, not implemented)

- **why**: the recovery surface itself as the killed operation. **what
  property**: an interrupted undo leaves the op log recoverable. **where
  from**: the tutorial's undo section. Deferred: measuring the recovery
  path's own crash behavior belongs after the primary path has a result.

## Define shape (P1)

- State root: the repository directory — working copy, `.jj` and the
  colocated `.git` together; pre-state disables the git reflog
  (`core.logAllRefUpdates=false`, init's lines dropped), both per the
  amended probe plan and its measured reasons.
- Identity and clocks pinned entirely through the `JJ_*` environment
  (values in the launcher); `HOME` is a fresh directory.
- Checker reads run `--ignore-working-copy` so the assertions observe the
  crashed state rather than triggering jj's auto-snapshot before L0 has
  company; the staleness leg then runs the documented recovery and
  re-asserts.
