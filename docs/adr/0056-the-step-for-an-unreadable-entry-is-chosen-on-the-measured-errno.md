# 0056 — The step for an entry the snapshot could not read is chosen on the measured errno

Status: Accepted (2026-09-09)

## Context

A snapshot that gives up on an entry refuses `state_unsnapshotable`. Until #535 the
refusal said "a file or symlink inside the state tree could not be read" and its step was
`environment` — "Fix what the detail above names in the environment" — for every such
failure, at every site. lbdb's fetcher takes a dotlock (`O_CREAT|O_EXCL`, mode 0), and a
world killed before the lock is released leaves a file nobody but root can open; the
refusal named nothing and blamed a party that had not done it. The issue lists four things
the refusal has to say and defers the question of whether the snapshot could *judge* such a
state (read it as root, change its mode, treat "present, unreadable" as an observation) to
its own decision. This one is about what the refusal says.

Two designs were taken apart before this one. The first branched the step on the run's
phase — "before exploration it is the operator's tree, during it the run left it" — and
the plan's adversarial reader found that the before-side of that branch is never rendered:
the initial snapshot's failure goes through `setupError`, which writes no `next_step` at
all, so half the branch was unfalsifiable. The second gave every `ReadFailed` past the
recording run one new step, "an entry this user cannot read appeared in the state during
the run", and the diff's first-read reader counted the ways `readWhole` fails: an entry
gone between `readdir` and `open` (`ENOENT`), an `EIO`, a descriptor that turned out not to
be a regular file, a `readlink` that filled its buffer. One report could have said
`errno 2 ENOENT` in its detail and "this user cannot read" in its step.

## Decision

**The walk records the entry it gave up on and the errno of the libc call that failed,
read before anything else runs and left null where no call failed; the refusal names the
entry, and past the recording run its step is chosen on that errno.**

- `EntryDiag` carries the entry's path relative to the state root (`EntryRel`, the shape
  the per-file cap's diag already used), its kind, and `errno: ?c_int`. `readWholeDiag`
  captures errno on the first statement after a failed `open`, `lseek` or `read`;
  `readLinkTarget` after a failed `readlink`. A refusal that is not a failed call — a
  descriptor that was not a regular file, a `readlink` that filled its buffer, a
  `statNoFollow` that returns a kind and no number — leaves it null, and the message then
  names the entry without a number. `FileTooLargeDiag.size` has followed the same rule
  since #265: a quantity nobody measured does not appear in a message.
- `readFailedStep(errno)`: `EACCES` or `EPERM` → `unreadable_entry_appeared` ("An entry
  this user cannot read appeared in the state during the run (a lock created with mode 0000
  is the common case): re-run as a user that can read it, or point --state at a directory
  that leaves it outside."); `ENOENT` → `quiesce`, the step that already describes a state
  still moving after the run was contained; anything else, or null → `environment`, which
  now has a named entry to point at. `ClassifyFailed` keeps `environment` for the same
  reason its errno is null: only a measured errno may choose the step.
- The initial snapshot's failure stays `SETUP ERROR`, which carries no step, and names the
  entry in its message. "Appeared during the run" is true past the recording run because
  the initial snapshot read the tree; the sentence does not say who created the entry,
  because the engine did not measure that.

## Alternatives considered

- **Branching the step on `run_phase`.** Unfalsifiable on one side, as above.
- **One new step for every `ReadFailed` past the recording run.** False on four of the five
  ways a read fails, and the falsity would have sat inside a single report.
- **Widening `environment`'s sentence to "the environment or the target".** Names nothing
  and keeps sending the operator to the wrong place for the common case.
- **Giving `ClassifyFailed` the new step too**, on the reasoning that the initial snapshot
  classified the tree so a later failure also appeared during the run. `statNoFollow`
  hands out no errno; choosing the access sentence without one is the second design's
  mistake again.
- **Making the snapshot judge the state anyway** (root, mode changes, "present,
  unreadable" as an observation). The issue defers it and this decision does not touch it;
  each changes what a verdict means.

## Consequences

- `NextStep` gains `unreadable_entry_appeared`. The frozen closed set is `unknown_reason`
  (`docs/contract-freeze.md` surface 2), which is unchanged; what reaches the JSON is the
  rendered sentence. `docs/report-schema.md`'s remedy list gains "re-run as a user that can
  read what the run left".
- The sentence names `--state`, so the #274 test (every flag a step names appears in the
  help text) covers it.
- `spike/acceptance.sh` check 2ff leaves a mode-0000 `lock` through a single-image
  operation (`install -m 0000 /dev/null`, no shell — a `chmod` child would meet the
  process-boundary machinery before the snapshot did) and reads the entry, `EACCES` and the
  new step off text and JSON at the final-state snapshot. Non-root only: root reads mode
  0000, and the leg fails loudly there rather than skipping, as `acc-rw` does.
- The walk's `opendir(...) orelse return` still snapshots a directory it cannot open as
  empty. Measured under this decision with a target that leaves a mode-0000 directory
  holding a file: `explore` and `preflight --twice` both refuse `state_rewrite_failed` at
  the restore, before any verdict, so nothing was filed. That refusal names no entry
  either; it is a different reason code and a different decision.
