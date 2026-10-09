# Security policy

## Supported versions

Only the latest release is supported. A fix ships as the next release, and through the Homebrew tap once that release is published; earlier releases do not receive backports.

## Reporting a vulnerability

Report it privately, through GitHub's private vulnerability reporting: [Report a vulnerability](https://github.com/yottayoshida/sideeye/security/advisories/new) (the Security tab of this repository). Please do not open a public issue or pull request for something you believe is a vulnerability.

A useful report names the version (`sideeye --version`), the platform, how Sideeye was installed, and the smallest steps that show the problem. The report is visible to you, the maintainer and anyone the maintainer adds to it, and stays private until the maintainer publishes an advisory for it.

## What counts

Sideeye runs the commands you declare and empties the state directory you name, on purpose. What it does document is a set of protections, each with its limits written beside it. **A way past one of them that its document does not already name as open is a vulnerability:**

- **The MCP server's confinement.** A tool path outside `SIDEEYE_MCP_ROOT`, or a replayed case whose state directory does not lie strictly inside `SIDEEYE_MCP_STATE_ROOT` ([docs/mcp.md](docs/mcp.md), [ADR 0022](docs/adr/0022-the-naming-root-and-the-destruction-range-are-separate.md)). What stays open is written down: [ADR 0010](docs/adr/0010-mcp-adapter.md) names the window between a tool path's check and the child's open, out of scope only while the root and the work directory are not writable by an attacker; on the state directory a replay empties, [ADR 0037](docs/adr/0037-the-root-the-walk-deletes-is-the-root-that-was-vetted.md) closes the window between the check and the open and names what it does not cover, and [ADR 0024](docs/adr/0024-holding-the-root-is-not-choosing-the-root.md) names the names still resolved while the state is rebuilt.
- **The MCP server's environment.** The target sees `PATH` and the variables you list in `SIDEEYE_MCP_CHILD_ENV`, and nothing else of the server's ([docs/mcp.md](docs/mcp.md), [ADR 0011](docs/adr/0011-mcp-child-env-and-fresh-state.md)).
- **The shim search.** A candidate that is a symlink at its last component, or a file owned by someone other than you, root or the owner of the `sideeye` binary, being loaded instead of refused ([ADR 0044](docs/adr/0044-the-shim-search-refuses-what-it-cannot-attribute.md), which calls this a mitigation and names the window it cannot close).
- **The work directory.** A work directory Sideeye did not just create being used although its last component is a symlink or it belongs to someone other than you ([docs/cli.md](docs/cli.md), [ADR 0099](docs/adr/0099-the-work-directory-is-refused-unless-it-is-the-runners-own.md), which calls this a mitigation and names what it does not close).
- **The trace file's refusals.** The trace being written through, or read back through, a symlink or a FIFO where [docs/cli.md](docs/cli.md) says it refuses one.
- **Attribution in the text block of an MCP result.** Text the target influenced, read as the engine's own words in the text block, where [ADR 0010](docs/adr/0010-mcp-adapter.md) says the byte-counted region prevents it. `structuredContent` is not marked, and ADR 0010 says so.

## What does not

- **A config or a saved case running its commands**, and an exploration restoring the state directory its config names, wherever that is: both are trust boundaries by design, the same as a script you run — vet them before you hand them over ([ADR 0010](docs/adr/0010-mcp-adapter.md), [ADR 0022](docs/adr/0022-the-naming-root-and-the-destruction-range-are-separate.md), [docs/mcp.md](docs/mcp.md)).
- **What a target does inside the directories it is given** — the state directory, and the work directory it can write, where a target that hands Sideeye a trace it wrote itself is not stopped by any flag ([docs/cli.md](docs/cli.md)). Sideeye's checks on pathnames are mitigations, not a sandbox. Run a target you do not trust in a container, network-off where it allows.
- **A window a document above already names as open.** A report that one is easier to reach than the document says is still welcome.

## Where the threat model is written down

- [ADR 0010](docs/adr/0010-mcp-adapter.md) — the MCP server: confinement, the minimal environment, attribution, and the residual issues it accepts.
- [ADR 0044](docs/adr/0044-the-shim-search-refuses-what-it-cannot-attribute.md) — the shim search, and why it is a mitigation rather than a boundary.
- [ADR 0099](docs/adr/0099-the-work-directory-is-refused-unless-it-is-the-runners-own.md) — the work directory, refused unless it is the runner's own, and what that check does not close.
- [docs/mcp.md](docs/mcp.md) — what the server reads from its environment, what it confines and what it does not.
