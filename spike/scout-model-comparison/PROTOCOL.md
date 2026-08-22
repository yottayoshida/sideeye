# Scout model sensitivity — protocol (#221)

Filed verbatim as issue #221 on 2026-08-22, before the arms ran; reproduced here as the frozen design. Results are in `RESULTS.md` beside this file.

## Why

#118's thesis is *bring your own scout — Sideeye remains the judge*: nothing the scout believes enters a verdict, so a weaker scout cannot corrupt PASS/FAIL/UNKNOWN. What a weaker scout *can* degrade is the quality of the question — whether the proposal names the real state root, the cross-file transaction, a property someone relies on, and the determinism risk before it bites. The scout artifacts in `spike/assisted/` were produced by a single scout (the interactive session agent; the artifacts do not record the model). Whether the method in `docs/scouting.md` degrades gracefully with scout capability has never been measured.

## Design: four fresh agents, paper-only, over the assisted five

- **Arms**: four fresh (context-free) subagents — Fable 5 (control), Opus 5, Sonnet 5, Haiku 4.5 — each given the identical single-pass task.
- **Targets**: the five from `spike/assisted/` — buku 4.7, calcurse 4.7.1, devtodo 0.1.20, pass 1.7.4, stow 2.3.1 — as local checkouts pinned to those versions.
- **Task**: steps 2–3 of the scouting loop only (scout the five things; at most 3 proposals per target, each with why / what-property / where-from, plus a determinism expectation). Paper-only: no define, no execution of the target, no explore, no measured contact, nothing upstream. Not blind — this is assisted-replication and wears the assisted label.
- **Why a Fable control arm**: the committed 2026-08-14 scout read `--help` of the pinned build, ran behavior probes, and (for buku and pass) used DeepWiki; the arms read source/docs/tests only, with no execution and no network. Conditions therefore differ from the committed baseline, so the primary comparison is arm-vs-arm under identical conditions; the committed record (`proposals.md` + RUNLOG outcomes) serves as the scoring key, not as an arm.

## Contamination controls (probed 2026-08-22)

A no-tool probe agent confirmed the workspace memory index is injected into fresh subagents. Consequences, applied:

- Cohort 2/3 targets (borg, mercurial, jj, keepassxc, bun, cargo, …) are excluded: the index names their walls and outcomes.
- Of the assisted five, the index leaks *existence of an upstream filing* for calcurse and stow (issue numbers only — no state / operation / invariant details); buku, devtodo and pass showed no mention in the probe. calcurse/stow results will carry this caveat.
- Arms are forbidden network access, tracker reads, and any read of this repository (the trackers now contain the filed findings; this repository contains the answers). Each arm must disclose any prior knowledge of these tools it notices in its own context.

## Scoring

Each arm's proposals are scored against what the measured record established, on five axes: (1) state root correct; (2) the cross-file transaction operation found; (3) the property is a contract someone relies on, not "the file parses"; (4) determinism risk called up front where the record shows one bites; (5) where-from verifiable in the named checkout. No numbers in this issue until measured; results and run artifacts land under `spike/`.

## What this is not

- Not blind — ADR 0012's word stays with the sealed protocol.
- Not a criterion-1 vehicle: no new targets, no measured contact, no filings.
- Not a verdict-soundness question: by construction the judge never consults the scout; this measures question quality only.

Refs: #118, `docs/scouting.md`, `spike/assisted/`.
