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
| `contract_version` | int | yes | The trace contract the binary speaks (v16 today). Crash-point numbering does not carry across contract versions; a saved case from another version replays as `case_no_longer_applies`, never as a verdict. |
| `verdict` | string | yes | `"PASS"`, `"FAIL"`, `"UNKNOWN"`, or `"SETUP_ERROR"`. The one field everything else hangs off. |
| `exit_code` | int | yes | Mirrors the verdict: 0 PASS / 1 FAIL / 2 UNKNOWN / 3 SETUP_ERROR. The process exits with the same value. |
| `oracle_verified` | bool | yes | True only when the completeness oracle's comparison completed and agreed with the shim's account; false in every other case — no oracle named (`--oracle` on Linux, `--oracle-fs-usage` on macOS), `--allow-unverified` with no oracle, or a comparison cut short by a refusal. A fact about the run, never about the verdict: a FAIL stands without an oracle. The "verified PASS only" gate is `verdict == "PASS" && oracle_verified` — the prose `oracle` string below is an account, not a field to branch on. |
| `oracle_verified_subject_only` | bool | only when true | Present, and `true`, only when a run's writing children were admitted as crash points (contract v15, ADR 0053): the completeness comparison is the subject's account against the oracle's view of the subject, so a crash point performed by a child is one the oracle placed and ordered but did not compare operation by operation. What the oracle contributes for those is that the process existed, that the shim recorded it, and that nothing else wrote while it ran. `oracle_verified` stays **false** whenever this is true, because a machine field changes name before it changes meaning (`docs/contract-freeze.md`, surface 2), so the `verdict == "PASS" && oracle_verified` gate keeps reading this class as unverified. The shape that makes it visible is a shell whose own process writes nothing — the report then says "agreed on 0 operations" beside a PASS, and every crash point in it is a child's. The net for a write neither observer places is the per-path reconciliation (`state_changed_unaccounted`, #405), not this field. A field added after the v1.0 tag under the additive allowance surface 2 keeps open (#320). |


## What `--observe syscalls` does not see

Under `--observe syscalls` the oracle watches the run whose trace is judged, as it does in
every other mode. **What follows is that the mode stops deciding which claim a run earns:**
a completed and agreeing comparison here is read by the same rules as anywhere else, so it
earns `oracle_verified` on a run whose crash points are all the subject's, and
`oracle_verified_subject_only` on one whose writing children were admitted (the row above).
Before 2026-09-08 the mode itself capped the claim, whatever the run contained.

The capture is read with one mode-specific rule: a trapped call reaches strace twice — the
kernel refuses it, the handler re-issues it — and the refused entry is retracted when its
`--- SIGSYS ... si_code=SYS_SECCOMP ---` line is read. The `oracle` account says so on
every run in this mode **that reaches the comparison**; a run with no `--oracle`, or one
refused before the two accounts are compared, has no such account to carry it.

What the mode does not account for is listed here rather than in a field, because it is
what a reader consults to decide how much that account is worth. Since #542 the trap set is every operation Sideeye counts as a crash point — open, write, rename, unlink, fsync, truncate, mkdir, rmdir, link, symlink, in each spelling the architecture has — so the list below is what remains after that widening, not what was always outside it. (1) A raw `copy_file_range`: six arguments leave the filter no free register for the marker below, so the syscall is not trapped at all and is seen in this mode only when the call passes through the libc entry point; a raw one is seen by the oracle alone, which refuses. **`pwritev2` has the same six arguments and is handled differently: it is refused rather than counted** — neither counting it in the wrapper nor silencing the wrapper is right on both kernels, because glibc falls back to a trapped number when the kernel lacks `pwritev2` and does not when the kernel has it. The wrapper records `unsupported` instead and the run refuses with `unsupported_syscall_observed`, on either kernel and without needing an oracle to notice. Under the default mode `pwritev2` is counted as it always was. (2) A process executing in a different syscall ABI (32-bit compat): the filter cannot read the call number in an ABI it does not know and allows it through uncounted; the oracle sees those operations and the comparison refuses. (3) A target that itself issues one of the trapped syscalls with the handler's 64-bit re-issue marker already in its sixth argument register: that operation would be allowed uncounted. The marker exists because a filter cannot be replaced after an `exec`, so the handler cannot be recognised by its address; the odds of a collision are 2^-64 per call. (4) A target that takes `SIGSYS` away **without going through libc** — a raw `rt_sigaction` or `rt_sigprocmask`, or a `SECCOMP_RET_TRAP` filter of its own. Through libc it is covered: the shim interposes `sigaction`, `signal`, `sigprocmask` and `pthread_sigmask`, accepting a request that names `SIGSYS`, answering it successfully, and not applying the part that would replace the handler or block the signal — which is what lets a Go target be observed at all, since Go installs its own handler and touches the mask through libc. What is left is the raw path — and, through libc, the entry points those four do not cover: `sigset`, `bsd_signal` and `sysv_signal` also set a disposition, and `sigsuspend`, `pselect`, `ppoll`, `epoll_pwait` and `sigtimedwait` each block signals for the length of one call. A statically linked Go binary is the case to expect on the raw side; the libc side is listed because it is a gap and not because a target has been seen using it. None of this refuses: a trap on a thread with `SIGSYS` blocked ends the process, and the engine reads that as a run that did not complete (`recording_run_failed`). (5) A trapped call whose path or `struct open_how` pointer is invalid. The handler reads the path to place the operation before the kernel has looked at the pointer, so a target that passes a bad one expecting `EFAULT` faults inside the handler instead, and the run ends as `recording_run_failed`. The libc wrappers have always read the same pointers — what is new is that a caller who never reaches a wrapper now meets it too.

**The retraction is not gated on the mode**, and that is deliberate rather than an
oversight. The reader applies it to any capture it is given, so a target that installs a
`SECCOMP_RET_TRAP` filter of its own would have its refused calls retracted under
`--observe wrappers` too. The reading is the correct one — a refused call did not run,
whoever refused it — and the alternative is worse: counting a call the kernel rejected
would place a crash point where no state changed. What it does mean is that such a target
can reach a verdict in the default mode where it previously refused
`oracle_missed_operation`, so it is stated here rather than left to be discovered. It stays
outside what this tool claims to model either way (item 4 above).

Until 2026-09-08 (ADR 0054) this mode reported `oracle_verified_across_runs` instead: its
oracle watched a separate untrapped run, so its two witnesses were of two executions of the
same operation. That field is gone — the run that produced it no longer exists — and
reports written by a build between its addition and its withdrawal are the only place it
appears. **Both movements are inside contract v15**, which is why this paragraph is dated
rather than versioned: the contract number did not move, because neither the trace nor the
shim/engine protocol changed.

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
| `paths_attributed_to_rename` | integer | How many differences were attributed wholesale to a directory a recorded `rename` moved in from outside the judged tree, rather than named individually (#405, ADR 0032). That source subtree was never snapshotted, so what arrived with the move cannot be told from what an unrecorded writer added afterwards — this is the width of that gap. **Zero is the common case and says the run has none**, which is why it is a number in every report rather than a sentence that appears only sometimes: the absence of a phrase is not a reading a caller can rely on. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |
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
| `setup_error_reason` | string | SETUP_ERROR | Machine-readable class of the refusal, one of the second closed set below (#518, ADR 0057): which of the define, the setup command, the machine, this platform, or Sideeye itself could not be got past. Classes, not one-to-one with the sites that raise them — the thing a caller branches on. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open; the set itself is closed by name from the release that carries it. |
| `setup_exit_code` | integer | SETUP_ERROR, `setup_failed`, the setup exited | The status `--setup` exited with — the number `message` quotes as `--setup exited N` — as data. An image that could not be executed is the child's 127 (the exec failed), and a child the engine could not arrange before exec is 126, with the message saying so. Absent when the setup was killed by a signal or ended in a status the engine does not decode. Added after the v1.0 tag under the same allowance. |
| `setup_signal` | integer | SETUP_ERROR, `setup_failed`, the setup was killed | The signal that killed `--setup`, the number `message` quotes. Absent when it exited, or ended in a status the engine does not decode (then `message` quotes the raw status and neither integer is present). Added after the v1.0 tag under the same allowance. |
| `message` | string | UNKNOWN and SETUP_ERROR | Human-readable detail: what was observed, and often which operation it happened at. The failure that produced it is typed by the reader that can raise it (#376): the snapshot walk and the trace read declare separate error sets, so a failure only one of them can produce cannot be described by a sentence written for the other. The trace read used to carry one sentence for all of its failures, chosen by the call site rather than by the failure; the split stopped a trace failure from reaching the snapshot's wording without making the trace side distinguish its own. **`unresolvable_path` no longer shares that sentence** (#485): the shim records why the operation could not be placed, and the refusal names that reason, the pid, and the last name the file had where there was one — so two targets that fail for different reasons no longer produce identical output. The rest of the trace read's failures still share their sentence. The kinds it can name are `unresolvable-path` (the path could not be resolved at all), `fd-without-path <op> fd:N` (a descriptor whose file could not be read back to a path), `unlinked-fd <op> fd:N` (an operation through a descriptor whose file was unlinked while open — the `perl -i` shape; the operation is named because `fsync` and `truncate` reach this too, not only `write`. **`close` reaches it and no longer refuses** — ADR 0003 §2's amendment of 2026-09-08 exempts the one class that can be neither a kill point nor a mutation, so `unlinked-fd close` appears in a trace and not in this field. It still appears here as `fd-without-path close`, where the path query itself failed and the descriptor's target is unknown), `link-by-descriptor fd:N` (a link whose source is a descriptor), `trace-closed-by-target`, and `count-read-failed` (v15: the shim could not read the trace back to find the run's highest number, so it could not tell which position in the run the operation holds — numbering from a count it happened to remember would give the operation another one's address). They are defined in `contract.unresolved_kind` rather than as literals on either side, and the list is open: an engine meeting a record from an older shim sees an empty reason and says so. **A `--setup` that fails leaves what it wrote where this field names it** (#483): its output — both streams — is captured to `setup-output-<pid>.txt` in the work directory, and the refusal carries the command's last non-empty line beside the file's path. The line is a target's own bytes, so it is defanged and clipped the way every other target-chosen string in a report is; the file holds the rest untouched. Three answers and not two: a capture that could not be read back says so rather than reporting that nothing was written — which is also what a capture past the read cap reports, since a file too large to read back is one this engine did not see. A setup that wrote nothing is said to have written nothing and names no file: there is no capture to point at, because an empty one is removed rather than kept. When the setup succeeds the file is kept if it holds anything and removed if it does not, so a warning printed by a setup on a green run is still somewhere after capture took it off the terminal. The pid is in the name because this is the one capture whose contents reach `message`, and two runs sharing a work directory would otherwise quote each other. |
| `divergence_syscall` | string | `oracle_missed_operation` | The operation the oracle saw at the diverging position, named the way that oracle names it — `openat` / `renameat2` from strace, `open` / `rename` from fs_usage. Each observer's own spelling, not a normalised one, so a reader going back to the capture can find the line again. The quoted line stays in `message`; this is the same fact in a form nobody has to parse, and it is the observer's vocabulary rather than the target's. Not present on `oracle_saw_phantom`: that refusal is raised at an index the oracle's account does not reach, so there is nothing there to name. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |
| `apparatus` | string[] | the define declared it | The define's `[define] apparatus` entries (or `--apparatus` flags), each as spelled — `env:NAME`, `env:NAME=VALUE`, `preload:LIB`, `pythonpath:FILE`, `note:TEXT` — in order. The engine checked every entry it can after `setup` and before recording, and refused the run as SETUP ERROR when one was missing; a report that carries this field is a run those devices reached (ADR 0041). Absent when the define declared nothing, so a report from a define without the key reads as it always did. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |
| `apparatus_unchecked` | string[] | `apparatus` has a `note:` entry | The `note:` entries of `apparatus` again: declared, carried, not checked by the engine. Present only when there is at least one, beside `apparatus`. A field added after the v1.0 tag, under the same allowance. |
| `scratch` | string[] | the define declared it | The define's `[define] scratch` entries (or `--scratch` flags), each as spelled after normalisation (trailing slashes dropped), in order: paths relative to the state directory that the built-in invariants judged in no world — not their bytes, not their presence, whether the recording had them before, after, or both — each entry covering the path itself and everything beneath it (ADR 0043). The `l0` line says how many recorded paths the declaration matched, and `not_tested` names the declaration. Absent when the define declared nothing, so a report from a define without the key reads as it always did. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |
| `next_step` | string | UNKNOWN | One sentence saying what to do about the refusal — change the define, pass a flag, narrow the state directory, fix the environment, re-run as a user that can read what the run left, or file it as Sideeye's defect. Chosen at the site that raised the refusal, where the cause is known, so two refusals sharing an `unknown_reason` may carry different steps; `message` keeps the observation and this keeps the action (ADR 0030's line). A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |

`unknown_reason` values (closed set, contract v16 — the set is unchanged from v12;
the version moved because the recorded account did, not the vocabulary):
`no_shim_marker`,
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
`state_not_quiescent`, `unsupported_state_entry`, `state_changed_unaccounted`,
`trace_budget_exhausted`.

A new refusal joins this list in the change that introduces it, and the
acceptance check above holds this page to that.

**`faccessat2` and `epoll_ctl` on the state directory are read as reads** — a
permission query, and an event loop registering a descriptor — not refused as
unmodelled (#542). A call the oracle has no name for is refused as
`unsupported_syscall_observed` when its line reaches the state directory, because it
may have changed something; these two cannot, and they are the two that refused real
targets for nothing (ocrmypdf asking whether it may write its input, mlr's Go runtime
registering a file with its netpoller). Other calls that change nothing on disk and
have no name yet — extended-attribute reads, `inotify_add_watch`, `preadv`, `poll` —
still refuse as unmodelled.

`setup_error_reason` values (closed set — added with #518, ADR 0057, held to the
contract's enum by the same acceptance check, and carrying no version of its own: the
`unknown_reason` paragraph is the one the version check reads; the list below is what the set check
reads, so it names members and nothing else):
`define_invalid`, `setup_failed`, `environment`, `platform_unsupported`, `internal`.

What each class means: define_invalid — the refusal is about what the define says and
could have been raised from its text and declared values alone (a flag the mode refuses,
an empty command, a case file of the wrong version, a path spelled too long, a work
directory inside the state directory); setup_failed — the setup command was handed to
exec and exited non-zero, was killed by a signal, or ended in a status the engine does not
decode, with the status beside it as the two integer fields above; environment — the
engine asked the machine for something and was refused (memory, a path that would not
resolve, a file it could not open or create, a process, a privilege, a tool, the state
tree it could not snapshot or rewrite before exploration, an apparatus entry the
environment does not carry); platform_unsupported — what the define asks for does not
exist on this platform or kernel (the fs_usage oracle off macOS, syscall observation off
Linux or on a kernel that refuses the trap, a preload apparatus on macOS); internal — the
engine contradicted itself.

The classes are coarse on purpose, and the rule above places a site: resolving a path the
define names is the machine's answer (`environment`), a path too long as written is the
define's (`define_invalid`). A class added later is the same break the `unknown_reason`
paragraph in `docs/contract-freeze.md` records.

`baseline_violates_invariant` says which layer failed in the world that was
never killed (#199). For the byte layer the `message` names the first path and
what was observed of it — gone, holding neither recorded content, or its
recorded history no longer a prefix — and `next_step` is the class wall: the
README's limits list byte-repeatable writes beside `preflight --twice`, which
measures them before a define exists. The engine does not name a cause; a
clock, a random id and a cache keyed on an inode the restore moved all look
the same from the bytes. For the success marker and the checker, `next_step`
is `fix_define`.

`no_shim_marker` is raised at two sites, and only one of them chooses its
`next_step` from an observation (ADR 0040). At the recording run, `noShimNext`
reads the same image facts the detail line reports. A statically linked ELF, a Mach-O not
linked against dyld, and one whose code directory names a platform or carries
the library-validation or hardened-runtime flag take the class wall. A file
that was read and could not be recognised as an executable image — first
four bytes unreadable, a magic none of the three families claims (where a `#!`
script lands), an ELF magic followed by a class or data byte outside the two
each admits, or a Mach-O slice whose own magic is neither — takes
`operation_not_an_image`, whose sentence names the define: nothing there is a
thing a library is inserted into, so `--shim` and the environment are not what
to look at (#481, #482). Everything else — a first word resolved through
`PATH`, a file that could not be read, one whose structure ran outside itself
— is silent about linkage and keeps the shim step, which is the honest default
rather than a diagnosis. The second site is `preflight --twice`'s second
observed run, and it keeps the shim step whatever the image says: the first
run's marker already answered every signing and linkage question about that
file, so its absence the second time is not about the image.

When the shim's trace is the witness, `child_touched_state_dir`'s `message`
names the foreign process's pid and the first state-directory operation it
performed — its class and its path, both ends for a two-path operation (#484): `a process
other than the subject (pid 4379) performed rename(/…/.git/objects/… ->
/…/.git/objects/…) during the recording run`. One record carries no class:
the shim's own `kill_landed` marker, which a spawned child that loaded the shim
and re-armed itself writes in place of its k-th operation's record when that
operation is its first inside the state directory. For it the `message` says
`was killed at a state-directory operation on <path>` — both ends when the
marker carries two — rather than inventing a class. The refusal stays; what changes
is that the operator's next move — a config flag, a `scratch` declaration, a
different invocation — starts from the record rather than from a guess. When
the oracle is the witness (a child that never loaded the shim), there is no
trace record to name and the `message` stays the sentence it always was. In
either case, when a strace capture exists the `message` ends by saying where
it is — `; the oracle's capture at <work>/oracle.txt holds the child's own
lines, its execve among them` — because the child's argv is in that file and
nothing used to say the file existed.

## The account (always present)

Free-form strings whose *presence* is stable and whose prose may improve
between releases. They exist so a PASS states what it did not look at — the
report refuses to be reassuring without an account.

| Field | Type | Meaning |
|---|---|---|
| `l0` | string | What the built-in atomicity form judged (file counts, forms applied) — and, when the define declared scratch paths, how many recorded paths that declaration matched, with the declaration itself in parentheses: `; K path(s) matched by scratch, not judged (declared: …)`. A define that declared everything reads `0 path(s) judged pre-or-post` here, which is what its PASS is about. |
| `l1` | string | The success-marker layer's account (`"no marker configured"` when unused). A run that declared a marker and stopped before the recording run was scanned says the marker is configured; a run that stopped while its arguments or define were still being read says nothing was established (#352). |
| `case` | string | Path of the saved counterexample this run wrote or replayed; `"(none)"` when no case exists; `"(not saved)"` when a FAIL's case could not be written. |
| `replay` | string | The exact replay command for the saved case; `"-"` when there is none. |
| `oracle` | string | The completeness account, one of: how many operations the two witnesses agreed on; that the oracle ran and the comparison did not complete; that an oracle was named and this run stopped before the comparison; that nothing checked the shim's account (`--allow-unverified` with no oracle); that no oracle was named; or, on a run that stopped while its arguments were still being read, that nothing was established. The account describes what the run was asked to do, so a run that named an oracle never reads as one that did not (#352). |
| `metadata_writes` | string | Ownership/permission/timestamp writes on the state directory (#121, #190): observed by the oracle and excluded from judgement — the chown/chmod and utime families change none of the judged state (names, bytes, link targets). Without an oracle the note says they are not observable at all (the shim does not interpose them); absence of a note is never absence of writes. Like `oracle`, the note says which state the run was in: no oracle named, an oracle named but the run stopped before its metadata account was completed, or the arguments not yet read to the end (#352). |
| `checker` | string | The declared invariant's account (`"none configured"` when unused). A run that declared a checker and stopped before it ran says so, and a PASS with no crash point says it was configured and not run; a run that stopped while its arguments or define were still being read says nothing was established (#352). |
| `processes` | string | The process-boundary account: what each witness observed, and whether anything else touched the state. The shim sees only libc's own entry points (`fork`, `vfork`, `posix_spawn`, the `exec` family, `pthread_create`, `setsid`, `setpgid`), so a child created through a raw syscall is not observable to it at all; where nothing that could have seen a boundary looked, the note says the question was not established rather than answering it. `fs_usage` drops whole processes by name (ADR 0031), so its silence is not an observation of absence either, and where the two witnesses disagree the note reports both rather than preferring one. Absence of a boundary from the note is never absence of a boundary. The UNKNOWN text block prints it too (#123), so a run stopped by another process still says whether the engine followed the subject across an image change and a reader can tell which slice stopped them. Not every text block carries it: `SETUP_ERROR` prints a single line, the zero-operation PASS renders its own shorter block, and the MCP summary carries verdict, message, case and next step only. The JSON is where this field is unconditional. Since v15 it also says whether another process's operations were **admitted** as crash points — the two witnesses named the same writers, no two writers' operations overlapped, and every writing child was reaped — or refused for want of one of those, and it says that an explored world inherits that finding rather than re-deciding it (a world runs without an oracle). Since v16 a judged run that created threads says so in a clause of its own — how many threads the shim saw created (a floor: a raw `clone` leaves no record) and how many thread ids wrote the judged directory — so "single process" is never read as "single-threaded"; a thread is not a process boundary in this field's sense, and a run whose only boundary is a thread reads as one process with that clause after it. Since #544 that clause can appear on a run verified by `fs_usage` too: the subject's writing thread ids come from the trace, which names the process and the thread on every record, so a single-process run whose state-directory writes come from one recorded thread is judged on macOS as it is on Linux (ADR 0060). A writer that is on neither side of that map is still refused, and under a witness that names threads the refusal calls it an id rather than a process. |
| `not_tested` | array of strings | Fault classes this run does not claim to have tested (power loss, torn writes, concurrent processes, …), widened by what the run declared: appended tails when a file took the history form, post-only file contents when a marker made L1 apply, and `declared scratch paths (neither bytes nor presence judged)` when the define declared any (ADR 0043). Read it before trusting a PASS. |

## Reading it from the MCP surface

`sideeye_explore_config` and `sideeye_replay_case` return this same document as
the tool result's `structuredContent`, minified. `isError` is derived from
`verdict`: a real verdict (PASS/FAIL) is `isError: false`; every refusal
(UNKNOWN, SETUP_ERROR) is `isError: true` — retry after doing what `next_step`
says and fixing what the `message` names, don't parse the error text (ADR 0010).
A SETUP_ERROR says which class it is in `setup_error_reason` (#518), and a
failing setup's status in `setup_exit_code` / `setup_signal`; branch on those,
never on the sentence. The text block's first line carries the class the way it
carries `unknown_reason` — `SETUP_ERROR (setup_failed):` — ahead of the marked
region, since it is a closed set the engine spells. It carries `next_step` too,
as a `next:` line after the marked region and before `case`/`replay`.
