# BorgBackup — scout proposals (cohort 2 follow-up, #200; revision r3)

*r3 of `../borg-r2/`: the r2 explore cleared the cache refusal and hit
`unsupported_syscall_observed: sendfile`
(`../borg-r2/explore-r2-transcript.txt`) — CPython's shutil fast-copy,
the exact syscall hg-r3 already met and worked around; the sitecustomize
gains the same one line (`shutil._USE_CP_SENDFILE = False`). Question
bytes unchanged. r2 of `../borg/`: the r1 explore refused `kill_did_not_land`
(`../borg/explore-r1-transcript.txt`) — the engine restores only the
state root, and Borg's client cache lived outside it, so after the
recording every world's `borg create` saw a cache newer than its
rolled-back repository and refused (rc 2) before reaching any state
operation the kill could land on. Two changes, both to where derived
state lives rather than to the question: `BORG_BASE_DIR` moves inside
the state root (`state/ambient`) so worlds restore the client state with
the repository — the engine's own semantics, the same lesson as hg's
wcache — and the checker discards the crashed cache before reading
(leg R0: Borg documents cache deletion as the handling for a suspect
cache; the env overrides answer the two first-contact prompts that
follow). Question bytes (the operation, the contract legs) unchanged.*

Sources: the Borg FAQ and README transaction claims (the selection scout's
named sources), `borg help create` / `borg help break-lock`, the #200
probe transcripts (`../probes/borg-frozen.txt` and its controls), and the
1.4.5 source reads recorded in `../probes/recheck-borg.txt`. Assisted; no
exploration has run and no crash failure of the target has been observed
(the probes are normal executions).

**The declared apparatus (owner-approved 2026-08-21, measured in the
frozen probe)**: libfaketime via `/etc/ld.so.preload` with FAKETIME
`@2026-01-01 00:00:00 x0` (realtime frozen at speed zero; monotonic left
real), plus a setup-generated sitecustomize pinning `time.monotonic` to a
constant and `os.urandom` to fixed bytes, reaching borg via PYTHONPATH.
Three measured leaks made it necessary: the monotonic duration inside
`time_end`, the manifest's utcnow, and the TAM authentication tag's
random salt — the last present even at encryption=none, and ruled an
integrity tag's salt rather than encryption. The measured borg therefore
runs on pinned clocks and a pinned entropy source: **any finding must
reproduce against stock borg (strace fault injection, the method of the
four standing filings) before it is claimed or reported.**

## P1 — `borg create` over a repository holding a prior archive (IMPLEMENTED)

- argv: `borg create --timestamp 2026-01-01T00:00:00 /tmp/cohort2/borg/state/repo::probe /tmp/cohort2/borg/src`
  (string form fits; all paths absolute)
- **why**: Borg's documentation makes the strongest crash promise in this
  cohort: "Borg repositories are transactional. A command either succeeds
  completely and commits its changes, or it fails/is interrupted and the
  changes are not committed" — backed by segment files, a repository
  index, and a commit protocol. A kill anywhere inside `create` is
  exactly the promise's own scenario.
- **what property**: crash anywhere inside `borg create`, and the
  repository is valid or recoverable through the documented steps: after
  removing the stale lock a killed process leaves (`borg break-lock` —
  lock removal, not repair), `borg check` passes, the pre-existing
  archive `base` is still listed and extracts byte-identically, and the
  archive listing is the old state or the new one — never a third thing.
- **where from**: the README/FAQ transactional claim; `borg help
  break-lock` (the documented stale-lock step); the frozen probe's
  determinism and closure conditions.

## P2 — `borg delete` of one archive (recorded, not implemented)

- **why**: the destructive transaction over the same machinery. **what
  property**: a killed delete never damages the archives it did not name.
  Deferred: P1 asks the same transactional question with creation's
  richer write set.

## P3 — `borg prune` (recorded, not implemented)

- **why**: the compound policy-driven delete. Deferred: same machinery as
  P2 with selection logic on top.

## Define shape (P1)

- State root: the repository directory's parent (`state/`, holding
  `repo/`). The source tree sits outside it (an unwritten input, like
  hg's working files); the borg client state (cache, security) lives
  under `BORG_BASE_DIR` outside the root, rebuilt by setup and pinned by
  the launcher's environment.
- Pre-state: `borg init --encryption=none`, then one committed archive
  `base` over the pinned source tree, then the source's `alpha` modified
  (pinned bytes and mtime) so `::probe` archives new content. All under
  the frozen clock/entropy, so the pre-state itself is reproducible.
- The launcher writes `/etc/ld.so.preload` (container-root apparatus),
  exports FAKETIME and PYTHONPATH; setup generates the sitecustomize and
  the hgrc-precedent applies: bytes that decide the question live in
  D2-held files.
- Checker: documented recovery first (`break-lock` exactly when a lock
  is present), then `borg check`, then conservation (base lists and
  extracts byte-identically), then old-or-new on the listing, with a
  new-side content assertion. Every borg output's rc checked explicitly;
  reads run at the canonical path (a copied repo is a relocated repo to
  borg's security machinery).
