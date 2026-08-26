# 0025 — Three ledgers decide corpus membership, and the partition is checked

Status: Proposed

## Context

`docs/unknown-rate.md` defines the A-group as "every committed, runnable define in the
repository" and publishes a rate measured on 2026-08-16. Cohorts 2, 3 and 4 have since
committed eighteen further defines. By the page's own definition they belong to that
corpus; none of them is in it. The page and `PRD.md` both disclose the gap and defer to
#239, which is this work.

"Every committed, runnable define" turns out to under-determine the answer in three
independent ways, and each of them changes which defines are measured:

- **Revisions.** `spike/cohort3/PROTOCOL.md` states that "a define revision is a new target
  directory", so hg's four directories are four defines, not one define measured four
  times. Read literally, the A-group admits all four — and Mercurial then contributes to
  the rate four times, with three of those contributions recording where an apparatus fell
  short rather than where the engine did.
- **Class.** `docs/target-classes.md` is where the criterion's word "supported" is defined,
  and it is explicit: "supported classes are exactly the rows of the first table below
  (Measured, with verdicts). The refusal tables and the Rust narrative are not supported
  classes." Four of the eighteen — jj, Bun and cargo's two revisions — sit in the refusal
  tables.
- **Apparatus.** `PRD.md`'s instrument note of 2026-08-26 records that himalaya's
  `no-accel-copy.so` is superseded: trace contract v11 interposes `copy_file_range` and
  `sendfile` directly (#244), so the apparatus now answers a wall that no longer stands.
  Whether such a define is still "runnable" is not obvious from either word.

The first draft of #239 answered the first of these by collapsing revisions silently — the
corpus would simply carry the last one — and justified it by noting that the count matched
the number of directories carrying a `RUNLOG.md`. That justification was an accident:
himalaya's RUNLOG is in the r1 directory, whose verdict was UNKNOWN, while the FAIL it is
known for is in r2 under `RESULTS.md`. Eleven equalled eleven for unrelated reasons.

There is also a disagreement already in the tree, pointing the other way. watson is in the
A-group denominator as a Python CLI — it is the single UNKNOWN in 1/28 — while
`docs/target-classes.md` lists watson under its refusal tables, which that page says are not
supported classes. The two documents give watson two different classes.

## Decision

**Every committed cohort define appears in exactly one of three ledgers, and `count.py
check` holds the partition rather than trusting it.**

- `spike/unknown-rate/corpus.tsv` — measured. Eight rows, entering as generation `g2`.
- `spike/unknown-rate/supersession.tsv` — replaced by a later revision of the same target.
  Six rows, each naming its **successor**, which the check requires to be a corpus define.
- `spike/unknown-rate/class-exclusions.tsv` — the target's class is not a supported class.
  Four rows, each quoting the `docs/target-classes.md` refusal-table row it rests on.

The union must equal the set of committed cohort defines on disk and the three must be
disjoint. A define cannot be dropped by being left out of all three, and cannot be
double-counted by appearing in two.

**Superseded apparatus is marked, not judged.** `corpus.tsv` gains a `flags` column:
`apparatus_declared` where a define carries apparatus beyond its toml, and
`apparatus_superseded` where a primary source says an engine change has overtaken it.
A marked define is neither rebuilt nor dropped; it runs as committed and its outcome is
published as measured, refusal included. The flag reaches the arithmetic, not only the
table — the check requires a flagged trial to sit in its group's rated set exactly once.

**watson stays in the denominator, and the disagreement is written down rather than
resolved.** New rows do not follow it: they take a first-table row or they go in
`class-exclusions.tsv`.

**The direction this decision moves the published rate is recorded in `BUILDLOG.md`, not in
the rule files.** A rule that argues about which way it moves a number is evidence the
number was in view when the rule was written, which is exactly what the two-merge
discipline (rulebook first, results after) exists to rule out.

## Alternatives Considered

**Collapse revisions implicitly, with no ledger.** Rejected: `PROTOCOL.md` says revisions
are separate defines, so silence would be a departure from a written rule with nothing
recording that a departure happened. The explicit file also gives the check something to
verify — the successor's existence — which an implicit rule cannot offer.

**Two ledgers: corpus plus supersession.** Rejected on measurement. The eighteen do not
split two ways: jj, Bun and cargo were not replaced by anything, so recording them as
superseded would state something false in a file whose only purpose is to be checked.

**Admit all eighteen to the corpus.** This is the reading with the most textual support,
and it is rejected on what it measures: one target contributing four trials, three of them
recording apparatus shortfalls, describes the cohort's development history rather than the
engine's current reach. The cost is stated in BUILDLOG.

**Rebuild the superseded defines for v11.** Rejected as scope: `PROTOCOL.md` makes a
revision a new target directory, so rebuilding is a cohort re-run, not a re-sweep.

**Drop the superseded defines.** Rejected as deletion of a result: that the engine's own
development inputs now include some it cannot measure unchanged is a finding, and dropping
them removes it from the record.

**Resolve watson by dropping it from the denominator.** This is what `docs/target-classes.md`
says literally, and it is rejected because the page that includes watson says why it does —
counting a known refusal is "the honest direction" — and dropping it moves the published
figure the other way. Two adversarial reviews of the plan called the inclusion post-hoc
selection, correctly: it was decided after the sweep that produced the number. Disclosure
does not make it otherwise, which is why the disagreement is stated in both documents
rather than quietly settled in one.

## Consequences

- Closing a cohort now has a follow-on step: its defines must be sorted into the three
  ledgers before the next sweep. The check fails loudly when they are not, which is the
  intended cost.
- The `flags` column is a general mechanism with one flag in use. A second flag with no
  aggregation behaviour of its own would be a place for a mark that decorates without
  counting — the check that a flagged trial is rated exactly once is what keeps that from
  being silent.
- Nothing verifies that a corpus row's class slug corresponds to a `docs/target-classes.md`
  row. The mapping is a convention recorded in the corpus header. Adding that check is its
  own issue; folding it in here would mix a new gate into the decision it is meant to hold.
- The supersession ledger's criterion is narrow by construction ("a later revision of the
  same target, and it is in the corpus"). A define that ought to leave the corpus for some
  other reason has no home, and that is deliberate: the alternative is a general "excluded"
  file whose rows cannot be checked against anything.
