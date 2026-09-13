# 0063 — A handler's mask does not take `SIGSYS` with it, and the filter does not trap the signal calls

Status: Accepted (2026-09-13)

Amends **ADR 0059** — decision 5, and the Alternatives entry that kept "trap `rt_sigaction`
and `rt_sigprocmask` in the filter" as the next step if a target needed it. Nothing else in
0059 moves.

## Context

ADR 0059 decision 5 interposes libc's `sigaction`, `signal`, `sigprocmask` and
`pthread_sigmask`, so that under `--observe syscalls` a request naming `SIGSYS` through them
is declined, and it disclosed the raw path as the gap.

#556 reported CPython's `subprocess` dying of signal 31 when the program it spawns does not
exist. Re-measured on 2026-09-13, that was already fixed by decision 5 as #562 shipped it:
v1.3.0 printed `returncode -31` on all four of the issue's rows with Python 3.11 on glibc 2.36
and on the two that find the program through `PATH` with Python 3.13 on glibc 2.41, main
printed `FileNotFoundError` on all four in both, and a main build with the `sigaction` guard
taken out brought `-31` back on the same rows. Probing the other ways a process the shim is loaded into loses the
signal, on main, found three that still kill:

- **A handler for another signal installed through libc `sigaction` with every signal in its
  `sa_mask`.** The kernel blocks that mask while the handler runs, so `SIGSYS` is blocked and
  a trapped call inside the handler kills the process: a `SIGUSR1` handler written that way
  died of signal 31. libuv installs its handlers that way, and node 20.19.2 was refused
  `recording_run_failed` for a `process.on('SIGUSR2')` handler and for an `execFile` child.
  This is a libc call the shim already interposes; decision 5 did not look inside the
  request.
- **Raw `rt_sigaction(SIGSYS, SIG_DFL)` and raw `rt_sigprocmask(SIG_BLOCK, all)`** — signal
  31. The path 0059 disclosed.
- **glibc's `posix_spawn` with a file action that opens for writing.** The child runs its
  file actions before the exec with every signal blocked and dies of signal 31 (glibc 2.36
  and 2.41).

The first is fixable where the shim already stands. The other two are the raw path, and the
question was whether 0059's next step should now be taken.

## Decision

**1. `sigaction` takes `SIGSYS` out of the `sa_mask` of a request for any other signal.** In
`syscalls` mode, a request whose mask holds `SIGSYS` reaches the C library as a copy with that
one bit clear; the handler, the flags, the restorer and every other bit are the caller's. A
request without the bit is forwarded as the caller's own pointer, and a request for `SIGSYS`
itself is declined as before. The default mode changes nothing.

**2. The copy reads glibc's `struct sigaction` through std's `c.Sigaction`, pinned to a
measurement.** Measured with `offsetof` and `sigaddset` on aarch64 and on x86_64, glibc 2.36:
152 bytes, `sa_mask` at 8 for 128 bytes, `sa_flags` at 136, and `SIGSYS` at byte 11 as `0x40`
(`spike/followup-556/transcripts/saoff-*.txt`). A comptime block in `shim/src/syscalls.zig`
stops the build if std's struct stops matching, and unit tests hold the removal against
glibc's own `sigfillset` and `sigismember`. The copy is on the stack, because `sigaction` can
be called from a handler.

**3. The filter does not trap `rt_sigaction` or `rt_sigprocmask`: 0059's next step is not
taken.** Two designs were measured, and each kills targets that run on main today.

- *Trap both, and decline the `SIGSYS` part in the handler.* An exec'd image's startup issues
  them before the shim's constructor has installed a handler — glibc 2.31 issues
  `rt_sigaction(SIGRTMIN)` and `rt_sigaction(SIGRT_1)` in each image measured, and OpenSSL
  1.1.1w adds `rt_sigaction(SIGILL)` and `rt_sigprocmask(SIG_SETMASK, [])` (bullseye, aarch64,
  `probe-startup-bullseye.txt`) — so each such image would take a trap no handler receives.
  glibc 2.41's `posix_spawn` clones with `CLONE_VM|CLONE_VFORK|CLONE_CLEAR_SIGHAND` where
  `clone3` is allowed (`probe-masks.txt`), and that flag leaves the child no handler (its documented effect, not observed). And the
  oracle retracts a refused call when it reads the `SIGSYS` that refused it, which a first
  review found would erase a real write next to an `rt_sigprocmask` line — not measured.
- *Trap only a call whose arguments name `SIGSYS`.* `pthread_create` blocks with
  `SIG_BLOCK ~[]` around its clone (glibc 2.41, `probe-masks.txt`), and `~[]` names `SIGSYS`,
  so an image whose startup creates a thread would die before the shim's constructor ran. A
  Go child built with cgo blocks every signal with `SIG_SETMASK` and then issues a raw
  `rt_sigaction(SIGSYS)` between fork and exec — from Go's source, not measured.

What decision 3 leaves uncovered is named in `docs/report-schema.md` item (4) instead.

## Alternatives Considered

- **Trap the signal calls in the filter**, either design above. Rejected on the measurements
  in decision 3.
- **Write the gap down and change nothing.** Rejected: node dies of a libc call the shim
  already interposes, and one bit of the request fixes it.
- **Clear the whole `sa_mask`** rather than one bit. Rejected: the target's handler would run
  with signals deliverable that it asked to block. `toy-raw samask` checks inside its handler
  that `SIGUSR2` and `SIGTERM` are still blocked, and a shim clearing the whole mask exits 3
  there.
- **Install the shim's own handler with every signal in its `sa_mask`**, so that no other
  signal's handler can run while it does (item (4)(c)). Rejected: the re-issued call would
  then not be interruptible by a signal the target relies on, on every trap, to close a gap no
  target has been seen in.

## Consequences

- **A target can see it.** A handler installed with `SIGSYS` in its mask reads back without
  it. A `SIGSYS` sent to the process while such a handler runs is taken during the handler
  rather than after it; under the shim a `SIGSYS` that is not a trap kills the process either
  way (0059, Consequences) — that follows from the design and was not measured.
- **What still takes `SIGSYS` away is named, not refused.** `docs/report-schema.md` item (4)
  lists the ways known by what the kernel does — the raw calls and the C library's internal
  ones, a mask applied for one call or one handler, a signal handled inside the shim's handler,
  a trap filter of the target's own, a call made before the guards are armed, a mask carried
  across `exec`, a child that lost Sideeye's environment. A target that dies of one is
  refused; a child that dies of one while the target carries on is not — measured as an
  accepted preflight of the `posix_spawn` child, whose file action opened outside the state
  directory, so a run judged without a dead child's state-directory work was not measured. DESIGN's "a child the shim *is* loaded into … is unaffected"
  was not true of that child and now names it, and README says what happens to a process
  whose `SIGSYS` is blocked or reset — it dies at its first state-changing call, and only a
  target's death is refused — rather than that the shim keeps the signal deliverable.
- **mlr runs as it did.** Six runs each of the define in
  `spike/dogfood/2026-09-11-syscall-trap-542b/`, main and then this change, same image: main
  refused `multiple_threads_detected` five times and passed once over 4 worlds, this change
  three and three, and no run of either died. Which thread performs which write is Go's
  scheduler, and six runs cannot tell one pass in six from three.
- **Held on every push** by two legs of `spike/acceptance.sh`: `toy-raw samask`, seen red on
  main, with the removal taken out and with the whole mask cleared; and #556's four Python
  rows, which pin #562's fix and not this one — green with the removal taken out, red with
  `returncode -31` on every row with the `SIGSYS` guard taken out.
- **The contract number does not move.** Nothing in the trace, the announcement or the
  report changes.
