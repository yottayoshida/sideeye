# 0136 — A case carries the apparatus its replay checks

Status: Accepted (2026-10-15)

Closes #875. Amends ADR 0041 ("The saved case does not carry it"), ADR 0100 ("The mode is written
into the case, and only when it is not the default") and the sentence of ADR 0043 that cited
ADR 0041's choice.

## Context

#786 moved the `env:` entries of a define's `apparatus` ahead of the setup, in `explore` and
`preflight`: a setup started without a declared variable writes wherever the tool falls back to,
which on a developer's machine is the real data. `replay` was left out, because the case does not
carry the declaration and `replay` refuses `--apparatus` (it takes its define from the case). A
case saved from such a define and replayed in a shell without the variable ran its setup and its
recorded operation against the fallback, and the refusal ADR 0041 leaned on — the baseline not
repeating the recorded bytes — came only after both had run.

The replay path already runs the explore pipeline on a define rebuilt from the case: the
before-setup and after-setup apparatus checks are the same calls. What it lacked was the entries.

## Decision

**A case saved from a define whose `apparatus` holds an entry a replay checks — `env:`,
`preload:` or `pythonpath:` — is `case_version` 7 and carries the declaration as written,
`note:` entries included, in `define.apparatus`.** `replay` puts it back where the flag or the
toml would have, so the checks run where `explore` runs them: `env:` before the setup, the other
kinds after it. A define declaring nothing, or only notes, keeps the case it always got.

**Version 7 spells every key the ladder's upper rungs introduced**, for version 5's reason — a
version holding independent optional fields cannot be held honest by a one-field gate: `cwd`
(null when none was declared), `scratch` (an array, empty allowed), `apparatus` (non-empty, with
at least one checked entry), and `observe`, **`wrappers` included**. That last one reverses ADR
0100's "only when it is not the default" for this version alone: at version 6 the mode was the
only reason to climb, so writing the default would have moved every case; at version 7 the
apparatus is the reason, and a mode left implicit would be one more key whose absence the gate
cannot tell from an omission. A version-6 file whose mode is `wrappers` is still malformed.

The read gate refuses as malformed: a version-7 file without `observe`, with an unknown mode,
without `apparatus`, with an empty one, with notes alone, or with an entry the define grammar
refuses; and an earlier version carrying an `apparatus` array (a JSON `null` reads as no declaration, as it does for `expected_status` in version 1).

## Consequences

- An earlier binary refuses a version-7 case as a file it cannot parse — an honest refusal, the
  cost ADR 0100 accepted for version 6, falling only on cases whose define declared a checked
  entry.
- A case saved before this change carries no declaration and still replays unchecked; nothing in
  it says whether there was one, so it cannot be refused on that ground.
- A version-7 case counted under the default records `wrappers`, so `replay --observe syscalls`
  on it is refused as on any case that records its mode; the same define's case before this
  change, at version 2 to 5, accepted the flag.
- Over MCP, `sideeye_replay_case` runs the same checks, so a variable the server does not pass
  through `SIDEEYE_MCP_CHILD_ENV` refuses the replay, as it refuses `sideeye_explore_config`.

## Alternatives considered

- **Carry the `env:` entries only** (the issue's "at least"). Refused: `preload:` and
  `pythonpath:` are part of the define, and `explore` checks them; a case without them asks a
  different question.
- **Let `replay` take `--apparatus`.** Refused: the define comes from the case, and the caller
  would have to remember what the case was saved with.
- **Refuse cases saved before this change.** Refused: they cannot say whether a declaration
  existed.
- **Move every apparatus-declaring define to version 7, notes included.** Refused: a notes-only
  declaration has nothing for a replay to check, and the version would only lock out earlier
  binaries.
