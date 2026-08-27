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
  level deeper in the meantime. (Both were superseded on 2026-08-27; see
  the Amendment below. The message no longer says that.)
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

## Amendment, 2026-08-27 (#329): the naming root loses the depth rule

The Decision above called exempting the naming root from the depth rule "a
coherent future loosening — filed, not done". This is that, with a correction
the filing did not anticipate.

**What changed.** `mcp.zig` now calls `engine.assertSafeNamingRoot`, which keeps
every check `assertSafeRoot` has except the depth rule, and adds one it does not
have: both denylists are read **outwards** as well as inwards, so a root that is
an *ancestor* of a denied entry refuses along with a root inside one. A
single-component mount — `/work`, `/opt` — starts.

**The ruling was made twice.** The first, on 2026-08-26, exempted the depth rule
only when `SIDEEYE_MCP_STATE_ROOT` is set, reasoning that the root doubles as
the destruction range when it is unset. Review then measured that the condition
is nearly always satisfied in practice (this repository's README, quickstart and
sweep apparatus all set that variable, and nothing requires it to differ from the
root), and that a conditional couples the two knobs this ADR exists to separate —
"set the destruction range and the naming vet relaxes" is the same shape as the
wall rejected above. The ruling was changed to an unconditional exemption on
2026-08-27.

**The argument that made the depth rule indefensible was a measurement.**
`SIDEEYE_MCP_ROOT=/var` **started the server**, rc=0, before this change: realpath
turns it into `/private/var` on macOS and two components pass. The rule was a
proxy for danger and the proxy had a hole on the platform the tool is developed
on. The lists name the danger directly; reading them outwards is the same
statement without the proxy.

**This is a trade and the boundary moves both ways.** Enumerated over both lists,
the outward read closes exactly `/var`, `/private` and `/private/var`. Dropping
the depth rule opens every depth-1 path in neither list: `/opt`, `/cores`,
`/nix`, `/srv`, whatever a host has at `/`. The relaxation rests on ADR 0010's
operational precondition — the root is the operator's own workspace and not
attacker-writable — not on a claim that less is now reachable.

**What is closed here is not closed on the destructive side.** `assertSafeRoot`
is unchanged, so `sideeye explore --state /var` still passes the destructive vet
and empties `/private/var` once per explored world. Confining one PR to the
naming consumer is a scope decision; it is recorded here because ADR 0024 exists
to correct exactly the inversion of describing two neighbouring defences as if
one covered the other. Filed as #358.

**And what the naming vet admits is not confined to naming.** With
`SIDEEYE_MCP_STATE_ROOT` unset the fallback above makes the root the
destruction range, so every depth-1 path this now accepts is a directory
whose children a replayed case may empty. `/work` and `/repo` are the
intended shape; `/opt` also passes the vet and is where installed software
lives. The relaxation rests on ADR 0010's precondition — the root is the
operator's own workspace — and the README carries the part no denylist can:
name a directory whose contents are yours to lose.

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
