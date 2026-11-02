# 0148 — A crash point can pause the operation while a second copy of it runs to the end

- **Status:** Accepted (2026-11-01)
- **Amends:** DESIGN §9 ("Not in v0": multi-process races), §15 and §21 (concurrent processes as a later malice).
- **Refs:** #961; #962 (the 2026-10-18 product review, problem 3).

## Context

Every crash world Sideeye explores kills the operation at a crash point: `crash_model` is `"process-kill"`, and a
PASS lists concurrent processes under `not_tested`. Nothing in the engine can show a missing lock or a lost
update, the defects two copies of one command meet when they run at once. The owner ruled on 2026-11-01 that
concurrent processes enter scope.

## Decision

`explore --interleave` explores the same crash points with a different failure. At crash point k the operation is
paused instead of killed, a second copy of the same operation runs to its end (or for 5 seconds), and the first is resumed. The world is judged once both have ended.

1. **The yardstick is the serial result.** Sideeye already requires byte-repeatable writes. S1 is the baseline
   world's final state; S2 is the state after the operation runs twice in a row from the initial state, built
   twice and refused when the two differ. A world in which both copies succeeded must equal S2, one in which one
   succeeded must equal S1, and one in which neither did fails; each comparison skips the declared scratch paths.
   The define's checker runs as well. The checker is not asked to count how many runs it sees.
2. **The pause is the shim's.** At `s == kill_at`, after writing `kill_landed` and before stepping aside from a
   cgroup, the shim raises `SIGSTOP` at its own thread when `SIDEEYE_STOP_AT_KILL` is set, and on resume performs
   the k-th call. The engine sees the stop through `waitid` (`CLD_STOPPED`), starts the second copy without the
   shim, waits, and sends `SIGCONT` whether or not the second copy has ended: a second copy blocked on a lock
   proceeds once the first releases it.
3. **The first form is narrow.** Linux, the default observation mode, a process that creates no children. macOS,
   `--observe syscalls` and `supervised`, `pin:random`, a success marker, `[recovery]`, `--leave-crash-state`, a run without
   `--world-timeout` and an operation that does not succeed twice in a row are refused as setup errors. No
   `unknown_reason` is added.
4. **Surfaces.** `crash_model` gains `"interleave"` (an open set); the report gains an `interleave` object; a case
   from such a run is version 9; the evidence bundle carries `crash_model` `"interleave"` and reads its boundary as a
   pause, and a world failed against the serial result says how each copy ended. The config format does not change.

## Alternatives considered

- **Judge by the define's checker alone** (#961's direction). A lost update leaves a state with one run's change,
  which a checker that asks "is this intact" passes.
- **Kill the second copy at the wait.** A copy that waited on a lock would always count as failed and the world
  would match S1: waiting and being slow could not be told apart.
- **Stop by having the shim read a descriptor the engine holds.** No `SIGSTOP`, so no `EINTR` on resume and no
  platform difference in which thread a signal reaches; but only the calling thread waits, and the target's other
  threads keep writing beside the second copy.
- **`kill(0, SIGSTOP)`.** A process-directed stop is delivered to whichever thread takes it first; a worker thread
  that called it can return and perform the k-th call before the group stops.
- **Shim the second copy too.** Its records would join the first copy's account and every gate on a foreign
  writer would refuse the world.

## Consequences

- A target that waits on a lock spends up to 5 seconds per crash point. The wait is not a flag: the
  explore help holds its 80 lines, and a run that needs another wait has not been met.
- After the resume, system calls the target was blocked in can return `EINTR` (signal(7)), as after a terminal's
  Ctrl-Z; a target that mishandles that takes a path it would not take otherwise, and the verdict is about that
  path.
- A target that writes time or unpinned randomness cannot build S2 twice alike and is refused.

## Residual windows

- Orders other than one pause at a crash point of the first copy: three or more copies, a pause inside the second copy, a different second operation.
- What the second copy does is judged only through the final state and the checker; its own records are not taken, so a write it makes and later undoes is not seen.
