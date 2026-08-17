# ADR 0014 — The operation's success status is part of the define

- **Status:** Accepted (the implementing PR merged long before this line caught up — flipped 2026-08-17, noticed by the freeze audit, which cites this ADR as a frozen surface's ground)
- **Relates to:** ADR 0007 (the config file form), ADR 0009 (saved cases), DESIGN §12
  (the define budget sentence this deliberately spends against)
- **Scope:** `--expect-status` / `expected_status`, case schema v1 → v2, the report's
  always-present `expected_status` field

## Context

The recording run had to exit 0 (`recording_run_failed`), and so did the un-killed
baseline world (`baseline_run_failed`). The checks are right — crash points are read
off the recording, and a target that fails partway through would be explored against
a sequence it never performs. But "completed" and "exited 0" are different claims: a
tool that reports "nothing to do" as exit 1, or anything with git-style status
conventions, was refused on every invocation with no way to opt out (#3).
`--allow-unverified` does not cover this — it weakens the completeness claim, not the
success convention.

DESIGN §12 says: *"If Define ever needs more than this, that is movement toward the
kill criteria in §18, and we should notice."* This ADR is the noticing. The define
grows its fifth key (`setup`, `operation`, `check`, `marker`, now `expected_status`) —
not a new verb, but the fact of what the operation's own success looks like. A target
whose success convention cannot be spelled is not a simpler define; it is an
unjudgeable target.

## Decision

1. **One declaration, two spellings, one grammar.** `--expect-status <n>` and the
   toml's `expected_status = "<n>"` accept exactly the digits 0..255, validated by a
   single shared routine — the two spellings cannot drift into accepting different
   values. Anything else refuses as a setup error by name.
2. **One value governs every un-killed run of the operation.** The recording run and
   the baseline world are the same command over the same state, so they answer to the
   same declared status (issue #3 raised this as "one flag governing two checks with
   different meanings"; the resolution is that the two checks share one meaning —
   *un-killed runs of the operation must exit N*). A status mismatch always names
   both the expected and the actual status — "matches the run" and "was declared"
   are different facts and a refusal must keep them apart. A signal death is
   reported as a signal death: it has no exit status to name, and naming one would
   invent a fact.
3. **Killed worlds are untouched.** A crash world must die by the kill signal itself;
   a signal death is not an exit status and never substitutes for one. `_exit(137)`
   under `--expect-status 137` explores normally, and the 128+9 == 137 conflation is
   pinned against in acceptance.
4. **The saved case freezes the declaration — case schema v2.** A case is a contract
   that must replay identically years later without consulting anything outside the
   file, so v2 writes `expected_status` even at the default. Readers accept v1 and
   v2; a v1 file has no field and means "exit 0 was the contract", which is what
   every v1 case was recorded under. Replay continues to reject the define-surface
   flags, `--expect-status` included: the case is the define.
5. **Preflight accepts the declaration and its graduation hint carries it.** A hint
   without the status would hand `explore` a define that refuses the very recording
   preflight just accepted — the known defect class where the hint carries a
   different define than the one that ran.
6. **The report states it, always.** `expected_status` is an always-present field:
   a PASS over a non-zero convention must be machine-distinguishable from a PASS
   that required 0, without diffing invocations.

## Alternatives considered

- **Per-check statuses** (one for the recording, one for the baseline). Rejected:
  the two runs are the same command over the same state; two knobs would let them
  drift apart and turn the baseline check into a tunable instead of a witness.
- **Accept any exit status once declared-nonzero** (a boolean "non-zero is fine").
  Rejected as fail-open: "exits 3 by convention" and "exited 5 today" are different
  events, and the second is exactly the partial-failure the check exists to catch.
- **A status *set* or range.** Rejected for v1 of the key: no concrete target needs
  it yet, and a range is strictly wider than the measured need — the key can widen
  later without breaking v2 cases, while narrowing never works.
- **Keep refusing and document the limitation.** The status quo #3 was filed
  against; rejected by the issue's own measurement — the class is common (git-style
  conventions) and the refusal is not a soundness necessity, only a missing fact.

## Consequences

- Targets with non-zero success conventions become explorable; their PASS reports
  carry the convention they were judged under.
- Case files gain a version. v1 cases keep replaying unchanged; new cases refuse on
  binaries older than this change (they know versions 1 only — the forward refusal
  is by the existing strict schema gate).
- The define budget sentence in DESIGN §12 is spent once more, on a fact rather
  than a verb, and says so.
