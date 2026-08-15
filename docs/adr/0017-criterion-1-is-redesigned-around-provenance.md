# ADR 0017 — Criterion 1 is redesigned around provenance, not blindness

- **Status:** Proposed (flips to Accepted when the implementing PR merges)
- **Supersedes:** the blind-only reading of v1.0 entry criterion 1 (PRD). ADR 0012's
  two-seal protocol, the campaign records, and the assisted/blind labeling rules are
  all unchanged — this decides what the v1.0 gate MEASURES, not how either funnel runs.
- **Scope:** PRD (v1.0 entry criterion 1 and its status trail); no code.

## The decision

v1.0 entry criterion 1 required the qualifying bug to be found on omamori, the
calibration target, or a blind-protocol target. It now requires:

> A real, novel, author-confirmed crash-consistency bug, **discovered by Sideeye's
> deterministic judge from a declared invariant — with the question's provenance
> recorded and labeled (blind, or assisted with the scout named)** — fixed, and kept
> as a replayed regression case.

What is unchanged, deliberately: **novel** (a tracker search with a positive control,
recorded), **author-confirmed**, **fixed**, **replayed regression case**, and the rule
that an assisted finding is never presented as blind. What changed is one thing: the
gate no longer requires the question itself to have been posed blind.

## Why this is a redesign and not a moved goalpost

The distinction was pre-committed in #118, before any of the evidence below existed:
loosening a bar because results are thin is goalpost-moving; replacing a bar because
an experiment falsified the hypothesis the bar was testing is a redesign. The order
of events is the argument:

1. **The blind path was run to exhaustion first.** Campaign 1 (topydo) found 12/13
   counterexamples under machine-verified seals — and the find was not novel
   (upstream already knew). Campaigns 2 and 3 (abook, khal) returned null under the
   same seals. The remaining candidate (hledger) is unselectable while its sweep
   refusal stands. Each campaign cost roughly 1.5 hours of sealed declaration work
   plus review; the pool the seals inherited is spent.
2. **The assisted experiment was run under its own pre-registered rules** (#118:
   measured windows, mandatory proposal metadata, assisted-never-blind, and — written
   into the issue by the owner before the first run — "assisted success NEVER
   satisfies criterion 1; the only path is an explicit §18-class redesign").
3. **The experiment's scoring recorded an inversion** (#120): the metadata gate was
   built against an agent posing vacuous questions, and that failure mode never
   appeared — question quality scored 5/5. The binding constraint was the judge's
   reach: three enumerated engine gaps.
4. **The gaps were closed and the re-measurement ran** (#121, #122, contract v9,
   `spike/assisted/REMEASURE.md`): four of the five committed defines reach
   replay-confirmed counterexamples; the fifth is blocked by the one gap deferred as
   too heavy (#123).

The hypothesis criterion 1 was actually testing — "the value proof requires the
question to be posed unassisted" — is the only thing this evidence falsified. The
judge's half ("Sideeye finds real counterexamples in ordinary software from declared
invariants") is now measured three independent ways: blind (topydo), calibration
(timewarrior), assisted (four targets, verified). The product's own thesis line,
written at #118 filing time, already drew this boundary: *"AI may propose the
question. Sideeye answers whether it survives hostile execution."* The gate now
measures the product that sentence describes.

## What this does not do

- It does not close criterion 1. The novel/confirmed/fixed/replayed legs are all
  still open for the assisted findings — novelty is deliberately unchecked for all
  four, and the next step is exactly those tracker searches (with positive controls,
  recorded), then upstream contact, then a fix and a replayed case.
- It does not retire the blind protocol. The seals, the campaign records and ADR 0012
  stand; blind remains the stronger provenance a finding can carry, and nothing
  assisted may borrow it.
- It does not touch criteria 2–6.

## The cost, stated

A future reader can still say "you widened the gate after nulls." The defence is not
rhetoric but order: the experiment preceded the criterion change, the change was
pre-committed as the only legitimate path, the un-widened legs are the ones that
carry the honesty (novel, confirmed, replayed), and the widening's own precedent —
the 2026-08-13 sentence-widening to include blind targets, done explicitly BEFORE any
campaign ran so it could not be goalpost-moving — is the same discipline applied in
the same repository.
