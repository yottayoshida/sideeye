# spike/dogfood — using Sideeye on targets outside a cohort

A cohort is an instrument for one question: is this finding *novel*, discovered
*automatically*, under *mini-seal provenance* (`spike/cohort4/PROTOCOL.md`). It
pays for that with a frozen protocol, an owner sign-off, and a seal that cannot
be reopened. Most use of Sideeye is not that. Someone points it at a tool they
actually use and finds out whether it can be judged at all.

This directory is where that use is recorded. It is **not a cohort**: nothing
here is sealed, nothing claims blindness, and no run here is evidence for
criterion 1. What it is for is the question a cohort cannot answer, because a
cohort only ever names targets that passed selection: **what happens when
Sideeye meets a tool it was not chosen for.**

## What a run records, and why both halves are needed

Each run gets one directory, `YYYY-MM-DD-<slug>/`, holding two documents:

- **`SELECTION.md`** — which targets were considered, what was measured about
  each, and **why the rejected ones were rejected**. `spike/cohort4/SCOUT-BRIEF.md`
  says why the second half is not optional: *"a slate with no visible rejections
  is indistinguishable from a slate chosen by taste."* That is as true outside a
  cohort as inside one.
- **`RESULTS.md`** — what each target did, whether the finding was already known
  upstream, and where it was reported if it was reported. A verdict with no
  novelty check is a claim nobody checked.

Plus the apparatus (`apparatus/`) and the engine's own output (`transcripts/`),
so a reader can re-run rather than believe.

## The selection rules, and the one thing this directory adds

Selection follows the rules a cohort uses — #209's 1–13 plus cohort 4's 14–17,
written out in `spike/cohort4/SCOUT-BRIEF.md`. They are conjunctive and they are
not restated here; that page is the text.

What this directory adds is an **ordering** rule, bought on 2026-09-05 by
spending four target slots to learn it:

> **Measure linkage and threads before writing the candidate table, not after.**

Rule 16 asks for a wall forecast. The natural way to produce one is to read the
project and reason about it, and that is what the first slate of 2026-09-05 did:
four targets, four forecasts, and **four walls** — two static Go binaries, two
thread refusals — none of which cost less than an image build and a preflight to
discover. The second slate on the same day screened eight candidates by running
`file` and one `strace -e trace=clone` against the real binary first, dropped
four in twenty minutes, and **all four survivors reached verdicts**.

The rule is cheap to follow and it is not a substitute for rule 16: a forecast
still belongs in the candidate row, because a target whose wall is *expected* and
*named* can enter with the apparatus that lifts it. What the measurement removes
is the case where the forecast was simply wrong.

Two measured details that reading would not have produced, both from that day:

- `oxipng -t 1` still starts a thread. The flag sets rayon's pool size; it does
  not remove the pool.
- `beet ls` — a **read-only** command — trips `multiple_threads_detected`, while
  `python3 -c "import beets"` does not. The thread belongs to the `beet` entry
  point, not to Python and not to the import.

## What a run must push upward, in the same sitting

The same rule a cohort close follows (`CLAUDE.md`: "A cohort close moves the
top-level record too"). A run that reaches a verdict or a named wall belongs in
`docs/target-classes.md` — one row per verdict, one per wall — and a run that
produces an upstream report belongs in `spike/upstream-reports.tsv`, which
`spike/check-upstream-ledger.sh` holds to that page's markers in both directions.

Neither of those is optional and neither is automatic. `check-upstream-ledger.sh`
says what it cannot see: *"a filing in neither record is outside what these two
can say"*. Two reports filed before this directory existed sat in exactly that
gap, and the check was green the whole time.

## What this directory does not do

- **It does not claim blindness.** `docs/scouting.md`'s "what a scout must never
  do" applies in full; every run here reads its targets.
- **It does not decide reporting.** Whether a finding goes upstream is the
  owner's call, made per run and recorded in that run's `RESULTS.md`.
- **It does not hold maintained code.** `apparatus/` is what was run that day,
  kept so the run can be repeated, not a harness anything else imports. That is
  why this directory needs no entry in `.gitattributes` or in
  `check-gitattributes.sh`'s `exempt_dirs`: `spike/**` is documentation by
  default (ADR 0021), which is what a record should be.

## Sunset

Delete this directory if `RUNS.md` gains no row for twelve weeks (from
2026-09-05, so 2026-11-28). An empty log means the use it was built for is not
happening, and the two runs it would hold by then belong in BUILDLOG entries
instead.

Delete the ordering rule above — not the directory — if a run ever produces a
candidate table where the screening measurement and the rule-16 forecast
disagree in the direction that matters: the screen says a target is measurable
and the engine then refuses it. That would mean the screen is not measuring what
it claims to.
