# 0057 — A SETUP_ERROR says why as data, in five classes, and carries the setup's status

Status: Accepted (2026-09-09)

## Context

A refusal that could judge nothing is `UNKNOWN`, and it carries `unknown_reason` — a closed set
whose members are one-to-one with the branches that raise them — beside a `message` for the
reader and a `next_step` chosen where the cause is known (ADR 0040). A refusal because the
engine could not get what it needed is `SETUP_ERROR`, and until this decision it carried
`message` alone. #483 made a failing `--setup` say what it observed — `--setup exited 7` — and
#518 followed: the 7 exists only inside an English sentence. `spike/acceptance.sh` asserted
the contract by grepping the sentence, so a reworded sentence was a red check; the MCP adapter
forwards the sentence inside a region it marks as target-influenced, so an agent driving
`sideeye_explore_config` had to regex text this project is free to reword, or do nothing.

`setupError` is raised at 193 sites in `src/main.zig`. Some pass a variable detail. Three
of those hold a discriminant that tells the refusals apart — `spawnFailure` on a
`posix.SpawnError`, `snapshotRefusal` on the `engine.SnapshotError` its caller switches on,
`restoreFailure` on an `engine.RestoreError` — and a few more collect several refusals
under one constant class (the capped snapshot's out-of-memory, `readTraceCapped`, the
parsers that take their message as a parameter), which is right for them because every
refusal they collect is of one class.

## Decision

**Every `SETUP_ERROR` report carries `setup_error_reason`, one of five classes a caller can
branch on, and one raised because `--setup` ran and ended badly carries the status it observed
as integers.** The text report is unchanged.

- `contract.SetupErrorReason` has five members, and unlike `unknown_reason` they are classes,
  not branches. The rule that assigns a site is written on the enum: `define_invalid` when the
  refusal could have been produced by reading the define alone (flags, toml, case file,
  declared values, a mode that refuses a flag); `setup_failed` when `--setup` was handed to
  `exec` and exited non-zero, was killed by a signal, or ended in a status `waitpid` did not
  decode — an image that could not be executed arrives here as the child's `_exit(127)`
  after the failed exec (measured: a setup path that does not exist reports 127), and a
  child the fork stub could not arrange before exec as its 126, since `posix.SpawnError`
  has no exec member; `environment` when the engine asked the machine for something — memory,
  a resolved path, a capture file, a process, a privilege, the state tree before exploration —
  and was refused; `platform_unsupported` when what the define asks for does not exist on this
  platform or kernel; `internal` when the engine contradicted itself.
- `setupError(reason, detail)` and `setupErrorFmt(arena, reason, fmt, args)` take the reason
  as a required first argument, so a site that names none does not compile — ADR 0040's
  discipline for `next`. At a funnel that holds a discriminant, the reason is chosen by an
  exhaustive `switch` on it, even where every arm lands on one member, so a member added to
  the discriminant has to be given a reason. The snapshot chooses in the same `switch` over
  `engine.SnapshotError` that chooses its reason and step — so an unsorted entry list, which
  that switch already calls a defect in Sideeye, is `internal` and not `environment`.
- `setup_exit_code` (the exit status) and `setup_signal` (the signal number) are integer
  fields present only on `setup_failed`, one or the other, and neither when `waitpid`
  reported a status the engine does not decode; `message` keeps quoting the number. Two flat
  integers rather than one object: the schema check flattens an object's keys into rows, and
  `expected_status` is the flat precedent.
- `buildJson` takes the reason as `?contract.SetupErrorReason`, not a string beside the two
  strings it already takes, and writes it through `name()`.
- The MCP adapter's summary line puts the reason in the slot `unknown_reason` uses —
  `SETUP_ERROR (setup_failed):` — outside the target-influenced region; the acceptance leg
  that derives the expected prefix from the report learns the third field.
- The three fields are additive under `docs/contract-freeze.md` surface 2. The set is closed
  by name from the release that carries it: adding a member afterwards is the same break the
  page records for `unknown_reason`. The freeze audit has no extraction for it yet; the next
  sweep adds one and pins it in the same commit, and `docs/freeze-audit.md` says so.

## Alternatives considered

- **The status integers alone.** Answers the sentence #518 quotes and nothing else; every
  other `SETUP_ERROR` stays English, and the adapter's caller keeps its regex. Declined by the
  owner (2026-09-09) in favour of the set.
- **Members one-to-one with sites, the way `unknown_reason` is.** 193 names nobody could
  branch on, frozen by name.
- **`next_step` on `SETUP_ERROR`.** #483 ruled it UNKNOWN-only and #518 does not reopen it.
- **Printing the reason on the text line** (`SETUP ERROR  setup_failed`). The text is the
  reader's view and its sentence already says what happened; the acceptance suite reads the
  rest of that line as the detail.
- **One object field, `setup_status: {exited: 7}`.** Two rows in the schema check either way,
  and the flat form is the existing one.
- **A `contract_version` bump.** The version follows the recorded account (ADR 0055), and no
  field addition has moved it.

## Consequences

- A caller branches on `setup_error_reason`; `spike/acceptance.sh` asserts `setup_exit_code`
  and `setup_signal` from the JSON instead of grepping the sentence, and a leg over every
  report the suite leaves under `/tmp/acc*` holds `verdict == "SETUP_ERROR"` to a member
  of the set (checks that remove their directory at the end are not seen by it).
- `spike/check-report-schema.py` holds the doc's paragraph to the enum in both directions,
  as it does for `unknown_reason`; the schema check's fixtures gain a setup killed by a
  signal, so the reverse direction sees `setup_signal`.
- The classes are coarse on purpose, and the rule decides the boundary: a path that does not
  resolve is `environment` (the OS was asked), a path too long as written is `define_invalid`.
  A site the rule cannot place is a reason to doubt the rule before adding a member.
