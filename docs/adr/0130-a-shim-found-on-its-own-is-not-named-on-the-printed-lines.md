# 0130 — A shim the run found on its own is not named on the lines it prints

- **Status:** Accepted (2026-10-14)
- **Refs:** #827 (found in the 2026-10-11 survey); `docs/ci-quickstart.md`'s "`replay` is the exact
  command that reproduces it"; the Homebrew formula's "The shim is installed alongside the binary
  and is found automatically. Pass --shim only to override it"; ADR 0044 (the search declines a
  candidate it cannot attribute, a symlink among them).
- **Scope:** `src/report.zig` (`replayLine`), `src/main.zig` (the replay lines, preflight's `next`
  line, the demo's child), `src/mcp.zig` (the server's child), `spike/acceptance.sh`,
  `spike/mcp-acceptance.sh`, `docs/cli.md`, `docs/ci-quickstart.md`, `docs/evidence.md`.

## Context

When a run is not given `--shim`, it looks beside the binary's real path and finds
`<that directory>/../lib/libsideeye_shim.*`. A FAIL's `replay` line and an accepted preflight's
`next` line then printed `--shim <that path>`. On Homebrew the real path is
`<cellar>/sideeye/<version>/…`, so the line pinned one installed version. After `brew upgrade`
and `brew cleanup` the path is gone and the pasted line fails to find the shim. Without the
cleanup, the new binary runs with the old version's shim. The demo and the MCP server passed the
shim they found to their child explicitly, so their lines carried the same path.

## Decision

- The `replay` and `next` lines name `--shim` only when the run was given one. A run that found
  its own leaves it for the `sideeye` the line runs with, which finds the shim beside itself the
  same way. A case does not record the shim, so a replay without the flag searches as any run
  does.
- The demo passes `--shim` to its child only when the demo was given one. The MCP server does so
  only when `SIDEEYE_MCP_SHIM` is set. It still searches first, so a missing shim is refused at
  the call as before.
- The `reproduce` line is unchanged. It runs without Sideeye, so it has to name the shim, and it
  names the resolved path, which goes stale on upgrade; `docs/cli.md` says so.

## Alternatives considered

- **Start the search from the binary's symlinked side and print that path.** On Homebrew that is
  `<prefix>/lib/libsideeye_shim.*`, which survives upgrades, but it is a symlink, and the search
  declines a symlinked candidate it cannot attribute (ADR 0044) — the property this would undo.
- **Print the shim path without resolving it.** `findShim` holds only the resolved path; keeping
  the unresolved one is the alternative above.

## Consequences

- Measured in the Linux container. An install was copied to a prefix A, and `explore` there
  without `--shim` gave a FAIL whose `replay` line names no shim. Moving A to B and running that
  line with B's `bin` first on `PATH` reproduced the FAIL. The same line from the build before
  this change named A's shim and was refused, exit 2. Preflight's `next` line names no shim
  either. A run given `--shim` still names it. Over MCP with no `SIDEEYE_MCP_SHIM`, the result's
  `replay` names no shim; with it set, it names that path. The MCP check was red on the build
  before this change.
- A pasted line runs with whichever `sideeye` is first on `PATH`, and with that one's shim. Before
  this change, a newer binary on `PATH` could be paired with an older shim; now the two match.
- Preflight's `next` line, rebuilt here, now quotes a `--shim` it was given, as `replay` already
  did, and carries `--observe syscalls` when the preflight ran under it. The mode was dropped
  before, and the pasted `explore` counted the default way.
- macOS, and Homebrew itself, were not measured. The search is the same code on both platforms.
