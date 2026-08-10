# ADR 0002 — Process boundaries: containment, and what makes a child tolerable

- **Status:** Proposed (2026-08-10)
- **Supersedes:** none. Narrows the "single-process only" limit stated in ADR 0001's
  interposition table and DESIGN §9
- **Scope:** the trace contract (v2 → v3), the kill mechanism, and the conditions under
  which a target that creates other processes can be judged at all

> **What is implemented as of this ADR being written: decision 1 only** (containment). It
> ships without any contract change and without altering a single verdict. Decisions 2–6 —
> oracle-decided tolerance, the second witnesses, the arming restriction, contract v3 and
> the oracle's pid attribution — are **proposed and not built**. They are written in the
> present tense below because that is what an ADR records: the decision, not its progress.
> Anything a reader might mistake for a current guarantee is called out where it appears.

## Context

v0.1 refuses any target that creates a process: one `fork`, `posix_spawn` or `execve` and
the run ends `child_process_detected`. Pointing sideeye at its first real target
(omamori, the v0.4 dogfood subject) ended there — and decoding that trace showed the
refusal is costing more than it buys:

| | what the issue first claimed | what the trace says |
|---|---|---|
| boundary event | an `exec` at the end | **`posix_spawn` twice, no `exec` at all** |
| position | after the state work | **records 1–2 of 152, before any of it** |
| state work observed | "the part before the hand-off" | **all 143 kill-point operations, in the observed process** |

Two helper processes at startup, then everything of interest in the process sideeye
already watches. This is not an omamori quirk; it is the shape of every shim, wrapper,
launcher and subcommand dispatcher.

**Why the refusal exists is not what the code comments say.** The comments frame it as
"v0.1 explores single-process targets". The measured reason is *addressing*: `seq` is a
per-process counter while a crash point must be a globally unique address. Measured:

```
fork:  shim_ready, open a(seq=1), write(seq=2), close, FORK,
       open c(seq=3), write(seq=4), close      <- child
       open b(seq=3), write(seq=4), close      <- parent   ** collision
exec:  shim_ready, open a(seq=1), write(seq=2), close, EXEC,
       shim_ready,                              <- init runs again
       open c(seq=1), write(seq=2), close       <- new image ** collision
```

`SIDEEYE_KILL_AT=3` does not name one operation. That is the real defect, and it points
at its own fix.

## Decision

### 1. Containment comes first, and is independent of tolerance

Run every child in its own process group (`setpgid(0, 0)` before `execvp`, repeated by the
parent to close the scheduling window); after `waitpid` on the direct child, send
`kill(-pid, SIGKILL)` and reap what is still ours. **Snapshot only after that.**

This is not part of the tolerance decision — it is a precondition for it. `runChild`
currently waits for the direct child only, so a grandchild outlives the subject and
writes into the state directory while the engine is snapshotting, restoring, or running
the checker. The verdict then describes a moment nobody chose. v0.1 gets away with it
only because such targets are refused before any world is explored.

**The signal is safe by construction rather than by checking.** An earlier draft of this
ADR required confirming `getpgid(child) == child` first, on the grounds that a failed
`setpgid` would leave the group id equal to the engine's own and the group kill would kill
the engine. That risk is unreachable: `kill(-N, …)` addresses the group whose id is N, and
N here is the child's freshly allocated pid, which cannot equal the id of a live process
group — POSIX keeps a pid out of circulation while it is in use as a group id. If the
child never got its own group, no group with that id exists and the signal reaches nothing.
The check was defending against something that cannot happen, so it was removed: a
structural argument is worth more than a guard, and one fewer guard is one fewer thing to
keep true.

### 2. A boundary is tolerable when something can account for the child

The rule is not "single process". It is:

> **No process other than the subject touched the state directory.**

This works because of one measured property: the shim discards kill-point operations
outside the state directory *before* incrementing `seq` (`observe`, `shim/src/common.zig`).
So a child that stays out of the state directory consumes no sequence numbers, and the
subject's addresses remain unique and complete. **Numbering safety and honest judgement
turn out to be the same condition.** No cross-process counter is needed.

### 3. The oracle decides, not the child

The first draft had each child announce itself (a marker written by the child) and treated
the absence of an announcement as "unobserved". Two problems, both fatal:

- **It is scheduler-dependent.** A child killed by the group kill before it announces
  leaves no announcement, so the same target yields different verdicts on different runs.
  For a tool whose product is determinism, non-determinism is worse than a wrong answer.
- **It cannot distinguish "died before doing anything" from "ran unobserved".** That is
  the confusion this whole project exists to avoid, one level down.

The oracle has neither problem: `strace -f` prefixes every line with a pid (measured:
42 of 42 lines), and a `posix_spawn` appears as `clone(…CLONE_VFORK…)` plus the child's
`execve`, with the child's pid visible. It sees children whether or not they load the
shim.

**Therefore: a target that crosses a boundary can be judged only when an oracle is
present.** In practice that means Linux. macOS has no usable oracle (ADR 0001, DESIGN §9),
so multi-process targets stay UNKNOWN there — which is what happens today, so nothing
regresses.

The shim still provides a second, independent witness: no kill-point record outside the
subject's pid, checked on the recording run **and on every explored world and the
baseline**. A child's behaviour can differ between worlds, because the parent dying
earlier changes which path the child takes.

### 4. Only the subject is armed

The engine sets `SIDEEYE_PRIMARY_PID` in the child before `execvp`; the shim arms
`kill_at` only when `getpid()` matches. A forked or spawned child has a different pid and
is therefore never able to raise the kill.

Prevention, not detection. The earlier draft compared against the pid captured at `init`,
which only covers `fork` — a spawned child runs `init()` in its own pid and would have
armed itself. The check that `kill_landed` belongs to the subject stays as a second layer.

### 5. What stays refused, and why

| refused | reason |
|---|---|
| `exec` | replaces the image without changing the pid, so `(pid)` cannot say which image to kill; allowing it would push an epoch concept into the kill path |
| `vfork` | the child shares the parent's address space with the parent suspended; running the shim's recording path there risks breaking the target itself |
| `thread` | operation order stops being deterministic — the core claim |
| leaving the process group | `setsid`/`setpgid` escape the containment of decision 1. They are to be interposed and recorded as `.detached`, so the escape becomes visible and refused rather than silent. **Not implemented yet** — until it is, containment reaches only what remains in the child's process group, and a target that deliberately detaches is outside it |

### 6. Trace contract v3

- `Record.pid: u32` on every record. Several processes append to one file with `O_APPEND`,
  so "belongs to the previous segment" does not decide anything.
- `.spawn = 203`. `posix_spawn`/`posix_spawnp` are currently recorded as `.fork`
  (`shim/src/ops.zig`), which is wrong in kind: the child is a new process *and* a new
  image. Fixing the classification is a precondition for relaxing anything.
- `.detached = 204` for the escape above.
- Boundary records are written **after** the call succeeds. Today they are written before,
  so a failed `fork` produces a false UNKNOWN. `exec` keeps the pre-call record — there is
  no "after" in the same image — which is safe because `exec` is refused anyway.

## Alternatives considered

**A cross-process sequence counter** (shared memory, or a lock file) so children could be
numbered too. Rejected: it puts shared mutable state and locking inside a library that
must stay signal-safe and heap-free, and decision 2 shows it is unnecessary — the only
children worth numbering are the ones we refuse.

**One trace file per process** (`trace.bin.<pid>`). Attractive: no interleaved writes, and
the subject's trace stays byte-identical across runs. Rejected: the engine would have to
enumerate and order several files, and the global ordering between parent and child
operations is lost — which forecloses reporting "the child ran between operations 3 and 4"
later.

**Children announce themselves.** Rejected after review; see decision 3.

**Tolerate only a `fork`/`wait` pair completed before the first kill point** — the reviewer's
minimal proposal. It holds for omamori (the boundary is at records 1–2) but is fragile as a
rule: a target that moves its helper after the second operation goes back to UNKNOWN for a
reason nobody can explain from the outside. The adopted rule keys on what the target *did*
(touch the state directory or not), and costs about the same to implement.

**Allowing `exec`** by carrying an epoch alongside the pid. Rejected for now: it doubles
the concept count in the kill path for a shape (wrapper that execs and *then* does the
state work) that the current rule already handles in its more common form (wrapper that
does the state work and then hands off).

## Consequences

Accepted costs:

- **The feature is effectively Linux-only**, because tolerance requires an oracle. Stated
  in the report rather than branched on: the same asymmetry `--allow-unverified` already
  encodes.
- **Trace bytes stop being identical across runs**, since pids differ. The v0.1 determinism
  claim becomes "identical after normalising pids to order of first appearance", with a
  test for exactly that.
- **A FAIL on a tolerated run attributes its window to the subject process only.** The
  counterexample is real and reproduces; the named window may not be the cause if an
  unobserved process contributed. The report says so.
- **One path is knowingly left open**: a target that behaves differently in explored worlds
  and reaches the state directory through raw syscalls or stdio there. Closing it means
  running the oracle on all N+1 worlds instead of one. Filed rather than fixed, with the
  cost written down. A target that branches on `SIDEEYE_KILL_AT` is adversarial and outside
  DESIGN's black-box premise; that premise is now stated explicitly.
- **Quiescence is observed, not proven.** `ECHILD` does not establish that no descendant
  remains — a reparented grandchild is not the engine's child to wait for. The engine takes
  the snapshot twice and requires agreement. The report says "observed stable", never
  "proven quiescent", because no finite check can prove the absence of a future writer.
- **The oracle changes the timing of the recording run.** Measured while building the
  containment check: `strace -f` does not exit until all of its tracees do, so a target
  whose stray child sleeps 300 ms makes the recording run take 310 ms and the child's write
  lands *inside* the measured window. The recording run under an oracle and an explored
  world without one are therefore not timing-equivalent, and the recording run's `final`
  snapshot can contain a file no world will ever see. It cannot produce a wrong L0 verdict
  today — `judgeL0` only constrains paths present in both the pre and post snapshots, and a
  stray file is in neither — but a checker would see a different tree. Decision 2's
  quiescence check is the place this has to be reconciled.
