# The report, as a schema

Every `--json` run writes exactly one JSON document. This page documents that
document field by field — for the coding agents DESIGN §3 names as the report's
audience, and for anyone wiring the exit codes into CI.

**Stability**: the document says so itself — `"schema_status": "experimental"`.
Until v1.0 any release may change this schema without apology; at v1.0 it
freezes (PRD, versioning philosophy). What is stable *now* is the meaning of
the fields below, the verdict/exit-code pairing, and the promise that a field
never silently changes meaning — it would change name instead.

This page is held to the code by an acceptance check: every field that appears
in a generated report must be named here, and every field named here must
appear in a generated report. A field added to one side without the other goes
red in CI.

## The envelope

One JSON object, written atomically (temp file + rename — a crash of sideeye
itself never leaves a half-written report). Absence is unambiguous: the file
is removed at startup, so a report at the path always describes *this* run.

| Field | Type | Always | Meaning |
|---|---|---|---|
| `schema` | string | yes | The literal `"sideeye/report"`. Reject anything else before reading further. |
| `schema_status` | string | yes | `"experimental"` until the v1.0 freeze. |
| `contract_version` | int | yes | The trace contract the binary speaks (v7 today). Crash-point numbering does not carry across contract versions; a saved case from another version replays as `case_no_longer_applies`, never as a verdict. |
| `verdict` | string | yes | `"PASS"`, `"FAIL"`, `"UNKNOWN"`, or `"SETUP_ERROR"`. The one field everything else hangs off. |
| `exit_code` | int | yes | Mirrors the verdict: 0 PASS / 1 FAIL / 2 UNKNOWN / 3 SETUP_ERROR. The process exits with the same value. |

## Counters

Read from the run's own state, so an UNKNOWN raised at world 4 of 6 still
reports what was actually explored — a caller aggregating coverage never
records zero for a run that ended early.

| Field | Type | Always | Meaning |
|---|---|---|---|
| `crash_points` | int | yes | State-changing operations counted in the recording — one deterministic kill point in front of each. On a replay this equals the case's operation total when the recording still matches. |
| `explored` | int | yes | Worlds actually run, **including the baseline** (no-kill) world. A full exploration reports `crash_points + 1`; a replay reports 2 (the case's point plus the baseline). One exception: an operation that performs nothing state-changing PASSes with both counters 0 — do not assert `explored == crash_points + 1` unconditionally. |
| `violations` | int | yes | Crash worlds whose invariant did not hold. `0` on PASS; `>= 1` on FAIL. |

## The counterexample (`FAIL` only)

| Field | Type | Meaning |
|---|---|---|
| `earliest` | object | The earliest failing crash point — the minimal counterexample the verdict rests on. |
| `earliest.crash_point` | int | The logical address: the kill landed immediately before operation *k*. Deterministic; the same recording yields the same number. |
| `earliest.after` | object | `{op, path}` — the last state-changing operation that **completed** in this world (`"(start)"` when the kill precedes the first). |
| `earliest.before` | object | `{op, path}` — the operation the kill landed in front of, which **never ran** (`"(end)"` when past the last). The failure window is the gap between `after` and `before`. |
| `earliest.invariant` | string | Which layer judged it: `"built-in atomicity (L0)"`, `"the post-success invariant (L1)"`, `"the checker (L2)"` — or the combined forms `"built-in atomicity, and the checker"` and `"the post-success invariant, and the checker"` when two layers failed the same world. |
| `earliest.subject` | string | What the violation is about — a file name for L0, `"(named by the checker, not by path)"` for L2. |
| `earliest.observed` | string | What was actually seen in the crashed state, in one sentence. |

What the loop-closure experiments' judges actually read, for calibration: the
gate predicate was `verdict`, `explored`, `crash_points`, and the absence of
`unknown_reason`; the fix-side agents read `earliest.before` / `earliest.after`
paths to find the window. Both runs' agents fixed the bug from this object plus
the case file — nothing else in the report was load-bearing for them.

## Refusals (`UNKNOWN` / `SETUP_ERROR` only)

| Field | Type | Present | Meaning |
|---|---|---|---|
| `unknown_reason` | string | UNKNOWN | Machine-readable reason, one of the closed set below. |
| `message` | string | UNKNOWN and SETUP_ERROR | Human-readable detail: what was observed, and often which operation it happened at. |

`unknown_reason` values (closed set, contract v7): `no_shim_marker`,
`state_changed_without_ops`, `contract_version_mismatch`,
`unsupported_syscall_observed`, `oracle_missed_operation`,
`oracle_saw_phantom`, `oracle_saw_nothing`, `child_process_detected`,
`child_touched_state_dir`, `multiple_threads_detected`, `unresolvable_path`,
`kill_did_not_land`, `completeness_not_verified`, `trace_truncated`,
`checker_not_falsified`, `marker_never_observed`, `case_no_longer_applies`,
`recording_run_failed`, `baseline_run_failed`, `baseline_violates_invariant`,
`boundary_without_oracle`, `state_not_quiescent`.

A new refusal joins this list in the change that introduces it, and the
acceptance check above holds this page to that.

## The account (always present)

Free-form strings whose *presence* is stable and whose prose may improve
between releases. They exist so a PASS states what it did not look at — the
report refuses to be reassuring without an account.

| Field | Type | Meaning |
|---|---|---|
| `l0` | string | What the built-in atomicity form judged (file counts, forms applied). |
| `l1` | string | The success-marker layer's account (`"no marker configured"` when unused). |
| `case` | string | Path of the saved counterexample this run wrote or replayed; `"(none)"` when no case exists. |
| `replay` | string | The exact replay command for the saved case; `"-"` when there is none. |
| `oracle` | string | The completeness account: how many operations the two witnesses agreed on, or that no oracle ran. |
| `checker` | string | The declared invariant's account (`"none configured"` when unused). |
| `processes` | string | The process-boundary account: what else was observed and whether it touched the state. |
| `not_tested` | array of strings | Fault classes this run does not claim to have tested (power loss, torn writes, concurrent processes, …). Read it before trusting a PASS. |

## Reading it from the MCP surface

`sideeye_explore_config` and `sideeye_replay_case` return this same document as
the tool result's `structuredContent`, minified. `isError` is derived from
`verdict`: a real verdict (PASS/FAIL) is `isError: false`; every refusal
(UNKNOWN, SETUP_ERROR) is `isError: true` — retry after fixing what the
`message` names, don't parse the error text (ADR 0010).
