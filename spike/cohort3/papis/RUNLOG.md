# papis (cohort 3, target 5) — run log and ruling

## Timeline (all 2026-08-22)

1. The scout landed on main first (`e43d96e`): papis's documented
   `PAPIS_NP` switch takes the probe's 3 threads / 14 clones / 14 pids
   to **0 / 0 / one pid**, with rc and document-landing asserted
   beside every count.
2. The define merged (`22cec73`) after one review round that reversed
   part of its own reasoning — the `papis doctor` rejection had been
   measured without doctor's selection flag, so in every
   two-document library it fell to the interactive picker and
   examined nothing, including the state built for the check the
   rejection cited. Re-measured fairly, doctor is disqualified three
   times over (below). Mini-seal verified: define first-parent on
   main before any artifact.
3. **Two explores, identical verdicts.** Run 1 is the committed
   artifact set; run 2 matched it on every compared field — verdict,
   exit code, `oracle_verified`, crash points, worlds, violations,
   and the l0 / oracle / metadata / checker lines verbatim.

## The verdict

**PASS — 2 of 2 worlds, crash points 1 + 1 baseline,
`oracle_verified: true`, single process.** The declaration named this
outcome, this headline and this world count before the engine ran, and
the report matched line for line:

- the expected headline, not the vacuous one (`PASS 2/2 explored
  worlds satisfied the built-in atomicity invariant`, **not** "the
  operation performed nothing that can change the judged state" —
  which would have meant the shim never saw the rename);
- `metadata: 1 … write(s) observed and excluded from judgement …
  fchmodat x1` — the mode seam, disclosed and unjudged, exactly as
  declared;
- `checker: falsified before the run (corrupted state -> check
  failed)` — the gate fired through leg E ("the existing document's
  attachment changed"), visible in the transcript;
- `processes: single process` — the `PAPIS_NP=0` forecast held under
  the engine, not only in the scout.

**Why it passes, in one sentence**: `papis add` builds the whole
document in a temp directory outside the library and moves it in with
a single `renameat`, so the only crash world the engine can produce is
the library before the move — the pre-state, healthy by construction.
An operation with one atomic mutation has no interior to crash inside.

## What this establishes, and what it does not

Establishes: the single crash world this operation can produce is the
pre-state, and the pre-state is healthy — i.e. `papis add` has no
crash-visible interior in the library. This is the cohort's contrast
case: four targets that rewrite files in place and lose data
(black, rustfmt, poetry, and poetry's revision), and one that stages
outside and moves in, measured under the same engine, the same
discipline and the same seal.

Does not establish: that the all-or-nothing assertion was exercised
against damage. In the reachable crash world the new document is
absent, so leg D's block is skipped and the document assertion runs
only on the un-killed baseline, which the engine requires green
anyway. Also unjudged: a crash during the staging phase leaves an
abandoned temp directory **outside** the library (a leak, not a
corruption); and the `fchmodat` seam, which restore cannot reproduce
(restore assigns 0755/0644 — papis's own post-chmod modes — so a mode
leg would be vacuous here and a false-candidate generator under a
stricter umask; the cohort-2 `checkisexec` shorthand, corrected).

## Target observations (not findings, not claimed)

Measured while building the define, recorded because they are true and
because someone reading this record should not have to re-measure
them. None is a crash-consistency finding; any upstream conversation
about them is a separate, owner-gated step.

- **`papis list` writes.** A document whose `info.yaml` lost its
  `papis_id` gets one generated and **persisted into the file** by a
  bare `papis list` — attributed by three trial states (no command:
  no id; list alone: an id; a second byte-identical torn state: a
  *different* id, so the value is random rather than derived).
- **The reader is silent about incomplete documents and credulous
  about missing files**: a directory without `info.yaml` is ignored
  entirely (an orphaned attachment is invisible to the tool), while a
  document whose attachment is gone is listed happily.
- **`papis doctor` is not a repair for these shapes**: red on an
  untouched healthy library (six type errors over two documents, rc 0
  while saying so); its one applicable auto-fix removes the lost file
  from the document ("[FIX] Removing file from document", leaving
  `files: []`) rather than restoring it; and on a torn `info.yaml` it
  dies with an uncaught `AttributeError`.
- **Indexing is recursive**: a document nested inside another
  document's directory becomes a third document, invisible to any
  top-level enumeration. This is what leg R exists to see, and the
  drill that proves it.

## Bounds

Assisted provenance, as the whole cohort. Not tested: power loss, torn
writes, concurrent processes (the report's own line). The single-rename
shape depends on staging directory and library sharing a filesystem;
`TMPDIR` is not pinned and both are under `/tmp` here. The scout's
strace filter was narrower than the oracle's, and the oracle — which
runs the wider filter — agreed on the one operation, which is what
closes that gap in practice.
