# Campaign 3 findings — khal 0.14.0: no counterexample

The third blind campaign (ADR 0012 via ADR 0015/0016) ran to completion and
found nothing: every crash world of every declared operation satisfied the
declared invariants. This file is the campaign's result — a null one —
recorded with the same precision a counterexample would have received.

## What ran

Exploration from Seal B `9028b04b`, through the phase driver, inside the
pinned container, engine `sideeye 0.7.0 (trace contract v8)`. The full
verifier over (Seal A `2239fba`, Seal B `9028b04b`, this run's manifest, the
sealed sweep reports) returns **ALL SEAL CHECKS PASSED (R1 audited)** — the
committed transcript is `verify-seals.txt` beside this file; that line is
its last line, not a prose claim. The declaration precedes the exploration
in the pushed history, the exploration ran from the seal in a clean tree,
and the engine and shim that explored are byte-equal to the ones that swept
(SHA-256, R3).

## The numbers

| Op | Crash points | Worlds explored | Violations | Verdict | expected_status |
|----|--------------|-----------------|------------|---------|-----------------|
| import (fresh UID into the vdir) | 10 | 11 (10 crash + baseline) | 0 | PASS | 0 |
| import-update (same UID, --batch) | 21 | 22 (21 crash + baseline) | 0 | PASS | 0 |
| new (the sweep row's shape) | 10 | 11 (10 crash + baseline) | 0 | PASS | 0 |

Oracle agreement on every operation (9338/9041/13713 syscall lines examined;
81/170/81 touching the state directory — the update path touches the state
directory roughly twice as often as the fresh import, consistent with the
normal-run observation of its temp-file traffic, and nothing beyond that
consistency is claimed). Raw artifacts: `run-manifest.json` and `reports/`
beside this file; the uncommitted originals sit under
`../artifacts/explore-9028b04b/`.

**Both pre-registered refusal expectations did NOT fire.** The declaration
pre-registered refusals for import-update (random-suffixed leftover files on
a normal update) and new (random UID-as-filename, DTSTAMP=now); the
recordings were nevertheless ACCEPTED and explored fully — 21 and 10 crash
points respectively. The pre-registrations were risk notes, deliberately not
predictions ("if that shape defeats the baseline…"); the risk did not
materialize, and this file does not speculate about why — the mechanism was
not measured, only the acceptance.

**The checker's red side ran post-seal, as designed.** The engine's
falsification gate fired in all three runs (`checker: falsified before the
run (corrupted state -> check failed)`), and the induced failure was the
checker's I-C leg, visible at the top of each `.out`. The pre-seal red
suite (19 cases) plus this post-seal falsification closes the loop the
khard burn opened, for the second campaign in a row.

## What this does and does not mean

- **Means**: on this surface — the three declared argv forms, single
  process, the engine's crash model — khal's writes never left a state that
  violated byte-conservation of the bystander event file, the anchored
  liveness of the bystander through khal's own search, query byte-neutrality
  over the existing vdir (I-W), or subject-query totality. 43 crash worlds
  and 3 baselines, zero violations.
- **Does not mean**: khal is crash-safe. The engine lists what it did not
  test (power loss, torn writes, concurrent processes); the TUI, `edit`,
  `configure`, the ask-first and stdin import forms are excluded by the
  inventory and undriven; the update path's leftover temp files and the
  subject file's post-crash shape are deliberately not invariants; and a
  null result under declared invariants bounds only those invariants, not
  the tool.
- **Disclosure** (pre-registered duty, discharged in the declaration and
  repeated here): khal shares the vdir/iCalendar storage class with
  todoman, which this project has explored. Class knowledge is declared,
  not denied; no khal-specific internals were consulted.

## Campaign accounting

- khal: explored, null result. Consumed (ADR 0015: every selected target is
  consumed regardless of outcome).
- Remaining unconsumed in the sealed order: **hledger** — refused at both
  sweeps (exit 2, reason sealed and unread to this day). Under the sealed
  predicate it is not selectable while it refuses; a fourth campaign would
  first need the refusal understood, which means opening the sealed reason
  — a step this campaign deliberately did not take.
- PRD criterion 1 **remains open**: two blind campaigns (abook, khal) have
  now returned null on their designated path. What that pattern means for
  v1.0 — more campaigns, a different target class, or the kill analysis —
  is a decision recorded in PRD as open, not made here.
