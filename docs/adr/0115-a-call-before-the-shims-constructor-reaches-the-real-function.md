# 0115 — A call before the shim's constructor reaches the real function, and one that reaches the state refuses

- **Status:** Accepted (2026-10-10)
- **Refs:** #753 (met on the 2026-10-09 user-data-4 dogfood run: OpenImageIO 2.5.18's `iconvert`
  and ROOT 6.40.04's `rootrm` end `recording_run_failed`, SIGABRT); #405 (the per-path
  reconciliation, `state_changed_unaccounted`); contract v8 (no descriptor is exempt from
  observation).
- **Scope:** `shim/src/common.zig` (`reach`, `resolveAll`, the calls-before-the-constructor mark,
  `reportPreInit`, the mark's carry across `exec`), `shim/src/ops.zig` (the stdio and exec
  wrappers), `shim/src/syscalls.zig` (TSYNC), `src/contract.zig` (`unresolved_kind.before_constructor`,
  `env.before_constructor`), `src/boundary.zig` (the refusal's sentence). Linux: macOS calls the
  originals directly and never had the table.

## Context

On Linux the shim reaches each real function through a table, `real`, filled by
`dlsym(RTLD_NEXT)` in its own `.init_array`. Another shared library's constructor can run before
that — the loader orders constructors by dependency, and `LD_DEBUG=files` on the measured shape
shows the library's before the shim's — and a call interposed from it met a null entry and
answered `-1`. Thirty-nine wrappers did. `pthread_create`'s callers expect an error number, so a
C++ `std::thread` started there threw `std::system_error` "Unknown error -1" and the process
aborted; ROOT's `GetCryptoRandom` opens `/dev/urandom` through a `std::ifstream` and the open
failed. Both tools exit 0 by hand.

Letting those calls through has a second half. They are not recorded — nothing can be until the
trace is open — so a call that changes the judged state lands before crash point 1 in every world
and the windows around it are never explored. When a later recorded write names the same path,
the per-path reconciliation reads the change as accounted for and a verdict comes out. Until now
such a target never got that far: the call answered `-1` and it usually died, an honest UNKNOWN.

## Decision

1. **`reach(name)`**: a wrapper takes the table's entry, or, when the table has not been filled,
   looks the symbol up there and then. Nothing is written back: `resolveAll` stays the table's only
   writer, so a thread a constructor started cannot race it, and once `init` has run the entry is
   one load, as before. `resolveAll` fills the table from the struct's own field names, the same
   names `reach` uses. A symbol that is genuinely missing answers an error number where the real
   function returns one (`EAGAIN` for `pthread_create`, `ENOSYS` for `posix_spawn`), and `-1` with
   `ENOSYS` set — or null with it set — elsewhere, rather than a bare `-1`.
2. **A mark for a call that reaches the state before `init` has finished.** In each recording entry
   point's not-yet-armed branch, a write-capable call whose path — or whose descriptor's path,
   because a descriptor can come from an earlier image — is inside the state directory (either
   spelling, read from the environment) sets a mark. One atomic word holds where this image stands
   (before, recording, unused) and the mark; `init`'s last act swaps in `recording` and reads the
   mark it displaced, so a call that loses that race is recorded the ordinary way. A stream opened
   for writing (`fopen`, `freopen`) reaches the mark too, whether or not `fpending` — which `init`
   looks up — is there yet; a descriptor opened read-only is not marked, whatever goes through it.
   An `exec` before `init` would carry the mark out of existence with the image, so it is handed
   on in the environment (`SIDEEYE_BEFORE_CONSTRUCTOR`; `execve`'s envp is rebuilt as the operation
   count's carry rebuilds it) and the next image's `init` reports it — through the three entry
   points the shim interposes; the `execl` family, `execvpe`, `fexecve` and `execveat` call the
   kernel from inside the C library and escape it, as they escape the count's carry (ADR 0018).
   Only the process that set the mark hands it on: a `vfork` child shares its memory and must not
   `setenv` there. The engine pins the variable empty for every child it starts, as it pins
   `SIDEEYE_SEQ_BASE`, so a value in the operator's shell cannot refuse a run; the carried value is
   therefore never empty (`?` when the path was not read in time).
3. **One `unresolved` record, `before-constructor`, written by `init` after the announcement and
   the cgroup record** — in front of `shim_ready` the engine would read it as another process's and
   speak of a process boundary — naming the first such path when it was published in time. The
   engine refuses on it through the path every unresolved record takes: `unresolvable_path`, whose
   sentence for this kind says the call was made before the shim's constructor and so was not
   numbered.

4. **`--observe syscalls` installs its filter with `SECCOMP_FILTER_FLAG_TSYNC`.** Its comment
   said the flag was not needed because the constructor runs before the target creates any thread.
   That stopped being true here: a pool another constructor starts now starts. Without the flag
   such a thread had no filter, while the process-wide `armed` kept the wrappers silent for it —
   measured, a run whose pre-constructor thread wrote the state was PASS 3/3 with that write in no
   account. With it, every thread takes the filter (no_new_privs with it), or the install fails
   and the run is refused as before.
5. **macOS is unchanged.** The originals are called directly there from the first instant, and
   the system libraries make interposed calls in great number while libSystem is starting; the
   mark costs nothing and does nothing on that platform.

## Alternatives considered

- **Initialise the shim first** — not available: constructor order between shared libraries is the
  loader's, `DT_PREINIT_ARRAY` belongs to executables only, and a constructor priority orders only
  within one object.
- **Run `init` from the first call that finds the table empty** — rejected: `init` assumes it runs
  on the main thread before the target has created any (the thread slot it announces from, the
  seccomp filter it installs), and the first such call can be on a thread a constructor started.
- **Write the looked-up entry back into the table, atomically** — rejected: the table's other
  readers are not atomic, so mixing them changes the race rather than removing it.
- **Only fix `pthread_create`** — rejected: ROOT failed on the `fopen` side.
- **Let the calls through and only document that they are not counted** — rejected: a target that
  is an honest UNKNOWN today would become a verdict nothing stands behind.

## Consequences

- `iconvert`- and `rootrm`-shaped targets run under the shim as they do by hand, and are judged.
- A target whose library constructor writes into the state directory is refused, where before the
  write failed and the target ran on without it; the refusal names the path.
- Not counted, still: a call before the constructor that reaches the state some other way than a
  recorded entry point (a raw syscall), which is the gap every raw syscall already is; and a
  process that ends before any constructor of the shim's has run in it — a child a constructor
  forks and that exits there — takes its mark with it, the gap a process that never loaded the
  shim already is.
- Under `--observe syscalls`, in an image that mode `exec`'d into, a call before the constructor
  that traps ends the process: the filter crossed the `exec`, its handler did not. Before #753 the
  call answered `-1` and issued nothing; now it reaches the kernel. The run is refused
  (`recording_run_failed`), and this is the README's existing limit for that mode.
- Over-marking, conservative, rare: an `*at` call whose base directory was deleted is marked
  wherever that directory was, because `resolveAt` asks the state directory `init` has not set
  yet; a `fflush` or `fclose` of a writable stream on a state file with nothing pending, because
  `fpending` is not looked up yet; a `close` of a writable descriptor on a state file that a
  constructor inherited and closed without writing (the armed side records that close and does
  not refuse); and a thread a constructor started can record between `active` and the
  announcement, which the engine reads as another process's. Each is a refusal, not a verdict.
- Under `--observe syscalls`, a thread a constructor started with `SIGSYS` blocked — a pool made
  after blocking every signal — dies at its first trap once TSYNC puts the filter on it: the
  guards that keep `SIGSYS` deliverable were not up when it was made (`docs/report-schema.md`'s
  gap (e)). A refusal (`recording_run_failed`), not a verdict.
- Unmeasured hang: a constructor that `dlopen`s a library whose own constructor starts a thread
  and waits for it, while that thread makes an interposed call — the thread's `dlsym` waits for the
  loader's lock the `dlopen` holds. Before #753 the call answered `-1` instead.
- A call made before the constructor pays a `dlsym`; one made from a signal handler in that window
  meets the loader's lock where it used to meet `-1`. After `resolveAll` nothing is looked up
  again: a null entry then means the C library lacks the symbol. Measured on glibc 2.36 (the
  acceptance image), 2.41 (Debian trixie, OpenImageIO's `iconvert`, now FAIL 1/7 where it was
  `recording_run_failed`) and in CI on 2.39; glibc 2.28–2.33, where `dlsym` lives in `libdl`, were
  not measured.
- Not frozen: `unresolved_kind` is the trace contract's, open by design; `contract_version` does not
  move, because an engine that predates the kind refuses a record it does not know (it is not
  `unlinked-fd`, the one kind it lets through).
