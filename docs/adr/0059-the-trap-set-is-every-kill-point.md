# 0059 — The trap set is every kill point, and the shim keeps the signal that makes it work

Status: Accepted (2026-09-11)

Amends **ADR 0052** — decision 1, and two of its Consequences. Nothing else in 0052 moves:
the marker in an argument register, the contract-14 announcement, and the oracle rule all
stand as written.

## Context

ADR 0052 gave `--observe syscalls` a trap set of four names — `write`, `pwrite64`,
`writev`, `pwritev` — and said so for a measured reason: a set containing `openat` kills
the process, because an exec'd image's `ld.so` opens its libraries before any constructor
has installed a handler and an unhandled `SIGSYS` is fatal (exit 159). It also said the set
was *unnecessary* wider, on the strength of `target-classes.md`'s stdio row: what was
missing there was "the shim recorded the `open` and no `write`".

That second half stopped being true the moment the tool was pointed at a Go program.
#542 asks for mlr's writer count, and mlr records **nothing at all**: Go reaches the kernel
directly for `openat`, `write` and `renameat`, so no interposed wrapper sees any of them
and the shim's account ends after zero operations. The four-name set does not help, because
`write` is only one of the three. The class is not "libc issued this from inside itself";
it is "this runtime does not use libc for files", and it covers every kill point at once.

## Decision

**1. The trap set is every operation `contract.OpClass.isKillPoint` admits** — open, write,
rename, unlink, fsync, truncate, mkdir, rmdir, link, symlink — in each spelling the
architecture has: the `*at` forms on both, plus `open`, `creat`, `rename`, `unlink`,
`rmdir`, `mkdir`, `link` and `symlink` on x86-64, where those still exist as syscalls.
Twenty-five names across the two architectures, seventeen of them shared.

**Two calls stay outside, for one structural reason**: `copy_file_range` and `pwritev2`
take six arguments, and the re-issue marker lives in the sixth argument register. A
`comptime` arm in `install` refuses a new member that does. `copy_file_range`'s wrapper
therefore keeps recording in both modes; `pwritev2` keeps 0052's third answer — refused
rather than counted, because glibc's fallback lands on a trapped number on a kernel that
lacks it and does not on one that has it.

**2. The `ld.so` problem is solved by the flags, not by the set.** The filter admits an
`open` or `openat` only when its flags carry `O_ACCMODE`, `O_CREAT` or `O_TRUNC` — the same
mask `common.openIsWriteCapable` applies and the oracle's `isReadOnlyOpen` mirrors, so for
those two the observers admit exactly the same opens. **`openat2` is trapped
unconditionally** and is the one place this is not true of the filter: its flags are inside
`struct open_how` and classic BPF cannot follow a pointer, so the handler re-reads them and
records nothing for a read-only one. The account is the same either way; what is not is
that a loader reaching for `openat2` would still die across an exec. glibc's uses `openat`
(measured), so this is a note rather than a wall — and `src/oracle.zig`'s `isTrapped`
answers "trapped" for every `openat2`, because that is what the filter does.

A loader opens read-only, and the flag test is what lets it. **Measured on 2026-09-11 in a
preload probe of this design, not in the shipped shim** — three legs, same box: a filter
trapping every `openat` then `exec`ing `/bin/ls` gives exit 159 (0052's measurement
reproduced); the same filter with the flag test gives exit 0; and the flag-tested filter
against `sh -c 'echo x > /tmp/f'` gives exit 159 again — so the surviving case is a live
filter admitting a read-only open, not a filter that died. What the shipped shim is held to
instead is `spike/acceptance.sh`'s self-exec leg, which crosses an `exec` under this mode on
every push and would come back 159 if either half of decision 2 or 3 broke.

**3. The handler is installed before anything the filter could trap, in every mode.** A
filter survives `execve` and a handler does not, so an exec'd image stands in front of the
inherited set with `SIGSYS` at its default — and the first thing the shim's own constructor
does after that is open the trace file for writing, which the widened set traps.
`installHandler` is therefore its own call, made first thing in `common.init`, **including
when this process's mode is `wrappers`**, because the filter may have come from a parent.
Measured in a preload probe of this design: with the two in the other order the `cat` an
`sh -c` exec'd died of `SIGSYS` (159); in this order both survived.

**4. One flag decides which of the two doors counts.** `syscalls.armed` is set only by a
successful `seccomp` install in *this* process. The handler records only while it is set,
and every wrapper whose syscall is in the set stays silent while it is set
(`common.countedAtSyscall`). A process standing in front of a filter it did not install has
the flag false: the handler re-issues without recording and the wrappers count, which is
the right answer there and falls out of the same flag rather than a second mechanism.
`PR_GET_SECCOMP` was considered for that case and dropped — two places answering one
question is how the two places disagree.

**And the wrapper asks the flag in one place, not thirty-one.** Because decision 1 makes
the trap set exactly the kill-point classes, the class a wrapper is about to record already
answers whether the handler is counting it: `common.zig`'s recording functions ask
`countedAtSyscall() and op.isKillPoint()` once, and no wrapper carries a fact of its own to
forget. The handler reaches the same bodies through `*FromTrap` names that skip the test —
without that split a gate inside one body would silence both doors. `copy_file_range` is
the single wrapper that uses the handler's door, because its six arguments keep it out of
the set. `.close` needs no exception: it is not a kill point, so the class lets it through
in both modes, which is what the trace has always said and what an acceptance leg now pins.

**5. In this mode the shim keeps `SIGSYS` deliverable, and this reverses a stated
principle.** It interposes `sigaction`, `signal`, `sigprocmask` and `pthread_sigmask`: a
request naming `SIGSYS` is accepted, answered successfully, and the part that would replace
the handler or block the signal is not applied. **Only when this process's mode is
`syscalls`** — declining a request is a change the target can observe, unlike installing a
handler nothing raises, so the default mode declines nothing. It is not untouched, and the
distinction matters: the four symbols are exported in every mode, because a symbol cannot
be exported conditionally, so the default mode forwards every call through a wrapper. That
forward must not reach `dlsym` — it is not async-signal-safe while `signal` and
`sigprocmask` are — so all four are resolved in `common.init` and the wrapper does a load
and a null test (review, P1). The gate is the mode and not `armed`: a process whose own
`install` failed while its parent's filter was inherited has `armed` false and needs the
guards most. 0052 declined exactly this, on the grounds that it means
"overriding the target's own choice rather than observing it — the opposite of what this
tool does". That argument is sound and is overridden here, because the alternative is not
observation either: Go installs its own `SIGSYS` handler through libc and touches the mask
through it, and a trap on a thread with `SIGSYS` blocked **ends the process** — the kernel
resets the disposition rather than queueing a signal it forced (measured: exit 159, with
the handler installed). So the choice is not between overriding the target and leaving it
alone; it is between overriding one signal's disposition and being unable to observe the
target at all. The override is narrow — one signal, no other behaviour changed, every query
answered truthfully — and the mode is opt-in.

**6. `SA_ONSTACK`.** 0052 left it off, on the reasoning that threads were refused so the
subject is on its main stack. Threads are judged since contract v16, and a Go target's
goroutine stacks are small while its threads carry an alternate signal stack for exactly
this. The handler is installed with `SA_SIGINFO | SA_ONSTACK`. A thread with no alternate
stack is unaffected: the flag then means nothing and the handler runs where it would have.

## Alternatives Considered

- **Leave the set at four and answer #542 from outside the process** — the `#217`
  direction, a supervisor tracing the target. Rejected by the owner before this plan: it is
  a second observation architecture for one question, and the in-process path already had
  the filter, the handler and the account.
- **Trap `rt_sigaction` and `rt_sigprocmask` in the filter** instead of interposing libc.
  Four arguments each, so the marker fits, and it would cover the raw callers interposition
  cannot see. Not taken here: it puts the shim in the business of rewriting the target's
  signal state from a handler, and the measured case (mlr, and Go generally under cgo)
  goes through libc. It stays the next step if a target needs it, and the gap is disclosed.
- **`PR_GET_SECCOMP` to detect an inherited filter**, so that a `wrappers`-mode process in
  front of one could count at the handler. Rejected: `armed` already answers the question
  the recording side needs, and the wrappers are a correct door in that process.

## Consequences

- **A `SIGSYS` that is not a seccomp trap is not the handler's to answer, and the handler
  now says so.** It reads a syscall number out of the `siginfo_t` and re-issues it; only a
  trap puts one there, and `si_value` sits at the same offset as `si_syscall` on both
  platforms (measured), so `sigqueue` lets the sender choose the number. Decision 3 carried
  that into the default mode by installing the handler everywhere, which is what made a
  pre-existing hazard reachable without asking for the mode. The handler tests `si_code`
  first and, for anything else, restores the default disposition and raises again — what
  would have happened with no shim loaded. Returning instead would swallow a signal the
  process was going to die from, which is a change to the target of the same kind as
  running the wrong syscall. `spike/toys/toy_raw.c`'s `foreign-sigsys` and an acceptance
  leg over all three conditions hold it.
- **An image the shim cannot be loaded into still dies, but later.** 0052's sharpest cost
  is unchanged in kind: a statically linked helper, or any image the preload does not
  reach, takes an unhandled `SIGSYS`. What changed is where — at its first *state-changing*
  call rather than at its loader's first library open — so it gets to start. The README
  limit is reworded, not removed.
- **A target that takes `SIGSYS` away without libc is outside this**, and a statically
  linked Go binary is the case to expect. It does not refuse: the process dies and the
  engine reads `recording_run_failed`. Disclosed in `docs/report-schema.md` item (4), which
  0052 wrote as "a target that manages `SIGSYS` itself" and which now names only the raw
  path.
- **mlr's wall moved from the observer to the thread rule.** Six runs each, same build:
  under `wrappers` all six refuse `oracle_missed_operation` at operation 1 with a
  zero-operation account; under `syscalls` five refuse `multiple_threads_detected`, naming
  the two threads and what each did, and one is judged over 3 crash points — mlr's three
  writers, one `SYS_SECCOMP` trap each in the capture. Recorded in
  `spike/dogfood/2026-09-11-syscall-trap-542b/`.
- **The `SA_NODEFER` premise was re-measured and was wrong.** The handler runs with
  `SIGSYS` blocked, which was justified by "nothing the handler calls is in the trap set".
  Read out of a capture — what the shim issues between each trap and its re-issue, over 20
  traps — it issues `write` 19 times, and `write` is trapped. What makes it safe is that
  the trace channel goes through `traceWrite`, which carries the marker, so the filter
  allows it. Absence was never the reason; marking was.
- **The drift detectors grew with the set, and one became unnecessary.**
  `spike/check-shim-coverage.py` reads the trap set per architecture, holds the oracle's
  copy against the union of both, and asks about every kill-point member of the oracle's
  `known` — the classes read from `isKillPoint` rather than listed in the script.
  Forgetting fails closed in both. It grew a fourth comparison first, when the gate was
  written at each of `ops.zig`'s 31 recording sites: ninety lines that walked the file for
  wrappers that had forgotten it, plus a fourteen-entry table of exemptions. Moving the
  gate into `common.zig`'s wrapper door — one test, on the class — deleted the call sites
  and the check together. Decision 4's flag is what makes that possible, and this is the
  shape it was for.
- **The filter grew from four comparisons to seventeen (aarch64) or twenty-five (x86-64),
  and it runs on every syscall the process makes — measured, and below the noise.** A
  classic-BPF program is a linear chain of `JEQ`s, so a syscall the set does not hold now
  walks 22 instructions instead of 9 on aarch64. Review raised it as the widest path this
  change touches, which is true of the path and not of the cost. Measured with the shim
  preloaded directly, and with two positive controls so that a quiet result could not be a
  shim that never loaded or a filter that never went up — the trace was non-empty and
  announced `observe:syscalls`, and a *trapped* call (raw `write(-1, …)`, 200,000 of them)
  cost **127 ns/call without the filter and 625 ns/call with it**, which says the filter was
  live and puts one trap's round trip at about half a microsecond. Against that, an
  *untrapped* call (`getpid(2)`, two million, five pairs run alternating to cancel drift)
  cost **117.8–118.9 ns/call in every condition**, no shim, shim without the filter and
  shim with it, each pair within a nanosecond of itself. The filter's share of a syscall it
  does not trap is not visible beside the syscall. If a much larger set ever makes it
  visible, the answer is named here so it need not be rediscovered: sort the set by number
  and emit a `BPF_JGE` binary search, which `buildProgram` is already positioned for — it
  computes every jump offset at comptime from the set's own length.
- **Filters stack across `exec`, and each one is now larger.** A seccomp filter cannot be
  replaced, so every image in a self-exec chain that loads the shim installs its own on top
  of what it inherited. The program is 66 instructions on x86-64 where it was about a
  dozen, so a chain reaches the kernel's per-path limit (32,768 instructions) roughly five
  times sooner — on the order of 490 images rather than 2,700, derived from the program's
  length rather than measured. It fails closed: a refused install announces
  `observe:syscalls-failed` and the engine refuses the run.
- **The contract number does not move.** Nothing about the trace's shape, the
  announcement's three values or the report's fields changes — this widens what one
  opt-in mode can see, inside contract v16.
