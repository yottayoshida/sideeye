# 0151 — The engine stops the wall clock when the define asks, and translates the waits that take a deadline on it

- **Status:** Accepted (2026-11-03)
- **Amends:** ADR 0041 (its first alternative, "the engine applies the apparatus", now for `pin:clock` too) and ADR 0146
  (the clock it took out, in the same library).
- **Refs:** #1025; #951; `spike/dogfood/2026-10-12-shipped-v1120/` (KeePassXC judged with libfaketime on
  `/etc/ld.so.preload`).

## Context

A target that writes the time it ran is refused for non-repeatable runs unless its author stops the clock by hand.
KeePassXC on FAT reached PASS with `pin:random` only because its define also loaded libfaketime through
`/etc/ld.so.preload`, which fakes the clock of every process on the machine, strace and the engine's shell included.
ADR 0146 took the clock out of `pin:random`: a wall clock stopped at one instant may let a timed wait end where it would
not have.

Measured on 2026-11-03, aarch64 Linux, before designing:

1. KeePassXC on FAT reaches PASS 6/6 with libfaketime stopping the wall clock and `DONT_FAKE_MONOTONIC=1`: the monotonic
   clocks need not stop.
2. A stopped clock that only answers reads changes what a program does. A wait on `pthread_cond_timedwait` or
   `sem_timedwait`, deadline two seconds on, to be woken at 0.3 seconds: with the instant months in the past it timed
   out at once, with it in the future a wait that should expire never did. Under `explore --oracle` the first reached
   PASS 5/5 with the state holding `timeout` where the unpinned run left `woken`: the recording and every world took the
   same wrong path, so nothing differed. libfaketime, which translates such deadlines, left `woken`.
3. Every run restores the state before it starts, the recording too, and a restore does not keep modification times:
   whatever the instant, the state's files are dated after it in every run.
4. libfaketime named in `LD_PRELOAD`, before the shim or after it, held KeePassXC in a futex wait at its first run; the
   same binary ran under libfaketime without the shim.

## Decision

1. `apparatus` gains `pin:clock`, applied as `pin:random` is, by the same library, and independent of it.
2. The instant is the real wall-clock time, read once per invocation where the pin library is written, after the setup
   and before the recording, and kept in the case (version 11, `pin_clock`); a replay uses the case's. The runs of
   `invariant = ["rerun"]` read it too.
3. The library answers `clock_gettime` for `CLOCK_REALTIME` and `CLOCK_REALTIME_COARSE`, `time`, `gettimeofday` and
   `timespec_get` with the instant, and translates the deadline of the listed waits (`docs/apparatus.md`) to the real
   now plus the deadline minus the instant, saturating. A condition variable's clock is read from the bit glibc keeps it
   in, found by comparing a condition variable made for the monotonic clock with a default one — when the library loads,
   or, where the condattr calls are not loaded yet (libpthread before glibc 2.34), at the first `pthread_cond_timedwait`;
   when that comparison does not single out one bit, the process is stopped with a message.
4. Refused by name where it cannot hold or would mislead: `--observe supervised`, macOS, a work directory the loader
   would skip, beside `preload:libfaketime`, and under `--interleave`. No cgroup is required.

## Alternatives considered

- **Load the system's libfaketime** in `LD_PRELOAD` when the define asks. It stopped KeePassXC at its first run beside
  the shim (context 4), and the engine would depend on another project's internals and leave its shared memory behind
  every killed world.
- **Document libfaketime on `/etc/ld.so.preload`** and pin nothing. The clock stays faked for every process on the host.
- **Answer the reads, translate nothing.** Context 2: a PASS on a path the program does not take.
- **A clock that advances**, from the instant at each process start. A tool writing nanoseconds writes different bytes
  in every run; KeePassXC passed only because its timestamps are in seconds.
- **A fixed date**, the same in every invocation. A deadline handed to a wait the library does not translate would then
  be months off rather than as long as the invocation has run.
- **Advance the clock by the time spent in translated waits.** A wait entered again with the same deadline would end
  when it should; a wait woken early would advance the clock by a different amount in each run, and every target that
  writes the time after one would be refused.
- **Remember a condition variable's clock when it is initialised**, in a table. A lock, an address reused after
  destroy, a shared condition variable and a full table each needed a rule.
- **Read the condition variable's clock at a fixed offset.** glibc 2.41 removed a field in front of it.
- **Give the rerun invariant's runs the instant plus one second**, so they do not mint the crashed run's time-derived
  ids again. Its runs are compared with runs from the starting state, which would read the later time too, and a
  target keeping the time an earlier run wrote — a migration recorded with the time it was applied, killed between
  two — then ends as neither: measured, a toy migration did not reach PASS that way and does with one instant.
- **Probe the condition variable's clock in the library's constructor only.** Before glibc 2.34 the condattr calls
  are in libpthread, which a process that never waits does not load; there the probe waits for the first
  `pthread_cond_timedwait`.

## Consequences

- A case carrying `pin:clock` is version 11; an earlier binary refuses it at parse.
- `docs/apparatus.md` lists what the pin does not reach in two kinds: reads it does not stop, which leave the two runs
  different and are refused, and waits judged on another path — a wait entered again with the same deadline waits its
  whole remainder again (measured: 4.0 seconds against 1.0), a deadline handed to a wait the library does not translate,
  a loop timing itself by the wall clock, a file dated after the instant. A replay, whose instant is the case's, meets
  the second kind days late.
- The acceptance suite runs a toy reading the clock through every entry point and every listed wait, woken early and
  left to its deadline, on glibc 2.36 and 2.41.

## Residual windows

None: the pin changes the time an operation reads and when its waits end, not which of its calls the shim and the oracle see; what it does not reach is refused, or judged on the path the pinned run took, which docs/apparatus.md lists.
