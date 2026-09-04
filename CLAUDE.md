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

- ADRs live in `docs/adr/` and are **written `Accepted`**, with provenance — at minimum
  `Accepted (YYYY-MM-DD)`, and ``Accepted (implementing PR merged as `sha`, DATE)`` once a
  merge commit exists to name. The old rule was "created `Proposed`, flipped when the
  implementing PR merges", and it asked for something one pull request cannot do: the ADR
  file arrives *with* the work it decides, so the flip is always a second commit. Measured
  over the whole history, twenty of twenty-five born-`Proposed` ADRs were flipped and five
  were not — all five inside the three dense release days of 2026-08-25..27 (#360).
  The exception is **pre-registration**: a campaign Seal A declares its ADR before the
  campaign runs (ADR 0012, 0015, 0016), and `Proposed` is the honest value there. Write it
  as `Proposed (design-first: …)`; a bare `Proposed` is refused. That marker is a claim,
  not a proof — like `Filed-under:` on an issue, it removes the silent slip, not the lie.
  `spike/check-adr-status.sh` reports this on pull requests and on `main`: it judges the
  first word of the Status line only, so `Accepted (…; proposed …)` and a body that
  discusses a proposal both pass, and it fails on a missing Status line, on a walk that
  covered fewer files than the directory holds, and on an empty directory.
  **The directory holds nothing but ADR files, every name is
  `NNNN-slug.md`, and the four digits are unique** — reported by
  `spike/check-adr-numbering.sh`, which runs on pull requests and on `main`. Numbering is
  highest-plus-one, which reserves nothing: on 2026-08-27 two sessions each wrote an
  `0028-*.md`, the slugs differed so the filenames differed, and git merged both without a
  conflict — the only thing that noticed was the two sessions telling each other (#373;
  ADR 0030 records it). **Nothing checks contiguity**, deliberately: renumbering 0028 to
  0029 leaves 0028 a gap until the other side lands, and that gap is the correct state
  during exactly the window the check matters.
  What the check does **not** do is stop the merge that creates a collision. No status
  check is required on this repository, so a branch cut from a `main` that already holds
  your number goes red on your PR, but two branches taken from the same base can each
  carry a unique number, both go green, and both merge — that case surfaces only on the
  post-merge run. Closing it needs a required up-to-date check or a merge queue, which is
  a repository setting and a separate call.
  If your number collides, renumber yours — **and do it before anything cites the path**.
  Several tracked documents hardcode `docs/adr/NNNN-slug.md`, and only `spike/acceptance.sh`
  sweeps any of them (three pages, for slashed backtick references). Bare `ADR NNNN` prose
  citations are checked by nothing and break semantically rather than loudly: after a
  renumber they point at a different decision.
- `CHANGELOG.md` keeps a `[Unreleased]` section; every merged feat/fix appends to it.
  **A release reads the block against itself before it renames the heading**, and records
  the reading in `BUILDLOG.md` — which entries a later one falsified, and what was done
  about each. Appending per merge means the author of an entry reads their own paragraph
  and nothing else, so entry-to-entry consistency is nobody's job until this moment; and a
  release that renames the heading without reading freezes whatever disagreed. `[1.0.0]`
  shipped that way: it carries "`readTrace` stays deliberately uncapped" beside the entry
  that capped it, two entries calling itself "this same unreleased block", and a filed-not-
  fixed note the entry above it already called wrong twice (#374). Merging the repeated
  `### Added`/`### Changed`/`### Fixed` headings into one of each belongs to this reading,
  not to CI: forcing it per pull request would put every branch in the same region of the
  file. `spike/check-changelog-block.py` holds the mechanical half on every push —
  duplicate titles, whole sentences shared by two entries, and references that no longer
  resolve or no longer point the way they say.
- **A closing campaign or cohort needs nothing done to `.gitattributes`.** That rule used
  to run the other way, and it was missed on every closure it faced — cohort 4, then
  `spike/macos-oracle/`, then `spike/scout-model-comparison/` — because nothing opens
  that file at the moment a record closes. The default is inverted now (ADR 0021):
  `spike/**` is `linguist-documentation`, `spike/*` and `spike/toys/**` are code, so a
  record is documentation from the day its directory exists and a new top-level script
  is code without a line. **What still needs a decision is a new _live_ directory** — a
  subdirectory of `spike/` holding maintained code — and it has to be named twice, in
  `.gitattributes` and in `exempt_dirs` in `spike/check-gitattributes.sh`. Naming it in
  only one of the two fails CI from either side; **naming it in neither is green**, and
  that is the misclassification ADR 0021 takes deliberately, not something the check
  catches. Verify with that script rather than by eye: it runs `git check-attr` over the
  full tracked list, not a sample, and `unspecified` is a failure now rather than the
  state the live harness sits in.
- **A cohort close moves the top-level record too, in the same sitting.** The rows
  belong in `docs/target-classes.md` (one per verdict, one per wall), the cohort
  paragraph in `PRD.md`'s criterion-1 trail and `DESIGN.md` §17, and the new define
  count in the as-of note of `docs/unknown-rate.md`. The revision that produced the
  recorded outcome also leaves its `verify-transcript.txt` beside its artifacts, the
  way cohorts 2 and 3 did — one per outcome, not one per define directory: cohort 2
  holds nine define directories and four transcripts. Cohort 4 closed with none of that written and
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
