# Where Sideeye's output turns into an outside outcome

Every row of this funnel is backed by a record committed to this repository, and the
counts below are generated from those rows rather than written by hand. Nothing here
is a projection: a stage no campaign has reached says so with a zero.

This page answers one question, mechanically and over time: of the targets Sideeye was
run against, how many reached a verdict, how many of those verdicts were worth
reporting, and how many reports turned into something upstream. The project already
measured reach ([target-classes.md](target-classes.md)) and the reports it filed
(`spike/upstream-reports.tsv`) — what it could not do was count the path between them,
because the states lived in four records that nobody could add up.

It is not a conversion rate to maximise. Filing more issues is not the goal, and
upstream acceptance is not what makes a counterexample true. The point is to make this
project's own next decision falsifiable: if most fresh targets still refuse, reach work
dominates; if targets are judgeable but few failures are worth reporting, widening
reach further will not change outcomes; if reports land but re-measuring them is
expensive, that is a different bottleneck again.

## The records

| File | What it holds |
|---|---|
| `spike/outcome-funnel.tsv` | One row per (campaign, target): the furthest stage that campaign reached with that target, why it stopped, and the record that says so |
| `spike/outcome-funnel-campaigns.tsv` | One row per campaign: its date, whether it recorded every target it met, and how many candidates it screened |
| `spike/outcome-funnel.py` | The checker, the generator of the block below, and its own self-test |

Each file's columns and closed sets are documented in its own header. The checker runs
on every pull request and on `main` as the `outcome-funnel` job, self-test first.

## The stages

A row carries the furthest stage its campaign reached. The stages are cumulative: a
row at `filed` was judged, and a row that never got past a wall is at `attempted`.

| Stage | What it means |
|---|---|
| `attempted` | The target reached a define and the engine ran against it |
| `explored` | The report says worlds were run (`explored ≥ 1`, baseline included) |
| `judged` | PASS or FAIL |
| `novel` | The run's record says the finding is not already known |
| `report_worthy` | The owner judged it worth filing |
| `filed` | An upstream report exists |
| `acknowledged` | Upstream confirmed the defect |
| `fixed` | Upstream landed a fix |
| `revalidated` | This project re-measured against the fix |

Three of those names were chosen against the obvious ones, because this repository
already spells the obvious ones the other way round. The issue that asked for this page
called the first stage `screened`; `spike/dogfood/RUNS.md` uses that word for the
candidates a run turned *away* ("20 measured …, 21 screened out"), and
[target-classes.md](target-classes.md)'s first table heading spells `Measured` for
targets that have a verdict. `attempted` collides with neither. And `judged` rather
than a stage per verdict, because a verdict here is PASS or FAIL — everything else is
a named refusal, never a silent pass — so UNKNOWN is a row that stopped below this
line, with the refusal in its `stop` and `note`.

`explored` and `judged` are decided from the report the row names, not from prose and
not from the refusal's name. `docs/report-schema.md` holds the refusal vocabulary as a
closed set of thirty-four reasons but says nothing about which phase raises which, so
reading a stage off a refusal name would be inventing a classification this project has
not made. Reading `explored` off the report needs no such invention — and the first
draft of this page, written from prose, put three fewer targets past exploration than
the reports did: bat, ccache and meson each explored worlds (8, 55 and 110) before
refusing.

`acknowledged` is confirmation, not contact. Four of the reports on this ledger were
closed with a substantive reply that declined them, and one is open with several
comments and no resolution; all five stay at `filed`, with `declined` or `discussing`
saying which. Reading a reply as acknowledgement would make the stage
measure how much upstream wrote rather than whether the defect was granted, and the
issue that asked for this page is explicit that upstream acceptance is not what
makes a counterexample true.

One asymmetry is deliberate. `novel`, `report_worthy` and `filed` are about a
counterexample and require a FAIL. The three stages above them do not: the 2026-09-06
re-measurement of ImageMagick's third patch PASSes, and that PASS is exactly what
`revalidated` means.

## What the checker holds, and what it cannot

It holds every row to the record the row names. Where that record is a report this
engine wrote, the row's verdict and its stage are compared against the report's own
`verdict`, `explored` and `crash_points`; a row that claims a verdict the report does
not carry is red, and so is a row calling a zero-operation PASS a verdict. Where the
record is not a report, the row is held to the record existing and to it naming the
target — in its text, or in its file name, which for an engine refusal transcript is
the only place the tool appears. A row whose record is a transcript is also held
to its refusal: the note has to name a refusal that transcript actually raised,
which is what caught a row citing a measurement its own run had set aside. It
holds the funnel and `spike/upstream-reports.tsv`
to each other: a report filed without a row here is red, with the row to add named in
the failure.

What it cannot see is written here rather than left to be discovered:

- **Every stage above `judged`.** The comparison against a report stops there,
  because a report cannot know whether its finding was novel, was judged worth
  filing, or was filed. Those stages are the record's word. What holds them is
  internal: `novel`, `report_worthy` and `filed` need a FAIL, `filed` and above need
  a report this project filed and the date its state was read, and a report is filed
  once. Nothing compares `acknowledged`, `fixed` or `revalidated` against anything
  outside this repository.
- **A record that names every target.** Two rows cite
  [target-classes.md](target-classes.md) and one cites `BUILDLOG.md`, because the
  measurement behind them left no record of its own. Against a page that names every
  tool this project has met, the naming rule is satisfied by construction and adds
  nothing beyond the path existing.
- **Which report a row names**, when a campaign produced several for one target. mlr
  answered UNKNOWN five times and PASS once; composer PASS, PASS, then FAIL. The row
  names the one its campaign's record names, and a row naming the convenient report
  passes every rule.
- **A campaign that found two things in one target.** The 2026-09-06 patch3 row records
  that the reported windows closed; the fresh regression that run also found lives in
  its `note` and in no count.
- **Rows whose campaign kept no report.** Those are held to existence and naming only.
  The generated block says how many rows are in each state rather than letting the
  reader assume.
- **The live state of an upstream report.** Each row at `filed` or beyond carries the
  date its state was read. `spike/upstream-report-status.sh` measures the state now;
  nothing here reaches a tracker.
- **Whether a campaign happened at all.** There is deliberately no rule that every
  directory under `spike/dogfood/` has rows. A new run would go red for a reason its
  author could do nothing about, and the drift worth catching runs the other way.

Stages before `judged` are counted over campaigns that recorded every target they met.
A campaign entered for its filings alone contributes to the outcome half and to nothing
above it, which is why the block below prints both columns: subtracting across the two
halves is not a funnel step.

## The funnel

Regenerate with `python3 spike/outcome-funnel.py --write-doc`; CI compares this block
against a fresh rendering and fails on any difference, so no figure inside it is typed
by hand. The prose above it is not generated, and the numbers it quotes are held by
review the way ADR 0039 rules for figures quoted from other records.

<!-- outcome-funnel:summary:begin -->

```
outcome funnel -- every campaign

82 encounters (one campaign meeting one target) over 21 campaigns, 15 of them
recording every target they met; 69 distinct targets.
61 rows are held to a report this repository committed; 21 name a written record only.
159 candidates screened before the slates were fixed, over the 15 campaign(s) that
recorded one; the rest kept no such count.

reach, over the 15 campaign(s) that recorded every target they met
  attempted        73
  explored         45
  judged           41
    PASS           14
    FAIL           27

outcome            encounters   in full campaigns   distinct reports
  novel                23              14             21
  report_worthy        23              14             21
  filed                23              14             21
  acknowledged          4               2              3
  fixed                 4               2              3
  revalidated           4               2              3

why encounters stopped: awaiting 12, declined 4, discussing 2, known 8, no_content_lost 1, not_worth 5, wall 32, withdrawn 1
upstream states last read between 2026-08-13 and 2026-09-16; spike/upstream-report-status.sh measures them now.
```

<!-- outcome-funnel:summary:end -->

Narrower questions take the same generator: `summary --campaign <name>` for one
campaign, `summary --since YYYY-MM-DD` for a period.
