# Prediction — 2026-09-22 shipped-v160, written before any explore ran

Its sha256 and the time it was taken are in `transcripts/prediction.sha256`, recorded before
the first `run.sh`; this file is committed unchanged, so the two can be compared.

## What each verdict will be written as

- **PASS** — the target reached a verdict through the adoption path and the page's command.
  Recorded with `oracle_verified` or `oracle_verified_subject_only` from the JSON, the
  crash-point count, and whether `command_cwd` and `l0_judged_paths` are in the report. A PASS
  has no evidence bundle; "evidence not reached" is written for it, not "evidence missing".
- **FAIL** — definitive only when `sideeye replay` reproduces it twice. Recorded with the
  earliest crash point, what the checker said, the replay transcripts, and `sideeye evidence`'s
  Markdown (rc 0). Then the upstream question: re-measured on the target's latest release
  first, then novelty, then report-worthiness — decided per target and asked of the owner.
- **UNKNOWN** — the point where the release stopped carrying the target. Recorded with the
  reason, the `next_step` sentence as printed, and — if that sentence names
  `--observe syscalls` — the one explore that follows it. A second follow is not taken.

## How "the gate cleared it and explore refused it" is read

The gate is the installed engine's `preflight --twice --oracle`, and preflight runs the same
recording phases explore does. So the reading follows the **phase** of the refusal, not the
detector's name:

- a refusal in a phase preflight ran — the recording run's shim account, the oracle
  comparison, the boundary account, quiescence — is **the same engine answering twice
  differently**, and counts against ADR 0085's sunset;
- a refusal in a phase preflight itself prints as `not checked` — kill landing, world-side
  process boundaries, baseline behaviour, checker falsification — is **where explore went
  further than the gate could**, and does not;
- `checker_not_falsified` is the checker's author's (mine), and is counted in the adoption
  record, not against the gate.

todo.txt-cli is expected to refuse under the default mode: the gate saw
`oracle_missed_operation` with a next step naming `--observe syscalls`. That refusal is the
gate's own answer repeated, so it is not the sunset case either way — it is the product's
next-step loop, and the follow is the measurement.

## Expectations, stated so they can be wrong

- todo.txt-cli: default mode UNKNOWN `oracle_missed_operation` (confident — the gate showed it);
  under `--observe syscalls`, a verdict (not confident — the operation forks helpers).
- commitizen: a verdict under the default mode (not confident — it runs git as children).
- ast-grep: a verdict under the default mode; FAIL if it writes a.js with a truncating open,
  which is the shape this project has seen in formatters in six languages (not confident).
