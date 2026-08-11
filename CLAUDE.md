# Working in this repository

## BUILDLOG.md is a delivery artifact, not an afterthought

This repository keeps a development journal (`BUILDLOG.md`, newest first) that records
decisions **when they are made — including the ones that turn out wrong**. It is the one
artifact here that generic delivery routines (CHANGELOG, ADRs, PR bodies) do not cover,
and it went unwritten for four pull requests once because no routine asked for it.

The contract:

- **Write the entry before opening the PR.** Heading format: `## YYYY-MM-DD — <claim>`.
- State what was decided, what was measured (real numbers, real output), and what went
  wrong or was reversed — the reversals are the point of the log.
- CI enforces the mechanical half: a pull request that changes `src/`, `shim/`, `spike/`,
  `build.zig` or `build.zig.zon` without touching `BUILDLOG.md` fails.

## Other conventions

- ADRs live in `docs/adr/` and are created `Proposed`, flipped to `Accepted` when the
  implementing PR merges.
- `CHANGELOG.md` keeps a `[Unreleased]` section; every merged feat/fix appends to it.
- Acceptance (`spike/acceptance.sh`) runs in the Linux container; every new check must be
  seen red once (mutation or synthetic input) before it is trusted.
- English for everything committed.
