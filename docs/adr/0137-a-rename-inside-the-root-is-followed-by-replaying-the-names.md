# 0137 — A rename inside the root is followed by replaying the names

Status: Accepted (2026-10-16)

Closes #892. Amends ADR 0032 §4, whose sentence "a rename entirely inside the root … the
descendants are reconcilable" the reconciliation did not implement.

## Context

The per-path reconciliation (ADR 0032, ADR 0121) accounts for a difference between the
recording's two snapshots by a record that names the path, or by the path sitting under a
directory a recorded rename moved in from outside the root. A rename whose both ends are inside
the root moves every descendant to a new name, and no record names a descendant by that name:
the write that filled `gen.tmp/data` names `gen.tmp/data`, and the snapshot holds `gen/data`.
So a run that builds a directory under one name and publishes it under another, or swaps a
directory for a new one and removes the old copy, was refused `state_changed_unaccounted` with
every operation recorded. ADR 0032 §4 had said those descendants are reconcilable, as the reason
the outside-in exemption did not need to cover them; nothing reconciled them.

A record is written before its call runs and carries no result, so a failed call leaves its record
too. A rename that failed with `ENOENT`, or with `ENOTEMPTY` on a destination that still held
files, names two paths and moved nothing. `renameat2(RENAME_NOREPLACE)` and `renamex_np(RENAME_EXCL)`
record as a plain rename, and refuse a destination that exists.

## Decision

**The recorded name operations are replayed over the first snapshot's names, and the replay is
used only when it ends on exactly the second snapshot's names.** The operations are the ones that
create, remove or move a name: `mkdir`, `open` of a name not yet there, `unlink`, `rmdir`,
`rename`, `link`, `symlink`, in record order, each path resolved the way the reconciliation already resolves a
record. Each succeeds or fails as POSIX says it would on the names the replay holds at that
point — a rename whose source is missing, whose destination is a non-empty directory, which moves
a directory under itself, or whose two ends disagree on being a directory moves nothing. The
names the replay ends with are compared with the second snapshot's, declared `scratch` paths left
out of both; any difference, and any record the replay cannot place (`unresolved`,
`unsupported`), and the replay is not used. It is not used either when the differences the run
was handed do not agree with the two snapshots, and not at all in a run that records no rename.

Where the names cannot say whether a rename moved anything, the replay is not used:

- **a directory renamed over an existing empty directory**, which a no-replace rename refuses;
- **a removal or rename of a name the replay says an earlier rename emptied**, which a program
  issues when that rename failed — cleaning up the source it still has;
- **renames recorded by more than one thread or process**, whose record order need not be the
  order their calls ran in.

When it is used, a difference is accounted for in three more ways than before:

1. **A record names a path by the name it had when the record was made.** Each name the replay
   holds carries the names it was known by and the record positions between which it held each,
   so a write to `gen.tmp/data` before the rename accounts for `gen/data`, through any chain of
   renames, and a write to the old name after the rename accounts for nothing at the new one.
   Only a record that is a crash point has a position; a `close` names nothing by an earlier
   name.
2. **A file a rename moved, holding the bytes and kind it held before under its first name, is
   accounted for by the move.** Bytes that differ need a record that can have put them there, as
   ADR 0121 requires of every file.
3. **A path the replay removed is accounted for**, except one a rename moved out of the root:
   those were never accounted for by a record, and still are not.

A name the replay holds because a recorded rename brought it in from outside the root is counted
in `paths_attributed_to_rename`, as ADR 0032 §4 counts a moved-in subtree; a rename inside the
root adds nothing to that count, and neither does a `link` from outside, which brings in one file
and no subtree.

## Consequences

- A run that builds a directory and renames it into place, or swaps one directory for another,
  with every operation recorded, reaches a verdict. `spike/toys/toy_dirswap.c` measures both: the
  publish PASSes with `gen.tmp` declared `scratch`, the swap FAILs where `cur` is missing, and
  each reports `paths_attributed_to_rename` 0; on the commit before this both were refused.
- An unrecorded write or removal is refused as before, before or after the rename: a rewrite of a
  moved file changes its bytes, and a removal or creation the records do not hold leaves the
  replay's names different from the snapshot's, so the replay is not used. A `scratch` path is
  left out of that comparison, so one the replay still holds is not counted as removed.
- **One shape is not refused.** A directory rename that fails for a reason the names do not show
  — permissions, a sticky directory — is replayed as having moved its subtree. If calls without a
  record then build the destination's names and remove the source — or leave it, when it is
  declared `scratch` — the replay ends on the snapshot's names, and a file the destination holds
  is accounted for by a write recorded under the source's name. This is the per-path net's existing limit — a failed call's record accounts
  for a change at the path it names, `docs/report-schema.md` — reaching the descendants of the
  directory the failed rename names. Closing it needs the rename's result in the trace, a contract
  change for every saved case (#279); the shapes the names do show — a no-replace rename over a
  directory, a recorded clean-up of the source — are closed above.
- A run that does without the replay is reconciled as before, which is the refusing side: renames
  from several threads, a clean-up that removes a renamed source unconditionally, and a failed
  `open` without `O_CREAT` — the replay creates any name an `open` names, the record not saying
  whether the call did, and the snapshot then lacks it.
- A path moved out of the root is refused as it was: ADR 0032 §4 decided that and this keeps it.
- A failed `open` followed by an unrecorded creation of the same name ends on the snapshot's
  names; the file it leaves holding bytes is still refused, since an `open` accounts only for a
  file it left empty (ADR 0121).

## Alternatives considered

- **Widening the outside-in exemption to renames inside the root.** ADR 0032 §4 rejected it: the
  source is in the first snapshot, so wholesale attribution would hide an unrecorded write that a
  reconciliation can see.
- **Using only the renames whose destination the second snapshot holds.** A failed rename whose
  destination exists anyway passes that test (`ENOENT` on a missing source; `ENOTEMPTY` followed
  by a recorded removal of the source), and a chain or a swap whose intermediate name is gone fails
  it.
- **Recording each rename's result in the trace.** A contract bump for every saved case (#279),
  for what replaying the records already tells.
- **Naming the rename in the refusal's message.** The run would still be refused.
