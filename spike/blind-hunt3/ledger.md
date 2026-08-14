# Campaign 3 ledger — every consultation, deviation, and breach, as it happens

Seal A artifact (ADR 0012 via ADR 0015 and ADR 0016). Append-only; entries are
dated and never rewritten — written only through `spike/ledger-append.sh`. The
sealed-at-A sections of `candidates.md` record what was known before this
campaign's seal, including everything inherited from the prior campaigns'
ledgers; this file records everything after it.

What belongs here is what the prior ledgers held: source consultations under
the operational-facts carve-out, invocation edits with their permitted source,
wrapper edits after Seal B (they mark the checker sighted), reviewer-covenant
breaches, experimenter deviations (burned targets), and sweep re-runs with
both manifests kept. The campaign-2 additions carry: the declaration phase
records the documentation consulted for the recovery-path rule (ADR 0015 §2),
and voids land in `voided-seals.txt` with their narrative here.

## Entries

- **2026-08-14 — campaign 3 apparatus created (pre-seal).** Tooling copied
  from campaign 2's sealed copies with paths adapted (`blind-hunt2`→
  `blind-hunt3`, `/tmp/blind2`→`/tmp/blind3`), then swept for leftovers by
  grep (zero hits) — the campaign-2 void class (a config naming another
  campaign's state root) is what that scan exists to keep out, and
  `check-config-paths.sh` remains the mechanical gate. Candidates inherited
  per ADR 0016: khal then hledger (khard burned, abook consumed). The khal
  random-`.ics` refusal risk and the todoman storage-class disclosure duty
  carry from the prior seals, restated in `candidates.md`. No target was
  executed during this construction.
- **2026-08-14 — Seal A R1: five findings, all adopted before the seal.**
  The P1 sat in the void-class gate itself: `check-config-paths.sh` resolved
  config references by basename, so a stale reference to another campaign's
  configs would have been checked against THIS campaign's file and passed —
  the contradiction the gate exists to refuse, reachable through the gate.
  Discovery now requires the reference to name this campaign's mounted
  configs dir (`/work/spike/blind-hunt3/configs/`) and the file to exist;
  falsified both ways in scratch before this entry (foreign reference →
  refused, pinned message; missing config → refused; real rows → green).
  Also adopted: eleven tool-comment sites had rewritten campaign-2 history
  as campaign-3 findings during the mechanical adaptation — restored to
  honest attribution ("carried" where inherited); the rehearsal's fabricated
  campaign name is guarded at run time (must not exist in the repo, must not
  equal CAMP) instead of hoped unique; the earlier "zero hits" scan claim in
  this ledger is hereby scoped to the operational apparatus files — the
  ledger narrative itself names campaign 2 legitimately, so a whole-tree
  grep does hit; and the verifier's header summary now states B1 as the code
  checks it (invocations sealed at A; only the manifest first appears at B).
