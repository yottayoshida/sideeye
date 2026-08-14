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
- English for everything committed.

## Blind-hunt campaigns: the apparatus rules

The campaign protocol is ADR 0012 (+ per-campaign ADRs). Four operating rules,
each purchased with a specific failure:

- **Rehearse before sealing.** `spike/rehearse-campaign.sh` runs the entire
  pipeline — real tooling, synthetic targets, planted defects, then a clean
  end-to-end pass — in a scratch repository. Run it green before opening any
  Seal A PR and after any change to campaign tooling. Blindness is the only
  non-renewable resource; the rehearsal is where apparatus errors are free.
- **Phases go through the driver.** `spike/campaign-driver.sh` (status / sweep /
  select / verify / explore) checks each phase's preconditions and refuses
  otherwise. No hand-typed docker/git chains for campaign phases. The driver
  never merges and never commits: irreversible steps stay human, and a merge is
  its own invocation issued only after reading the checks' pass/fail column.
- **Ledgers are written through `spike/ledger-append.sh`** — it appends and then
  proves the file still extends HEAD's copy, restoring it if not. Hand edits
  broke the append-only prefix twice; the tool makes that unmakeable.
- **Campaign PR reviews carry two fixed axes** in addition to the reviewer
  covenant (never name target internals or known issues — a breach burns the
  candidate): (1) verify every "Verified"/"measured" claim against the committed
  transcripts and flag any claim whose measurement did not look at what the
  claim covers — measured on something other than the shipped thing must say so
  in the claim; (2) for any new guard, require falsification against the
  guard's own predicate, not only against the accident that motivated it.
  These two axes are where external review has repeatedly out-detected
  self-checks; prompts for R1/R2 must include them verbatim.
