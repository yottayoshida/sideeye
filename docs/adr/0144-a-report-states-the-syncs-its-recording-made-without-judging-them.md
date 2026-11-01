# 0144 — A report states the syncs its recording made, without judging them

- **Status:** Accepted (2026-11-01)
- **Refs:** #959 (from the 2026-10-18 product review, #962); the owner's ruling on 2026-11-01
  that an observation which is not a verdict may enter the report; DESIGN §4.3 "Counterexamples,
  not warnings" and §15 ("Static analysis" is a non-goal); ADR 0110 (power loss is not the crash
  model yet) and its first reopen condition, measured in
  `spike/dogfood/2026-11-01-power-loss-rules/RESULTS.md` (#958).
- **Scope:** `src/syncs.zig`, `src/report.zig`, `src/main.zig`, `docs/report-schema.md`,
  `docs/faq.md`, `docs/cli.md`, `spike/acceptance.sh`.

## Context

Sideeye's crash is a process crash, so a missing `fsync` cannot fail a run: a tool that writes a
temporary file and renames it over the original without syncing it PASSes, and the report said
nothing about it. Under power loss — outside the model (ADR 0110) — that shape can leave the new
name holding nothing. The recording run's trace already holds what is needed to say so: every
write, `fsync`/`fdatasync` and rename inside the state directory, with paths. Of the 46
supported-class PASS rows re-recorded for #958, 19 rename a file into their state with no sync of
it first.

DESIGN §4.3 says a finding is a counterexample, not a warning, and §15 rules static analysis out.
Read strictly, both keep anything that is not a verdict out of the report. The report already
carries such lines — `metadata` says which ownership writes were excluded, `processes` what
the witnesses saw — so the strict reading was never the practice.

## Decision

- The recording run's trace is read for one thing more, and the report states it as an account
  line, `syncs`, beside `metadata`: the renames into the judged state; each file with a write recorded
  at the path it was renamed from and no `fsync` or `fdatasync` recorded for it between its last
  recorded write and the rename; how many renames were of a file with no write recorded at the path
  it was renamed from; and, only when the define declared a marker, each rename whose directory had no sync
  recorded after it. The JSON report carries the sentence and the two lists.
- **It changes neither the verdict nor the exit code**, and it uses no word of judgement. It says
  what was recorded and ends saying that a process crash keeps unsynced writes and power loss is
  not tested.
- It is present on a PASS and a FAIL from `explore` and `replay`, read from the recording run —
  not on a refusal, which can come before the recording finished, and not in preflight's document.
- The directory half needs a marker: without one nothing in the run says the update was done, and
  6 of the 8 targets that sync their file in ADR 0110's notes would show it.

This is the reading of §4.3 and §15 the report keeps from now on: a verdict is only ever a
counterexample, and an account line may state what the run did that no verdict judges, in the
terms it was recorded in.

## Alternatives considered

- **A warning.** It would read as a finding Sideeye cannot reproduce, which is what §4.3 rules out.
- **The directory half for every define.** On the measured rows it would show on most PASSes and
  say nothing a reader could act on without a marker.
- **A verdict under a second crash model.** That is #960, taken up separately: an opt-in mode that
  builds the worlds, so its findings are counterexamples. This line is not a substitute for it.

## Consequences

- `docs/faq.md`'s "Does it check my fsync?" no longer answers "No": it does not judge it, and the
  report says what it saw.
- What "recorded" leaves out is a known gap the line inherits: an `fcntl(F_FULLFSYNC)` on macOS
  (#948), an `O_SYNC` open, `sync`, `syncfs`, and a raw `syscall(SYS_fsync, …)` under
  `--observe wrappers` are not recorded, so a tool syncing that way is named. Writes that are
  not recorded — through a shared mapping, or a raw `syscall(SYS_write, …)` under `--observe
  wrappers` — leave a rename counted, not named, as do a file written outside the state
  directory and renamed in, and a rename through a symbolic link inside it (the write is
  recorded at the link's target, the rename at the link).
- A field added under the additive allowance of `docs/contract-freeze.md` surface 2; its presence
  (PASS and FAIL only) is part of what 1.x keeps.
