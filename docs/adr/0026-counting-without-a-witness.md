# 0026 — Counting without a witness

Status: Accepted (implementing PR merged as `975e2fd`, 2026-08-26)

## Context

On Linux every operation the shim records is checked against a second observer, and
every operation the shim misses that strace sees becomes an honest refusal
(`oracle_missed_operation`). macOS has no usable oracle (#181): a write the shim
misses is invisible to everything, and the existing zero-ops guard
(`state_changed_without_ops`) fires only when zero MUTATIONS were recorded — one
recorded mutation anywhere in the run disarms it, while non-mutating records (an
open, an fsync) leave it armed. Measured for #333: a `clonefile`
into the state directory recorded zero operations while a real file appeared with
real content, and with a single `unlink` beside it the run **PASSed**. Rust std's
`fs::copy` reaches `fclonefileat` first on this platform, so the silent route was
the common one.

The first draft of the fix took the issue's framing — interpose `fcopyfile` — and
measurement discarded it: `fcopyfile`/`copyfile`'s DATA paths were already visible
(libcopyfile binds plain `_open`/`_write`, which cross the interpose boundary), and
what was invisible was the **clone family**, selected by a *flag*, not a function
name. Adversarial review then widened the object from one function to a family:
`dyld_info` enumeration found `renamex_np`/`renameatx_np` (named in the interpose
table's own comment as `renameat2`'s macOS spelling, and not taken), `exchangedata`,
the `setattrlist` family (`ATTR_CMN_NAME` renames), `mkfifo`/`mknod`,
`msync`/`aio_write`, `undelete`, `open_dprotected_np`.

## Decision

**Close the family, not the function, and split it by what the model can hold
(trace contract v12):**

- **Counted** — `clonefile`/`clonefileat`/`fclonefileat` record one `.write` on the
  destination (COW leaves the source untouched, so one-path scope; the same
  reasoning ADR 0023 applied to `copy_file_range`). `renamex_np`/`renameatx_np`
  record `.rename` under the flag discipline `renameat2` has on Linux
  (`RENAME_EXCL` is a plain decline-to-clobber rename). `open_dprotected_np` routes
  to the open handler.
- **Refused** — `RENAME_SWAP` and `exchangedata` write the new `.unsupported`
  marker, which the engine answers with `unknown(.unsupported_syscall_observed,
  <spelling>)` — the *same reason and the same spelling shape* the oracle's flag
  refusal produces on Linux. The `setattrlist` family refuses only when
  `ATTR_CMN_NAME` is set; its other bits fall under the report's standing
  "metadata is not observable" declaration.
- **The refusal is scope-gated in the shim**, because the oracle's is on Linux
  (`scope == .outside` continues before the flag branch). An out-of-scope swap
  refuses nothing on either platform. This gate did not exist in the first design:
  moving a refusal from the oracle to the shim moved the *check* and silently
  dropped the *order* around it — the chain's order is part of the specification,
  and it does not travel with the function.
- **A ratchet, not just a fix** — `spike/check-macos-coverage.py` compares the
  runner's own `libsystem_kernel` exports against the interpose table and a reason
  table, in CI's macos job. Its Linux twin declared "a syscall the oracle
  classifies and macOS does not interpose … this check cannot see it", and that
  declared blind spot became this issue: declaring a blind spot is not covering it.

## The attempt semantics, kept deliberately

Records are written before the call (the kill must land before the effect). On
Linux that is also what makes the two accounts comparable — strace records
attempts. On macOS the comparison does not exist, but the kill-point meaning does,
so the semantics stays: **a record is an attempt, not an execution.**

That matters because `clonefile` fails whenever its destination exists, and both
`copyfile(COPYFILE_CLONE)` and Rust std then fall back to plain writes — so every
overwrite-shaped copy records one attempt that changed nothing. The failed
attempt's crash point is a **state-twin of its successor**: the world killed at the
attempt (ops 1..s-1) and the world killed just after it (ops 1..s, the attempt
having no effect) hold identical state and receive identical judgment, so v12's
worlds map one-to-one onto v11's and only the indices shift. Measured: a
failed-clone-then-fallback run PASSes with the attempt counted (7 crash points
where v11 had 6). An earlier phrasing of this argument said the twin was the
*predecessor* and that the phantom "cannot be the earliest failure" — both wrong
(the twin is the successor; a violation first present in the shared state makes the
phantom the earliest index, harmlessly), and the correction is recorded because the
wrong version reads plausibly and a doc carrying it would eventually be "verified"
against.

**The named cost:** an attempt record disarms `state_changed_without_ops`. A target
whose only recorded act is a *failed* clone, and whose only real mutation is
msync-class (invisible), was refused under v11 and can false-PASS under v12. This
is the one v11→v12 change that moves in the false-PASS direction on the platform
with no witness. It is inherent to attempt semantics, it is vastly outweighed by
what interposition catches, and it sits beside the msync issue rather than in
silence.

## Alternatives considered

- **Refuse-only (no counting)** — the `unresolved` channel could refuse every
  in-scope clone with no contract bump and no phantom question. Rejected by owner
  decision on product grounds: it makes Rust's `fs::copy` permanently unjudgeable
  on macOS, violating the stated value that both platforms answer the same
  scenario the same way — and the refusal reason would be a lie
  (`unresolvable_path` for a path that resolves fine), which this project treats as
  worse than no refusal.
- **A new OpClass for clones** — rejected; a clone's effect on the judged state is
  the destination's bytes, the `link`/`symlink` precedent was about a different
  *kind* of effect, and the snapshot carries kind differences anyway.
- **Interpose `copyfile`/`fcopyfile` themselves** — unnecessary today (DATA paths
  visible through plain imports; CLONE path caught via `clonefileat`) and pinned by
  a CI leg rather than assumed: the visibility rests on Apple's *internal import
  spelling* (`$NOCANCEL` aliases defeat interposition, and libsystem_c already
  binds those), so the leg goes red the day Apple moves libcopyfile.
- **Wrap `msync`/`aio_write`** — rejected: the mutation is a memory store no
  wrapper can see; the syscall is only the flush, and recording it would lend the
  account a completeness it does not have. Filed as the #217-shape.
- **Guard-coverage taxonomy** (with the concurrent #239 session): a guard can fail
  by covering a set **narrower** than believed (`mutation_count == 0` covers only
  the target that does nothing), by covering an **empty** set (a check whose
  predicate no fixture reaches), or by **not existing on one side** (the refusal
  the oracle issues on Linux had no macOS counterpart at all). The three need
  different detections: the first is found by measuring the set, the second by
  counting what the check walked, the third only by asking where each guard *lives*.

## Consequences

- Saved v11 cases refuse with `case_no_longer_applies` (the freeze's surface 4 —
  whose text this batch also corrected: an earlier revision split the reason across
  two names, and the second name, `contract_version_mismatch`, is the shim/engine
  pairing refusal, nothing to do with saved cases; the same misnaming stood in five
  other documents and is fixed with it).
- `spike/fsevents/`'s sensitivity leg is superseded: it deliberately planted
  `clonefile` as a mutation the shim provably misses, and v12 records it. The
  committed 15/15 result stands as a v11 measurement; its own precondition now
  refuses with "pick another mutation", and the re-point (to msync-class) is filed
  with #293. The same supersession happened to cohort 4's `no-accel-copy.so` one
  contract version earlier: an apparatus built on a wall outlives the wall.
- The macOS shim's interpose table grows from 42 to 52 entries; the coverage
  ratchet watches 15 write-capable exports (10 interposed, 5 excused with
  measured reasons) and exits BROKEN — never green — when `dyld_info`'s output
  stops parsing.
