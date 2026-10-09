# 0089 — A static target is counted from outside, by the engine supervising a seccomp user-notification filter

- **Status:** Accepted (2026-09-27)
- **Amends:** ADR 0052, decision 3 ("`SECCOMP_RET_USER_NOTIF` was declined"), and sets aside the
  owner rejection recorded in ADR 0059's Alternatives ("the `#217` direction, a supervisor tracing
  the target … a second observation architecture for one question"). Both by the owner's ruling
  of 2026-09-27, which chose this design over ptrace and over closing #217. Amendment notes on
  those pages point here.
- **Refs:** #217 (this is its first change; the measurement of real targets is the second).
- **Scope:** `src/supervise.zig`, `src/supervise_linux.zig` (new), `src/main.zig` (the three
  operation spawns, the `__filter-exec` dispatch, startup checks, report lines), `src/oracle.zig`
  (interrupted calls), `src/contract.zig` (`ObserveMode.supervised`, `observe_aux.supervised`,
  the cgroup reading moved here from the shim), `src/mcp.zig`, `src/cli.zig`, `src/boundary.zig`,
  `build.zig` (a test engine), `spike/acceptance.sh`, `spike/toys/toy_supsig.c`, docs.

## Context

A target no shim can be loaded into is refused: a statically linked binary has no loader to take
`LD_PRELOAD`, so the recording run carries no `shim_ready` and the answer is `no_shim_marker`
(`docs/target-classes.md` names Jujutsu, chezmoi, gopass, `gh` and lefthook). `--observe syscalls`
does not help — its filter and `SIGSYS` handler are installed by the shim. #217 asked for an
observer that does not have to live inside the target, under the rules the engine already keeps:
a saved case lands on the same recorded operation or says `case_no_longer_applies`, and the
component that kills and the component that claims completeness are not silently the same.

**Measured before choosing** (2026-09-27, Docker Desktop linuxkit 6.12, aarch64, a prototype
supervisor in C): a statically linked target's four state-changing calls were counted from outside
through `SECCOMP_RET_USER_NOTIF`, and with the k-th notification left unanswered and the target
killed, the k-th call never ran, for k = 1..4, with the state after each as expected; `strace -f`
attached to the same run printed the four calls and, at k = 3, `fsync(...) = ?` and
`+++ killed by SIGKILL +++`; Docker's default seccomp profile allows `NEW_LISTENER`. A target that
catches a signal while its call waits for the supervisor has the call restarted and notified again
— three operations counted as four — unless the filter carries
`SECCOMP_FILTER_FLAG_WAIT_KILLABLE_RECV`, with which it was three. lefthook 1.13.6's `install`
(static Go) wrote the repository from one thread in 3 of 3 runs.

## Decision

1. **A new mode, `--observe supervised`** (Linux 5.19+, aarch64 and x86_64). The engine spawns the
   operation as `sideeye __filter-exec <fd> -- <operation…>`; under an oracle, strace runs that. The
   installer resolves the operation's path first (so the one `execve` it issues is the launch),
   sets `no_new_privs`, installs a filter that answers `SECCOMP_RET_USER_NOTIF` for every kill-point
   spelling the shim's handler traps — plus `copy_file_range` and `pwritev2`, which that set could
   not hold because nothing here is re-issued — and for `close`, the exec and clone families,
   `setsid` and `setpgid`, sends the listener and its own pid back over the inherited socket, and
   execs. The pid does not change, so the process strace or the engine started is the subject, as
   under a shim.
2. **The engine counts, in a thread.** A session thread starts before the spawn, takes the listener,
   and for each notification reads the call's paths from the target (`process_vm_readv`,
   `/proc/<tid>/fd`, `/proc/<tid>/cwd`), asks `SECCOMP_IOCTL_NOTIF_ID_VALID` after every read, and
   applies the shim's own rules: scope by either endpoint, write-capable opens only, a descriptor
   that is a socket or pipe is not ours, one that cannot be placed is `unresolved`, the run's count
   and the crash point. At the crash point it records `kill_landed`, writes the world's
   `cgroup.kill`, signals the subject's process group, and never answers the call. A thread, not the
   wait loop, because `posix.runChildImplWithOps` carries every mode's timeout and budget and a
   listener polled there would change those paths for the modes that have none; the thread is
   joined after the spawn returns, when every process of the run is dead, and before the trace is
   read. (The plan said the wait loop; this was changed while building it.)
3. **The trace is the shim's format, written by the engine**, so the readers stay as they are:
   `shim_ready` (with `observe:supervised`) when the listener arrives and at every later image
   change, the `cgroup` answer after each announcement — `containment.holds` counts one per image
   — `exec`, `fork`, `spawn`, `thread` and `detached` from the boundary notifications, and the
   operations. The installer's own `execve` into the operation is the launch and records nothing;
   the plan's review found that recording it would refuse every run without an oracle as
   `boundary_without_oracle` (measured red by mutation). `readTrace` and `containment.holds` are
   unchanged — the plan expected a branch in each; writing the shim's records made them unnecessary.
4. **The cgroup is required.** Without the shim there is nothing inside a process to notice it left
   the process group, so the crash point's kill reaches the run through the world's cgroup; an
   engine that cannot create one refuses the mode as a setup error.
5. **The two witnesses stay two** — the answer to ADR 0052 decision 3. That decision declined user
   notification because the engine would then be the supervisor and `oracle_verified` would become
   "one observer agreed with itself". Here the engine counts through the kernel's notifications and
   strace watches the same run through ptrace: two processes, two kernel interfaces, neither reading
   the other's account. What changed since 0052 is that the claim was measured rather than argued —
   strace attached to a supervised run, and the oracle comparison agreed on every operation.
6. **Under this mode the oracle drops a call a signal interrupted** (`= ? ERESTART*`, read at the
   end of the line, where strace puts the return — a target-chosen string in the arguments cannot
   reach it): the entry either restarts, as its own line, or returns `EINTR`, and here the engine
   counted nothing for it, because the signal withdrew the notification before the engine took
   it. Measured as a refusal in 1 of 3 runs of a signal-heavy target before the change, 8 of 8
   agreeing after. **Not in the other modes**: the shim counts at libc's entry whatever the kernel
   does next, so a call that returns `EINTR` without `SA_RESTART` and is retried is two counts there
   and two entries here; dropping one would turn an agreement into `oracle_saw_phantom` (review of
   this change, which first applied it everywhere). **The drop is right for a call interrupted
   before the engine took it**, and that is the case measured. A call the engine took and let
   run, and that then blocked inside the kernel and was interrupted there — an `open` of a FIFO
   in the state directory — is counted by the engine again when it restarts, while the oracle
   now counts it once: the run refuses `oracle_saw_phantom` rather than judging (second review).
   Regular files, which is what a state directory normally holds, do not block that way.
7. **No `contract_version` bump, no new `unknown_reason`, no new `next_step`.** v14 bumped because
   the countable set of an unchanged target moved under a new mode; here no existing mode's numbering
   moves, and a bump would turn every saved case into `case_no_longer_applies` for nothing (ADR 0059
   widened the trap set without one). A case still does not record its mode (ADR 0052's known
   limit): replayed without the flag, a static target's case refuses `no_shim_marker`, never a wrong
   verdict. **Amended 2026-10-09 (ADR 0100):** a case saved under this mode now records it
   (case_version 6) and replays under it without the flag, so the refusal above is left to cases
   saved before that change. The report's `replay` and `reproduce` lines name `--observe supervised` instead of a
   shim. The static `no_shim_marker` detail says, beside `class_wall`, that this mode exists.
   **Amended 2026-09-29 (ADR 0090): the "no new `next_step`" of this item, and the detail
   sentence, no longer hold.** `observe_supervised` was added, and the detail line states the
   linkage only; the step names the mode. The reason this ADR gave for leaving the step alone —
   "the step set is closed (frozen surface 2)", in the Alternatives below — was wrong:
   `docs/contract-freeze.md` surface 2 closes `unknown_reason`, and `setup_error_reason` is the
   other closed set; `next_step` is neither. No `contract_version` bump and no new
   `unknown_reason`, as here.

## Alternatives considered

- **ptrace.** strace, the oracle, is a ptracer, and a process has one: the oracle would move to
  another run, which ADR 0054 withdrew. The wait loop would also have to become a tracer's.
- **strace's `--inject`.** Numbers per syscall name, not one sequence across the families, and the
  component that kills would also be the witness.
- **The filter installed by the engine's fork stub.** Under an oracle the stub execs strace, so the
  filter would be strace's and the subject would be strace (plan review, C2).
- **A supervising process of its own** (the installer forking a supervisor that writes the trace).
  It keeps `main.zig` almost untouched, but the supervisor sits in the run's cgroup and outlives the
  subject by the time it takes to notice the end, which the engine's lingering-process watch
  (`cgroupStop`, `noteLingering`) would read as a survivor on every contained run.
- **A `next_step` naming this mode for a static target.** The step set is closed (frozen surface
  2); the sentence beside `class_wall` names it instead. **Reversed 2026-09-29 by ADR 0090**: the
  premise was false (see Consequence 7's amendment), and the two lines of one refusal disagreed.

## Consequences

- Walls of this mode, in `docs/cli.md` and `--help`: writes from two or more threads refuse
  `multiple_threads_detected` — the thread-order records (v18) are the shim's, read inside
  `pthread_create` and `pthread_join`; a target's own seccomp filter that returns an error, traps or
  kills a call acts before this one (the stronger action wins) and a target using `NEW_LISTENER`
  itself gets `EBUSY`; `no_new_privs` keeps a setuid child from its privilege; i386-compat and x32
  calls pass unseen; macOS has no equivalent. A target's other threads can rewrite a path argument
  between the read and the call — the design assumes a target that is not working against its
  observer, as the shim does.
- `sideeye_replay_case` over MCP has no `observe`, so a supervised case cannot be replayed through it
  (ADR 0074 kept replay's surface fixed) — **amended 2026-10-09 (ADR 0100): it can now, with the
  surface still fixed, because the case carries the mode and the engine takes it from there;** `sideeye_explore_config` gained the value (frozen surface
  5, additive, `docs/contract-freeze.md`).
- A test engine, `sideeye-testsupervisedelay` (`-Dtest-supervise-delay`), holds each answer 2 ms so
  the acceptance leg for `WAIT_KILLABLE_RECV` does not depend on a race: with the shipped engine the
  window is microseconds, and a build without the flag passed 8 of 8 runs. With the delay and without
  the flag the run never finished (killed after nine minutes); with both, 5 of 5 agree.
- Measured on aarch64 only. x86_64's legacy spellings (`open`, `creat`, `rename`, `fork`, `vfork`
  and the rest) are compiled and first executed by CI's acceptance, contained.
- The real static targets were not re-measured by this change; #217 stayed open for that
  measurement. **Re-measured 2026-09-27** (`spike/dogfood/2026-09-27-supervised-static/`):
  busybox-static's `sed -i`, direct and through a dynamic `sh` that `exec`s it, PASS 3/3 with 5 of 5
  preflights accepted, judging the file it rewrites; `gh` PASS 3/3 judging no file it wrote; chezmoi,
  gopass and lefthook refused as first defined (their own second run, a random secret, a checker
  that cannot be falsified) and reach PASS 3/3 only with chezmoi's `--force`, gopass's `rm` in
  place of `generate` and lefthook without the checker, judging no file they wrote; Jujutsu stops at the thread wall 5 of 5.
