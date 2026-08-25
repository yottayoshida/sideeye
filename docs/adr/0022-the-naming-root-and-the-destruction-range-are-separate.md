# 0022. The naming root and the destruction range are separate knobs

Date: 2026-08-25
Status: Proposed

## Context

The MCP server confines which files a tool call may *name*:
`SIDEEYE_MCP_ROOT`, realpath-then-prefix-checked (ADR 0010). `#266`
measured that this confines nothing about what a replayed case
*destroys*: the case file itself carries `define.state`, the engine
empties that directory (`--fresh-state`) and deletes-and-rebuilds it
once per world (`restore`), and nothing resolved the value against any
root. A case inside the root could name any directory `#267`'s denylist
does not — the denylist stops the mistake that has a name (`/var/lib`),
not `/Users/alice/projects`.

Fixing it forces a decision about *which* range confines the case's
state, because the two obvious answers conflict:

- Confine to `SIDEEYE_MCP_ROOT`, and every case made at the CLI is
  unreplayable through the server: the documented convention — this
  repository's own quickstart, and every committed define — keeps state
  under `/tmp`, outside any sane workspace root. The operator's natural
  escape is to widen `SIDEEYE_MCP_ROOT`, which dissolves the naming
  boundary that variable exists to hold. The insecure path becomes the
  convenient one.
- Confine to nothing new and document the risk, and the hole stays open.

## Decision

Two knobs, two properties:

- `SIDEEYE_MCP_ROOT` keeps confining **which files may be named**.
  It gains a startup vet (`engine.assertSafeRoot`): a root of `/`,
  `/tmp`, another scratch parent, **or any single-component path**
  (`/work`, `/repo` — the predicate's depth rule needs two components)
  refuses to start. The last of those is wider than the danger this
  ADR is about: with strict-inside, a depth-1 naming root's states are
  always depth ≥ 2 and individually vetted, so exempting the naming
  root from the depth rule is a coherent future loosening — filed, not
  done, and the refusal message tells a container operator to mount one
  level deeper in the meantime.
- `SIDEEYE_MCP_STATE_ROOT` confines **which directories a replayed
  case may destroy**. The server passes it to the engine as a
  replay-only flag, `--state-under <dir>`; the engine checks it where
  the case's value is read — same bytes checked and used, no second
  parse of the case file, no check-to-use window. Unset falls back to
  the root: the narrow, safe default.
- The check is **strict** inside: a state equal to the range is
  refused. `SIDEEYE_MCP_ROOT=$HOME` is an ordinary configuration, and
  equal-allowed would let one received case make the whole workspace
  the sacrificial directory.

The operator with CLI-made cases sets `SIDEEYE_MCP_STATE_ROOT=/tmp`.
**The knob to widen is always `STATE_ROOT`, never `ROOT`.**

With `STATE_ROOT` unset, the fallback makes the workspace root itself
the declared destruction range: a received case may name any
subdirectory of the workspace — saved cases and reports included, when
the work dir lives inside the root — and replay will empty it. That is
the contract, stated rather than discovered; a dedicated `STATE_ROOT`
is the recommendation, not the requirement.

## Scope — what this does and does not close

This closes the **accident and received-case class**: a case obtained
from another machine or another person, replayed in a workspace the
agent cannot write, can no longer direct destruction outside the
declared range. It does not close:

- **Execution.** A case's setup/operation/check are executed on replay,
  by design (ADR 0010's posture; both tool descriptions now say so).
  An adversary who can write into the root does not need `define.state`.
- **The check-to-`opendir` window.** `assertRootUnchanged` re-resolves
  immediately before each delete and does not hold the root by
  descriptor; a hostile setup can retry the swap once per world. Filed;
  the fix is the same `openat`/`unlinkat` sunset `#267` recorded.

A claim that this "closes the destruction path" would prove less than
it concludes; the honest claim is the one above.

## Alternatives considered

- **Confine explore's config the same way** — rejected by owner ruling.
  A config is what the operator vets (`#96`); in the domain where this
  control is effective at all (agent cannot write the root), the config
  was placed by the operator, and applying the range to explore refuses
  every documented config for no gain in that domain.
- **Parse the case in mcp.zig and check `define.state` there** —
  rejected: a second reader of the case schema drifts green, and the
  server's bytes and the engine's bytes are different reads (a
  check-to-use window this design has zero of).
- **One knob (`ROOT`) with a wall** — rejected for the secure-by-default
  failure above: the wall teaches operators to widen the wrong variable.
- **Equal-to-range allowed** (`isInsideDir`'s ordinary meaning) —
  rejected; see Decision.

## Consequences

- CLI-made cases are not replayable through a default server; the
  refusal message, the tool description, the README and the quickstart
  all name `SIDEEYE_MCP_STATE_ROOT` as the recovery.
- `resolveInsideRoot` and the new check share one predicate family
  (`contract.isInsideDir` / `isStrictlyInsideDir`). The unification and
  the startup vet ship atomically: the hand-rolled check and
  `isInsideDir` answer root `/` in opposite directions (reject-all vs
  accept-all), so either change without the other flips fail-closed to
  fail-open. `mcp-acceptance` pins the startup refusal.
- `spike/loop-closure-timew`'s MCP variant sets `STATE_ROOT=/tmp`
  (its staged cases keep state at `/tmp/loop-state`).
