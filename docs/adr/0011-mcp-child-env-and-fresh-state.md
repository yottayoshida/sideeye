# ADR 0011 — The MCP child gets named env vars back, and replay gets `--fresh-state`

- **Status:** Accepted (2026-08-13)
- **Supersedes:** nothing. Amends two consequences of ADR 0010 (the minimal-env
  child) and ADR 0009 (replay's implicit pristine-state precondition), found by
  attempting the MCP-mediated loop-closure run (#68, #69)
- **Scope:** the env construction in `src/mcp.zig`, a `--fresh-state` flag in
  `src/main.zig`, a guarded `freshDir` in `src/engine.zig` (since #491: now `src/engine/state_fs.zig`)

## Context

The first attempt to drive the loop-closure experiment through `sideeye mcp`
(2026-08-13) failed before any agent ran, in two independent ways, both measured
against the recorded timewarrior stage:

1. ADR 0010's minimal-env exec hands the child PATH only, so that a config's
   operation cannot read the server's credentials. But timewarrior locates its
   state through `TIMEWARRIORDB`; the replay came back `UNKNOWN
   (case_no_longer_applies): the recording now counts 0 state-changing
   operation(s)` — setup and operation ran against the target's env-free
   fallback location, not the case's state dir. Any env-located-state target
   (watson's `WATSON_DIR`, anything HOME-relative) is in the same class. The
   2026-08-12 over-the-wire measurement used the toy scenario, whose operation
   takes its path as an argument, so this was invisible.
2. `sideeye replay` re-runs the case's setup onto whatever the state dir holds.
   Every CLI caller so far provided a pristine dir (a fresh container per
   replay), so the precondition was never written down. An MCP server is
   started once per client session and persists: the second replay in the same
   session died in setup (`timew: You cannot overlap intervals`) — measured
   over the CLI with correct env, so it is not a symptom of the first gap. An
   agent's edit → rebuild → re-check loop through this surface dies on its
   second check.

## Decision

1. **`SIDEEYE_MCP_CHILD_ENV` — an operator-side allowlist of variable NAMES.**
   Comma-separated. Each name is resolved from the server's own environment and
   appended to the child's env alongside PATH. Values never come from the
   request: the operator who starts the server (and already owns the trust
   boundary — the config is trusted input per ADR 0010) decides what the target
   needs; the caller cannot widen it. A name listed but absent from the server
   environment is a **loud tool error naming the variable** — a typo must not
   reproduce the silent zero-operations failure that motivated the feature.
   More than 16 names is refused rather than silently truncated.
2. **`sideeye replay --fresh-state` — empty the case's state dir before setup
   runs.** The dir is already sacrificial by contract: exploration kills
   processes mid-write into it, and restore rewrites it wholesale. The deletion
   rides the engine's guarded path — and the guard has two halves, both part of
   this decision: `assertSafeRoot` (lexical) plus the same `deleteTree` the
   restore path uses, applied to the **realpath'd** state (`state_abs`), never
   the case's raw spelling. The first implementation passed the raw string;
   review showed the lexical guard alone admits `/tmp/../etc` (three slashes,
   resolves to `/etc`) and a symlinked root — resolution is what makes the
   guard mean anything, and the requirement is recorded here so a refactor
   cannot silently undo it. A state dir that does not exist yet is covered by
   the call site's existing mkdir-then-resolve; a path that is not an openable
   directory is a loud error, never a silent no-op. The flag is replay-only —
   an explore's initial state may be legitimately pre-populated, and its
   meaning there would be a different decision. The CLI default is unchanged:
   callers that provide freshness themselves keep providing it.
3. **The MCP server passes `--fresh-state` on every replay child.** The server
   lives for the whole client session; nobody else is positioned to provide the
   pristine dir per call.

## Alternatives considered

- **Pass NAME=value pairs through the request or the allowlist.** Rejected:
  values in the request would let the caller redirect a target's state
  anywhere; values in the allowlist would put copies of the environment into
  process listings. Names-only keeps the server env the single source.
- **Silently skip absent names.** Rejected: the failure it produces downstream
  (`0 state-changing operations`) is exactly the silent one that cost this
  discovery a probe cycle.
- **Clean the state dir server-side (parse the case in `mcp.zig`).** Rejected:
  the case schema already has one reader (replay), and a second parser would
  drift from it. The child that owns the case owns the cleanup.
- **A fresh server process per call.** Not the server's to decide — MCP clients
  start one server per session; requiring otherwise would fight every client.

## Consequences

- The mutual contrast now holds through the MCP channel on the real target:
  the unpatched tree replays FAIL (crash point 19) twice in one session, the
  fixed tree replays PASS (explored 2) twice, same code path, opposite answers
  (mcp-acceptance 7 and 8 pin the toy-sized version of both halves; both were
  seen red before the implementation).
- Check 4's isolation claim survives verbatim: an unlisted server secret still
  does not reach the child, now asserted in the same breath as the
  pass-through (check 7).
- The operator's server invocation grows one env var per env-dependent target.
  The loop-closure MCP variant sets `SIDEEYE_MCP_CHILD_ENV=TIMEWARRIORDB`.
