# ADR 0053 — A crash point is an address in the run, and a run whose writers take turns is judged

- **Status:** Accepted (2026-09-08)
- **Supersedes in part:** ADR 0002 decision 2 ("no cross-process counter is needed") and
  decision 4 ("only the subject can land the kill"); narrows ADR 0018's decline of the
  multi-process slice. Amendments on both pages point here.
- **Scope:** the trace contract (v14 → v15), the kill mechanism, and the conditions under
  which a target whose children write in the judged directory can be judged at all

## Context

`pass mv` moves a password file. The move is a `rename` performed by `/usr/bin/mv`, and
the remove that follows is an `unlinkat` performed by `/usr/bin/rmdir` — both in children
the shell forks and waits for. Sideeye has never judged either. It refused the whole run
with `child_touched_state_dir`, and the class row in `docs/target-classes.md` has said so
since the #118 cohort: *"the dangerous slice runs in fork+exec children"*.

The reason was addressing, and ADR 0002's Context measured it in 2026-08:

```
fork:  shim_ready, open a(seq=1), write(seq=2), close, FORK,
       open c(seq=3), write(seq=4), close      <- child
       open b(seq=3), write(seq=4), close      <- parent   ** collision
```

`seq` was a per-process counter while a crash point has to be a globally unique address.
`SIDEEYE_KILL_AT=3` named no single operation, so the honest answer was to refuse.

ADR 0002 decision 2 closed the gap the other way, and elegantly: the shim discards
out-of-scope operations *before* incrementing, so a child that stays out of the judged
directory consumes no numbers and the subject's addresses stay unique and complete.
"Numbering safety and honest judgement turn out to be the same condition. No cross-process
counter is needed." That is true — for every child that does not write where the verdict
is read. For the ones that do, it is the sentence that says why they cannot be judged.

ADR 0018 declined to build the slice, and named what stood in the way: crash points are
addressed by one deterministic operation count, and across processes the engine cannot
reproduce the interleaving that count depends on, so the slice is *"not a widening of
coverage but a wager on the reproducibility the product rests on"*.

## Decision

### 1. The number comes from the trace, and it is a position in the run

The shim reads the trace back before it hands out a number and takes the highest any
process has written, plus one. A single-process run numbers exactly as it did; a run with
several writers numbers in one sequence.

The trace is the source because nothing else can be. A base passed down through the
environment travels one way, so a parent cannot learn what its children consumed — and
`system()` and `popen()` fork and wait from inside libc, where no wrapper sees either end.
A shared counter in a second file would be O(1) and was rejected for being a second source
of truth: the trace is written by every process that records anything and is created fresh
for every world, so a number read from it cannot be stale from a previous world.

It reads through the write descriptor (`O_WRONLY` became `O_RDWR`) rather than opening the
path again. A second resolution is a second chance to land on another inode — the hard
link at the trace path that `shim/src/common.zig` records as unrefused — and the number
that came back would be the crash point's address, so the address would become choosable
from outside.

A torn record at the end of the trace is an operation still being written: the scan stops
in front of it and reads it next time. Bytes that are not a record refuse outright
(`count-read-failed`). Two processes writing at once can read the same highest number and
both take it, and the engine's records-against-maximum check refuses that
(`sequence_numbering_broken`) rather than judging a world at an ambiguous address.

### 2. The kill takes the process group, and only where the engine made one

`raise(SIGKILL)` killed the process that reached the crash point. That is not a crash: the
shell that forked it runs the next command, so a world armed at an awaited child's
operation would carry operations from after the point it claims to have died at. The kill
is `kill(0, SIGKILL)` — the caller's own process group, which the engine made the target
the leader of before exec.

**Only where the engine says so.** `SIDEEYE_KILL_GROUP` is set on a world's spawn and
nowhere else, because the shim cannot decide this for itself: `getpgrp() == getpid()` is
true for the subject and false for every child, and a child that fell back to killing only
itself would leave the shell running. What differs is not the process, it is how the run
was started. Measured: an unconditional group kill made the `reproduce` line the report
prints — which an operator types into a shell that has done no `setpgid` — kill the
acceptance suite's own shell (SIGKILL, exit 137).

The pid guard on the arm is gone with its reason. ADR 0002 decision 4 required the landing
to be the subject's because a forked child counted its own operations and its k-th belonged
to nobody. A number is a position in the run now, so the process that reaches k is the one
the engine asked about.

### 3. Two conditions decide whether a run with a writing child may be judged

Asked on the recording run, where both witnesses are in hand, and inherited by the explored
worlds and by `preflight --twice`'s second run:

1. **The two witnesses name the same writers, in both directions.** A process the oracle
   saw mutate and the shim did not record holds no numbers, and a run judged over the rest
   is judged over an incomplete sequence — `TOY_SPAWN_WRITES` spawns exactly that, a
   `/bin/sh` with an emptied environment. The other direction guards against asking
   condition 2 about a set that does not contain the writer it was meant to be asked about.
2. **Each writing child was collected before anyone else wrote again.** In the oracle's
   line order: from a child's first state-directory operation to the wait that reaped it,
   no other process performs one.

Condition 2 is decided in the oracle's order and not in the trace's, and that is a
correction the first implementation of this decision needed. **The trace cannot answer
it**: an awaited child's records sit between its parent's, and so do a racing sibling's, so
`parent, child, parent` and `child A, child B, child A` are the same shape there. The wait
is what separates them, and the wait and the writes are in one order only in the capture.
The first draft used record order and called the poster-child shape an interleaving,
because a parent's first and last records always straddle its children's; its own unit test
caught it.

What condition 2 does **not** require is that the parent was blocked across the child's
writes. Measured (`spike/followup-item3/`): a shell blocks in `wait4` for a foreground
command and reaps a pipeline stage with `WNOHANG` afterwards. Gating on the stronger
reading would admit a target on one run and refuse it on the next, depending on whether the
child reached its write before the parent reached its wait.

### 4. `--observe syscalls` is outside the slice

**Withdrawn 2026-09-08 (ADR 0054).** The reason this section gave was true when it was
written and is no longer: that mode took its two witnesses from two runs — the oracle
watched an untrapped execution while the run whose trace was used was trapped with no
oracle attached (ADR 0052) — so condition 1 had no second witness for the run the trace
came from, and a child touching the judged directory refused there with a message naming
the mode. The oracle watches the judged run in that mode now, so the condition has its
witness and `childrenMayBeJudged` no longer takes the mode at all. This decision is left
standing rather than rewritten, for the reason the ADR convention gives: it records what
was decided and why.

### 5. No new `unknown_reason`

The closed set is frozen (`docs/contract-freeze.md`, surface 2) and its two post-tag
additions were each ruled on their own merits. This decision needs none: a run outside the
slice refuses `child_touched_state_dir` — the same fact as before, with a message that
names which condition failed — a numbering collision refuses `sequence_numbering_broken`,
and a world that reached its k-th operation through a different sequence refuses
`kill_did_not_land`.

## Alternatives considered

- **The shim records the waits.** Wrap `wait`/`waitpid`/`wait3`/`wait4`/`waitid` and write
  a window into the trace, making condition 2 answerable from the trace alone — in every
  explored world, not only in the recording. Rejected for this step: it doubles the change
  (five wrappers, two record kinds, a window walk in the reader) and re-litigates ADR 0002
  decision 3, which put this question with the oracle after measuring that a child's own
  announcement is scheduler-dependent. **It would not remove the oracle**: condition 1's
  forward direction is about a child that never loaded the shim, and the shim cannot report
  a process it was never in. This is the step that would close the world residual below.
- **Give the explored worlds an oracle.** Closes the same residual from the other side, and
  ADR 0002 already prices it. Out of scope here.
- **Per-image or per-process segments** — address crash points as (process, index).
  Rejected for the reason ADR 0018 rejected its exec-shaped twin: it changes the case
  format, the report's address language and every consumer, for no power the run-wide count
  does not have in this slice.
- **Refusal-precision only** — keep refusing, say which condition failed. Rejected: `pass`
  stays parked at the same wall, which is what ADR 0018 rejected the same proposal for.

## Consequences

- `pass`'s class row moves from a wall to a verdict, under an oracle and in the default
  observation mode. The acceptance toy that forks a writing child goes from
  `child_touched_state_dir` at 0 crash points to FAIL at crash point 8 of 8 over 9 worlds
  (the subject alone supplies 5, which is what the oracle compares); the toy whose child
  execs first goes from the same refusal to PASS.
- **The worlds inherit condition 1 and 2 rather than re-deciding them**, because a world
  runs without an oracle. That is the window ADR 0002 already records — a recording-crossed
  child behaving differently in a world — and this decision narrows it rather than closing
  it: every world now checks that the operations before its crash point are the ones the
  recording numbered (by class, the way a saved case's `prefix_hash` compares), so a run
  whose order moved is refused rather than judged at an address that no longer names the
  same operation. The report says the inheritance out loud.
- **A child's operations have one witness where the subject's have two.** The oracle's
  completeness comparison still covers the subject only; what the oracle contributes for a
  child is existence (condition 1) and order (condition 2). A raw-syscall child that writes
  where neither observer places it is caught by the per-path reconciliation instead
  (`state_changed_unaccounted`, #405), which is the net that shape has had since it was
  filed.
- **This decision and ADR 0052's do not compose, and a target has already been measured in
  the gap.** `lbdb`'s writing child flushes a buffered stdout at exit, which is the far side
  of the wrapper boundary ADR 0005 documents and the reason `--observe syscalls` exists —
  and that mode is the one §4 excludes here, because its oracle watched a different
  execution. So a run needing both is refused by whichever of the two it asks for second.
  Nothing about the shape is exotic: a shell redirecting a helper's stdout into the judged
  file is the ordinary way to spell "append to it". Closing it means the syscalls mode
  gaining a second witness for the run its trace came from — an oracle on the trapped run,
  which is what ADR 0052 rejected for a measured reason (a trapped write reaches strace
  twice) — or the worlds gaining oracles. Both are their own change; this one records that
  the gap is real and reached, with the run beside it
  (`spike/followup-item3/artifacts/lbdb-transcript.txt` and the two files beside it).
  **Closed 2026-09-08 by ADR 0054**, which took the first of the two routes named above:
  the syscalls mode's oracle now watches the run its trace came from. The measured reason
  ADR 0052 gave still holds — a trapped write does reach strace twice — and what it did not
  examine is that the refusal prints its own line between them. `lbdb`'s row in
  `docs/target-classes.md` records what the composition buys on that target.
- Saved cases from v14 and earlier refuse `contract_version_mismatch`, as at every bump.
  The committed `spike/assisted/*/cases*` are records rather than live artifacts and are
  not re-recorded, which is what v11 through v14 did with them too.
- macOS is unchanged: `fs_usage` cannot account for other processes (ADR 0031 §2a), so a
  boundary there is still UNKNOWN. The numbering and the group kill are platform-neutral;
  the admission is not reachable without an oracle that sees children.
