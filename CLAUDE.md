# Working in this repository

## BUILDLOG.md is closed at v1.6.0

`BUILDLOG.md` was this repository's development journal from its first commit to the
v1.6.0 release (2026-09-22). **It is no longer appended to** — the owner's decision, at the
release, that it no longer earns its place. It stays in the tree as the record up to that
release, and the many "see BUILDLOG YYYY-MM-DD" citations across the code, the docs and the
spike records still resolve. What a new decision needs goes where it would have gone beside
the journal anyway: an ADR when it is one, the pull request's body for what was measured
and what reversed, and `CHANGELOG.md` for what shipped. CI no longer requires the file to
change.

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
  What the check does **not** do is stop every merge that creates a collision. It is a
  required check on `main`, so a pull request whose run already sees your number on `main`
  goes red and cannot merge; but `main`'s protection does not require a branch to be up to
  date before it merges, so two branches taken from the same base can each carry a unique
  number, both go green, and both merge — the second one's green run predates the first
  one's merge — and that case surfaces only on the post-merge run. Closing it needs the
  up-to-date requirement or a merge queue, which is a repository setting and a separate
  call.
  If your number collides, renumber yours — **and do it before anything cites the path**.
  Several tracked documents hardcode `docs/adr/NNNN-slug.md`, and only
  `spike/check-doc-refs.sh` (acceptance check 11) sweeps any of them (four pages, for
  slashed backtick references). Bare `ADR NNNN` prose
  citations are checked by nothing and break semantically rather than loudly: after a
  renumber they point at a different decision.
- **An ADR numbered after 0145 ends with a `## Residual windows` section** — the ways a run under an oracle can
  still reach PASS with something unseen once the decision is in, or "None" — and each item, like every line of an
  ADR the vocabulary in `spike/check-silent-windows.py` matches, is filed in `spike/silent-windows.tsv`: as a window
  `docs/silent-windows.md` lists, or with the reason it is not one. CI fails on one nobody filed (ADR 0145).
- `CHANGELOG.md` keeps a `[Unreleased]` section; every merged feat/fix appends to it.
  **A release reads the block against itself before it renames the heading**, and records
  the reading in the release pull request's body — which entries a later one falsified,
  and what was done about each. Appending per merge means the author of an entry reads their own paragraph
  and nothing else, so entry-to-entry consistency is nobody's job until this moment; and a
  release that renames the heading without reading freezes whatever disagreed. `[1.0.0]`
  shipped that way: it went out carrying "`readTrace` stays deliberately uncapped" beside
  the entry that capped it, two entries calling itself "this same unreleased block", a
  filed-not-fixed note another entry already called wrong twice, and four statements about
  issues that had since closed. #374 corrected twelve of them after the fact, which is the
  expensive way. Merging the repeated
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
- Before pushing, merge the latest `origin/main` into the branch, commit everything, and run
  `sh spike/check-doc-refs.sh && sh spike/check-unknown-rate.sh`. They are acceptance checks
  11 and 12, need no build and take seconds; otherwise a moved path a page still cites, or a
  ledger row no B2 rule covers, turns up as a red Acceptance suite after the push. CI runs
  them on the branch merged with `main`, which is why the merge comes first. They read the
  filesystem, not git: a file left uncommitted or ignored by `.gitignore` makes them green
  here and red in CI, and so does a path that differs from the real one only in case, which
  macOS's file system does not tell apart.
- Unit tests never write to a fixed shared path: `zig build test` runs the same test in
  several concurrent binaries, and seen-red-once validates assertions, not races — a
  fixed `/tmp` name passed every single run and then failed 66 of 80 paired runs (#28).
  Use a pid-unique directory or `std.testing.tmpDir`.
- A test that has flaked CI twice gets fixed before anything else merges. Flaky tests
  are self-detecting — the gap #28 exposed was response, not detection: filed within a
  day, then left rolling a die on every push for three days.
- Every tracked `.zig` file is what `zig fmt` leaves it, and CI fails a pull request, or a
  push to `main`, where one is not (`spike/check-zig-fmt.sh`, the `fmt` job; #695). Run
  `zig fmt $(git ls-files '*.zig')` before pushing.
- **A new job in `ci.yml` goes into the `required` job's `needs:` in the same pull request.**
  Branch protection requires `required` (with `crash-consistency`, `linux` and `macos`), not a
  list of job names, and `required` fails when a job of the workflow is missing from its list
  (`spike/check-ci-required.py`, ADR 0131).
- **Every job in every workflow carries its own `timeout-minutes`**, set from its longest recent
  successes rather than GitHub's six-hour default; `required` fails on a job without one, in
  any workflow, `.yml` or `.yaml`. A step's timeout does not count — the job around it can
  still hold a runner for GitHub's six hours. The image `ci.yml` builds `FROM` is pinned by
  digest inside a `run:` string, where Dependabot does not look, so it moves by hand.
- English for everything committed.

## Releasing

- **Every place in this repository that names a release's version is written by
  `spike/release_pins.py`, and CI fails a change where a place a release moves before it
  differs from `build.zig.zon`, or the places it moves after it name another release than
  `build.zig.zon`'s or the one `CHANGELOG.md` lists right below it.**
- Before the release, `python3 spike/release_pins.py bump X.Y.Z`, in the commit that renames
  `[Unreleased]` to `[X.Y.Z]`: the check fails a `build.zig.zon` whose version has no heading.
- Once the release is published, `python3 spike/release_pins.py pin vX.Y.Z --tap <checkout of
  yottayoshida/homebrew-tap>`. It downloads the three assets, refuses one whose sha256 is not
  the digest the release publishes, and writes the CI quickstart, its workflow, the MCP
  container's Dockerfile and the tap's `Formula/sideeye.rb`. The pull request to the tap is
  opened by hand. A pin never written fails the next bump.
- The places are the script's `BEFORE`, `AFTER` and `TAP` lists, each found by a fixed string
  that must match one line exactly once; a version anywhere else — a measurement's record, a
  dependency's — is not touched.

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
