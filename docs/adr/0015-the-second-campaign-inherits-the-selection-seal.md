# ADR 0015 — The second campaign: an inherited selection seal, and the recovery-path rule

- **Status:** Proposed (flips to Accepted when the campaign-2 Seal A pull request merges)
- **Extends:** ADR 0012 (the two-seal blind declaration protocol). Everything 0012
  fixes still holds; this ADR records only what campaign 2 does differently and why
- **Scope:** procedure only — `spike/blind-hunt2/`, no product code

## Context

Campaign 1 (topydo) ran to completion: twelve counterexamples from blind-declared
invariants, the seal order machine-verified. Its criterion-1 scoring then split —
the automated find was not novel (`topydo/topydo#318`), and the novel find (the
post-crash `revert` misfire) was reached by post-seal human analysis, which the
author ruled does not count as "found by Sideeye" (BUILDLOG 2026-08-14). Criterion 1
therefore stays open, and its designated path is a second campaign whose declaration
covers the ground campaign 1 explicitly left out: the recovery path.

A second campaign cannot simply re-run ADR 0012 from zero, because the world has
moved: the remaining candidates have been installed, run normally, and swept once —
all of it under campaign 1's rules, all of it ledger-recorded, and the sweep's exit
codes are public in the committed manifest. Pretending campaign 2 chooses its
candidates fresh, "before any candidate has been installed or run", would be theater.
This ADR records the honest alternative.

## Decision

### 1. The selection seal is inherited, not re-performed

The candidate list, priority order and selection predicate are **taken unchanged
from campaign 1's Seal A** (`217ec4f`, re-anchored at `a21b093`), which was merged
before any of these candidates had been installed or executed. Campaign 2 removes
exactly one name: topydo, consumed by campaign 1 and now fully sighted. The order
of the remaining four (khard → abook → khal → hledger) and the predicate (first
exactly-one with preflight-with-oracle exit 0 ∧ in-image resolution) are byte-level
inherited; no reordering, no predicate change, no additions.

What the experimenter knows about these candidates since that seal, exhaustively:
the permitted-source consultations in campaign 1's ledger (`--help`, docs pages,
normal-run observation), and the campaign-1 sweep verdicts (exit codes only —
khard/abook/khal accepted, hledger refused with its **reason still sealed and
unread**). None of this is trace, crash, source or bug-tracker knowledge; the
declaration-side blindness of all four candidates is intact. The selection-side
guarantee ("the order was fixed before anything ran") is carried by campaign 1's
merge date, not re-created — and this ADR says so instead of claiming a freshness
that no longer exists.

The predicate is deliberately **not** amended to dodge known refusal shapes.
Campaign 1's normal runs showed khard minting randomly named files per contact;
the watson precedent says that shape risks a `baseline_violates_invariant` refusal
at exploration time. Using that ledger-recorded observation to reorder or
re-predicate would be selection steered by observed behavior — the exact leak the
seals exist to close. The risk is pre-registered here instead: **if the selected
target refuses every declared operation at exploration, that is the campaign's
recorded result**, it feeds #84, and the next attempt is campaign 3 with the next
candidate. No within-campaign reselection (ADR 0012 breach rules unchanged: burns
before Seal B skip via `burned.txt`; after Seal B the campaign ends).

### 2. The recovery-path rule (the lesson campaign 1 paid for)

Campaign 1's sharpest behavior sat in the documented recovery path, which its
declaration had explicitly scoped out ("recoverability after a crash ... is not
asserted either way"). Campaign 2 closes that hole **as a declaration requirement**:

> Where the selected target's documentation names a recovery, undo, or repair
> command, the declaration MUST include, for each declared operation, an invariant
> of the form: *after a crash at any point and one invocation of the documented
> recovery command, tasks the crash left intact still satisfy the conservation
> invariant.* If the documentation names no such command, the declaration states
> that explicitly and the rule discharges vacuously.

This is declarable from documentation alone — no traces, no crash observation —
so it costs nothing in blindness. It means the checkers run the recovery command
inside the crash worlds, and a misfire of campaign 1's class would be found **by
the search, from a blind checker**, not by post-seal analysis.

### 3. Campaign directory and re-sealed tooling

Campaign 2 lives in `spike/blind-hunt2/`, self-contained: its own `candidates.md`,
`priority.txt`, `seal-a-contents.txt`, `ledger.md`, `configs/`, and its own copies
of the tooling (`sweep.sh`, `select.sh`, `verify-seals.sh`, `wrapper-template.sh`),
path-adapted where paths were baked in. Copies, not references: each campaign seals
its own verdict logic (ADR 0012 decision 7), improvements flow forward into new
seals and never mutate a closed campaign's frozen artifacts. `spike/blind-hunt/`
(campaign 1) stays untouched; editing its declaration would mark those checkers
sighted retroactively.

The sweep re-runs for campaign 2 (fresh container, current engine), against a
campaign-2 `invocations.tsv` committed before the sweep, exactly as ADR 0012
requires. The invocation rows are the campaign-1 rows for the four candidates with
paths moved into `blind-hunt2/` — their content is already public, so committing
them pre-sweep binds the sweep to a spelling, which is the property that matters.

### 4. The taint ledger grows

topydo joins the excluded list (crash worlds explored, states read, bug tracker
searched). The carried-over class knowledge — the in-place-rewrite window, the
backup-store state-matching hazard, the recovery-path lesson itself — is declared
here, not denied, per campaign 1's `candidates.md`: class knowledge informs what
kinds of invariant are worth declaring; target-specific internals stay out.

## What this honestly cannot claim (unchanged, plus one)

ADR 0012's three bounds carry over verbatim (auditable-not-proven ordering,
unread-by-rule sealed reports, a language-model experimenter). Campaign 2 adds a
fourth: **its experimenter has seen campaign 1's full results.** The seals cannot
make it forget how topydo broke. What keeps campaign 2 meaningful is that the
knowledge is class-level, publicly recorded, and — through the recovery-path rule —
converted into declared coverage rather than a private hunch.

## Consequences

- Criterion 1 gets its designated path: a finding that would hold "found by
  Sideeye" and "novel" in one piece, at full strength, with the misfire class
  inside the blind checker's reach.
- A refusal-heavy or null campaign stays cheap and honest: the declaration phase
  is the only sunk cost, the refusals feed #84, and campaign 3 inherits the same
  way this one does.
- The protocol acquires its steady-state shape: one seal chain per target,
  selection inherited down the frozen order, lessons entering as declaration
  rules rather than as predicate tweaks.
