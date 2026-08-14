# Working in this repository

## BUILDLOG.md is a delivery artifact, not an afterthought

This repository keeps a development journal (`BUILDLOG.md`, newest first) that records
decisions **when they are made — including the ones that turn out wrong**. It is the one
artifact here that generic delivery routines (CHANGELOG, ADRs, PR bodies) do not cover,
and it went unwritten for four pull requests once because no routine asked for it.

The contract:

- **Append at the moment of the decision, not at delivery.** Start the entry when the
  work starts and let it grow: a design choice, a measurement, a reversal — each gets its
  paragraph when it happens, in the same working tree as the change it describes.
  Batch-writing at PR time is the documented failure mode, not a lesser form of
  compliance: the containment entry was written once at PR-open, its central argument
  was reversed in review two hours later, and the reversal never made it back in.
- **Re-read the entry at PR-open and after every review round.** Anything that reversed
  or moved since a paragraph was written gets recorded before merge. PR-open is when the
  entry is *re-read*, not when it is written.
- Heading format: `## YYYY-MM-DD — <claim>`. State what was decided, what was measured
  (real numbers, real output), and what went wrong — the reversals are the point.
- CI enforces the mechanical half only — a pull request that changes `src/`, `shim/`,
  `spike/`, `build.zig` or `build.zig.zon` without touching `BUILDLOG.md` fails. CI sees
  the final diff and cannot see *when* the entry was written; the timing half of the
  contract lives in this file and in the habit.

## Other conventions

- ADRs live in `docs/adr/` and are created `Proposed`, flipped to `Accepted` when the
  implementing PR merges.
- `CHANGELOG.md` keeps a `[Unreleased]` section; every merged feat/fix appends to it.
- Acceptance (`spike/acceptance.sh`) runs in the Linux container; every new check must be
  seen red once (mutation or synthetic input) before it is trusted.
- Unit tests never write to a fixed shared path: `zig build test` runs the same test in
  several concurrent binaries, and seen-red-once validates assertions, not races — a
  fixed `/tmp` name passed every single run and then failed 66 of 80 paired runs (#28).
  Use a pid-unique directory or `std.testing.tmpDir`.
- A test that has flaked CI twice gets fixed before anything else merges. Flaky tests
  are self-detecting — the gap #28 exposed was response, not detection: filed within a
  day, then left rolling a die on every push for three days.
- English for everything committed.
