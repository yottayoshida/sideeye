# 0124 — A run stopped by a signal stops its child, then ends by that signal

- **Status:** Accepted (2026-10-11)
- **Refs:** #819 (found by reading the source in the 2026-10-11 survey); `--stop-when-orphaned`
  (#269), which covers an engine whose launcher went away, not an engine that went away itself.
- **Scope:** `src/posix.zig` (the handlers, the spawn path's block, registration and checks),
  `src/refuse.zig` (`stopForSignal`, `stopLiveSidecar`), `src/main.zig` and `src/mcp.zig` (where the
  handlers are installed), `src/supervise_linux.zig` (the listener thread's mask), `docs/cli.md`.

## Context

Every child the engine starts leaves the engine's process group before it runs, so that a crash
point's `kill(0, SIGKILL)` cannot reach the engine. A terminal's Ctrl-C therefore reaches the engine
alone, and the engine installed no handler: it died of the default action and nothing stopped what
it had started. The operation went on writing the state directory until it ended by itself, a hung
one never did, `--world-timeout` could not fire because the engine enforcing it was gone, and a
contained run's cgroup stayed behind. A CI job cancelled with SIGTERM ended the same way. The MCP
server is in the same position with its engine.

## Decision

`explore`, `replay` and `preflight` (and so `demo`, which execs into one) and `mcp` install handlers
for SIGINT, SIGTERM, SIGHUP and SIGPIPE, with `SA_RESTART`, after the arguments are parsed.

- **The handler only signals; the process stops in ordinary code.** It records the signal and, if a
  child is being waited on, sends its process group `SIGKILL` (an engine started by the MCP server
  gets the signal itself, so that it can stop its own children first), arms a 5-second alarm and
  returns. The wait returns as it does for any child that died, and `stopForSignal` stops `fs_usage`
  the usual way, writes one line and ends the process by the same signal. With no child and no
  `fs_usage`, the handler ends the process at once.
- **A recorded signal takes effect where nothing it waits for remains, all in `posix.zig`:** when
  the waited child returns — before the spawn path hands its end to the caller, since a setup this
  process killed would otherwise be reported as one that died of signal 9, and a world as one that
  reached its crash point — when `fs_usage` is gone, when a stop of it ends, and before a new child
  starts. Those are the only states in which a signal is recorded and not acted on, so no verdict
  path needs a check of its own.
- **Ends by the signal, with no verdict.** Exit codes 0–3 are promised for a run that produces a
  verdict (`docs/contract-freeze.md`, surface 3); this one produces none, and a shell sees 130, 143
  or 129, as it did before.
- **A child the signal cannot end is named and left after 5 seconds** (`world_kill_grace_ms`): a
  process in an uninterruptible wait, or one that switched credentials, does not die of `SIGKILL`
  from the engine, and the wait for it has no bound. Without one, Ctrl-C would stop returning the
  terminal, which it always did. The MCP server waits 20 seconds for its engine, which stops its own
  child and `fs_usage` first. The alarm is cancelled once the child has returned, so it does not
  cut short the stop of `fs_usage`. A second signal ends the run at once, at any point: whoever sends
  it will not wait. Either way `fs_usage` is first sent the SIGTERM that stops it, not waited for.
  (Amended 2026-10-28, #896: this was SIGINT, which sudo on macOS does not pass on, because it
  relays SIGINT only when `si_code` is `SI_USER` and macOS leaves it 0 on a `kill()`; ADR 0031 §4.)
- **What the process started with is kept.** A signal ignored at startup gets no handler; children
  get the mask, the SIGCHLD and SIGALRM dispositions the engine started with, and the four signals
  at their default, before they exec. An inherited SIGCHLD of `SIG_IGN` is set to its default in the engine
  alone, because a child auto-reaped leaves an id nobody holds, and the handler must never signal an
  id nobody holds; the registered child is cleared before every wait that reaps it, for the same
  reason.
- **Signals are blocked from before a run's cgroup is made until the child is registered**, and
  `fs_usage` is registered before they are unblocked; the supervised listener thread is created
  with them blocked. No handler runs where a child or a cgroup exists and is not yet known.
- **Stopping `fs_usage` is a stop of its own.** It starts `sudo -n /bin/kill`, which goes through the
  spawn path; while it runs, a recorded signal stops nothing new, and `fsu_live` is cleared only once
  `fs_usage` has stopped.

## Alternatives considered

- **A new `unknown_reason`, `interrupted`.** Surface 2 is a closed set, and the run has no verdict
  to report; the signal is the answer.
- **SETUP ERROR under an existing reason.** Nothing about the setup was wrong.
- **`PR_SET_PDEATHSIG` in each child** (the issue's second direction). It is for an engine killed
  by `SIGKILL`, which is not an interruption it can see, and it reaches only the direct child — not
  the target under strace. For the MCP server's engine it would close `--stop-when-orphaned`'s gap on
  Linux when the server is `SIGKILL`ed; that is a promise of its own, not this one.
- **Restoring the state directory before ending.** No document promises the state after a run
  (`docs/cli.md`: the state afterwards holds what the last recovery left), and a restore after an
  interruption is a run of its own that can itself be interrupted.
- **Handling the stop inside the handler.** Stopping `fs_usage`, writing the line through the
  allocator and removing the cgroup are not async-signal-safe; the handler does only `kill`,
  `alarm`, `write`, `sigaction` and `sigprocmask`.

## Consequences

- Ctrl-C, a cancelled CI job, a closed terminal and an MCP host's SIGTERM stop the target, strace
  and the run's cgroup before Sideeye ends, and leave no report.
- The `fs_usage` observer is stopped through sudo as at the end of a recording, which can take up to
  its 10-second grace.
- A process that left the child's group survives where the engine made no cgroup, and one the
  signal cannot reach further down (under sudo) survives unnamed, as both do under
  `--world-timeout`. `SIGKILL` to Sideeye still leaves its children.
- An inherited `SIGCHLD` of `SIG_IGN` no longer reaches the engine: it sets its own back to the
  default (its children still inherit the ignore), so a run started that way waits for its
  children as any other does.
