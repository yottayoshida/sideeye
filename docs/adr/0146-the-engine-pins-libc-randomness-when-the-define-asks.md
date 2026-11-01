# 0146 — The engine pins libc's randomness when the define asks, through a library of its own

- **Status:** Accepted (2026-11-01)
- **Amends:** ADR 0041 (its first alternative, "the engine applies the apparatus", for `pin:random` only)
- **Refs:** #951; `spike/dogfood/2026-10-12-shipped-v1120/` (KeePassXC judged with a hand-written `pin-random.c`).

## Context

A target whose writes depend on randomness is refused for non-repeatable runs unless its author pins the
randomness by hand. The dogfood record crossed most such targets with scratch paths and checkers; KeePassXC
needed a hand-written preload (`pin-random.c`) on `/etc/ld.so.preload`, which needs root, and a pin shared by
every process made seeded UUIDs collide. ADR 0041 had the owner decline the engine applying apparatus: the engine
would be composing the experiment rather than judging it. On 2026-10-31 the owner ruled that the engine may pin
randomness when, and only when, the define asks; that the seed is drawn per invocation and kept in the case; and
that a define asking for it runs only where the engine can make cgroups. On 2026-11-01 the clock was taken out of
this decision (a wall clock stopped at one instant lets timed waits in a world expire where the recording's did
not); it is a separate question.

## Decision

1. `apparatus` gains one kind, `pin:random`. It is applied, not checked: the report lists it in `apparatus`, never
   in `apparatus_unchecked`.
2. The pin lives in its own library, embedded in the `sideeye` binary and written beside the run's work directory
   when a define asks for it, then put ahead of the shim in the operation's `LD_PRELOAD`. A run whose define does
   not ask preloads no such library, and hands its operation the seed variables empty, as it does `SIDEEYE_SEQ_BASE`.
3. Through libc's entry points only: `getrandom`, `getentropy`, `arc4random*`, and reads of `/dev/urandom` and
   `/dev/random` (the device is opened for real; reads of a remembered descriptor that is still that device are
   served from a ChaCha20 stream).
4. One seed per invocation, drawn from the real source and kept in the case (v8); each process derives its own from
   its parent's and a count, carried in the environment an exec or spawn passes on — rebuilt for the call, not set
   with `setenv`, except for `execv`, `execvp`, `system` and `popen`, which read `environ` themselves. Every key is
   claimed once per run by an exclusive create in the work directory, so a key that reaches two processes — the
   children of a relay the library is not loaded in — is drawn from by the first and the second draws the real source,
   and the two runs differ rather than agree on a shared stream.
5. Refused by name where it cannot hold: `--observe supervised` (no shim, no preload), macOS, a Linux host where the
   engine cannot make cgroups, and a work directory the loader would skip.

## Alternatives considered

- **Inside the shim.** Every run would carry the new exports, and the shim's own calls would meet them.
- **A constant seed.** The pinned bytes would be computable by anyone holding the source. Declined by the owner.
- **The clock in the same change.** Taken out by the owner; see the context.
- **A memfd in place of the device.** End-of-file, a regular-file `fstat` and a writable descriptor each changed
  what a reader sees.

## Consequences

- A case carrying `pin:random` is version 8, holding the seed and the generator's version; an earlier binary
  refuses it at parse.
- What is not reached — raw syscalls, a statically linked Go binary, RDRAND, the auxiliary vector's AT_RANDOM,
  `/proc/sys/kernel/random/uuid`, two threads drawing in varying order — is listed in `docs/apparatus.md`; each
  leaves the two runs different, which is refused as before.
- The pinned bytes are recomputable from the case. The report and `docs/apparatus.md` say so, and that a define
  touching real keys or network credentials should not ask for it.

## Residual windows

None: the pin changes the bytes an operation reads, not which of its calls the shim and the oracle see, and what it does not reach leaves the two runs different, which is refused.
