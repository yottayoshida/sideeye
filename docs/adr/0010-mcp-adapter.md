# ADR 0010 — The MCP adapter is a `sideeye mcp` subcommand that self-execs, over paths, not commands

- **Status:** Proposed
- **Supersedes:** nothing. Implements #40 (v0.5's "sideeye is agent food") and the
  first half of DESIGN §17's second criterion (the agent-facing surface)
- **Scope:** a new `src/mcp.zig`, a `mcp` dispatch arm in `main.zig`, a minimal-env
  exec and canonical self-path in `posix.zig`

## Context

DESIGN §3 names coding agents as the audience and §17's second criterion is "an agent,
given only the report and the repository, produces a fix that makes the replay pass".
Until now an agent could only reach sideeye through the CLI. #40 adds the standard
surface — an MCP server — so the loop-closes experiment can run (the timewarrior
counterexample is already in hand to feed it).

MCP 2026-07-28 changed the ground under this: the protocol became **stateless** (no
`initialize` handshake; every request carries its version and capabilities in `_meta`),
and **stdio transport is explicitly exempt from OAuth** (credentials come from the
environment). That removed the one strong reason to wrap sideeye in an SDK in another
language, and made a hand-written Zig server small.

## Decision

1. **`sideeye mcp` — a single-binary subcommand, not a separate service or language.**
   Consistent with the single-binary thesis (DESIGN §9), zero-middle-layer (the zig
   rule), and no second definition of the contract (ADR 0001). The server is a
   stateless loop over three methods: `server/discover`, `tools/list`, `tools/call`.
   `initialize` is legacy and is not implemented.
2. **Tools take paths, never raw commands.** Two tools —
   `sideeye_explore_config {config_path}` and `sideeye_replay_case {case_path}`. The
   operation to run lives *in the config file*, which a human can inspect, rather than
   arriving as a model-chosen command string on the exec path (that would be
   confused-deputy RCE, since MCP tools are model-selectable). The `define`/parse tool
   from #40's sketch is dropped: parsing alone diverges from what `--config` actually
   does at run time (realpath, state resolution, required shim), so it would say "OK"
   and then fail. Two path-tools are enough for loop-closes.
3. **Transfer is self-exec, isolated three ways** — the review's three Criticals:
   - **stdout**: the child's report is captured to a work-dir file (`runChildCapture`);
     fd 1 (the MCP transport) is written only by the adapter, one JSON line per
     response. A leaked child report would corrupt the transport on the first real run.
   - **path**: the running binary is found via `/proc/self/exe` (Linux) or
     `_NSGetExecutablePath` + realpath (macOS), never argv[0] (PATH hijack). If it
     cannot be resolved the server refuses to start.
   - **env**: the child is exec'd with a *minimal* environment (`execve`, only `PATH`),
     not the server's — so a config's operation cannot read the server's credentials.
4. **Confinement.** `config_path` and `case_path` must realpath to inside
   `SIDEEYE_MCP_ROOT` (a component-boundary prefix check, after realpath collapses
   `..`/symlinks). Operational settings — the shim, an optional oracle, the work dir —
   come from the environment (`SIDEEYE_MCP_SHIM`, `SIDEEYE_MCP_ORACLE`,
   `SIDEEYE_MCP_WORK`), not from tool input. **The config is a trust boundary**: its
   operation is executed; the confinement bounds *which* config, not what it may do.
   **Operational precondition:** `SIDEEYE_MCP_ROOT` and the work dir are user-owned and
   **not attacker-writable** — the operator sets them to their own workspace. Two
   residual issues are out of scope *only under this precondition*, and would need
   revisiting if it did not hold: the check→open TOCTOU (a writable root could swap a
   vetted file for a symlink between the realpath check and the child's open — a
   copy-into-work-dir defence was rejected because it breaks a config's own relative
   resolution), and the predictable work-dir filenames (`report-N` / `child-N`; the
   captures open `O_NOFOLLOW|O_EXCL` 0600 in a 0700 dir, so a pre-planted symlink fails
   closed, but the dir's own contents are not owner/mode-verified on `EEXIST`).
5. **isError distinguishes verdict from actionable failure.** A crash-consistency
   PASS/FAIL is a real verdict (`isError:false`); a SETUP ERROR or an UNKNOWN the caller
   can fix (`completeness_not_verified`, `recording_run_failed`, `marker_never_observed`,
   `case_no_longer_applies`, …) is `isError:true`, so the model self-corrects. The
   report is minified into `structuredContent` and summarized (verdict + reason + replay
   handle) into a text `content` block for the agent.

## Alternatives considered

- **A thin Python/Node SDK wrapper** — rejected: a runtime dependency and a second
  contract definition, and the SDK's one advantage (session/OAuth) is moot on stdio.
- **In-process (call the engine directly)** — rejected: every verdict path in
  `main.zig` ends in `std.process.exit` through ~15 module globals; there is nothing to
  return. Self-exec matches the existing grain (the engine is built on fork+exec).
- **Raw `operation`/`shim` as tool input** — rejected: confused-deputy RCE and a
  credential-exfiltration surface.
- **A `define` parse tool** — rejected: parse-only diverges from run-time resolution.
- **Full cancellation / async Tasks** — deferred: v1 is synchronous, so a long
  explore blocks the loop and `notifications/cancelled` is not read. **Parent-death
  cleanup of the self-exec'd explore group is not implemented** (the child is a process
  group, killed only when the direct child exits — if the server dies mid-explore the
  target group can outlive it); tracked as a known limitation, not claimed as done. The
  Tasks extension is future work.

## Consequences

- An agent can drive sideeye over MCP with no CLI knowledge, and the loop-closes
  experiment (§17 second criterion) has its surface — explore → saved case → replay all
  measured end-to-end through the server.
- The security posture is "the config is the trust boundary": raw command execution is
  off the tool surface, paths are confined, the child env is minimal, and the real
  binary is what runs. What remains is that a confined config's operation still runs —
  stated, not hidden.
- Long real-target explores block the single-threaded loop; small targets are the v1
  assumption, with async deferred to the Tasks extension. A server killed mid-explore
  can leave the target process group behind (parent-death cleanup unimplemented) — a
  known limitation filed for the async work, not a claim of cleanliness.
