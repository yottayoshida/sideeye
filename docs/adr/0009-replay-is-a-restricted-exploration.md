# ADR 0009 — Replay is a restricted exploration, and a case gates on its landing context

- **Status:** Accepted (2026-08-12)
- **Supersedes:** nothing. Implements DESIGN §13's case storage and `sideeye replay`;
  moves the promise "case no longer applies — never a different point, silently"
  from prose into a detector (`case_no_longer_applies`)
- **Scope:** the case file written on FAIL, the `replay` subcommand, the landing
  context and its comparison

## Context

A counterexample's value is that it can be re-run after a fix and watched to stop
reproducing (DESIGN §17). Two shortcuts looked tempting and were the review's two
sharpest findings against the plan's first draft. A *dedicated light replay path* —
setup, kill at k, judge — would skip the oracle comparison, the structural
detectors, checker falsification, landing evidence and quiescence, and every one of
those gates exists because its absence once blamed a target for the tool's own
blindness. And a *local landing check* — comparing only the operations adjacent to
k — reads identically when one same-class operation is inserted earlier: every
index after it shifts by one, and the replay would confidently verify the wrong
window.

## Decision

1. **A FAIL saves its counterexample** to `<work>/cases/NNNNNN.json` (id claimed
   with `O_EXCL`): schema and versions (case schema, sideeye, trace contract), the
   *resolved define* (state, setup, operation, check, marker — the counterexample's
   identity includes what was run), the crash point `k`, and the landing context —
   the total operation count, an FNV-1a hash over the class sequence of operations
   1..k, and the classes and paths adjacent to k. The report prints the case path
   and the ready-to-paste `sideeye replay` line, in text and JSON.
2. **`sideeye replay <case.json>` is `explore` with the kill set restricted** to
   {the case's k, the baseline}. Same code path, every gate intact: a replay that
   cannot falsify the stored checker refuses `checker_not_falsified` exactly as an
   explore would. Machine-local knobs (`--shim`, `--oracle`, `--work`, `--json`,
   `--allow-unverified`) come from flags; the define comes from the case, and the
   define-surface flags are refused.
3. **Applicability gates on classes, warns on paths.** The recording's operation
   count, the class-prefix hash up to k, and the adjacent classes must all match,
   or the answer is UNKNOWN `case_no_longer_applies` — checked before the
   zero-crash-points early PASS, so a case whose operations all disappeared cannot
   be answered with a green. Paths are deliberately only a warning: pid-embedded
   temp names (`undo.data.<pid>-3.tmp` — the timewarrior shape) differ between runs
   while naming the same logical operation, and a fix that reorders same-class
   operations (timewarrior's again) keeps the class structure while moving the
   paths — exactly the replay-after-fix this feature exists for.
4. **A replay does not mint cases.** It re-verifies one; a reproduced FAIL says so
   in the replay line instead of writing a copy.
5. **A case from another trace contract refuses** (`case_no_longer_applies`): the
   crash-point numbering does not carry over between contracts (v4 and v5 changed
   what `SIDEEYE_KILL_AT` counts), and the prefix hash cannot vouch for a counting
   rule it was not computed under.

## Alternatives considered

- **A dedicated light replay path** — rejected: skipping the trust gates turns
  "the fix worked" and "the tool went blind" into the same green.
- **Local (adjacent-only) context matching** — rejected: prefix insertion aliases
  the index; the class-prefix hash is what refuses it.
- **Gating on paths as well as classes** — rejected: nondeterministic path
  components would permanently strand replay on the very targets (pid-named temps)
  where it matters most.
- **An id registry (`replay 000042`)** — rejected: the case file's path is already
  an unambiguous name; a registry is state that can drift from the files.

## Consequences

- The §17 loop closes mechanically: report JSON carries the case path, the case
  carries the define, and an agent holding only those can re-run the counterexample.
- A fix that removes the operation window (shortening the sequence) answers
  "case no longer applies" rather than PASS — the honest reading: the address the
  bug lived at no longer exists.
- The `explored N worlds (crash points M + 1 baseline)` line reads with M as the
  *available* addresses during a replay that visits two worlds; the counts stay
  truthful individually.
