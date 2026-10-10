# 0106 — An explored config's state is confined like a replayed case's

- **Status:** Accepted (2026-10-10)
- **Refs:** #765 (the owner's ruling of 2026-10-09, made while #717's `sideeye_preflight` was
  designed); ADR 0022 (the naming root and the destruction range, whose "Confine explore's config
  the same way" alternative this reverses); #96 (the reading ADR 0022 rested on); #717 (which gave
  `sideeye_preflight {twice}` the range).
- **Scope:** `src/mcp.zig` (the explore child's argv, and the next line of a preflight
  summary), `src/cli.zig` (explore takes `--state-under`), `src/main.zig` (the refusal's way out,
  now by command); the check itself is unchanged.

## Context

An exploration empties and rebuilds the config's state directory before every world. Through the
MCP server, `sideeye_replay_case` passes `--state-under SIDEEYE_MCP_STATE_ROOT` (#266) and, since
#717, so does `sideeye_preflight` with `twice`, whose second run rebuilds the state.
`sideeye_explore_config` passed nothing, and the engine refused `--state-under` on explore by name:
the state a config names could be anywhere the server's user can write.

ADR 0022 chose that on purpose. "A config is what the operator vets": in the domain where the
range is effective at all, an operator placed the config, and confining explore would refuse
every documented config — whose state conventionally lives under `/tmp` — for no gain.

The use #716 and #717 build toward is a different domain. An agent writes the config, checks it
with `sideeye_preflight`, then explores it. Nobody vetted that config, and the root's confinement
of the config's *path* says nothing about the state the path names: a `state = "../.."` or an
absolute path the agent got wrong is emptied by the first world. `sideeye_preflight {twice}` was
refused for such a config before setup ran; `sideeye_explore_config` on the same config went ahead.

## Decision

`sideeye_explore_config` passes `--state-under SIDEEYE_MCP_STATE_ROOT` (default: the server root),
and `explore` takes the flag. The check is the one replay and `preflight --twice` already meet
(`main.zig`, before setup, on the realpath'd bytes the destruction will use, strictly inside):
outside the range the call is refused before setup runs, and the refusal names
`SIDEEYE_MCP_STATE_ROOT` as the way to widen it, as replay's does.

The command line is unchanged: an `explore` typed by a person takes no range unless it is given
one, and the state of a config run that way remains the operator's to vet (`SECURITY.md`, "What
does not").

## Alternatives considered

- **Check the state in `mcp.zig`** — rejected for ADR 0022's reason: a second reader of the
  config resolves the state from different bytes than the engine does, a check-to-use window this
  design has none of.
- **Leave it to the config's path** — rejected: the path being inside the root is what #765 shows
  says nothing about the state.
- **Confine only configs an agent wrote** — rejected: the server cannot tell who wrote a file.

## Consequences

- An operator who explores, through the server, a config whose state is outside the server root
  is refused where the call used to run; setting `SIDEEYE_MCP_STATE_ROOT` to a directory holding
  that state (`/tmp`, for the CLI convention) restores it. `docs/ci-quickstart.md` says so beside
  its `/tmp` example.
- **Surface 5 (`docs/contract-freeze.md`) is read, not used.** The tool's name, its input schema
  and the isError rule are unchanged; a call refused for its state is a refusal like any other,
  `isError: true`. What changes is which inputs are refused, which that surface does not freeze;
  the page records the reading beside its other entries.
- The range is one directory. An operator who set `SIDEEYE_MCP_STATE_ROOT=/tmp` so that CLI-made
  cases replay — what `docs/mcp.md` has advised since #266 — now has explorations confined to
  `/tmp` as well, and a config whose state is under the root but not under `/tmp` is refused where
  it ran before. Accepted rather than worked around: a second range would make "which directories
  may be emptied" two answers, which is what ADR 0022 separated the knobs to avoid. The CHANGELOG
  and `docs/mcp.md` say so.
- The refusal says, for explore and `preflight --twice`, to move the state inside the range first
  — not to run the config from the command line, which is unconfined and would route an agent's
  mistake around the check — and names both spellings of the range, the server's variable and the
  command line's flag. For a replay it keeps "replay it from the command line" first, as before:
  a case the engine saved has its state where the command that saved it put it. A case an agent
  wrote by hand meets the same sentence; that was so before this ADR, and is left to a ruling of
  its own rather than folded in here.
- The tools apply one rule to every state the server has the engine rebuild, so a config a `twice`
  call accepted, its state inside the range, is one the exploration accepts on that count too. One
  observed run of `sideeye_preflight` does not check the range (ADR 0102); its `next` line now says
  the exploration will.
