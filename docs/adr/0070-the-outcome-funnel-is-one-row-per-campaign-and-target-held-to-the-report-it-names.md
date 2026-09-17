# 0070 — The outcome funnel is one row per campaign and target, held to the report it names

- **Status:** Accepted (2026-09-17)
- **Scope:** `spike/outcome-funnel.tsv`, `spike/outcome-funnel-campaigns.tsv`,
  `spike/outcome-funnel.py`, `docs/outcome-funnel.md` and the `outcome-funnel` CI job.
  Not the engine, not the report schema, not `docs/target-classes.md` or
  `spike/upstream-reports.tsv`, which this record reads and does not change.

## Context

This project measures reach and verdict quality and does not measure what happens after
a verdict exists (#605). A FAIL may be already known, recoverable, not worth reporting,
reported and declined, acknowledged, fixed, or re-measured against a fix, and those
states lived across `BUILDLOG.md`, the dogfood run records, `docs/target-classes.md`
and `spike/upstream-reports.tsv`. Nobody could add them up, and the project's next
engineering decision depends on the shape of the drop-off rather than on any one of
those records.

The first draft of this decision was written from prose, and it was wrong in a way that
decided the design. It put eleven of the 2026-09-16 run's twenty targets past
exploration; the reports that run committed say fourteen, because bat, ccache and meson
each explored worlds — 8, 55 and 110 — before refusing. A funnel assembled by reading
records and writing numbers reproduces the failure `spike/upstream-report-status.sh`
was written against: "a table saying 0 comments is indistinguishable from a table nobody
re-read".

## Decision

1. **One row per (campaign, target), carrying the furthest stage that campaign reached.**
   Not an event log: "how many reached stage X" would become a distinct-count over
   events and the same question would have two answers. Not one row per target: mogrify was
   filed by one campaign, answered by the next and re-measured by a third, and
   collapsing campaigns loses exactly the re-measurement this record exists to count.

2. **`explored` and `judged` are read from the report the row names, never inferred
   from a refusal's name.** `docs/report-schema.md` holds thirty-four refusal reasons as
   a closed set and says nothing about which phase raises which; a stage read off a
   refusal name would be a classification this project has not made. `explored` is the
   report's own `explored ≥ 1`; `judged` is PASS or FAIL with `crash_points > 0`, so an
   operation that performs nothing — which PASSes with both counters zero — is not a
   verdict about the tool.

3. **The checker holds each row to the record it names**, and where that record is a
   report this engine wrote, to its `verdict`, `explored` and `crash_points`. Where it
   is not, the row is held to the record existing and naming the target, in its text or
   in its file name — an engine refusal transcript carries the refusal and never the
   tool's name — and, where that record is a transcript, to its note naming a refusal
   that transcript raised. **The comparison caps at `judged`**: a report cannot know
   whether its finding was novel or filed, so every stage above it is the record's
   word, held only by the internal rules in decisions 4 and 5. `summary` prints how
   many rows are in each state, so the weaker half is counted rather than assumed.

4. **A report is filed once, by the earliest campaign carrying it at `filed` or beyond;
   later campaigns advance it.** A rule of one row per report would put the top of the
   ladder out of reach: ImageMagick#8939 was filed by the 2026-09-05 run, answered on
   the same issue by the refix run, and re-measured by the patch3 run — and that last
   row is the only `revalidated` this project has.

5. **`novel`, `report_worthy` and `filed` require a FAIL; the three stages above them do
   not.** The patch3 re-measurement PASSes, and that PASS is what `revalidated` means.

6. **Containment runs from the funnel to `spike/upstream-reports.tsv` and back, and not
   from the dogfood directories.** A report filed without a row here is red, with the
   row to add named in the failure — forgetting the funnel after filing is the drift
   this record exists to stop. There is deliberately no rule that every directory under
   `spike/dogfood/` has rows: a new run would go red for a reason its author could do
   nothing about.

7. **Reach is counted over campaigns that recorded every target they met.** The
   campaigns file declares `full` or `filings-only` per campaign, and the generated
   block prints both columns so that subtracting across the two halves is visibly not a
   funnel step.

8. **The counts in `docs/outcome-funnel.md` are generated and compared byte for byte in
   CI.** ADR 0039 declined a figure check that would compare two hand-written records
   and call one of them the truth; this one has a source that is not hand-written prose.

## Alternatives Considered

- **An append-only event log.** Rejected under decision 1.
- **Deriving the tail from the trackers at check time.** Rejected: CI would depend on
  the network, and the live state already has an owner in
  `spike/upstream-report-status.sh`. Each row at `filed` or beyond carries the date its
  state was read instead.
- **Deciding whether the evidence is a report by its file extension.** Rejected after
  measuring: the forty `.json` files under `spike/dogfood/2026-09-13-joplin-turns/` are
  strace readings with no `verdict` at all. The checker decides by content.
- **Rows for the candidates a campaign screened out.** Rejected: the candidate tables
  differ in shape per run and are easy to count two ways — a straightforward count of
  the 2026-09-16 run's tables gives 63 where the run's own record says 41. The
  campaigns file carries one `candidates` number taken from the campaign's record.
- **`screened` and `measured` as the first stage's name.** Rejected: `RUNS.md` spells
  `screened` for the candidates a run turned away, and `docs/target-classes.md`'s first
  table spells `Measured` for targets that have a verdict. Both read backwards here, so
  the stage is `attempted`.
- **A column for operator time.** Rejected: nothing records it today, and a column that
  is always empty is a field that lies.
- **A separate checker and generator.** Rejected: two readers of one record drifted in
  this repository once already — `upstream-report-status.sh` and
  `check-upstream-ledger.sh` spelled a comment differently and the table printed
  "read 7 of 7" over six standing reports. One file, several modes.

## Consequences

- Filing an upstream report now requires a row here, or CI is red. That is the point,
  and the failure names the row to add.
- A campaign that found two things in one target is one row; the second finding lives
  in the row's note and in no count. The 2026-09-06 patch3 row is the first instance.
- Nothing checks which report a row names when a campaign produced several for one
  target. A row naming the convenient report passes every rule. This is written on the
  page and in the script rather than left to be discovered.
- Rows whose campaign kept no report are held to existence and naming only. They are
  counted separately so the reader can see how much of the funnel is machine-backed.
