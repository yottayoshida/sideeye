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
- **When a campaign or cohort closes, add its directory to `.gitattributes`.** Everything
  under `spike/` that is a finished record rather than maintained code is marked
  `linguist-documentation`, so the language bar reflects the engine instead of the
  apparatus; the live harness is deliberately excluded from that list. The rule was
  already written at the top of `.gitattributes`, and cohort 4 still closed without it
  being applied, because nothing opens that file at the moment a cohort ends. It is
  repeated here because this is the file that is open. Verify with `git check-attr`
  over the full tracked list, not a sample, and check the live harness comes back
  `unspecified`.
- **A cohort close moves the top-level record too, in the same sitting.** The rows
  belong in `docs/target-classes.md` (one per verdict, one per wall), the cohort
  paragraph in `PRD.md`'s criterion-1 trail and `DESIGN.md` §17, and the new define
  count in the as-of note of `docs/unknown-rate.md`. Each define that reached an
  explore also leaves its `verify-transcript.txt` beside its artifacts, the way
  cohorts 2 and 3 did. Cohort 4 closed with none of that written and
  `target-classes.md` still calling a closed issue open — one day after that same page
  had been hand-backfilled for the two cohorts before it. Backfilling is the symptom;
  the pages moving when the cohort does is the fix.
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
  A post-campaign **open re-measurement** of a consumed campaign's committed
  defines (e.g. the #84 sweep) is not a campaign phase: it runs outside the
  driver, claims no blindness, and must not emit verify-seals-shaped artifacts
  (`run-manifest.json`) or write into any `blind-hunt*/` directory.
- **Ledgers are written through `spike/ledger-append.sh`** — it appends and then
  proves the file still extends HEAD's copy, restoring it if not. Hand edits
  broke the append-only prefix twice; the tool makes that unmakeable.
- **Declaration scripts the engine execs (setup/check) are committed mode 755,
  and a green run must spawn them the way the engine does** — through the
  file's own exec bit, never via `sh file`. A 644 script proven green under
  `sh` failed with Permission denied at the first sealed exploration
  (campaign 2, abook), because the engine spawns argv directly.
- **Campaign PR reviews carry two fixed axes** in addition to the reviewer
  covenant (never name target internals or known issues — a breach burns the
  candidate): (1) verify every "Verified"/"measured" claim against the committed
  transcripts and flag any claim whose measurement did not look at what the
  claim covers — measured on something other than the shipped thing must say so
  in the claim; (2) for any new guard, require falsification against the
  guard's own predicate, not only against the accident that motivated it.
  These two axes are where external review has repeatedly out-detected
  self-checks; prompts for R1/R2 must include them verbatim.
