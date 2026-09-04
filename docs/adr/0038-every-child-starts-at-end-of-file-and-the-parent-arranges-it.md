# 0038 — Every child starts at end-of-file, and the parent arranges it

Status: Accepted (2026-09-02)

Closes the second half of #263 (the first half, `--world-timeout`, landed in #385).
Sibling of ADR 0007's `cwd` paragraph, which makes the same argument about a different
piece of caller state.

## Context

Every process the engine forks inherited the engine's own standard input, except on one
path: the MCP server's self-exec redirected fd 0 to `/dev/null`, and only when a stdout
capture was also being set up. On the CLI, then, a target that read its stdin blocked on
the operator's terminal or pipe, and the explore hung with no output at all — the one
state outside the "UNKNOWN never goes silent" promise. Under MCP the same target saw EOF
at once and finished. One target, two behaviours, decided by which door it came in.

The engine's stdin is the caller's state. A committed `sideeye.toml` cannot declare it,
a saved case cannot replay it, and no spawn site the engine has — the setup command, the
recording run, each world, the checker and its falsification probe, the `sudo -n` probe,
the demo's compiler, the privileged signal helper, the fs_usage sidecar, the MCP
self-exec — reads it on purpose. That is the shape ADR 0007 gave `cwd`: state the
define cannot carry has to be pinned by the engine, not inherited from whoever ran it.

## Decision

Every child the engine forks starts with fd 0 at `/dev/null`, on every path, with no
parameter for a spawn site to opt out.

The descriptor is opened by the **parent, before the fork**, and handed to the child,
which `dup2`s it onto 0 (retrying `EINTR`) and closes its copy; the parent closes its own
copy whether or not the fork succeeded. A parent that cannot open `/dev/null` refuses
with a new spawn error, `StdinUnavailable`, which `spawnFailure` names as a SETUP ERROR
in either phase — the same reading a fork failure gets: the environment could not be
arranged, and no child ran whose exit status could be read as anything.

Two details are the decision's edges:

- **No `O_CLOEXEC`.** When the engine's own fd 0 is closed, `open` returns 0; `dup2(0, 0)`
  is a no-op, and a close-on-exec flag would then shut fd 0 at exec, so the target would
  read `EBADF` rather than EOF. The child keeps the descriptor where it landed in that
  case, and the flag is not used.
- **The child never exits with a code of its own.** With a valid descriptor in hand,
  `dup2` fails only on `EINTR`, which is retried; any other failure is treated as
  unreachable and the child `abort`s. A signal death is outside the target's 0..255 and
  cannot be mistaken for its status.

In `runChildImplWithOps` — the one function every wrapper a define's commands reach goes
through, and the engine's self-exec with them — the `fork` and the `/dev/null` open are on
the wait seam (`RealOps` / `FakeWait` / `FakeBudget`), so a test can arrange the open to
fail and measure that no fork happened. `spawnSidecar` is the other fork site and calls
both directly: it takes no seam type, and its child (`sudo -n fs_usage`, macOS only) is
held by reading and by the macOS acceptance leg, not by that unit test. The `dup2`
retry in both children is bounded — nine attempts on `EINTR`, then the abort — for the
reason every retry loop in that file is bounded: a resumable signal handler installed by a
preloaded library, with its signal arriving continuously, would otherwise spin before exec
under no budget, which is the silent hang this change exists to remove.

## Alternatives considered

- **The child opens `/dev/null` and reports failure with `_exit(123)`.** Rejected in the
  design review, and recorded so it is not proposed again: `expected_status` accepts
  0..255, so 123 is a status a define may legitimately declare, and a parent reading 123
  as "stdin could not be arranged" would misdiagnose that target — the same ambiguity
  126 already carries between the capture stub and a checker that exits 126 itself.
  There is no exit code the engine can mean something by.
  (**That example moved on 2026-09-04.** #469 applied this decision's own reasoning to
  the capture, so 126 no longer carries "the capture could not be opened" — a refusal
  reaches the caller as `error.CaptureUnavailable`. What it still carries is a `dup2`
  that failed in the child, against a checker that exits 126 itself. The decision this
  ADR records is unchanged; the sentence illustrating it named a case that has since
  been fixed by applying it.)
- **A one-time `/dev/null` check at startup, then the child-side open.** A window between
  the check and each fork, and the child-side failure is back in the exit-code namespace.
  Opening per spawn in the parent makes the check unnecessary.
- **`O_CLOEXEC` to spare the parent's close.** The fd-0-closed case above.
- **A per-wrapper parameter, as `cwd` has.** Every wrapper would pass the same value: no
  site has a reason to inherit. A parameter would only be a way for a new site to inherit
  by accident.
- **An `--inherit-stdin` flag, or a `stdin` config key.** A define that reads the
  operator's terminal is not a reproducible define, and DESIGN §12 admits a key only when
  no caller has another way to say it. Whether a target that genuinely needs input can be
  spelled through the argv form (`["/bin/sh", "-c", "prog < input"]`) is **not
  claimed** by this change: ADR 0019 and `docs/unknown-rate.md` record lbdb's stdin
  redirect as outside any argv shape's reach, and whether `sh -c` execs without a fork
  is shell-dependent. Measured once and recorded in BUILDLOG; a promise, if one is ever
  made, has to update those two records with it.
- **Worlds only.** The owner's ruling on #263 named the recording run and the checker
  too, and the hang was measured at setup.
- **An error pipe (`CLOEXEC`) from the child to identify the `dup2` failure exactly.**
  A path that does not occur; the pipe would complicate both fork sites for it. The
  `abort` keeps the failure out of the target's namespace, which is the property that
  matters.

## Consequences

- A CLI run whose operation read the operator's stdin now sees EOF where it used to
  block. Recorded as a Changed entry; the MCP path already behaved this way, so this is
  the two paths becoming one rather than a new constraint.
- `SpawnError` gains a member, and every exhaustive switch over it names it: the narrow
  wrapper in `posix.zig`, the world-timeout call site in `main.zig`, and the MCP server's
  self-exec in `mcp.zig`, which names it in its tool error rather than folding it into
  "could not run".
- The `fs_usage` sidecar is covered by the same sentence; `sudo -n` never prompted, so
  nothing observable moves there.
- README's Usage section carries the promise; `spike/acceptance.sh` holds it on the CLI
  with a FIFO held open across setup, operation and checker, and `spike/mcp-acceptance.sh`
  holds it on the MCP path with the transport held open past the cut.
