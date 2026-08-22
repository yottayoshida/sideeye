# 0020. The report carries a second exhibit: the earliest checker-red world

Date: 2026-08-22
Status: Accepted

## Context

A FAIL saves exactly one counterexample — the earliest violating world
(ADR 0009) — and the campaign claim readings built on top of that fact:
cohort 2 froze "a criterion-1 candidate is a run whose saved case — the
earliest violating world, the only one the engine saves — has the
declared checker as its violated invariant", and cohort 3 restated it.
The rule was frozen to prevent world-shopping, and it worked. But the
cohort-3 poetry pair (#231) demonstrated what it also does: it promotes
an engine implementation detail — one saved case per run — into a
scoring rule. `poetry add` writes the lock before the manifest, so the
lock's mid-write world (an L0-only precision-limit observation, which
the declared checker heals through poetry's own documented chain)
structurally precedes the manifest-destruction world (checker-red
through the whole documented chain) in every run of the operation. The
real violation existed, was measured, was reproduced — and could never
be the exhibit, because the exhibit slot is defined as "earliest of any
class" and the engine saves nothing else. The revision that would have
put it first (`poetry version patch`, whose only in-root write is the
manifest) was itself barred from candidacy by the FAIL-freeze rule.
Both records are sealed; the lesson is an engine lesson.

The report schema is freeze surface 2 (`docs/contract-freeze.md`): it
freezes at the v1.0 tag, and unlike surfaces 1 and 5 it carries no
additive-extension clause. A second exhibit added after the tag would
be a breaking change. The next campaign's claim reading (cohort 4)
needs the mechanism on main before its own PROTOCOL freezes, so the
rule can cite a report that already exists.

## Decision

1. **The overall earliest keeps its meaning, its field, and its file.**
   `earliest` in the report remains the first violating world of any
   class; its case remains the first case written, landing on
   `cases/000001.json` in a fresh work directory. No existing consumer
   moves.
2. **The report gains `checker_earliest`** — present on FAIL exactly
   when some violating world's violation includes the declared checker
   (the world-judgment bits: `l2_failed`; never a parse of the
   invariant string). It carries the `earliest` shape (`crash_point`,
   `invariant`, `after`, `before`, `subject`, `observed`) plus its own
   `case` and `replay` fields inside the object. When no checker-red
   world exists — including every checkerless define, structurally —
   the object is absent.
3. **The checker exhibit is saved as its own case** when it is a
   different world from the overall earliest, written strictly after
   the earliest's case so the id order is deterministic and 000001's
   owner never changes. When it is the same world, `checker_earliest.
   case` names the same file; no duplicate is written. When the
   earliest's case cannot be written at all, the checker case is not
   written either — "the earliest's case takes the lower id" (000001
   in a fresh work directory) stays an invariant even under write
   failure.
4. **Replay does not mint cases** (ADR 0009, unchanged): the second
   case write sits inside the same explore-only guard as the first. On
   a replay of a checker-red case, `checker_earliest` appears with
   `case` naming the replayed file and `replay` carrying the existing
   "(this run is a replay; the case reproduced)" convention.
5. **The text report changes only when the two exhibits differ**: a
   three-line section headed `checker red crash point {k} of {n}
   ({invariant})` with indented `case` and `replay` continuation lines
   (the bare `checker` label already belongs to the falsification
   account). The section carries the crash point, the invariant form
   and the case/replay pair only; the world's full window
   (after/before/subject/observed) is machine-read from
   `checker_earliest` in the JSON — a deliberate asymmetry with the
   earliest's text block, and the one place DESIGN §13's "identical
   content" is narrowed on purpose. When the earliest is itself
   checker-red — every FAIL this engine had produced before poetry —
   the text is byte-identical to today's.
6. **The case file format does not change.** Its `violation` field
   keeps the existing rule (the L0 tag when L0 fired, else
   `"checker"`), which means a combined-world case file cannot by
   itself answer "is this checker-red" — that answer is machine-read
   from `checker_earliest` in the report. This is why the report
   object exists at all: the alternative "just point at a case file"
   fails on combined worlds, and on refusals there is no case file.

## Alternatives considered

- **A `cases[]` array.** Rejected: the schema checker's flattening is
  one level deep and does not inspect array-of-object members, so the
  two-way documentation pin would silently weaken; the doc's row
  format is scalar paths; and the always-present `case`/`replay`
  account strings are an existing contract.
- **Always-present `checker_case`/`checker_replay` account fields.**
  Rejected in review: nesting them inside the conditional object
  freezes two fewer sentinel-bearing fields at the tag, and the
  bidirectional schema pin is satisfied either way once the check-4
  FAIL fixture runs with a checker.
- **Per-class saving for all five invariant forms.** Rejected: no
  reader exists for the L1 classes; the claim reading needs exactly
  the checker-red class.
- **A separate "earliest L0-only" exhibit** (the issue's literal
  sketch). Rejected as redundant: when the overall earliest is not
  checker-red it already is the L0-side exhibit, and when it is
  checker-red no earlier L0-only world can exist.

## Consequences

- The frozen cohort-2/3 PROTOCOL sentences ("the only one the engine
  saves") describe the engine of their day and are not edited — their
  amendment locks stay intact, and the sealed readings they produced
  (poetry: recorded, not claimed; poetry-r2: recorded, never claimed)
  stand. The next campaign's PROTOCOL cites #231 and this ADR when it
  freezes its own reading against the new report.
- `docs/report-schema.md` gains the rows, and acceptance's check-4
  FAIL fixture gains `--check` (it runs without one today, so a
  checker-red world was structurally impossible in the schema corpus).
  The schema checker's flattening needs no change: it descends one
  level, so `checker_earliest.after`/`.before` surface as single keys
  matched by their own documented rows, exactly as `earliest.after`/
  `.before` always have.
- A run whose earliest is L0-only but which contains a checker-red
  world now yields two replayable counterexamples instead of one; the
  poetry shape becomes exhibitable by machinery instead of by prose.
