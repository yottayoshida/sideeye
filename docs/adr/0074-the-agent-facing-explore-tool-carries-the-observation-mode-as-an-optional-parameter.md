# ADR 0074 — The agent-facing explore tool carries the observation mode as an optional parameter

Status: Accepted (2026-09-18)

## Context

The engine has two observation modes. The default, `wrappers`, counts state-changing
operations at the interposed libc entry points; `--observe syscalls` (Linux) counts them
at the kernel boundary and reaches targets the first mode cannot account for (ADR 0059,
#542). Since #599 (ADR 0069) the engine *names* that mode in its own `next_step` when a
run refuses `oracle_missed_operation`: the oracle saw a state-changing operation the shim
did not, and the syscall boundary is where it would be seen.

The MCP surface could not carry that step. `sideeye_explore_config` took `{config_path}`,
`sideeye.toml` has no key for the mode, and the server passed no `--observe`. So an agent
driving Sideeye through its own agent-facing interface could receive a correct next step
from the engine and have no way to execute it — the loop `explore → named refusal →
next_step → retry → verdict` broke at the retry (#617).

The MCP surface is frozen (v1.0, `docs/contract-freeze.md` surface 5: the two tool names,
their input schemas, and the isError rule). The same paragraph says what is still open:
**"Additive extension stays open: new tools, new optional parameters."** No optional
parameter existed on either tool until this change, so this is the first exercise of that
allowance rather than a reading invented for it.

## Decision

`sideeye_explore_config` takes an optional `observe`, whose value is one of the CLI's two
names — `wrappers` or `syscalls`. Omitted, the server passes no `--observe`, which is what
the default means and what every caller written before this sent. A value outside the two
is refused at the protocol edge with `-32602`, the shape a missing `config_path` already
had, before any child is spawned.

A call that omits the parameter reaches the same run it reached before.

## Alternatives considered

- **A key in `sideeye.toml`.** Rejected: the config format is surface 1, also frozen, and
  a key there changes what the file means at the command line too — the mode is a property
  of one invocation, not of the declaration.
- **A server environment variable (`SIDEEYE_MCP_OBSERVE`).** Every other knob the server
  reads is an environment variable, so this was the shape to beat. Rejected because it
  cannot do the job: an agent cannot change the environment of a server it is already
  talking to, and following a `next_step` is precisely a mid-session act.
- **Letting the engine refuse the bad value.** Rejected: the value is a closed set the
  server already knows, and passing it through means a child runs against the caller's own
  target before the mistake is named. The refusal belongs where the caller can still fix it.
- **`sideeye_replay_case` taking the same parameter.** Not decided here. A saved case is a
  recording made under one mode, and replaying it under another raises case compatibility
  (`case_no_longer_applies`) rather than only an observation choice. Surface 5's allowance
  stays open for it. Until then the question is held by the type rather than by a comment:
  `RunKind` carries the mode on its `explore` arm, so a replay under a chosen mode cannot
  be spelled. Sending `observe` to that tool is unspecified — this server ignores unknown
  keys, its schema declares `additionalProperties: false`, and neither is promised.
- **The server following the `next_step` itself.** Rejected: the modes differ in what they
  refuse (`pwritev2` is refused rather than counted under `syscalls`; two calls stay at the
  libc entry points — ADR 0059), so an automatic retry would silently change the terms of
  the answer and double the run. An agent-facing surface should carry the choice, not make it.
- **Recording the mode in the report.** Rejected here: the report schema is surface 2, and
  the issue's own acceptance asks that the selected mode reach the same engine path and the
  same report fields as the CLI. The consequence is stated in `docs/mcp.md`: a server
  without this parameter ignores the key silently, and `tools/list` is where a caller sees
  which server it has.

## Consequences

- ADR 0069's bullet "The MCP server passes no `--observe` and a `sideeye.toml` has no key
  for it, so through the server `observe_syscalls` is advice for the command line" is
  **superseded by this ADR** for the first half. The second half still holds: the config
  format has no key for the mode. ADR 0069 is left as written — it is the record of what
  was true when it was decided.
- On macOS the parameter is accepted and the run ends `SETUP_ERROR` with
  `platform_unsupported`, the engine's own answer for a mode that needs seccomp. That is a
  named refusal rather than a silent fall back to the default, and it is checked on that
  platform (`spike/check-mcp-observe-macos.sh`).
- The freeze page records this as the first use of its additive allowance, so the next
  optional parameter has a precedent to cite rather than a reading to re-derive.
