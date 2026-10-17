# 0127 — A `vfork` child gives back the slot it claimed before it execs

- **Status:** Accepted (2026-10-14)
- **Refs:** #821 (measured in the 2026-10-11 survey); `DESIGN.md`'s threads paragraph, "a target
  under it is unaffected", which this makes hold on Linux for a target that starts children
  through `vfork`.
- **Scope:** `shim/src/common.zig` (`mine`, `resetSlotsInChild`, `init`, `noteExecBoundary`,
  `takeBackAfterFailedExec`), `shim/src/ops.zig` (`execve`, `execv`, `execvp`),
  `spike/toys/toy_vfork_many.c`, `spike/build-toys.sh`, `spike/acceptance.sh`, `DESIGN.md`.

## Context

The shim keeps per-thread state in a table of sixty-four slots keyed by thread id, and never
frees one: nothing in it observes a thread ending. A `vfork` child runs in its parent's memory,
so it shares that table. The first interposed call it makes — the exec wrapper's boundary
record, or a `close` before it — claims a slot under the child's own thread id. The exec takes
the child out of this memory and leaves the slot claimed. The `fork` wrapper rebuilds the table
in its child; a `vfork` child cannot, since the table is its parent's.

Measured on 2026-10-14 in `debian:bookworm-slim` (aarch64) at `e371ffe4`, under `--oracle`
strace, with a C toy that starts N children through `vfork` and `execve(/bin/true)` and then
rewrites its state file in place: N = 10 was FAIL 1 of 3, and N = 70 and N = 200 were UNKNOWN
`unresolvable_path` (`thread-slots-exhausted`). CPython 3.11's `subprocess.run`, which uses
`vfork` on Linux, did the same at 10 and 70 children.

## Decision

- The table records which process it belongs to (`table_pid`, set by `init` and by
  `resetSlotsInChild`), and each slot records the process that claimed it (`claimer_pid`, written
  by the compare-and-swap that claims it).
- In the exec wrappers, after the boundary record, a process that is not the table's owner gives
  back the slot it claimed itself. The thread's counts are cleared and its thread id is released
  with an atomic store. Nothing after that point uses the slot: the operation count's carry is
  the armed process's alone, and a `vfork` child is not it.
- The counts given back are kept on the exec wrapper's stack. If the exec returns, the thread
  claims a slot again and gets them back, so a process that goes on after a failed exec carries on
  with its own counts rather than from zero.
- `mine` looks for the thread's own slot in a first pass and claims a free one only in a second.
  Before this, no slot was ever freed, so the free slots were always the ones after the last
  claimed one, and one pass could look for both. A slot given back mid-table breaks that.

## Alternatives considered

- **Write a `vfork` child's records without a slot**, from the stack, as a thread's start record
  is. The boundary record could be written that way, but a child reaches other wrappers before
  its exec (`close`), and every one of them goes through `mine`. Each would need a second path.
- **Reclaim slots whose thread is gone when the table is full**, with `tgkill(getpid(), tid, 0)`
  answering `ESRCH` for a thread outside this process. A `vfork` child is outside it while it is
  still running and using its slot, so the reclaim has a window; and macOS has no such call.
- **Lend a slot for one call at a time.** The exec does not return, so the last lease is never
  given back.

## Consequences

- After this change, the measurements above gave FAIL 1 of 3 at N = 10, 70 and 200, and for
  CPython at 10 and 70. A toy whose children close descriptors 3 to 63 before their exec also gave
  FAIL 1 of 3 at 70. Sixty-five threads that each make one interposed call are still refused
  `thread-slots-exhausted`: the limit on threads is unchanged.
- Eight threads that each start twenty such children at once are judged, FAIL 1 of 3 in five runs
  of five. The first version of this change kept the one-pass `mine`, and it refused this shape
  in five runs of five: a child's exec gave back a slot in front of another child's, and that
  child then held two. The first review found this.
- A slot is given back only by the process that claimed it. One it found already its own belongs
  to a thread of the owner. That would be the case if a `vfork` child answered with its parent's
  thread id. Clearing it would restart that thread's counts when the parent resumes.
- While it runs, a `vfork` child holds one slot, so a process already at sixty-four threads is
  refused when it starts one.
- A `vfork` child keeps a slot in four cases: its exec fails and it then exits (it took the slot
  back); it execs through `execvpe`, the `execl` family or `fexecve`, which the shim does not
  interpose; it execs before the shim's constructor has run; or a signal handler makes an
  interposed call between the give-back and the exec. Enough of them are refused as before,
  which is the honest direction.
- `mine`'s second pass also returns the thread's own slot if it meets it. A signal handler that
  interrupts a thread's first claim and makes an interposed call claims a slot for the same
  thread, and the pass would otherwise take a second one.
- A `vfork` child that closes the shim's trace descriptor through `close` marks it closed for
  its parent too, since the shim keeps the number in memory they share. The run is refused
  UNKNOWN `unresolvable_path` (`trace-closed-by-target`), the same before and after this change.
  That was measured with children closing descriptors 3 to 4095, at 5 children and at 70.
  CPython's `subprocess.run` was judged at 10 and 70 children, so its descriptor sweep does not
  end there; how it closes them was not measured. A toy closing 3 to 63 was judged as well,
  because the trace descriptor is moved above that range.
- macOS was not measured: the toy's runs end `recording_run_failed` there before and after this
  change.
- **Amended 2026-10-17 (#901): a slot whose claimer has exited is taken back when the table is
  full.** The give-back before an exec does not cover a child whose every exec fails: the failed
  exec takes the slot back so the child carries on with its counts, and a child whose every exec
  fails then `_exit`s holding it — CPython's after writing its errno to the parent's pipe — so
  each all-fail spawn still cost the parent a slot for good (`subprocess.run` of a program that is not installed,
  seventy times). `mine` now runs a third pass when the first two find no slot: a slot whose
  `claimer_pid` is not zero, not the table's owner and not this process, and for which
  `kill(pid, 0)` answers `ESRCH`, is taken back — arbitrated by a compare-and-swap on
  `claimer_pid`, the counts cleared before `tid` is published, so two threads cannot take it
  together. A zombie still answers `kill`, so a slot is taken back only once its child was
  reaped; a target that starts more than sixty-four failing children before it reaps any is
  still refused. A pid reused by another process or thread is alive to `kill` and keeps its
  slot. The same pass returns a slot a child left behind by `_exit`ing before any exec. A slot
  found by this thread's id under a claimer that is not this process is made this process's
  when the caller owns the table: on macOS a `vfork` child runs on its parent's thread id, so
  the slot it claimed is that parent thread's once the child is gone, and left with the child's
  pid it would be taken back from the thread using it. `kill`'s errno is put back. Left as it
  was: a child in a pid namespace of its own wrote a pid this process cannot `kill`, which reads
  as departed; a thread whose id equals a departed claimer's (the id reused after a pid wrap)
  resolves to that claimer's slot by id and carries on with its counts; and while the table is
  full and nothing is reclaimable every reserve call asks `kill` up to once per slot, on a run
  that is refused anyway.
