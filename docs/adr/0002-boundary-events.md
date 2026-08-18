# ADR 0002 — Process boundaries: containment, and what makes a child tolerable

- **Status:** Accepted (2026-08-11; proposed 2026-08-10). Superseded in part by #169
  (2026-08-18): a boundary that appears **only in an explored world** — one the
  recording never crossed — now refuses (`boundary_without_oracle`, the per-world
  analog of the recording-time refusal, same reason token, distinguished by message)
  instead of being tolerated with observation. The tolerance below still governs
  boundaries the recording crossed and an oracle accounted for. The knowingly-open
  window recorded at the bottom of this page is **unchanged** by #169 and now covers
  the whole remaining exposure: a target whose *recording-crossed* children behave
  differently in explored worlds (worlds run without an oracle, so a world
  child's state-directory operations are accounted for by neither shim nor
  oracle when the child does not load the shim — snapshots and the checker
  still observe the resulting state, but nothing accounts for the operations) —
  closing that means an oracle on all N+1 worlds, the cost already written
  down there.
- **Supersedes:** none. Narrows the "single-process only" limit stated in ADR 0001's
  interposition table and DESIGN §9
- **Scope:** the trace contract (v2 → v3), the kill mechanism, and the conditions under
  which a target that creates other processes can be judged at all

> All six decisions are implemented. Decision 1 (containment) shipped first and alone,
> with no contract change and no verdict change; decisions 2–6 shipped together with
> contract v3. Two decisions changed shape between proposal and implementation, and the
> text below records what was built, with the original idea and why it fell noted where
> it does: the arming mechanism (decision 4 — the proposed environment variable cannot
> work under an oracle) and the `vfork` row of decision 5 (its stated rationale was
> disproved by measurement, and the fix that came out of that made vfork+exec tolerable).

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

"Touched" means performed a non-read-only operation, known or unknown. A child reading a
state file consumes no sequence number and changes no state, and refusing on it would
fail every helper that inspects a config; an *unrecognised* syscall from a child against
the state directory falls on the refusing side, because nobody can say which kind it was.

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

### 4. Only the subject can land the kill

The shim arms `kill_at` only when `getpid()` matches the pid captured at its own
`init()`. A forked child inherits the captured value but answers `getpid()` differently,
so it can never arm — and the fork is the only case that matters, because it is the only
child that inherits the parent's `seq` mid-count.

The proposed mechanism was an engine-set `SIDEEYE_PRIMARY_PID`, on the grounds that the
init-pid check "only covers fork" — a spawned child re-runs `init()` and arms itself.
Both halves of that were wrong in practice. The environment variable cannot work at all
under an oracle: the engine's direct child is `strace`, the subject is *strace's* child,
and the engine never knows its pid at `setenv` time. And the spawned child arming itself
is harmless under decision 2: the kill fires only on a state-directory kill-point, a
child's state-directory kill-point already makes the engine refuse the run, so the arm
can only go off in a world that is thrown away. (A trace-file marker — "whoever wrote
the header is primary" — was also considered and rejected: the engine does not delete
the `reproduce` line's trace file, so the printed command would silently stop arming on
its second execution.)

Detection sits behind the prevention, twice: the engine takes the subject to be the
writer of the first `shim_ready` record, requires `kill_landed` to carry that pid, and
refuses any run in which a kill-point record carries any other. Under the tolerance rule
those layers overlap the refusal itself — measured: disabling the landed-pid check alone
changes no toy's verdict, because the foreign record already refuses the run — and they
are kept anyway, because the overlap argument depends on the refusal seeing everything,
which is exactly the kind of structural claim this project has already had fail once.

### 5. What stays refused, and why

| refused | reason |
|---|---|
| `exec` **by the subject** | replaces the image without changing the pid, so `(pid)` cannot say which image to kill; allowing it would push an epoch concept into the kill path. A *child's* exec is not this — it is a spawn doing what spawns do, and refusing it would refuse every `posix_spawn` |
| `thread` **in the subject** | operation order stops being deterministic — the core claim |
| leaving the process group | `setsid`/`setpgid` are interposed and recorded as `.detached`, so the escape is visible and refused rather than silently outrun. A `setpgid` that moves nothing — the direct child re-electing itself group leader, which shells do — is not recorded: the wrapper compares the process group before and after. `setsid` needs no such check, because it fails for a process that is already a group leader, and the engine makes the direct child exactly that |

`vfork` was on this list, with the rationale "running the shim's recording path in the
child risks breaking the target". Measurement disproved the rationale: the target broke
with the shim *inactive* — the danger was the interposing wrapper's stack frame across
vfork's double return, not the recording, and glibc's own frameless-assembly `vfork`
says as much. The wrapper is now a recorded boundary followed by a guaranteed tail call
(`@call(.always_tail)`, a compile error where the backend cannot honour it), which makes
vfork+exec just another fork-class boundary: tolerable when the children are accounted
for. A vfork child that touches the state directory shares the parent's `seq` counter,
and its records carry its own pid — the same refusal catches it.

One asymmetry is accepted rather than hidden: a target that calls `setpgid(0, 0)` as a
*non-leader* is refused under an oracle (in that configuration the group leader is
strace, so the call genuinely moves the target) and explored without one (as the direct
child it is already the leader and the call moves nothing). The refusal direction is the
safe one, and the shapes that trip it are job-control programs already outside the
stated audience.

### 6. Trace contract v3

- `Record.pid: u32` on every record. Several processes append to one file with `O_APPEND`,
  so "belongs to the previous segment" does not decide anything. The pid is read live per
  record, never cached: a forked child inherits the cache, and the cached value would be
  the parent's in the one process the field exists to distinguish.
- `.spawn = 203`. `posix_spawn`/`posix_spawnp` were recorded as `.fork` through v2, which
  is wrong in kind: the child is a new process *and* a new image. Fixing the
  classification is a precondition for relaxing anything.
- `.detached = 204` for the escape above.
- Boundary records are written **after** the call succeeds, so a failed `fork` no longer
  produces a false UNKNOWN. Two exceptions keep the pre-call record, both erring toward
  refusal: `exec` (there is no "after" in the same image) and `vfork` (there is no frame
  afterwards to record from — see decision 5).
- The v0.1 claim that two recording runs produce byte-identical traces becomes "identical
  after normalising pids to order of first appearance", and the acceptance suite compares
  exactly that.

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
- **A second one, same posture**: an *unshimmed* child that `chdir`s by a relative path and
  then names state files relatively. The oracle's containment test is textual — quoted
  arguments and `-y` descriptor annotations — and a relative spelling with no annotated
  descriptor matches nothing. An absolute `chdir` into the state directory is caught (any
  non-read-only state-directory line from another pid is), and a *shimmed* child's relative
  paths are resolved against its cwd by the shim; the residue is the unshimmed-and-relative
  combination, which sits in the same adversarial corner as the world-divergent target above.
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
