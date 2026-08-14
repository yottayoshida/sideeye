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

What the repository records the experimenter consulting or observing about these
candidates since that seal: the permitted-source consultations in campaign 1's
ledger (`--help`, docs pages, normal-run observation), and the campaign-1 sweep
verdicts (exit codes only — khard/abook/khal accepted, hledger refused with its
**reason still sealed and unread**). The record is self-reported, and ADR 0012's
honesty bounds — an unrecorded consultation is undetectable, and a language
model's training data cannot be un-known — carry unchanged (see "What this
honestly cannot claim"). None of the *recorded* contact is trace, crash, source
or bug-tracker knowledge; the declaration-side blindness of all four candidates
is intact at that recorded strength. The selection-side guarantee ("the order was
fixed before anything ran") is carried by campaign 1's merge date, not re-created
— and this ADR says so instead of claiming a freshness that no longer exists.

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

**Every selected target is consumed by its campaign** — whatever the outcome: a
finding, a null exploration, or a full-refusal exploration. A consumed target
never re-enters a candidate list; its blind shot was taken. Consumption is
distinct from a covenant burn (a burn is a breach event; consumption is the
normal end of a campaign) and both remove the name the same way: campaign N+1's
Seal A inherits the order with all consumed and burned names removed — exactly as
this campaign removes topydo. Without this rule, re-running the inherited
selector over an unchanged order could select the same target twice
(campaign-2 R1 finding).

### 2. The recovery-path rule (the lesson campaign 1 paid for)

Campaign 1's sharpest behavior sat in the documented recovery path, which its
declaration had explicitly scoped out ("recoverability after a crash ... is not
asserted either way"). Campaign 2 closes that hole **as a declaration requirement**:

> The Seal B declaration MUST: **(1) enumerate every recovery, undo, or repair
> command form the selected target's documentation names** — command plus
> argument shape, each with its citation — as a table in the declaration;
> **(2) for each declared operation and each enumerated form** the documentation
> presents as applicable to a damaged or interrupted store, **declare the
> invariant** *after a crash at any point and one invocation of that form (exact
> argv frozen in the checker), the entities the conservation invariant protects
> still satisfy it*; **(3) justify any excluded form** only from the fixed
> vocabulary — `interactive` / `network` / `destructive-by-design` /
> `not-applicable-per-docs`, the last quoting the documentation sentence that
> says so; and **(4) if the documentation names no such command, state that
> explicitly** — the rule then discharges vacuously. "Entities" means whatever
> the declaration's conservation invariant protects (tasks, entries, contacts,
> records); the declaration names them once and both invariants share the
> definition.

The enumeration duty is the load-bearing half: campaign 1's two documented
recovery forms behaved materially differently after a crash
(`spike/blind-hunt/analysis/findings.md`), so a rule that let the declarer pick
one convenient form would test the safe half and call it coverage. Coverage is
enforced by the Seal B review against the enumeration table — the verifier
checks that the declaration exists and names the selected target, not that the
table is complete, and this ADR says so rather than implying a machine check.

All of it is declarable from documentation alone — no traces, no crash
observation — so it costs nothing in blindness. It means the checkers run the
recovery forms inside the crash worlds, and a misfire of campaign 1's class
would be found **by the search, from a blind checker**, not by post-seal
analysis.

### 3. Campaign directory and re-sealed tooling

Campaign 2 lives in `spike/blind-hunt2/`, self-contained: its own `candidates.md`,
`priority.txt`, `seal-a-contents.txt`, `ledger.md`, `configs/`, and its own copies
of the tooling (`sweep.sh`, `select.sh`, `verify-seals.sh`, `wrapper-template.sh`),
path-adapted where paths were baked in. Copies, not references: each campaign seals
its own verdict logic (ADR 0012 decision 7), improvements flow forward into new
seals and never mutate a closed campaign's frozen artifacts. `spike/blind-hunt/`
(campaign 1) stays untouched; editing its declaration would mark those checkers
sighted retroactively.

The sweep re-runs for campaign 2 against a campaign-2 `invocations.tsv` that is
**sealed at Seal A itself** — stronger than ADR 0012's committed-before-the-sweep,
and possible only because the rows have been public since campaign 1 (the
campaign-1 rows for the four candidates, with config paths moved into
`blind-hunt2/` and state roots into `/tmp/blind2/`). The file rides the A2
no-touch set, so it cannot be tuned between the seals at all. Every row was
verified resolvable in the pinned image before sealing (resolution only — no
target executed) — **and the first seal proved that check insufficient**: it
looked at command resolution and file existence but not at the paths *inside*
the config files, two of which still carried campaign 1's state roots. The
resulting sweep mis-verdicted khard (our bug, not its answer), the seal was
voided before any declaration existed, and this re-seal adds the missing
mechanical check: every `/tmp/...` path in every sealed config must sit under
an invocation state root (run green before sealing; the void itself, the
displayed exit codes, and the superseded manifest are in the ledger). A frozen
apparatus can still dead-end on its own internal contradiction — the freeze
only guarantees the dead end is public and the exit is a recorded re-seal, not
a quiet tune. The campaign-2 `select.sh` additionally rejects manifest names
outside the sealed order (the inherited version accepted appended extras
silently).

**The execution environment is identified at the strength actually available.**
Campaign 2 runs in the already-built `sideeye-blindhunt` image (built 2026-08-13
for campaign 1; not rebuilt during this campaign — the ledger records the image
ID at sweep time, self-reported, and the base tag and apt installs beneath it
are mutable, which this sentence admits rather than hides). The engine identity
is recorded where committed artifacts can be compared: the sweep manifest
carries the engine's version string and the SHA-256 of the binary and shim that
swept (`sweep.sh`), and the exploration's run manifest must record the same
fields, so what ran at each phase is readable from the history. This binds the
phases to each other, not to a source tree — a hash does not prove which commit
built the binary, and the campaign claims only what it records.

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
