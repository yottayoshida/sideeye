# 0058 — The audit says whether the record it read is the record that was made

Status: Accepted (2026-09-09)

## Context

`spike/loop-closure-timew/judge.sh` opens with "Five subcommands, one discipline: nothing the
agent can edit is trusted", and then says the sentence is narrower than it reads: it covers
what the judge *decides*, not the judge's *inputs*. `run-agent.sh` writes the transcript and
the control verdicts into `spike/runs/` on the host; the agent runs as the same user with
`Bash`, `Write` and `Edit`; the audit's only input is therefore writable by the subject it
audits (#515). The path channel voids a transcript that names this repository, but it
matches the repository path as a literal string, so a relative walk out of the stage reaches
those files without naming it.

Two designs were taken apart before this one, both by measurement.

**Writing the record to a file whose name has been removed.** `exec 3<>tmp; rm tmp;
claude … >&3 3>&-` leaves no name for a subject to open. Measured on macOS: the walk finds
nothing — and the subject wiped the record anyway, because its stdout *is* the record and
`ftruncate(1, 0)` succeeded. Closing fd 3 for the child closes fd 3, not fd 1.

**Putting the record behind a pipe, with a recorder process holding the only handle.**
Measured: `ftruncate(1, 0)` then fails with `EINVAL`, fd 3 is not usable in the subject, and
the bytes read back are the bytes that were written. But the record's handle now lives in
the launcher and the recorder, both the same user as the agent; on Linux
`/proc/<recorder pid>/fd/3` reaches the same inode. A promise of unreachability would be
false on the platform the CI container runs.

## Decision

**The audit reports whether the record it read is the record that was made, and the
manifest refuses to be assembled without that report.**

- `judge.sh audit` takes `--record-sha <hex>`, the digest of the transcript as it was
  recorded. `audit.json` always carries `record_sha`: `"verified"`, `"mismatch"`, or
  `"not supplied"` — a reader must be able to tell "nobody checked" from "checked and
  matched" — and `record_sha_value`, the digest the audit computed. The word alone would be
  weaker than the gates beside it: `expectation_met` is bound to its run by an mtime floor
  and to the seal by a pin, while a bare `"verified"` is a string anyone can write. The
  value travels into `manifest.json` with the rest of the audit, so what was verified is
  re-checkable rather than taken on faith. **Having `finalize` re-hash the named transcript
  itself is the stronger form and is not done here**: it needs the record's path in the
  audit and a digest whose provenance is not the caller's, which is the other half. A mismatch is a void, through a channel of its own
  (`record_sha_mismatch`), decided **before** the no-tool-calls exit: a transcript whose
  calls were deleted is a changed record, not an unauditable one.
- **A line the reader cannot parse is a void** (`record_lines_unparsed`). The digest is over
  the bytes; it says nothing about a line corrupted inside the stream before those bytes
  were written, and the audit's `except json.JSONDecodeError: continue` made that the
  quietest way to delete evidence — the tool call disappears and the verdict reads clean.
  `spike/onboarding-clock`'s audit has refused on unreadable input since it shipped.
- `judge.sh finalize` requires `audit.record_sha == "verified"`. **A positive mark, not the
  absence of a bad one**: an `audit.json` written by a later, digest-less invocation
  overwrites the launcher's, and a file saying "nothing suspicious" is exactly what a
  process left running can produce. Absence of a warning is not evidence.
- `--record-sha` is optional at `audit`. Requiring it would fail the sixteen selftest
  invocations that pass no digest; `finalize` is where the requirement
  binds, and `finalize` is the only path to `loop_closed`.

## Alternatives considered

- **Unreachability instead of detection.** Both measured designs above. The first is false
  (the subject's own stdout is the record); the second is false on Linux (`/proc`). A
  promise this project cannot keep is worse than a narrower one it can.
- **A digest file beside the record** (`record-seal.json`). Same user, same directory: the
  process that edits the record edits the digest. The digest travels as an argument
  instead, and never exists on disk during the run.
- **Marks whose *presence* voids** (`tamper.json`, `leftovers.json`). A subject that can
  leave a process behind can delete the mark that accuses it. The requirement is on the
  positive mark instead.
- **Requiring `--record-sha` at `audit`.** Sixteen selftest invocations record nothing.

## Consequences

- `judge.sh selftest` grows to eighteen refusals and six greens (24 cases). Three of the
  new ones are `record-sha` (bytes disagree with the digest), `record-torn` (a line that
  cannot be read, **with the digest correct** — the shape a digest cannot catch) and
  `finalize-unverified` (a manifest whose audit verified no digest), with
  `finalize-verified` as its control. Each has its own mutation in `seal-reds/MUTATIONS.md`
  and each killed exactly its own case; none is killed by `always-clean`, because the record
  channels exit ahead of the assembled verdict the way `unauditable` does and the finalize
  cases never reach the audit. **The finalize gate was nearly shipped unmeasured**: this
  file's header listed it among the preconditions a selftest cannot drive, which was wrong —
  its refusal is a `sys.exit` in a python child, the same shape every audit refusal has. A
  reviewer found that, and the header now says so. `spike/acceptance.sh` and the CI job carry
  the new counts.
- `finalize`'s new requirement binds **every** run, not only the ones recorded before this
  change: the launchers do not compute the digest while recording — that is the other half —
  so an operator who audits without `--record-sha` gets `incomplete record:
  audit.record_sha=not supplied`. Both launchers now print the digest in the `next:` line
  they hand the operator, computed from the file after the run; that value is only as good
  as the file was, which is the honest state of this half and the reason the other one
  exists. A run recorded before this change has no digest at all, and inventing one now
  would be the claim this decision exists to refuse.
- **This closes half of #515, and the issue stays open.** What remains: the record still
  lives where the agent can write, and the digest is supplied by the caller, so a caller
  under the agent's influence hands over a digest of whatever it likes. The launcher-side
  work — the recorder behind a pipe, digests of the pre-run records held in the launcher's
  memory, the leftover-process observation, and the launcher calling the audit itself — is
  the other half. Named here rather than left implicit, so this ADR cannot be read as
  "#515 is done".
- Also not covered, and named for the same reason: `judge.sh` itself, `spike/replay_gate.py`,
  `check-history.sh` and the container inputs are as writable as the record was. They belong
  to the launcher-side digest set when it exists.
- One shape neither channel catches, named rather than left for a reader to find: a line
  that parses but carries nothing (a `0` where an object was). It is not unreadable, so the
  line count does not fire; if it was changed after recording the digest fires, but the
  class `record-torn` exists for — corrupted before the bytes were written — passes through.
  `spike/onboarding-clock/clock-audit.py` already counts a parsed-but-not-a-dict line as
  rejected, and it also publishes the line total beside the rejected count so the two can be
  checked against the event count — both are deeper than what is here. Closing this means
  asserting a shape for every line and carrying a total nothing yet reads, which is a
  channel of its own with its own case, mutation and counts; it is named here rather than
  bolted onto a channel whose attribution is already measured.
