# ADR 0010 — The MCP adapter is a `sideeye mcp` subcommand that self-execs, over paths, not commands

- **Status:** Accepted (2026-08-12)
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
   `SIDEEYE_MCP_WORK`), not from tool input. The load-bearing half of that sentence is
   **not from tool input**; two of the three have defaults, which is a different question
   and always was. `SIDEEYE_MCP_WORK` has had one since this ADR was written, and since
   #389 the shim falls back to the search `README.md` describes for the whole product —
   beside the binary, then `../lib` — because demanding the variable made this the one
   command that did not do what that page says. Neither default takes a value from the
   caller of a tool.
   **What the shim fallback does add is a trust in the install directory**, and the
   precondition below does not cover it: whoever can write `bin/` or `../lib` of the
   installed prefix chooses the library injected into the target, and a symlink placed
   there is followed (measured). This is the CLI's behaviour since #78, so the exposure
   belongs to the product rather than to this adapter — what changed is that the adapter
   no longer sits outside it. Closing it product-wide is a separate decision (#423), because it
   would change how a shipped command resolves its own library. **The config is a trust
   boundary**: its
   operation is executed; the confinement bounds *which* config, not what it may do.
   **Operational precondition:** `SIDEEYE_MCP_ROOT` and the work dir are user-owned and
   **not attacker-writable** — the operator sets them to their own workspace. Two
   residual issues are out of scope *only under this precondition*, and would need
   revisiting if it did not hold: the check→open TOCTOU (a writable root could swap a
   vetted file for a symlink between the realpath check and the child's open — a
   copy-into-work-dir defence was rejected because it breaks a config's own relative
   resolution), and the predictable work-dir filenames (`report-N` / `child-N`; the
   captures open `O_NOFOLLOW|O_EXCL` 0600 in a 0700 dir, so a pre-planted symlink fails
   closed, but the dir's own contents are not owner/mode-verified on `EEXIST`). The
   names are also unlinked before each child runs: the counter is per-process, so two
   servers sharing a work dir collide on the same names — measured (2026-08-12) serving
   the previous server's report as the current call's verdict. Under the precondition
   those stale files are the operator's own leftovers, and after the unlink whatever
   exists at the names was written by this call's child or by nobody.
   **A third residual, and it is not closed by the precondition** (#326): the result
   relays text the target influenced. That is not a defect to remove — a refusal that
   cannot name the operation it refused on is not a diagnostic — so what ships is
   attribution rather than sanitisation. In the text block the quoted bytes sit inside a
   region whose **byte count** is stated at its start, and the count is the extent: a
   closing token would be forgeable by the very thing being quoted, since an entry name
   reaches the message verbatim. `structuredContent` is **not** marked: doing so would add
   a report field, and surface 2 of the freeze is not this ADR's to move. Its
   `earliest.*` paths carry names the target chose, JSON-escaped, so a parser hands the
   control bytes back — unlike the text side, which defangs them. The tool descriptions
   say both. The text block's 128 KiB ceiling bounds the digest, not the payload: the
   structured half still carries up to `readFile`'s 4 MiB.
   Separately, and often confused with the above: the check→open TOCTOU named earlier in
   this paragraph is about the **config path**, and it stays open under the precondition.
   The destructive path's own window is a different thing and is closed by ADR 0024.
5. **isError distinguishes verdict from actionable failure.** A crash-consistency
   PASS/FAIL is a real verdict (`isError:false`); every other outcome — SETUP_ERROR and
   every UNKNOWN — is `isError:true`, read structurally from the report's `verdict`
   field, so the model self-corrects. (The first implementation matched a fixed list of
   six `unknown_reason` substrings; the first reason from outside the list to appear
   live — `no_shim_marker`, 2026-08-12 — rode through as `isError:false`. A fixed-string
   guard is void the day the string is absent.) The report is minified into
   `structuredContent` and summarized (verdict + reason + replay handle) into a text
   `content` block for the agent.

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
  explore blocks the loop and `notifications/cancelled` is not read. A server killed
  mid-explore no longer strands its exploration indefinitely — see `--stop-when-orphaned`
  under Consequences (#269) — but the stop is a world-boundary event, not a
  cancellation: a run hung inside a world stays hung. The Tasks extension is future
  work.

## Consequences

- An agent can drive sideeye over MCP with no CLI knowledge, and the loop-closes
  experiment (§17 second criterion) has its surface — explore → saved case → replay all
  measured end-to-end through the server.
- The security posture is "the config is the trust boundary": raw command execution is
  off the tool surface, paths are confined, the child env is minimal, and the real
  binary is what runs. What remains is that a confined config's operation still runs —
  stated, not hidden. The root confines *which* config may be named, never what its
  operation may do: it is not an execution sandbox, and agent-driven deployments supply
  their own containment (a container or otherwise restricted workspace).

  **The engine neither provides that containment nor checks for it, and that is a
  decision rather than an omission** (#328, measured 2026-09-02). Two things were asked:
  could the engine confine the commands itself, and failing that, could it refuse to
  start when the containment this ADR assumes is absent. The answer to the second is no,
  which settles the first as well.

  Some of what a process can see about its own confinement does not move with it
  (measured in this project's image; the fourth column taken from the LinuxKit VM the
  containers run in):

  | observation | plain container | `--privileged` | `--pid=host --privileged` | host |
  |---|---|---|---|---|
  | `/.dockerenv` | present | present | **present** | absent |
  | `/proc/1/cgroup` | `0::/` | `0::/` | `0::/../..` | `0::/` |
  | `CapEff` | `00000000a80425fb` | `000001ffffffffff` | `000001ffffffffff` | `000001ffffffffff` |
  | `/proc/self/uid_map` | `0 0 4294967295` | same | same | same |

  `/.dockerenv` survives having the PID namespace shared and every capability restored,
  and `CapEff` is byte-identical between a `--privileged` container and the host — it
  measures privilege, not isolation.

  **But some observations do move**, and that is the finding rather than the exception:
  `Seccomp: 2` drops to `0` under `--privileged`, and Docker's ten masked `/proc` mounts
  drop to none. A check could read those. It would still be worthless here, for two
  reasons a measurement makes plain:

  - **The subject can raise them itself, and neither costs what it should.** `Seccomp`
    costs nothing: two `prctl` calls — `PR_SET_NO_NEW_PRIVS` then `PR_SET_SECCOMP` with
    an allow-everything filter — take `0` to `2` in a process holding
    `CapEff: 0000000000000000` (dropping the first call gives `EACCES`, which is the
    control). The masked mounts cost `CAP_SYS_ADMIN`: with it, three bind mounts inside
    a fresh mount namespace take the count from ten to twelve; without it `unshare -m`
    is `Operation not permitted`. That price buys nothing, because the process a check
    would be aimed at — the unconfined one, faking confinement — is the one that has the
    capability. A signal the thing being confined can raise is not evidence.
  - **They measure the wrong thing.** A container reading *maximally confined* by all of
    them — `/.dockerenv` present, `Seccomp: 2`, ten masked `/proc` entries, no extra
    capabilities, its own PID namespace — destroyed a file on the host through its
    bind-mounted root, which is exactly the shape README recommends ("a directory the
    container exists to hold"). Nothing a process can read tells it whether the root it
    was handed is the operator's to lose.

  macOS has nothing to put in the table at all: `sandbox-exec` exists and is deprecated,
  and a process learning whether it is itself sandboxed is private SPI (`sandbox_check`,
  no man page). So a refusal would also be a platform branch answering a different
  question on each side — the shape `requireCompleteness` rejects, "which would break the
  claim that both operating systems produce the same verdict for the same scenario".

  So the deployment guidance in README is the control, and it is guidance rather than
  a gate: **in a deployment where the agent can write the root, this ADR's precondition
  does not hold and nothing in the engine restores it.** Sandboxed command execution
  remains a posture change with its own cost line.

  The alternative examined and not taken was to require the launcher to declare its
  containment — an environment variable the engine refuses to start without. This
  project does accept unverifiable declarations elsewhere: `requireCompleteness`'s own
  resolution is that "the caller states the weaker claim deliberately, **and the report
  says which claim was made**", which is what makes `--allow-unverified` a control rather
  than a ceremony. The difference is the second half. That flag weakens something the
  report asserts, so the declaration lands in `oracle_verified` where a consumer gating on
  it can see it. A containment declaration would weaken nothing the report claims — the
  verdict is about the target's crash-consistency either way — so there is no field for it
  to land in and no consumer whose decision it would change. It would be a ceremony, and
  saying so is what distinguishes it from the flag above.
- Long real-target explores block the single-threaded loop; small targets are the v1
  assumption, with async deferred to the Tasks extension.
- A server killed mid-explore stops its exploration **at the next world boundary it
  reaches** (#269). The server passes `--stop-when-orphaned` on every self-exec'd
  explore and replay; under that flag the engine records `getppid()` once at process
  start and refuses to begin another world when it changes — parentage changes only
  when the parent dies, so nothing has to hand a pid around. The run ends as UNKNOWN
  `parent_exited`, before the next `restore`, so what replaces the deletion is the
  refusal.

  A flag, and deliberately not a pid-carrying environment variable, a signal, or a
  pipe. An environment variable is inherited and outlives its sender — the engine hands
  the target its own environment on the non-minimal path, so a pid passed that way
  reaches processes nobody set it for, and a stale copy refuses runs it was never about
  (both measured). `PR_SET_PDEATHSIG` is Linux-only and a signal arriving mid-world
  leaves a half-written state directory. A liveness pipe works on both platforms but
  needs the write end closed in the child, a fixed descriptor number, `FD_CLOEXEC`, a
  non-blocking read, and an exemption from the minimal environment's descriptor sweep.
  Argv is per-invocation, is not inherited, and appears in the synopsis like any other
  flag.

  **The bounds are real and stated rather than papered over**: a `--setup`, recording,
  baseline or checker run that hangs never reaches a boundary, and a server that dies
  between fork and the engine's first instruction is not seen (the baseline is then
  already the reaper's pid). So the claim is "stops at the next boundary reached", not
  "a killed server leaves nothing behind".
