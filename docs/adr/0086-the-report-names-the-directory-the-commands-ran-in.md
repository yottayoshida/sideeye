# 0086 — The report names the directory the define's commands ran in

Status: Accepted (2026-09-21)

## Context

The 2026-09-21 release-path dogfood run took the adoption route `docs/ci-quickstart.md` tells
a project to take and pointed it at `lefthook install`, an operation that only works inside a
git repository. It cost two rounds, both about `cwd` and neither on any page (#647):

1. The quickstart's define template had no `cwd`, so the operation ran in Sideeye's own
   directory, exited 1, and the run refused `recording_run_failed`.
2. `cwd` is resolved before the state directory is made, so a `cwd` the define's own `setup`
   would create is not there when it is checked. `docs/cli.md` named the key and not the order.

The refusal in round 1 said what it had observed — an exit status — and no cause. That is
ADR 0030's rule, and it is right: the engine cannot know that a missing `cwd` produced a
non-zero exit. But one fact it did know and did not say: **the directory the commands ran
in**. The engine resolves it in phase 0 and hands the same string to the oracle. That
observation is the one that names the line to add, and the report carried nothing of it — 25
keys, none a directory.

And `docs/ci-quickstart.md` said of itself that it "cannot quietly rot into fiction" because
CI executes it, while CI executed only defines that live in the engine's own directory and
need no `cwd`. The guarantee did not reach the field an adopting project needs first.

## Decision

**Every report produced after the declared `cwd` has been resolved states the directory the
define's setup, operation and checker ran in — the declared `cwd`, or Sideeye's own when none
was declared.** The JSON always; the text in the verdict and UNKNOWN blocks and in `preflight`'s
report.

Six parts.

1. **Two fields, and a name that is not `cwd`.** `command_cwd` (string, absolute) and
   `command_cwd_declared` (bool). A saved case already has `define.cwd`, which freezes what
   was *declared* and is `null` when nothing was. This is what *ran*. The same name with two
   meanings, both frozen, is not something a later release can take back. The bool is the
   useful half: the failure this answers was a `cwd` that was never written, and a path alone
   cannot say whether it was chosen.

2. **In the text, under `next` on UNKNOWN.** The text label is `cwd` — the key the reader would
   add. In the UNKNOWN block it sits under `next` — below `divergence` when there is one — and
   above the classification block. A reader of `recording_run_failed` is sent by the detail to
   `--expect-status` and by `next` back to the detail; a line further down with `expected`
   would exist and not be read. The verdict blocks carry it beside `apparatus`. SETUP ERROR's
   text does not: it is one line by design, and `recovery` set the precedent — the JSON still
   carries the field. An undeclared value says `(none declared: Sideeye's own)`, and the path is
   defanged (`textShown`), because a declared `cwd` arrives from a config or a case file.

3. **Present from the point the `cwd` is resolved.** Set directly after the pin block in phase
   0, before any later phase-0 refusal. A report raised before that point carries neither field
   — there is no directory to name. That covers the `cwd` vet's own refusal, the flag and config
   checks that come first, and replay's `case_no_longer_applies`, which is raised while the case
   file is still being read. One raised after it (`--work` inside the state, a failing setup)
   carries both; on a SETUP ERROR nothing has run yet, and the field names where it would have.
   Absent too if Sideeye's own `getcwd` fails: a value it does not have is not written.

4. **One computation, read twice.** The oracle used to take its own `getcwd` to resolve the
   subject's relative paths. It reads the same `effective_cwd` now. Two spellings of one fact
   are how a report and an oracle come to name different directories for the same run.

5. **The quickstart's own CI runs a define whose `cwd` holds something up.** The toy the
   quickstart uses never needs one — the engine hands every child `TOY_STATE` — so a `cwd` added
   to its defines would pass with or without the line. `TOY_PROJECT` makes the toy's `rotate`
   refuse outside a directory holding a marker; `sideeye-project.toml` declares that directory;
   the workflow makes it before Sideeye starts, runs the define, and then runs it again with the
   `cwd` line deleted, requiring exit 2 and `recording_run_failed` — the failure #647 recorded.

6. **`preflight` says it too, and its hint carries the `--cwd` it was given.** Added in review:
   preflight accepts `--cwd`, resolves it, and is where a define is first tried — and its report
   named no directory, while its `next` hint, which carries `--setup` and `--expect-status` so that
   it hands explore the define preflight accepted, dropped `--cwd`. Pasted as printed, a tool that
   needs its own directory refused `recording_run_failed` on the define preflight had just
   accepted. Preflight's text gains the `cwd` line, and the hint carries `--cwd`.

## Alternatives considered

**Diagnose the cause in the refusal** ("the operation may need a `cwd`"). Rejected by ADR 0030
and for its reason: the engine does not know. An operation can exit 1 for any reason, and a
refusal that guesses teaches the reader to trust guesses.

**One field, the path.** Rejected: undeclared and declared-to-the-same-place read the same, and
the undeclared case is the one that went wrong.

**`null` when undeclared, as the case file does.** Rejected: the report exists to say where the
commands ran, and `null` hides exactly the value a reader of the failure needs.

**The line beside `expected`, at the bottom of the UNKNOWN block.** The first draft. Rejected in
review: present, and not where anyone reading the refusal is.

**Add `cwd` to the quickstart's existing defines.** Rejected: it would hold nothing up, and the
guarantee would be met in letter and not in fact — the state #647 described.

**Bump `contract_version`.** No: it numbers the trace contract between the shim and the engine
(`docs/report-schema.md`), which this does not touch. The additive allowance (#320) covers two
plain optional fields, as it covered `setup_exit_code` and `setup_signal`.

## Consequences

- `docs/report-schema.md` gains two rows; `docs/contract-freeze.md` records the addition. The
  next `check-freeze-audit.sh` reports both names as drift (exit 3, the audit-is-stale signal —
  unlike `l0` / `l1`, these names match its extraction pattern). Moving the pin is a sweep's
  job, as that page says.
- The quickstart release lane pins v1.5.0, so **the new fields are not visible there until the
  next release** moves the pin. What that lane proves today is item 5 — that a `cwd` in the
  documented shape works and matters. The fields are held by the acceptance suite, which builds
  from source: all four verdict and UNKNOWN blocks, preflight's report and its hint run as
  printed, the position under `next`, and both sides of the presence boundary.
- `spike/toys/toy.c` is embedded in the shipped binary as `sideeye demo`. `TOY_PROJECT` is inert
  unless set, and the demo never sets it.
- **What this does not do**: it does not make the engine name a cause, does not change when `cwd`
  is resolved, and does not change the refusal's wording. An adopter who forgets `cwd` usually
  still gets `recording_run_failed` — or `setup_failed`, or, for a tool that walks up the tree to
  find its project, a run against some other project that nothing refuses. What they get beside
  any of these now is the directory their commands ran in.
