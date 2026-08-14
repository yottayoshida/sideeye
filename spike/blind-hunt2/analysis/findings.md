# Campaign 2 findings — abook 0.6.1: no counterexample

The second blind campaign (ADR 0012 via ADR 0015) ran to completion and found
nothing: every crash world of every declared operation satisfied the declared
invariants. This file is the campaign's result — a null one — recorded with
the same precision a counterexample would have received.

## What ran

Exploration from Seal B `eb51c483` (the exec-bit re-seal; the first Seal B
`84d0f2e1` refused at setup spawn with zero target contact — ledger
2026-08-14), through the phase driver, inside the pinned container, engine
`sideeye 0.7.0 (trace contract v8)`. The full verifier over
(Seal A `8878df82`, Seal B `eb51c483`, this run's manifest, the sealed sweep
reports) returns **ALL SEAL CHECKS PASSED (R1 audited)**: the declaration
precedes the exploration in the pushed history, the exploration ran from the
seal in a clean tree, and the engine and shim that explored are byte-equal
to the ones that swept (SHA-256, R3).

## The numbers

| Op | Crash points | Worlds explored | Violations | Verdict | expected_status |
|----|--------------|-----------------|------------|---------|-----------------|
| import (vcard→abook, fresh outfile) | 2 | 3 (2 crash + baseline) | 0 | PASS | 0 |
| export (abook→vcard beside the store) | 2 | 3 (2 crash + baseline) | 0 | PASS | 0 |
| import-refused (onto an existing outfile) | 1 | 2 (1 crash + baseline) | 0 | PASS | 1 |

Raw artifacts: `run-manifest.json` and `reports/` beside this file (copies of
the run's outputs; the uncommitted originals sit under
`../artifacts/explore-eb51c483/`). The oracle agreed on every operation
(95/96/87 syscall lines examined; 10/18/3 touching the state directory).
The full-verifier invocation is committed beside this file as
`verify-seals.txt` — "ALL SEAL CHECKS PASSED (R1 audited)" is that
transcript's last line, not a prose claim; its R2 leg re-hashed the sealed
sweep reports, which stay local by design (only their hashes travel).

**The checker's red side ran post-seal, as designed.** The declaration
deferred "the checker against real crash states" to the engine's
falsification gate; that gate fired in all three runs — `checker: falsified
before the run (corrupted state -> check failed)` — and the corrupted-state
failure it induced was the checker's I-C leg, visible at the top of each
`.out`. The pre-seal red suite (17 cases) plus this post-seal falsification
closes the loop the khard burn opened: the red side needed no mis-shaped
store shown to the target before the seal, and the seal's own machinery
proved the checker live afterwards.

## What this does and does not mean

- **Means**: on this surface — the three non-interactive `--convert` forms,
  single process, the engine's crash model — abook's writes never left a
  state that violated byte-conservation of unnamed stores, the anchored
  bystander query, or query totality on the partial outfile. The refusal
  path, explored under `expected_status = "1"`, never damaged the store it
  refused to replace. The few crash points are the surface being small: the
  operations touch the state directory in 10 (import), 18 (export, which
  both reads and writes inside the store) and 3 (refused) syscall lines of
  the ~90–96 examined per run.
- **Does not mean**: abook is crash-safe. The engine itself lists what it
  did not test (power loss, torn writes, concurrent processes); the TUI and
  the stdin-fed `--add-email` pair were excluded by the inventory and are
  undriven; and a null result under declared invariants bounds only those
  invariants, not the tool.

## Campaign accounting

- khard: burned before Seal B (blind breach in its red suite; ledger and
  PR #110). A burn is not consumption — ADR 0015 keeps the two distinct —
  but both remove the name from the next campaign's order.
- abook: explored, null result. Consumed (ADR 0015: every selected target is
  consumed regardless of outcome).
- Remaining unconsumed in the sealed order: **khal**; hledger refused at
  sweep (exit 2, reason sealed and unread to this day).
- PRD criterion 1 **remains open**: this campaign was its designated path
  and returned null. A further campaign over the remaining order is a
  resourcing decision (PRD, criterion 1 status).
