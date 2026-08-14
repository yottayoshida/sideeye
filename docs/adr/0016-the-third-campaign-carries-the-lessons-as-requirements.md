# ADR 0016 — The third campaign: the lessons ride as declaration requirements

- **Status:** Proposed
- **Date:** 2026-08-14
- **Extends:** ADR 0012 (the two-seal blind declaration protocol) and ADR 0015
  (the inherited selection seal and the recovery-path rule). Everything they
  fix stays fixed; this ADR records only the deltas for campaign 3.

## 1. The inherited order, two removals deeper

Campaign 3's candidate list is campaign 2's sealed order minus khard (burned
before campaign 2's Seal B — a breach, not consumption) and abook (consumed
by campaign 2's exploration, null result): **khal, then hledger**. The
selection predicate is unchanged — walk the sealed order, take the first
candidate that the sweep accepted (exit 0) and that resolves in the pinned
container; exactly one. ADR 0015's inheritance argument carries: both
remaining candidates have been installed, normally run once, and swept twice
(exit codes only; hledger refused both times, reason sealed and unread), all
of it public since campaign 1, so a fresh "nothing has run yet" seal would be
theatre. The campaign-2 additions — the sealed-at-A invocations, the
config-path consistency check, the burned-list input to the selector — carry
unchanged in this campaign's own tool copies (ADR 0015 §3: copies, not
references).

## 2. Campaign 2's lessons become declaration requirements

Each of these was purchased in campaign 2 and is now a requirement the Seal B
review checks, not advice:

1. **The checker inspects files first and queries the target last.** A red
   fixture that fails a file leg must provably never reach a target
   invocation, and every checker failure message names its leg so the pin
   doubles as the no-execution proof. (The khard burn: a query-first checker
   let the red suite show the target a mis-shaped store.)
2. **Red fixtures never hand the target out-of-contract state.** Every native
   store a real target invocation reads in the red suite is target-written,
   empty, or absent; branches that need an ill-behaved binary run through a
   documented stub seam, where the target does not run at all. Input files
   named in argv are committed, hand-authored, well-formed members of a
   documented input class.
3. **Declaration scripts the engine execs are committed mode 755, and the
   green run must spawn them the way the engine does** — through the exec
   bit, never via `sh file`. (Campaign 2's first Seal B refused at setup
   spawn: green had proven a path the engine never takes.)
4. **The commit order is the audit trail**: sources committed before the
   declaration exists, the declaration before the apparatus. Local
   reordering stays possible (ADR 0012's honesty bounds), but the default
   story is in the history.
5. **An observed refusal is declarable as an operation** (`expected_status`),
   and an interrupted refusal is a first-class crash window.
6. **The run manifest carries the engine's version string and the SHA-256 of
   engine and shim** (the R3 leg), the runner fails closed on a missing or
   unparsable report, and per-op exit + report state ride in the manifest.

## 3. What carries verbatim

The recovery-path rule (ADR 0015 §2) — enumerate every documented recovery,
undo, or repair form, declare per operation×form, fixed exclusion vocabulary,
vacuous discharge stated explicitly. The reviewer covenant and breach
handling (ADR 0012), the A2/A3 seal legs with PRD/DESIGN riding the no-touch
range, the ledger written only through `ledger-append.sh`, and the
pre-registered items restated in this campaign's `candidates.md`: khal's
random-`.ics` refusal risk, and the disclosure duty that khal shares the
vdir/iCalendar storage class with todoman (explored by this project) — if
khal is selected, the report must say so.

## 4. What this ADR does not decide

Whether a fourth campaign runs if this one returns null or refuses — that
stays a resourcing decision. The criterion-1 scoring language stays in PRD;
this ADR moves no goalposts.
