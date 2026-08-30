# ADR 0031 — The macOS oracle is fs_usage, and what it cannot scope refuses

- **Status:** Accepted (2026-08-30) — implementing PR #406 merged as 94ca450
- **Supersedes:** nothing. Answers the question #286 asked and #181 measured the
  ground for.
- **Scope:** the completeness oracle on macOS; `--oracle-fs-usage`; the capture's
  scoping, subject attribution and integrity rules. No frozen surface moves.

## Context

`oracle_verified` is the difference between a PASS that was checked and one that was
only unopposed. On Linux it is bought with `--oracle <strace>`. On macOS nothing
bought it: #181 measured every candidate and found no unprivileged observer at all —
SIP leaves DTrace's syscall provider with no probes even as root, `dtruss` exits 0
with an empty capture, OpenBSM is gone since 14.0, and Endpoint Security's CLI wants
root plus Full Disk Access. `fs_usage` works and needs root. So every macOS PASS has
carried `--allow-unverified`, and for an audience that skews macOS that is not an
edge case but the normal experience.

**A design that avoided paying root was tried first and does not hold.** Pay root
once, compare the two accounts for one binary, write a receipt, present it on later
unprivileged runs. External review rejected it on a sentence no binding repairs: an
agreement observed in one run does not establish that another run's shim trace is
complete. Same binary, different argv, environment or state, different code path —
a target reaching `open(2)` through libc under one mode and a raw syscall under
another agrees when calibrated and is invisible when judged, with the hash matching
throughout. Coverage is a property of the paths actually taken, not of the program.

Three measurements then made the thing the receipt existed to avoid look cheap.
`--oracle` observes the recording run only, not each crash world, so the cost is one
authentication per `explore` rather than one per world. CI runners already run
`sudo -n` unattended. And the shipped `--help` already named `fs_usage` "the one
candidate measured oracle-shaped".

## Decision

### 1. `fs_usage` is an oracle backend, not a new claim

It produces `oracle.Parsed` and is compared by the existing `oracle.compare`, so
`oracle_verified` keeps its frozen meaning — *this run's* comparison completed and
agreed. No report field is added, no `unknown_reason` member is added, and the
divergence vocabulary (`oracle_missed_operation`, `oracle_saw_phantom`,
`oracle_saw_nothing`) is the one that already exists.

`--oracle-fs-usage` is a valueless flag, refused on Linux by name, and refused
alongside `--oracle`: two observers produce two accounts of one run, and a caller who
named both has not said which the verdict rests on.

### 2. The capture is unfiltered and scoped by the state root

`fs_usage`'s pid filter does not follow a fork (measured, `spike/fsusage/RESULTS.md`).
Filtering by the subject therefore leaves a raw-forked child invisible to this witness
exactly where it is already invisible to the shim — the shape measured as #405, which
reaches PASS on the shipped build while the account says `processes: single process`.
So the capture is taken with no pid filter, scope is decided by the state root's path,
and a mutation inside that root appears whoever performed it. This is what
`spike/fsusage/RESULTS.md` already prescribed for an adapter that wants children.

The default exclusion list stays in force — `-e` removes fs_usage's own activity and
nothing more, and a `/bin/sh` child measured zero lines under its own name. An earlier
revision of this paragraph claimed the excluded shell's mutation was still "in the
account" because other processes' lines named the file it wrote; review pointed out
that those were read-only lines (`fseventsd`'s `lstat64`), which the reader drops, so
the mutation itself was in nobody's account. The consequence is decision 2a below: a
process boundary is not tolerated under this backend. Children that *are* visible are
still caught by path scope — that is what refuses #405's shape — but tolerance rests
on accounting for every child, and an exclusion list makes that unprovable.

### 2a. A process boundary is not tolerated under this backend

The strace oracle follows children (`-f`) and lets the engine tolerate a fork or spawn
when no child touched the state. fs_usage cannot make that statement: a child that
execs a name on its exclusion list — the shells among them — leaves no line. So a
boundary the shim reports refuses (`boundary_without_oracle`, with the reason in the
message) rather than being tolerated. On macOS the oracle verifies single-process runs.

### 2b. A `chdir` by the subject leaves relative operands unplaceable

`openat(AT_FDCWD, relative)` is placed by joining the operand to where the subject
started; the strace reader follows `chdir` and this one does not. Once a relevant
thread has issued `chdir`/`fchdir`, a relative operand that could change state refuses.
A `..` anywhere in a relative operand refuses regardless — a textual join puts it where
the string says, not where the kernel goes. Review constructed the false PASS this
closes: `chdir("/tmp")` then a raw `openat(AT_FDCWD, "st/missed")` joined to the
starting cwd and dropped as out of scope.

The cost is a larger capture holding other processes' paths transiently. It lives in
the work directory, is never part of a case, a report or any artifact, and is removed
with the rest of the work directory.

### 3. The subject is the thread that writes the shim's trace

`fs_usage` prints a thread id, not a pid, so with no filter something must say which
lines are the subject's. Only the subject carries the shim, and the shim writes to
`SIDEEYE_TRACE_PATH`; the tid that writes there is the subject. No trace-contract
field is added for this — a contract bump orphans every saved case (#279) — and the
identification is self-checking: no such tid, no verdict.

### 4. The capture must prove it covered the window

`oracle_verified` now rests on the capture, and a start sentinel establishes only that
the observer began. Four conditions, all required: an engine-created sentinel inside
the state root read back out of the capture *before* the subject is allowed to run; a
second sentinel required after the recording; `fs_usage` ended by an explicit stop
whose pre-signal observation says it was still running (a `-t` expiry means the window
closed early, and refuses); and both sentinels removed before anything judges the
state.

Drops inside the window are fail-safe in the direction that matters: a line the shim
recorded and the kernel lost becomes a divergence and a refusal, never a false
agreement. Two residues are disclosed rather than closed. A drop coinciding exactly
with an operation the shim also missed. And a neighbouring process that held a
write-capable descriptor into the judged directory from before the capture began: its
writes on that descriptor carry no path and no open the capture saw, and a reader that
refused on every such write refused on Microsoft Defender's log writes (measured), so a
neighbour is held to account only for what it opened under the root during the window.
The setup that populates the directory runs before the observer starts, which is where
that window sits.

### 5. Everything unresolvable refuses

A line the grammar does not match, a pathname cut by the display cap, an operation on
a descriptor never seen opened, a CALL on the state root this version does not model:
each is a hole in the account, and an account with a hole is not agreement. A state
root long enough to be cut by the cap is refused before the observer starts, because
scope is decided by path and a cut path takes the root's own prefix with it.

A rename is the one class `fs_usage` reports partially — it prints the old path only
(measured) — so a rename line the shim's record does not match refuses even when its
visible path is outside the state root. What a matched rename claims stops at the old
path; the destination's bytes are not verified, and the account says so.

## Alternatives considered

- **The calibration receipt** (#286 route C). Rejected above: no transfer rule exists.
  Recorded at length in BUILDLOG rather than repeated here.
- **A privileged daemon observing every run.** Buys what the receipt could not, at the
  cost of a resident root component this project has no appetite for.
- **Filtering by pid and declaring the backend single-process-only.** The reasoning was
  that children are caught by the existing boundary refusal; that refusal depends on
  the shim seeing the child, so it is circular. Measured as #405 rather than argued.
- **A trace-contract field carrying the subject's tid.** Correct and unnecessary: the
  trace's own writes already name the thread, and a bump orphans saved cases (#279).

## Consequences

- macOS gains verified PASSes for targets that reach a verdict — measured at five of
  six on a dogfood-derived population, all of which previously required
  `--allow-unverified`.
- macOS runs that use it pay one authentication per `explore`. Runs that do not pass
  the flag are byte-identical to before.
- The macOS oracle is narrower than the Linux one in the ways named below. The ADR
  first claimed two; review found the third; the second review round added boundaries
  and `chdir` (decisions 2a and 2b) and corrected the account of the first:
  1. **Rename destinations.** `fs_usage` prints a rename's old path and never the new
     one, so a matched rename is checked at the old path and the destination's bytes
     are not verified. The account says so per run.
  2. **Path depth.** A pathname cut by the display width refuses rather than being
     scoped, and a state root deep enough to be cut is refused before the run.
  3. **Containment-group departure.** `oracle.zig` watches `setsid`/`setpgid` because
     it "is the only observer of an unshimmed child detaching"; this capture runs under
     `-f filesys` and does not carry those calls. A child that loaded the shim is still
     reported by the shim's own account, so what is unobserved here is narrower than
     the class — an *unshimmed* child that leaves the group. It is disclosed rather
     than closed: closing it means a second capture class and a second stream to
     reconcile, which is a different promise from this one.

  The first two narrow toward refusal. The third does not — it is a gap in what this
  witness can see, and the run does not know it happened. That is the honest reading of
  "the same claim a Linux one does": the same claim *about what was compared*, over a
  witness that sees less.
- `fs_usage`'s behaviour under load is measured only within one envelope
  (`spike/fsusage/`): one machine, one operation class, up to ten thousand operations,
  with the shim attached. Nothing here claims a general bound.
