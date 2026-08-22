# poetry revision 2 (cohort 3) — run log and ruling

## Timeline (all 2026-08-22)

1. The define merged (main `88447be`) carrying the FAIL-freeze ruling
   on its face: poetry reached its FAIL verdict before this revision
   existed, so **nothing this revision measures is, or can become, a
   criterion-1 candidate or claim** — the revision exists as a sealed
   minimal reproduction for the upstream conversation, recorded and
   never claimed. R1 (which caught the first draft citing around the
   FAIL-freeze sentence) and R2 (which caught two residual candidacy
   phrasings) both ran before the freeze; the reversal is in
   BUILDLOG. Mini-seal verified: first-parent introduction on main
   before any artifact.
2. **Two explores, identical verdicts.** Run 1 is the committed
   artifact set (`explore-transcript.txt`, `report.json`,
   `cases/000001.json`, `--work` mounted from the start — the
   primary's run-0 lesson applied). Run 2 reproduced run 1 exactly on
   every compared field: verdict, violations, explored, crash_points,
   and earliest.{crash_point, invariant, subject, observed}.

## The verdict

**FAIL, 1 of 3 worlds (2 crash points + baseline) — the declared
expected shape, exactly.** The world map:

- **Crash point 1** (before the truncating `open`): the old manifest.
  Green — not a violation.
- **Crash point 2** (after `open(pyproject.toml, O_TRUNC)`, before
  the single 104-byte `write`): the empty manifest. **Violated
  invariant: "built-in atomicity, and the checker"** — L0 sees a file
  holding neither the old nor the new content, and the checker's leg
  R sees the whole documented recovery chain fail (config invalid:
  the name and version the rebuild needs were in the file that was
  destroyed; step 1 `poetry lock` rc 1, step 2
  `poetry lock --regenerate` rc 1). The transcript carries the full
  chain output. In user terms: kill `poetry version patch` between
  its truncating open and its write, and the entire user-authored
  manifest — dependencies, configuration, everything, not just the
  version line — is gone, and nothing in poetry's documented path
  brings it back.

Every declaration in `proposals.md` was confirmed: the write shape's
two crash points, the single violating world, the earliest-by-
construction structure (no noise world in front — the contrast with
the primary's L0-masked record is the point of this revision), the
combined invariant form, and the 0-threads/0-children forecast (the
oracle agreed on 2 operations; no refusal).

## The reading (frozen before the explore; binding here)

Under the FAIL-freeze ruling carried in `proposals.md`: **recorded,
never claimed.** This FAIL is not a criterion-1 candidate and cannot
become one — poetry's target-level FAIL predates the revision. What
the record now holds that it did not before: a **sealed minimal
reproduction** — define frozen on main before the engine ran, one
crash point, one world, checker-red through the whole documented
chain, reproduced twice — of the manifest wound the primary measured
at its crash point 4. Upstream-report material behind the standing
per-report owner gate; the stock-reproduction rule applies before any
conversation.

The claim-reading design gap this pair of records demonstrates (L0
precision noise ahead of a real checker red disqualifying a run under
the earliest-case rule) is filed as #231 for the next campaign's
protocol — frozen before that campaign's first contact, applying to
nothing in cohorts 1–3.

## Bounds

Assisted provenance, as the whole cohort. `oracle_verified: true`;
single process, no threads, no children (the probe's forecast held in
practice). Not tested: power loss, torn writes, concurrent processes,
appended tails (the report's own line). The conditional timeout
annotation was not needed: no red names a timeout.
