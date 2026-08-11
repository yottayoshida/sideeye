# ADR 0005 — stdio is observed at flush granularity

- **Status:** Proposed
- **Supersedes:** nothing. Extends the observation set of ADR 0001 (libc interposition)
  to the stdio layer; the addressing rules of ADR 0003/0004 are unchanged
- **Scope:** the shim only. The oracle, the engine and the report are untouched;
  trace contract v4 → v5

## Context

The calibration sweep (2026-08-11, three real targets) found the observation
mechanism's largest wall. Libc-internal calls do not cross the PLT, so a target that
writes through stdio — `fopen`/`fprintf`/`fwrite`/`fclose`, the most ordinary C idiom
there is — never reaches the interposed `open`/`write`/`close`. Measured:

- **taskwarrior** writes all of its data files through stdio; the shim recorded its
  four `fdatasync` calls and nothing else.
- **git** writes almost everything through raw syscall wrappers — 29 of 31 in-scope
  operations were recorded faithfully — and lost the entire run to the two stdio
  operations behind `COMMIT_EDITMSG`. One `fprintf` anywhere is enough.
- The refusal is honest (`oracle_missed_operation`; the strace oracle sees the syscall
  layer), but the class "ordinary C/C++ CLI" is structurally unjudgeable, on both
  platforms: the same probe on macOS shows dyld interposition equally blind to
  libSystem-internal calls.

Measured before decided, and one measurement chose the design: a stdio buffer cannot
hold more than its own size, so **the flush of pending data normally issues exactly one
`write(2)`** (glibc, four shapes probed under strace: 3 small `fprintf` + `fclose` = 1
write; `fflush` per line = 1 write each; a 10 KB `fwrite` = 2 writes *inside the
`fwrite`*; 3000 small `fprintf`s = 8 overflow writes inside the calls plus 1 final
flush). Flushes are the one place where stdio granularity and syscall granularity
coincide. taskwarrior sits entirely inside that boundary (every file: one write, at a
flush point, then `fdatasync`), and so does git's `COMMIT_EDITMSG`.

## Decision

### 1. Record at the flush, kill before the flush

- A write-capable `fopen`/`fopen64` records `.open` (mode-string predicate
  `modeIsWriteCapable`: only plain `"r"` without `+` is read-only; unknown strings err
  toward write-capable, the same fail-closed stance as the flag predicate of ADR 0003).
- `fflush`/`fflush_unlocked` with a non-null stream records `.write` **iff the stream
  has pending bytes**. An empty flush issues no syscall, and recording one would invent
  an operation the oracle never sees — the pending check is a correctness requirement,
  not an optimisation.
- `fclose` records the pending `.write` (if any), then `.close` (forensic, per ADR
  0003: close is recorded, never compared, never a crash point).
- `freopen`/`freopen64` records **[pending `.write`, old `.close`, new `.open`]** — the
  same order as the syscalls it issues. (The plan's first draft recorded only the last
  two; review caught it.)
- Recording happens before the real call, like every other wrapper, so
  `SIDEEYE_KILL_AT` lands **before** the flush: what the crash world loses is the
  unflushed buffer — exactly what a real crash loses.
- `fdopen`/`fdopen64` need no wrapper: no syscall happens at `fdopen` time, the
  descriptor's open was recorded by the raw-syscall wrappers, and later flushes reach
  the stream wrappers via `fileno`.

### 2. Pending bytes are read, never guessed

`__fpending` is resolved at runtime with `dlsym`. If it cannot be resolved, stdio
recording is **disabled entirely** — the shim behaves exactly as it does today, and on
Linux the oracle still refuses stdio targets rather than misjudging them. glibc and
musl both ship the symbol. On macOS, if the symbol is absent, the fallback reads the
SDK-public `__sFILE` fields (`_p - _bf._base`, write-mode flag checked); a unit test
writes two bytes into a real stream and asserts pending == 2 — an ABI shift breaks the
test loudly instead of the judgement quietly.

### 3. What is deliberately not modelled (the fail-closed boundary)

Writes that bypass the flush path are not recorded: a large `fwrite` that goes direct,
overflow flushes inside `fprintf`/`fwrite`, `fflush(NULL)` and `fcloseall` (no API
enumerates open streams), line-buffered flushes, and the exit-time cleanup of streams
that were never `fclose`d (libc-internal; interposing even an explicit `exit()` cannot
enumerate what it will flush). `freopen(NULL, mode, stream)` reopens the same file
through a path the wrapper cannot see, so its open likewise stays unrecorded. Also out
of scope: streams over descriptors 0–2 redirected into the state directory (the
`noteFd` filter, tracked as #13).

- **Linux:** every one of these produces writes the oracle sees and the shim did not
  record — `oracle_missed_operation`, the same refusal as today, from a much smaller
  class. Two toys pin the boundary (buffer overflow; write-then-exit-without-close).
- **macOS:** there is no oracle, so this net does not exist; the residue falls inside
  `--allow-unverified`'s already-declared weaker claim. This is still a strict
  improvement — today macOS observes zero stdio operations under the same claim — and
  the claim's wording does not change.

"One flush = one write" is an expectation, not a soundness requirement: if an `EINTR`
retry or a short write splits a flush, the accounts diverge and the run ends UNKNOWN.
No failure mode of this design reaches a wrong verdict.

## Alternatives considered

- **Force streams unbuffered (`setvbuf(_IONBF)` at `fopen`)**: makes every stdio call
  1:1 with a syscall — and changes the target's write granularity, exploring crash
  states the natural buffered execution cannot produce. A counterexample found in such
  a state would be manufactured by the observer. Rejected; this is the vfork lesson
  ("the target has to survive being observed") in a new coat.
- **seccomp/SIGSYS self-tracing**: observes the syscall layer itself, closing every
  gap at once. Linux-only, a new mechanism class, and of unknown interaction with
  targets that install their own seccomp filters (omamori does). Kept as the
  re-evaluation candidate if a real target gets stuck on in-call writes.
- **Oracle-primary mode**: let strace's account provide the addresses. Requires
  redesigning the kill mechanism, which lives in the shim.
- **Recording `fwrite`/`fprintf` calls as kill points**: the disk does not change at
  call time; the counts can never match the oracle's.
- **Shipping Linux-only** (review's minimal cut): rejected — macOS runs under the
  weaker claim either way, and zero visibility is not safer than boundary-complete
  visibility under the same declared weakness.

## Consequences

- taskwarrior and git cross the observation wall; "ordinary C CLI that writes small
  records and closes its files" becomes a judgeable class on both platforms.
- Trace contract v5: no format or class change, but the recorded set changes meaning.
  On Linux every affected run was UNKNOWN before, but a macOS `--allow-unverified` run
  of a stdio-mixed target could hold a verdict whose reproduce line's `k` counts
  different operations under v5 — the same reason v4 bumped (#23). A v4 shim under a
  v5 engine refuses loudly.
- The shim gains its first dependency on stdio internals (`__fpending` / `__sFILE`),
  guarded by runtime resolution, a disable-don't-guess fallback, and an ABI pin test.
