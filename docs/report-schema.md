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
| `contract_version` | int | yes | The trace contract the binary speaks (v12 today). Crash-point numbering does not carry across contract versions; a saved case from another version replays as `case_no_longer_applies`, never as a verdict. |
| `verdict` | string | yes | `"PASS"`, `"FAIL"`, `"UNKNOWN"`, or `"SETUP_ERROR"`. The one field everything else hangs off. |
| `exit_code` | int | yes | Mirrors the verdict: 0 PASS / 1 FAIL / 2 UNKNOWN / 3 SETUP_ERROR. The process exits with the same value. |
| `oracle_verified` | bool | yes | True only when the completeness oracle's comparison completed and agreed with the shim's account; false in every other case — no oracle named (`--oracle` on Linux, `--oracle-fs-usage` on macOS), `--allow-unverified` with no oracle, or a comparison cut short by a refusal. A fact about the run, never about the verdict: a FAIL stands without an oracle. The "verified PASS only" gate is `verdict == "PASS" && oracle_verified` — the prose `oracle` string below is an account, not a field to branch on. |

## Counters

Read from the run's own state, so an UNKNOWN raised at world 4 of 6 still
reports what was actually explored — a caller aggregating coverage never
records zero for a run that ended early.

| Field | Type | Always | Meaning |
|---|---|---|---|
| `crash_points` | int | yes | State-changing operations counted in the recording — one deterministic kill point in front of each. On a replay this equals the case's operation total when the recording still matches. |
| `explored` | int | yes | Worlds actually run, **including the baseline** (no-kill) world. A full exploration reports `crash_points + 1`; a replay reports 2 (the case's point plus the baseline). One exception: an operation that performs nothing state-changing PASSes with both counters 0 — do not assert `explored == crash_points + 1` unconditionally. |
| `violations` | int | yes | Crash worlds whose invariant did not hold. `0` on PASS; `>= 1` on FAIL. |
| `expected_status` | int | yes | The exit status that counted as the operation completing (`--expect-status` / `expected_status`, default 0). Always present so a PASS over a non-zero convention is machine-distinguishable from one that required 0. Governs the recording run and the un-killed baseline world; killed worlds require the kill signal itself, never an exit status. |

## The counterexample (`FAIL` only)

| Field | Type | Meaning |
|---|---|---|
| `earliest` | object | The earliest failing crash point — the counterexample the verdict rests on. |
| `earliest.crash_point` | int | The logical address: the kill landed immediately before operation *k*. Deterministic; the same recording yields the same number. |
| `earliest.after` | object | `{op, path}` — the last state-changing operation that **completed** in this world (`"(start)"` when the kill precedes the first). |
| `earliest.before` | object | `{op, path}` — the operation the kill landed in front of, which **never ran** (`"(end)"` when past the last). The failure window is the gap between `after` and `before`. |
| `earliest.invariant` | string | Which layer judged it: `"built-in atomicity (L0)"`, `"the post-success invariant (L1)"`, `"the checker (L2)"` — or the combined forms `"built-in atomicity, and the checker"` and `"the post-success invariant, and the checker"` when two layers failed the same world. |
| `earliest.subject` | string | What the violation is about — a file name for L0, `"(named by the checker, not by path)"` for L2. |
| `earliest.observed` | string | What was actually seen in the crashed state, in one sentence. |

The claim exhibit (#231, ADR 0020) — present on `FAIL` exactly when some
violating world's violation includes the declared checker, decided by the
judgment-time bits, never by parsing the invariant string. Absent on every
checkerless define, structurally. Often the same world as `earliest`; the two
diverge when a precision-limit world (an in-place writer caught mid-write,
which the checker heals) stands physically earlier than the world where the
declared invariant itself broke:

| Field | Type | Meaning |
|---|---|---|
| `checker_earliest` | object | The earliest crash world whose violation includes the declared checker — the claim exhibit. |
| `checker_earliest.crash_point` | int | As `earliest.crash_point`, for this world. |
| `checker_earliest.after` | object | `{op, path}` — as `earliest.after`, for this world. |
| `checker_earliest.before` | object | `{op, path}` — as `earliest.before`, for this world. |
| `checker_earliest.invariant` | string | One of the checker-bearing forms only: `"the checker (L2)"`, `"built-in atomicity, and the checker"`, `"the post-success invariant, and the checker"`. |
| `checker_earliest.subject` | string | As `earliest.subject`, for this world. |
| `checker_earliest.observed` | string | As `earliest.observed`, for this world. |
| `checker_earliest.case` | string | Path of this exhibit's saved case. The same path as `case` when the two exhibits are one world; its own file when they differ, written strictly after the earliest's — so within a run the earliest's case always takes the lower id, and in a fresh work directory that is `000001` (ids are claimed `O_EXCL`, so a reused work directory continues its numbering); `"(not saved)"` when no case could be written — including when the earliest's own case failed to write, so the ordering holds even under write failure. |
| `checker_earliest.replay` | string | The replay command for `checker_earliest.case`, mirroring `replay`'s conventions (`"-"` when there is no saved case; the replay-mode sentence when this run *is* a replay of it). |

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

`unknown_reason` values (closed set, contract v12): `no_shim_marker`,
`state_changed_without_ops`, `contract_version_mismatch`,
`unsupported_syscall_observed`, `oracle_missed_operation`,
`oracle_saw_phantom`, `oracle_saw_nothing`, `child_process_detected`,
`child_touched_state_dir`, `multiple_threads_detected`, `unresolvable_path`,
`kill_did_not_land`, `child_wait_failed`, `child_timed_out`, `sequence_numbering_broken`,
`completeness_not_verified`,
`trace_truncated`, `trace_too_large`, `state_file_too_large`,
`state_tree_too_large`,
`state_unsnapshotable`, `state_rewrite_failed`, `checker_not_falsified`, `marker_never_observed`,
`case_no_longer_applies`, `recording_run_failed`, `baseline_run_failed`,
`parent_exited`,
`baseline_violates_invariant`, `boundary_without_oracle`,
`state_not_quiescent`, `unsupported_state_entry`.

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
| `case` | string | Path of the saved counterexample this run wrote or replayed; `"(none)"` when no case exists; `"(not saved)"` when a FAIL's case could not be written. |
| `replay` | string | The exact replay command for the saved case; `"-"` when there is none. |
| `oracle` | string | The completeness account: how many operations the two witnesses agreed on, or that no oracle ran. |
| `metadata_writes` | string | Ownership/permission/timestamp writes on the state directory (#121, #190): observed by the oracle and excluded from judgement — the chown/chmod and utime families change none of the judged state (names, bytes, link targets). Without an oracle the note says they are not observable at all (the shim does not interpose them); absence of a note is never absence of writes. |
| `checker` | string | The declared invariant's account (`"none configured"` when unused). |
| `processes` | string | The process-boundary account: what each witness observed, and whether anything else touched the state. The shim sees only libc's own entry points (`fork`, `vfork`, `posix_spawn`, the `exec` family, `pthread_create`, `setsid`, `setpgid`), so a child created through a raw syscall is not observable to it at all; where nothing that could have seen a boundary looked, the note says the question was not established rather than answering it. `fs_usage` drops whole processes by name (ADR 0031), so its silence is not an observation of absence either, and where the two witnesses disagree the note reports both rather than preferring one. Absence of a boundary from the note is never absence of a boundary. |
| `not_tested` | array of strings | Fault classes this run does not claim to have tested (power loss, torn writes, concurrent processes, …). Read it before trusting a PASS. |

## Reading it from the MCP surface

`sideeye_explore_config` and `sideeye_replay_case` return this same document as
the tool result's `structuredContent`, minified. `isError` is derived from
`verdict`: a real verdict (PASS/FAIL) is `isError: false`; every refusal
(UNKNOWN, SETUP_ERROR) is `isError: true` — retry after fixing what the
`message` names, don't parse the error text (ADR 0010).
