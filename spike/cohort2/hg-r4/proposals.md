# Mercurial — scout proposals (cohort 2, #183; revision r4)

*r4 of `../hg-r3/`: the r3 explore ran the full campaign — 101 crash
worlds, every one green through the checker (the recover leg fired in 62
and succeeded in all of them) — and refused at the very end:
`baseline_run_failed`, the un-killed baseline died to the standing kill
because its operation stream ran past the recording's count
(`../hg-r3/explore-r3-transcript.txt`). The mechanism: the engine's
restore flattens modes (documented, #121), and hg caches the
filesystem's exec answer as the exec bit of `.hg/wcache/checkisexec` —
restored worlds re-probe what the recording did not, shifting every
operation index. The one change is setup removing `wcache` from the
pre-state so the recording and every world probe from the same blank
slate (measured outside the engine: mode-flattened and mode-preserving
copies then produce identical 167-call syscall sequences). Question
bytes unchanged.*

*r3 of `../hg-r2/` (itself r2 of `../hg/`). r1 stopped at a SETUP ERROR
(state root not pre-created by the launcher). r2 ran deep and refused
with `unsupported_syscall_observed: sendfile`
(`../hg-r2/explore-r2-transcript.txt`): CPython's shutil fast-copies the
transaction's backup files through sendfile, a syscall outside the
engine's frozen contract, and neither hg nor CPython 3.13 offers a
documented switch. r3 adds one declared apparatus piece, owner-approved
2026-08-21: a setup-generated `sitecustomize.py` (reached via `PYTHONPATH`
from the launcher) sets `shutil._USE_CP_SENDFILE = False`, flipping the
copies to shutil's read/write fallback — identical bytes on disk through
supported syscalls, verified by a normal run showing zero sendfile calls
and an unchanged commit. The measured hg therefore does not run a stock
copy path; any finding must reproduce against stock hg (strace fault
injection, the method of the four standing upstream filings) before it is
claimed or reported. Every question-carrying byte (toml, checker legs,
expected values) is unchanged from r1. A revision is a new directory
because the verifier anchors a define at its introduction and holds it to
byte identity from there (PROTOCOL, mini-seal).*

Sources: `hg help recover`, `hg help commit`, `hg help config.storage`
(pinned 7.2.4, the cohort image), the cohort-2 probe transcript
(`../probes/hg.txt`) and its raw strace log. Assisted use; the scout and
its sources are named per the protocol. No exploration has run and no
failure of the target has been observed: the probe was two normal commits
and a strace of a third.

## P1 — `hg commit` (IMPLEMENTED)

- argv: `hg -R <repo> commit -m probe -d "2026-01-02 00:00:00 +0000"`
  (argv form: the date argument carries spaces)
- **why**: commit is the store's multi-file transaction — the strace pass
  shows one commit appending to `00changelog.{i,d}`, `00manifest.i` and
  the filelog while rewriting `dirstate`, branch caches and `last-message.txt`
  under journal protection. A kill inside that window is exactly what the
  journal machinery exists to survive, and Mercurial documents the
  recovery contract in one line: "recover from an interrupted commit or
  pull" (`hg help recover`). A tool that promises recovery is a tool whose
  promise can be measured.
- **what property**: crash anywhere inside `hg commit`, and the
  repository is either already valid or returns to a valid state through
  the documented recovery: `hg recover` succeeds when an abandoned
  transaction exists, `hg verify` passes afterward, the pre-existing
  changeset and both committed files' bytes are conserved, and the
  **whole repository** is either the old state or the completed new
  commit — never a third thing. That includes the working copy's own
  account: old means parent rev 0 with alpha still modified, new means
  parent rev 1 and clean. A store that committed while the working copy
  still claims the old dirty state is the third thing — the next commit
  would silently duplicate the change.
- **where from**: `hg help recover` (the documented contract);
  `hg help verify` (the integrity oracle); the probe's strace listing for
  the write set. The byte-determinism and state-root closure that make
  the question askable at all: `../probes/hg.txt`, conditions 5 and 6.

## P2 — `hg pull` from a local peer (recorded, not implemented)

- **why**: the other operation `hg help recover` names. **what
  property**: same recovery contract over a cross-repository transaction.
  **where from**: `hg help recover`. Deferred: the same store-transaction
  machinery as P1 with a second repository's plumbing on top; P1 asks the
  sharper question with fewer moving parts.

## P3 — `hg update` (recorded, not implemented)

- **why**: the working-copy transaction (dirstate + working files).
  **what property**: an interrupted update leaves a state the documented
  `hg update` re-run completes. **where from**: `hg help update`.
  Deferred: the documented contract is weaker (re-run, not recover), and
  the working files live outside the judged state root in this define
  shape.

## Define shape (P1)

- State root: the **whole `.hg`** (a store-only root would leave
  `dirstate` pointing at a commit the restored store no longer has —
  measured reasoning in the protocol's probe-plan note). Working files
  (`alpha`, `beta`) sit beside `.hg`, outside the root: the operation
  reads them and does not write them (probe strace), and worlds restore
  `.hg` against unchanged working files exactly as the probe's two runs
  did.
- Environment: `HGRCPATH` names an hgrc that `setup.sh` **generates** —
  identity pinned, and `storage.revbranchcache.mmap=no`, the measured off
  switch for the commit-path thread (probe forecast table: default 1
  thread, `mmap=no` 0; the engine refuses any thread the shim sees). The
  config is generated rather than committed loose because the provenance
  verifier holds setup/check/toml/launcher to byte identity and nothing
  else — bytes that live inside `setup.sh` are bytes D2 defends.
- Checker: documented recovery first, then assert — if
  `.hg/store/journal` exists, `hg recover` must succeed; `hg verify` must
  pass; changeset 0 and both files' bytes must be conserved; the tip must
  be old-or-new at the contract level. The checker's hg calls run with
  the same pinned `HGRCPATH`.
- The recover leg's first live exercise deliberately waits for the
  explore's worlds: manufacturing an interrupted transaction by hand
  before the define is pushed would observe exactly the failure class the
  provenance gate requires the committed define to precede.
