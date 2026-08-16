# Scouting — driving Sideeye with an agent

Sideeye's define surface — a state directory, an operation, an invariant —
assumes someone already knows where a tool keeps its state and what its
documentation promises about it. That someone does not have to be you. This
page is the working method for handing that reading to an agent: the agent
(the *scout*) reads the repository and proposes the question; Sideeye answers
whether it survives hostile execution. **Nothing the scout believes enters a
verdict** — PASS, FAIL and UNKNOWN are deterministic and never consult the
scout.

The method below is not aspirational: it is the promoted form of the
experiment protocol this repository ran against real targets
(`spike/assisted/`; a related follow-up in `spike/followup-95/`), with the
lessons those runs paid for folded in. The measured results live there, not
here — numbers on a guide page go stale; the records don't.

## What the scout reads for

Five things, in one pass over source, docs, tests and tracker (all of it is
allowed — this is assisted use, not the sealed blind protocol):

1. **Where the persistent state lives** — a directory the tool reads *and*
   writes. Not caches, not scratch; note which is which.
2. **Which commands write that state** — and especially which touch **more
   than one file in one operation**. Cross-file transactions are the richest
   crash windows.
3. **What the documentation promises** about that state: conservation
   ("nothing else is modified"), consistency between files, "always valid
   X" claims. A promise is checker material.
4. **Whether an fsck / doctor / verify / undo / repair command exists** —
   both a ready-made checker and a crash-recovery contract worth testing.
5. **Whether writes look deterministic.** Random IDs or timestamps in
   filenames or bytes defeat the byte-reproducible baseline — expect a
   recording refusal and say so up front rather than discovering it.

## Propose before defining

Write at most three candidate (state / operation / invariant) sets, and give
each one its metadata **before** any toml exists:

- **why** — what could plausibly go wrong at a crash inside this operation;
- **what property** — the user-visible or documented property the checker
  will represent. "The file parses" is not a property anyone relies on;
- **where from** — the doc sentence, test or code path the claim came from.

The metadata is not ceremony. Sideeye's falsification gate proves a checker
*can* reject something; only the metadata lets a human judge whether the
question was worth asking. A proposal without all three does not count.

## Write the define

Pick the strongest proposal and write the explicit `sideeye.toml`: state
root, setup, operation, check, and `expected_status` when the documented
outcome is a refusal. Two spellings for the commands:

- the string form, split on spaces — for invocations that fit it;
- the argv form — `operation = ["tool", "-m", "a message with spaces"]` —
  for the argument a space-split string cannot spell (ADR 0019). One line,
  every element one double-quoted string, passed to the executor verbatim.

Write the checker to **fail closed**: a missing store is a failure, an
anchored exact match beats a substring, and every failure message names
which leg refused. Anchor the checker in the property from the proposal
metadata, never in "the target's output looks plausible".

## Falsify, then explore

Run the exploration; Sideeye falsifies the checker against deliberately
corrupted state before trusting it, and refuses rather than judging with an
instrument that was never shown to respond. Treat every UNKNOWN as a define
bug until proven otherwise: fix the define, record the fix, retry — and
never weaken the checker to make an UNKNOWN go away; narrow the claim
instead. A named refusal that survives an honest fix attempt is itself the
result: the define budget could not spell this target, and the refusal says
why.

One routing note: `sideeye preflight` reads the define-surface flags, which
carry the string form only — a define spelled as argv goes straight to
`sideeye explore --config`, which answers strictly more. Once a toml exists
that is the better door in either spelling.

And treat a null result — every world holds — as a result. Record it with
the proposal metadata; do not go shopping for a different question until
the recorded one has its answer.

## Lessons that each cost a measurement

- The operation child inherits the **engine's** environment, not your setup
  script's exports. A tool that resolves its store through an environment
  variable needs that variable exported where the engine launches — a
  zero-operation PASS ("the operation performed nothing that can change the
  judged state") is the tell.
- Prefer invocations with explicit path flags over environment plumbing.
- Probe determinism with a two-second gap between two clean runs:
  epoch-stamping targets are byte-identical within a second and flaky
  across one — the worst refusal shape to discover late.
- Capture the engine's exit code before piping its output anywhere; a
  pipe's exit code is not the engine's.
- Create the state root and the report's directory before exploring; the
  engine stops at state resolution otherwise.

## What a scout must never do

- **Call any of this "blind".** The word belongs to the sealed campaign
  protocol (ADR 0012); assisted runs read the target, and no run that read
  the target may wear the label.
- **Put itself in the verdict.** No "the model believes this is a bug",
  anywhere. A belief becomes a checker or it stays out of the record.
- **File findings upstream by default.** Whether a finding is reported is
  decided at target selection, not at discovery — the selection rule and
  its history live in `spike/assisted/PROTOCOL.md`.

## After a FAIL

The saved case is the handoff: a coding agent given the report, the case it
names and the checkout has produced the fix and passed the judge's own
replay — twice, measured. That loop and what it needs are the README's
agent section; the report's machine fields are `docs/report-schema.md`.
