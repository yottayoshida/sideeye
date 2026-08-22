# Cohort 4 — the campaign protocol, DRAFT

**This file is not a freeze and must not be cited as one.** The frozen
protocol is `PROTOCOL.md`, which does not exist yet: `PREP.md` §9 puts the
freeze at step 6, after the engine change (#231) merges and after the owner
signs off on the target list. Nothing here has contacted a target, and no
target is named.

The draft exists so that the freeze is a fill-in rather than a write. Every
section below is either **carried** (settled, by reference to text already
on main), **drafted** (written here, expected to survive review), or
**blocked** (cannot be written yet, with the reason named). A section left
blocked at freeze time is a reason not to freeze.

| Section | State | Blocked on |
|---|---|---|
| Purpose and selection rules | carried | — |
| Provenance and labelling | carried | — |
| The probe gate (conditions 1–9) | drafted | — |
| Probe plans, per target | **blocked** | the target list |
| Apparatus policy | carried | — |
| The mini-seal | carried | — |
| **Claim reading** | drafted | — (#231 merged, ADR 0020) |
| Bench and refill | drafted | — |
| Versions and image | **blocked** | the target list |
| Reporting | carried | — |

## Purpose and selection rules — carried

The rules are `PREP.md` §6: #209's rules 1–13 unchanged, plus 14 (novelty
pre-scan as a veto), 15 (interior forecast), 16 (wall forecast against
§3F), 17 (rule 11 measured on bug reports). The instrument that proposes
candidates against them is `SCOUT-BRIEF.md`. The freeze will name the
targets, their order, and the per-candidate measurements the brief
produced — including the rejected candidates, which is what makes the
slate auditable.

**What the cohort is for**, to be restated in the freeze in one sentence:
the missing combination is *novel × automatically discovered × mini-seal
provenance*, in one finding (`PREP.md` §2). Detection is not the binding
constraint and has not been since cohort 3.

## Provenance and labelling — carried

Assisted, with the scout and its sources named; never blind. The boundary
is criterion 1's own text — the invariant is committed before this project
observes any failure of the target *in execution*, and reading a report of
a failure while scouting is not observing one. `docs/scouting.md`'s "What a
scout must never do" applies in full.

## The probe gate — drafted

Cohort 2's seven conditions apply, with its predicates **sourced in place**
(`spike/cohort2/probes/lib.sh`) so the drilled lines stay the drilled
lines. One committed transcript per target; all conditions or the probe has
not passed. The positive control runs first, before any target's verdict
counts.

Cohort 4 adds two, already implemented and drilled in both colours
(`spike/cohort4/probes/lib.sh`, `spike/cohort4/probes/drills.txt`, 5 of 5):

- **Condition 8 — shim visibility agrees with the kernel.** Every in-root
  mutation the kernel performed must also have passed through a function an
  `LD_PRELOAD` interposer can see, measured with an interposer built from
  the shim's own exported symbols. A disagreement is a named wall at probe
  time. This is the condition cargo cost two defines and two explores to
  discover, and the one that catches the `mkstemp` idiom (#39, measured
  2026-08-22).
- **Condition 9 — the operation has an interior.** The count of
  engine-reachable kill points inside the state root, reported with its
  per-class breakdown. **A count of 1 is not a failure**: it is a fact the
  owner holds before the slot is frozen, with the bench available. That is
  the papis shape, discovered in cohort 3 at define time instead.

Both are engine-free — no kill, no checker, no define — so running them
observes normal execution only.

A drills re-run under this cohort's own image is required before any probe
verdict counts, because an image change is a harness change (cohort 3's
rule). That run is blocked on the image.

## Probe plans, per target — BLOCKED on the target list

Per target: the operation, the pre-state shape **including the fixture
bytes inlined**, the candidate state root, and the expected artifacts, all
frozen before the probe runs. Apparatus plumbing may be corrected at probe
time with the correction recorded in the transcript; the operation and the
pre-state may not.

## Apparatus policy — carried

The three tiers of `spike/cohort3/PROTOCOL.md` unchanged: configuration and
environment pinning is free and declared where used; the CPython sendfile
fallback is pre-declared for Python targets and used only on that refusal;
clock or entropy interposition is a per-target owner decision. Apparatus
discovered mid-probe is an amendment that must land **before that target's
first contact**.

Whatever the apparatus: a finding must reproduce against the stock tool
with no apparatus beyond strace fault injection before it is claimed or
reported.

## The mini-seal — carried

`spike/cohort2/PROTOCOL.md`'s "The mini-seal, sharpened for #140", read with
`spike/cohort4/` paths. No engine explore before the target's complete
define is on main; a define revision is a new target directory; **a FAIL
freezes the define** — later revisions cannot produce a criterion-1 claim
for that target, and a post-FAIL revision is therefore a record-only
artifact (`PREP.md` §3, B2, stated in advance so it is not re-litigated
with a fresh FAIL in hand).

The amendment rule is carried verbatim and extended as cohort 3 extended
it: an amendment made after a target's first explore cannot change how that
target's outcome is read, and neither can one made after its probe.

## Claim reading — drafted (#231 merged 2026-08-22, ADR 0020)

The mechanism this section waited on is on main: **ADR 0020**, "The report
carries a second exhibit: the earliest checker-red world"
(`docs/adr/0020-the-report-carries-a-second-exhibit.md`, Accepted), landed
with #231 in PR #241. What it changed, in the terms this protocol needs:

- `earliest` keeps its meaning, its field and its file — the first
  violating world of any class, its case still the first written. No
  existing consumer moves.
- The report gains **`checker_earliest`**, present on FAIL exactly when
  some violating world's violation includes the declared checker, decided
  from the world-judgment bits (`l2_failed`) and **never from a parse of
  the invariant string**. Absent when no checker-red world exists —
  including every checkerless define, structurally.
- The checker exhibit is saved as its own case when it is a different
  world, written strictly after the earliest's, so `000001`'s owner never
  changes.

**The rule this cohort freezes, to be written into `PROTOCOL.md` verbatim:**

> A criterion-1 candidate is a run whose **`checker_earliest`** exhibit
> exists — that is, a run in which some violating world's violation
> includes the declared checker — and the exhibit named there is the
> claim's exhibit. An **L0-only FAIL is a precision-limit observation,
> recorded and never claimed** (#35's ruling, applied cohort-wide in
> advance); a run whose only violations are L0-only has no
> `checker_earliest` and therefore no candidacy. The overall `earliest`
> remains the first physical counterexample and is reported as such,
> whether or not it is the exhibit.

Two things this does **not** change, stated so they are not read into it:

- **No re-reading of cohorts 1–3.** ADR 0020's own non-goal, and the
  amendment rule's. The poetry pair stays recorded-not-claimed and
  recorded-never-claimed on the rules they froze.
- **The FAIL-freeze rule still binds.** A post-FAIL revision cannot claim,
  and `checker_earliest` does not reopen that door — it changes which world
  is the exhibit within a run, not which runs are eligible.

One consequence for the probe plans, once targets exist: an operation whose
write order puts an L0-only world in front of its checker-red one is now
**measurable rather than unclaimable**, which widens what a candidate
operation may look like. It does not lower the bar — the checker still has
to break.

## Bench and refill — drafted

Cohort 3's rule, which worked and never fired: a target that fails its
probe is recorded as a named wall with its latest-upstream-stable recheck,
and the next bench target is promoted until four targets have passed
probes or the list is exhausted. A promoted bench target must itself pass
the selection rules **at promotion time, measured then**. Promotion
amendments land before their target's first contact.

The bench itself is blocked with the target list. One thing the cohort-3
bench got right and should be repeated: the bench is named and ordered in
the freeze, so a wall cannot consume the cohort and the worst recorded
outcome is "N substitutions happened".

## Versions and image — BLOCKED on the target list

Every target exact-pinned by hash; the apt layer pinned by build; the pins
recorded in a committed freeze-build transcript, which is the only
pre-freeze target contact. The versions that actually run are re-recorded
in each probe transcript and RUNLOG.

## Reporting — carried

Each upstream report is its own owner-approved gate; nothing in the cohort
authorises contact. The standing table of what has been filed and what has
come back is `spike/upstream-report-status.sh`, which measures rather than
remembers.

## Delivery — drafted

Merges in this cohort go through `spike/merge-gate.sh`, read as a printed
verdict and never chained to the merge command. The three merges that went
out wrong in cohorts 2 and 3 are one predicate now (`PREP.md` §3, D1–D3).

BUILDLOG entries open when the work starts, not at PR time — the contract
in `CLAUDE.md`, which this preparation itself broke once and recorded.
