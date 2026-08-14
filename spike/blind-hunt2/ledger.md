# Campaign 2 ledger — every consultation, deviation, and breach, as it happens

Seal A artifact (ADR 0012 via ADR 0015). Append-only; entries are dated and never
rewritten. The sealed-at-A sections of `candidates.md` record what was known before
this campaign's seal — including, per ADR 0015, everything inherited from campaign 1's
ledger; this file records everything after it.

What belongs here is what campaign 1's ledger held: source consultations under the
operational-facts carve-out, invocation edits with their permitted source, wrapper
edits after Seal B (they mark the checker sighted), reviewer-covenant breaches,
experimenter deviations (burned targets), and sweep re-runs with both manifests kept.

Two campaign-2 additions. First (ADR 0015 §2): the declaration phase must also
record the documentation consulted for the **recovery-path rule** — the full
enumeration of recovery/undo/repair command forms the docs name (with citations),
or the explicit finding that they name none. Second (ADR 0015 §3): the sweep
entry must record the **image identity** (`docker image inspect` ID of
`sideeye-blindhunt`) alongside the ambient environment — self-reported, said so.

## Entries

(none yet — the campaign has not passed Seal A)
