# The report, as a schema

Every `--json` run writes exactly one JSON document. This page documents that
document field by field — for the coding agents DESIGN §3 names as the report's
audience, and for anyone wiring the exit codes into CI.

**Stability**: the document says so itself — `"schema_status": "frozen"`. The
report schema is one of the five surfaces `docs/contract-freeze.md` declares
frozen at the v1.0 tag (surface 2), and that page, not the version number, is
where its compatibility is promised: a change the page does not allow is a
breaking change whichever release carries it. The page allows a new optional
field — so a consumer must tolerate fields it does not know — and better prose in
the account fields, never a change to their presence. It does not allow a
documented field to disappear or change meaning — a field would change name
instead — or a closed set such as `unknown_reason` to gain a member; each time one
of those has happened it was ruled on its own and recorded on that page. Every tag
through v1.3.0 wrote `"experimental"` in this field, the value the tag was meant to
turn over and did not (#565); the move to `"frozen"` is recorded there as the
fourth break of surface 2.

This page is held to the code by an acceptance check: every field that appears
in a generated report must be named here, and every field named here must
appear in a generated report. A field added to one side without the other goes
red in CI. The value of `schema_status` is held too: to the sentence above, to
the table's row, and to `"frozen"`.

## The envelope

One JSON object, written atomically (temp file + rename — a crash of sideeye
itself never leaves a half-written report). Absence is unambiguous: the file
is removed at startup, so a report at the path always describes *this* run.

| Field | Type | Always | Meaning |
|---|---|---|---|
| `schema` | string | yes | The literal `"sideeye/report"`. Reject anything else before reading further. |
| `schema_status` | string | yes | `"frozen"`: the schema froze at the v1.0 tag (`docs/contract-freeze.md`, surface 2). Tags through v1.3.0 wrote `"experimental"` (#565). |
| `contract_version` | int | yes | The trace contract the binary speaks (v19 today). Crash-point numbering does not carry across contract versions; a saved case from another version replays as `case_no_longer_applies`, never as a verdict. |
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
what a reader consults to decide how much that account is worth. Since #542 the trap set is every operation Sideeye counts as a crash point — open, write, rename, unlink, fsync, truncate, mkdir, rmdir, link, symlink, in each spelling the architecture has — so the list below is what remains after that widening, not what was always outside it. (1) A raw `copy_file_range`: six arguments leave the filter no free register for the marker below, so the syscall is not trapped at all and is seen in this mode only when the call passes through the libc entry point; a raw one is seen by the oracle alone, which refuses. **`pwritev2` has the same six arguments and is handled differently: it is refused rather than counted** — neither counting it in the wrapper nor silencing the wrapper is right on both kernels, because glibc falls back to a trapped number when the kernel lacks `pwritev2` and does not when the kernel has it. The wrapper records `unsupported` instead and the run refuses with `unsupported_syscall_observed`, on either kernel and without needing an oracle to notice. Under the default mode `pwritev2` is counted as it always was. (2) A process executing in a different syscall ABI (32-bit compat): the filter cannot read the call number in an ABI it does not know and allows it through uncounted; the oracle sees those operations and the comparison refuses. (3) A target that itself issues one of the trapped syscalls with the handler's 64-bit re-issue marker already in its sixth argument register: that operation would be allowed uncounted. The marker exists because a filter cannot be replaced after an `exec`, so the handler cannot be recognised by its address; the odds of a collision are 2^-64 per call. (4) A target that takes `SIGSYS` away **around the shim's four libc entry points**. Through them, once the guards are armed, it is covered: the shim interposes `sigaction`, `signal`, `sigprocmask` and `pthread_sigmask`, accepting a request that names `SIGSYS`, answering it successfully, and not applying the part that would replace the handler or block the signal — which is what lets a Go target be observed at all, since Go installs its own handler and touches the mask through libc — and `sigaction` also takes `SIGSYS` out of the `sa_mask` of a request for any other signal, so that a handler installed with every signal in its mask (libuv's, and so node's) does not hold `SIGSYS` blocked while it runs; a target that queries such a handler reads its mask back without `SIGSYS`. What is left is every change to a process's signal state that does not reach those four entry points while their guards are up, and the ways known are these: (a) `rt_sigaction`, `rt_sigprocmask`, or a `clone3` with `CLONE_CLEAR_SIGHAND`, issued raw — by a statically linked Go binary, or by a Go child between fork and exec — or issued by the C library from inside itself: glibc's `posix_spawn` child running a file action that opens for writing (measured: the child dies of signal 31), the library's other entry points that set a mask or a handler (`__sigaction`, `sigset`, `sighold`, `sigignore`, `sigpause`, `sigblock`, `sigsetmask`, `bsd_signal`, `sysv_signal`, `setcontext`, `siglongjmp`, each in glibc 2.36's dynamic symbol table), and the masks `posix_spawnattr_setsigmask` and `pthread_attr_setsigmask_np` hand to a new process or thread; (b) a mask the kernel applies without `rt_sigprocmask` — for the length of one call (`sigsuspend`, `pselect`, `ppoll`, `epoll_pwait`, `epoll_pwait2`, `io_uring_enter`), for the length of a handler installed by a raw `rt_sigaction`, or on an `rt_sigreturn` whose saved mask a handler edited; (c) a signal whose handler runs while the shim's own `SIGSYS` handler is running, which holds `SIGSYS` blocked; (d) a `SECCOMP_RET_TRAP` filter of the target's own; (e) a call to the four entry points made before the shim's constructor has armed them — another library's constructor can run first — after which a mask or an `sa_mask` holding `SIGSYS` stays as it was, since arming the guards clears nothing already in place; (f) a mask holding `SIGSYS` across an `exec`, which the next image keeps: its shim installs a handler and does not unblock the signal; and (g) a child that keeps the shim but loses Sideeye's environment, which installs the handler and never arms the guards while the filter it inherited still traps. Trapping the raw calls in the filter was measured and not taken (ADR 0063): an exec'd image's startup, glibc's `posix_spawn` child and an image whose startup creates a thread meet those calls before any handler of the shim's, and would die where they run today. A statically linked Go binary is the case to expect on the raw side; the rest is listed because it is a gap — the `posix_spawn` child was measured on a toy — and not because a target has been seen using it. None of this has a refusal of its own. A trap on a thread with `SIGSYS` blocked ends that process: a target that dies of it is refused as a run that did not complete (`recording_run_failed` when it is the recording run), but a child whose death the target survives ends without a refusal — measured as a preflight accepted with glibc's `posix_spawn` child above dead of signal 31, its file action outside the state directory. A child whose work was inside the state directory would leave the run judged without that work; that case was not measured. (5) A trapped call whose path or `struct open_how` pointer is invalid. The handler reads the path to place the operation before the kernel has looked at the pointer, so a target that passes a bad one expecting `EFAULT` faults inside the handler instead, and the run ends as `recording_run_failed`. The libc wrappers have always read the same pointers — what is new is that a caller who never reaches a wrapper now meets it too.

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
| `explored` | int | yes | Worlds actually run, **including the baseline** (no-kill) world. A full exploration reports `crash_points + 1`; a replay reports 2 (the case's point plus the baseline). One exception: an operation that performs nothing state-changing is refused `nothing_could_fail` with both counters 0 — it PASSed that way before ADR 0091 — so do not assert `explored == crash_points + 1` unconditionally. |
| `violations` | int | yes | Crash worlds whose invariant did not hold. `0` on PASS; `>= 1` on FAIL. |
| `expected_status` | int | yes | The exit status that counted as the operation completing (`--expect-status` / `expected_status`, default 0). Always present so a PASS over a non-zero convention is machine-distinguishable from one that required 0. Governs the recording run and the un-killed baseline world; killed worlds require the kill signal itself, never an exit status. |
| `command_cwd` | string | no | **The directory the define's setup, operation and checker run in**: the declared `cwd` (`--cwd` / `cwd`), resolved to an absolute path, or — when none was declared — Sideeye's own working directory, which is what every child inherits because the engine never changes its own. On a SETUP ERROR raised before any of them ran, it is the directory they would have run in. **Present on every report produced after the declared `cwd` has been resolved**, whatever its verdict — a SETUP ERROR raised after that point, such as `setup_failed`, included. **Absent from a report raised before that point**, which has no directory to name yet — among them the `cwd` vet's own refusal and replay's `case_no_longer_applies`, which is raised while the case file is still being read — and absent if Sideeye could not read its own working directory. The text report prints it as `cwd` in the UNKNOWN block under `next` (below `divergence` when there is one), in the two verdict blocks and in `preflight`'s report (three until ADR 0091 made the zero-operation PASS a refusal); like `recovery`, not on SETUP ERROR's one-line text (#647, ADR 0086). |
| `command_cwd_declared` | bool | no | Whether `command_cwd` came from a declaration (`true`) or is Sideeye's own default (`false`). Present exactly when `command_cwd` is. The text line says `(none declared: Sideeye's own)` for `false`. It exists because the failure it answers is a `cwd` that was never written: an operation that only works inside its own directory, run from somewhere else, refuses as `recording_run_failed` with an exit status and no cause (ADR 0030) — and the directory it ran in is the observation that names the missing line (#647). |

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
| `earliest.recovery` | object | Present only when the define declared a recovery (`[recovery]`, or `--recovery` with `--recovery-check`; #606, ADR 0072) and the run saved this exhibit — also when no recovery was run against it, because the recovery checker was not trusted (`result` `unknown`, `seconds` 0, no `command_exit`). What the target's own recovery did when handed this world's crash state, rebuilt in the state directory from its snapshot **after the exploration decided the verdict** — never part of the verdict, which is the same with or without it. The rebuilt state carries the names, kinds and contents the crash left, not its timestamps or permissions: a recovery that decides by modification time or by permission sees every file as newly written. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |
| `earliest.recovery.result` | string | One of the closed set below. `pass`: the recovery command ran and ended, the state stopped changing, and the recovery checker accepted it. `fail`: the same, and the recovery checker rejected it. `unknown`: anything that stops the run establishing either — the crash state could not be rebuilt, the command could not be started or ended in 125, 126 or 127 (the codes the engine's own child uses before exec), `--world-timeout` expired, a process the command or the checker started outlived the kill of the cgroup it ran in (and then the claim exhibit's leg after it too), the recovery checker could not be started or ended in 125, 126 or 127, the state was still changing after the command ended, the recovery checker accepted a corrupted state before any recovery ran, or it did not accept what the recovery left on the completed, uncrashed state (the world loop's baseline with the recovery run on it — a checker that rejects every state would otherwise read every exhibit `fail`). Never `fail` for a recovery that did not run, or for a checker that cannot accept anything. |
| `earliest.recovery.seconds` | number | Wall clock for this exhibit's recovery: rebuilding the crash state, the command, the settle check and the checker. The two controls that decide whether the recovery checker is trusted are counted once, in the `recovery` account; `0` when they did not trust it and no recovery was run against this exhibit. |
| `earliest.recovery.command_exit` | integer | The recovery command's exit status, present whenever the command exited — including 125, 126 and 127, the codes the engine's child also uses when it could not enter the declared cwd, could not be arranged, or could not exec, which is why those make `result` `unknown`. Absent when the command was killed by a signal, timed out, could not be spawned, or was not run against this exhibit. |

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
| `checker_earliest.evidence` | string | This exhibit's own bundle, beside its own case; `"-"` when none was written. The same path as `evidence` when the two exhibits are one world — one bundle per case, never the same measurement written twice under two names. Added under the same allowance as `evidence`. |
| `checker_earliest.recovery` | object | As `earliest.recovery`, for this world. When the two exhibits are one world the recovery ran once and both objects say the same. |
| `checker_earliest.recovery.result` | string | As `earliest.recovery.result`, for this world. |
| `checker_earliest.recovery.seconds` | number | As `earliest.recovery.seconds`, for this world. |
| `checker_earliest.recovery.command_exit` | integer | As `earliest.recovery.command_exit`, for this world. |

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
| `setup_exit_code` | integer | SETUP_ERROR, `setup_failed`, the setup exited | The status `--setup` exited with — the number `message` quotes as `--setup exited N` — as data. A setup the engine can tell will not start — its file, or the `#!` interpreter it names, missing or not executable — is refused before it runs, as `environment` (#701, ADR 0092). What that check does not judge still arrives here with whatever status the failed exec leaves: the engine's own child exits 127 when `exec` fails, and when the libc hands a file it does not recognise to `/bin/sh` the status is that shell's. A child the engine could not arrange before exec is 126, with the message saying so. Absent when the setup was killed by a signal or ended in a status the engine does not decode. Added after the v1.0 tag under the same allowance. |
| `setup_signal` | integer | SETUP_ERROR, `setup_failed`, the setup was killed | The signal that killed `--setup`, the number `message` quotes. Absent when it exited, or ended in a status the engine does not decode (then `message` quotes the raw status and neither integer is present). Added after the v1.0 tag under the same allowance. |
| `message` | string | UNKNOWN and SETUP_ERROR | Human-readable detail: what was observed, and often which operation it happened at. The failure that produced it is typed by the reader that can raise it (#376): the snapshot walk and the trace read declare separate error sets, so a failure only one of them can produce cannot be described by a sentence written for the other. The trace read used to carry one sentence for all of its failures, chosen by the call site rather than by the failure; the split stopped a trace failure from reaching the snapshot's wording without making the trace side distinguish its own. **`unresolvable_path` no longer shares that sentence** (#485): the shim records why the operation could not be placed, and the refusal names that reason, the pid, and the last name the file had where there was one — so two targets that fail for different reasons no longer produce identical output. The rest of the trace read's failures still share their sentence. The kinds it can name are `unresolvable-path` (the path could not be resolved at all), `fd-without-path <op> fd:N` (a descriptor whose file could not be read back to a path), `unlinked-fd <op> fd:N` (an operation through a descriptor whose file was unlinked while open — the `perl -i` shape; the operation is named because `fsync` and `truncate` reach this too, not only `write`. **`close` reaches it and no longer refuses** — ADR 0003 §2's amendment of 2026-09-08 exempts the one class that can be neither a kill point nor a mutation, so `unlinked-fd close` appears in a trace and not in this field. It still appears here as `fd-without-path close`, where the path query itself failed and the descriptor's target is unknown), `link-by-descriptor fd:N` (a link whose source is a descriptor), `trace-closed-by-target`, and `count-read-failed` (v15: the shim could not read the trace back to find the run's highest number, so it could not tell which position in the run the operation holds — numbering from a count it happened to remember would give the operation another one's address). They are defined in `contract.unresolved_kind` rather than as literals on either side, and the list is open: an engine meeting a record from an older shim sees an empty reason and says so. **A `--setup` that fails leaves what it wrote where this field names it** (#483): its output — both streams — is captured to `setup-output-<pid>.txt` in the work directory, and the refusal carries the command's last non-empty line beside the file's path. The line is a target's own bytes, so it is defanged and clipped the way every other target-chosen string in a report is; the file holds the rest untouched. Three answers and not two: a capture that could not be read back says so rather than reporting that nothing was written — which is also what a capture past the read cap reports, since a file too large to read back is one this engine did not see. A setup that wrote nothing is said to have written nothing and names no file: there is no capture to point at, because an empty one is removed rather than kept. When the setup succeeds the file is kept if it holds anything and removed if it does not, so a warning printed by a setup on a green run is still somewhere after capture took it off the terminal. The pid is in the name because this is the one capture whose contents reach `message`, and two runs sharing a work directory would otherwise quote each other. |
| `divergence_syscall` | string | `oracle_missed_operation` | The operation the oracle saw at the diverging position, named the way that oracle names it — `openat` / `renameat2` from strace, `open` / `rename` from fs_usage. Each observer's own spelling, not a normalised one, so a reader going back to the capture can find the line again. The quoted line stays in `message`; this is the same fact in a form nobody has to parse, and it is the observer's vocabulary rather than the target's. Not present on `oracle_saw_phantom`: that refusal is raised at an index the oracle's account does not reach, so there is nothing there to name. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |
| `define_warnings` | string[] | a string-form command was spelled for a shell | One sentence per setup, operation, check or recovery command whose string form holds a quote, or a whole word a shell would act on (`&&`, `\|`, `>`, a word beginning `$` or `~/`…), saying how Sideeye reads it — quotes passed as characters, the word as an argument — and, for quotes, the argv form that groups what they meant (#706, ADR 0095); and, from a toml, one per command value the parser read as ending at an inner `"` because a `#` followed it. In the order the define names its commands, the parser's sentences first; every piece of the command it quotes is shown through the same defang as other define text. Never set on a replay. Advice only: the commands ran as written and the verdict is unaffected. A field added after the v1.0 tag, under the allowance. |
| `apparatus` | string[] | the define declared it | The define's `[define] apparatus` entries (or `--apparatus` flags), each as spelled — `env:NAME`, `env:NAME=VALUE`, `preload:LIB`, `pythonpath:FILE`, `note:TEXT` — in order. The engine checked every entry it can after `setup` and before recording, and refused the run as SETUP ERROR when one was missing; a report that carries this field is a run those devices reached (ADR 0041). Absent when the define declared nothing, so a report from a define without the key reads as it always did. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |
| `apparatus_unchecked` | string[] | `apparatus` has a `note:` entry | The `note:` entries of `apparatus` again: declared, carried, not checked by the engine. Present only when there is at least one, beside `apparatus`. A field added after the v1.0 tag, under the same allowance. |
| `scratch` | string[] | the define declared it | The define's `[define] scratch` entries (or `--scratch` flags), each as spelled after normalisation (trailing slashes dropped), in order: paths relative to the state directory that the built-in invariants judged in no world — not their bytes, not their presence, whether the recording had them before, after, or both — each entry covering the path itself and everything beneath it (ADR 0043). The `l0` line says how many recorded paths the declaration matched, and `not_tested` names the declaration. Absent when the define declared nothing, so a report from a define without the key reads as it always did. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |
| `next_step` | string | UNKNOWN | One sentence saying what to do about the refusal — change the define, pass a flag, narrow the state directory, fix the environment, re-run as a user that can read what the run left, or file it as Sideeye's defect. Chosen at the site that raised the refusal, where the cause is known, so two refusals sharing an `unknown_reason` may carry different steps; `message` keeps the observation and this keeps the action (ADR 0030's line). A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |

`unknown_reason` values (closed set, contract v19 — v19 moved the recorded account, not the
vocabulary, ADR 0098; the set gained `nothing_could_fail` after v18 without moving the version, ADR 0091, and `checker_rejects_initial_state` after v19 without moving it, ADR 0107; before that it was unchanged from v12, the version having
moved because the recorded account did, not the vocabulary):
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
`trace_budget_exhausted`, `nothing_could_fail`, `checker_rejects_initial_state`.

**`nothing_could_fail` is an exploration in which no world could have failed** (#682, #683,
ADR 0091): no crash point; or no checker, no crash world that printed the marker over a path only
one snapshot holds, and no judged path touched — one that ended other than it began, or that a
crash point other than an `fsync` or a `mkdir` named, or whose directory a `rename` named. It is
raised by `explore` after every world has run, and by `preflight` when there is no crash point;
never by `replay`, whose one world answers whether that world still fails. Its `next_step` is
chosen where it is raised: where an undeclared define's commands run, and so where a relative
argument resolved, when there was no crash point; a check or a marker when there were crash points;
a check alone when a marker was declared or there is nothing created or removed for one to judge.
`preflight` raises it on a recording with no crash point whether or not an oracle ran; `explore`
asks its completeness gate first, so without an oracle or `--allow-unverified` the same define
meets `completeness_not_verified` there. It is a floor: a
crash point that names a judged path without changing it — a lock file opened for writing, a call
that failed — still counts as touching it.

**`checker_rejects_initial_state` is a checker that fails on the state the define starts from**
(#756, ADR 0107). The falsification shows the checker a corrupted state and requires it to fail;
since #756 the same gate then restores the state the define starts from and requires the checker to
pass on it — the restored copy every world starts from, not what setup left, so whatever a
restore does not carry (docs/cli.md) is not there either — before any world runs. A checker that fails there would fail in the world
killed before the first operation, which holds exactly that state — and until #756 that world was
reported as the target's FAIL at crash point 1, `after (start)()`, although nothing the target did is
in it. It is raised by `explore` and by `replay`, both of which falsify the checker, after the
falsification has passed; never by `preflight`, which does not run the checker. The checker's output
on that state is re-emitted with each line marked `start: `, as the falsification's are marked
`falsify: `, and only when it refuses. `next_step` is `fix_define` under every observation mode — no
run of the operation has touched the state it judged — or, for a toml that declares no `cwd`, the
step below; an exit of 126 takes `environment`, as the falsification's does, because the engine's
fork stub exits 126 too.

A member added after the v1.0 tag is a break of surface 2: each needs its own owner ruling, none licenses the next, and `docs/contract-freeze.md` records every one; whichever change adds one, the acceptance check above holds this page to the enum.

**A state file that can be written through a shared memory mapping is refused
`unsupported_syscall_observed`** (#689, ADR 0098): the `message` is
`mmap(PROT_WRITE|MAP_SHARED)` when the mapping was made writable, and `mprotect(PROT_WRITE) on
a shared mapping of a state file` when a read-only shared mapping of one was given
`PROT_WRITE` afterwards — on Linux from the strace oracle, for the subject and for every
child (a child the v15 rule does not admit is refused first, as that), and on macOS from
the shim, with or without an oracle (contract v19). Past the 32 read-only mappings the
macOS shim remembers it cannot tell which ranges are state files, and a later `PROT_WRITE`
`mprotect` is refused as `mprotect(PROT_WRITE) after more shared mappings of state files
than the shim tracks`. A read-only shared mapping is read as a read.

**`faccessat2` and `epoll_ctl` on the state directory are read as reads** — a
permission query, and an event loop registering a descriptor — not refused as
unmodelled (#542). A call the oracle has no name for is refused as
`unsupported_syscall_observed` when its line reaches the state directory, because it
may have changed something; these two cannot, and they were the first two found refusing
real targets for nothing (ocrmypdf asking whether it may write its input, mlr's Go runtime
registering a file with its netpoller). **Under the strace oracle, extended-attribute
reads (`getxattr`, `lgetxattr`, `fgetxattr`, `listxattr`, `llistxattr`, `flistxattr`),
`inotify_add_watch`, `preadv`/`preadv2`, `poll`/`ppoll` and `select`/`pselect6` on the
state directory are read as reads too** (#684): vim asking for a file's ACL, dotdrop and
firewall-offline-cmd listing a file's attributes, and fish watching its variables'
directory were each refused for asking. Extended-attribute writes (`setxattr`,
`removexattr` and their `l`/`f` forms) still refuse: what an attribute write does to the state
has not been ruled on — the restore does not put attributes back, and nothing yet says whether
such a write is judged or, like the ownership and permission calls #121 observes, set aside.
The macOS fs_usage oracle keeps its own list (`src/fsusage.zig`), which already reads
`getxattr`, `fgetxattr`, `listxattr`, `flistxattr` and `select` as reads; it was not measured
for the rest.

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
environment does not carry, a setup, operation or checker that cannot be started — its file, or
the `#!` interpreter that file names, missing, not a regular file, not executable or not
reachable, or a bare name with no executable file on `PATH`, refused before it runs (#701,
ADR 0092)); platform_unsupported — what the define asks for does not
exist on this platform or kernel (the fs_usage oracle off macOS, the strace oracle on macOS,
syscall observation off Linux or on a kernel that refuses the trap, a preload apparatus on macOS); internal — the
engine contradicted itself.

The classes are coarse on purpose, and the rule above places a site: resolving a path the
define names is the machine's answer (`environment`), a path too long as written is the
define's (`define_invalid`). A class added later is the same break the `unknown_reason`
paragraph in `docs/contract-freeze.md` records.

`recovery.result` values (closed set — added with #606, ADR 0072, held to the contract's
RecoveryResult enum by the same acceptance check, carrying no version of its own, and
naming members and nothing else):
`pass`, `fail`, `unknown`.

A third closed set rather than new `unknown_reason` members: nothing a recovery does can make
the run unknown, because the verdict was decided before any recovery ran. A result added later
is the same break the `unknown_reason` paragraph in `docs/contract-freeze.md` records.

`baseline_violates_invariant` says which layer failed in the world that was
never killed (#199). For the byte layer the `message` names the first path and
what was observed of it — gone, holding neither recorded content, or its
recorded history no longer a prefix — and, where both runs left a file of one
kind there, where their bytes first differ, how long the differing stretch is in
each and what kind of bytes it holds (#688; never the bytes, which only
`preflight --twice` prints, in its own output) — and `next_step` names what a
define can do about such a path (#710, ADR 0097): declare it `scratch` when its
bytes are not what the verdict should judge, and run `preflight --twice`, which
names the paths two clean runs leave differently (a bounded list, scratch left
out) before a define is explored. The README lists byte-repeatable writes among
its limits. The engine does not name a cause; a
clock, a random id and a cache keyed on an inode the restore moved all look
the same from the bytes. For the success marker and the checker, `next_step`
is `fix_define`.

**Where #710 gave a refusal a step of its own** (ADR 0097, from the refusals the dogfood
records and a first-time operator met most): `recording_run_failed` on an exit status nobody
declared takes `run_then_expect_status` — run the operation by hand first, then
`--expect-status` if that status is the tool's success — and on a run that ended on a signal
(which `message` now names) `run_by_hand_signalled`; `preflight --twice`'s second run ending
differently from the first takes `second_run_diverged`, which says the restore rebuilds the
names, kinds and bytes under `--state` and not their modes, owners or timestamps, so a tool that
checks the mode of a file under `--state` — an executable bit, a `0600` key, as in both
records — ends this way too; `kill_did_not_land` takes `kill_not_landed` where no landing was
recorded at the asked position and `not_repeating` where the world reached it through other
operations; `multiple_threads_detected` raised from the run's own record of its threads takes
`threads_limit`, which names the README's threads limit and the way past the records found — a tool's own switch for running its file calls on one
thread (`UV_THREADPOOL_SIZE=1` for Node, `GOMAXPROCS=1` for Go), declared in `apparatus`, with
`docs/apparatus.md` listing the switches measured and the targets each did not move (#686, ADR
0113) — and under `--observe supervised`, which records no join and not which thread a creation
made, `threads_supervised`, which says that and names the same switch without naming a shim. The
same reason raised under `--oracle-fs-usage` on macOS for a writer the shim never recorded — the
fs_usage capture saw a thread write that no record names (ADR 0060) — keeps the step it had,
`unwrap_or_class_wall`: that writer went around the shim, which is not what a pool's size changes.
Three refusals the records met keep the class wall because this build's step names no way past
them and no README line names their limit: `unresolvable_path`, `unsupported_syscall_observed`,
and `oracle_missed_operation` under `--observe syscalls` — except
for a statically linked operation in a shape measured to be crossed, the next paragraph.

**A static parent whose dynamic child carried the shim** (#685, ADR 0108). The default gate lets
this shape through, because the child's shim announces itself, and the parent's own calls are
recorded by nobody. Under `--observe wrappers` or `--observe syscalls`, in a build that can
supervise (Linux on aarch64 or x86_64) and outside a replay, when the operation's image is a
statically linked 64-bit ELF, three refusals take `observe_supervised_static_parent`, which names
`--observe supervised` and says that the image read before the run is one no shim can be loaded
into:
`oracle_missed_operation` where the shim announced itself from a process other than the one the
oracle saw start; the recording run's `unresolvable_path` where a process closed the shim's trace
(`trace-closed-by-target`); and `child_touched_state_dir` on its shimmed-writer arm, with the same
pair of processes. The `unresolvable_path` site reads the record's kind alone, so a static image
that exec'd a dynamic one which then closed the trace takes the step too — under that mode the
trace is the engine's. Each was measured to be crossed by that mode — aliyun-cli 3.5.1 and lefthook
1.13.6, roswell 26.02.116, and for the third a toy, no real target yet. Everywhere else the site's
own step stands, because one reason is raised from sites that mode crosses and from sites where
it refuses the same way, and a step that cannot work is worse than one that points at the class.
That includes shapes whose way past was not measured either way: the other kinds
`unresolvable_path` refuses (an unlinked descriptor, a descriptor without a path and a link by
descriptor are refused under that mode too, as `supervise_linux.zig` reads; not run); at
`oracle_missed_operation` and `child_touched_state_dir`, a static image that execs a dynamic one in
its own process, whose shim announces itself from the oracle's subject; `child_touched_state_dir`'s
other arm. A replay keeps the mode its crash point was counted in and is not sent on.

`child_process_detected` from the recording run's broken self-exec chain chooses
its `next_step` from an observation on macOS (#703). When the operation's first
word — or the interpreter on the `#!` line of the script it names — is a Mach-O
that resolves into a `bin` directory beside the framework's library — named after
the framework: `Python`, the Command Line Tools' `Python3`, the free-threaded
`PythonT` — and an interpreter in `Resources/Python.app/Contents/MacOS` named after
the framework or `Python`, the layout CPython's `pythonw.c` launcher relies on, the
`message` adds what was read (the image, before the run; at the refusal, the script
and the options on its `#!` line, the interpreter and, in a virtual environment, the
`__PYVENV_LAUNCHER__` value the launcher would set), and the step names that
interpreter as the operation's first word rather than asking about a shell
wrapper. Anywhere else, and for any other image, the step is the wrapper question
it always was. The reason, the verdict and the exit code do not move.

`no_shim_marker` is raised at two sites, and only one of them chooses its
`next_step` from an observation (ADR 0040, amended by ADR 0090). At the recording
run, `noShimNext` reads the same image facts the detail line reports. The image is
the file the operation's first word names — resolved against the define's `cwd`
when it is a path, and looked up along the engine's `PATH` when it is a bare name
(the operation inherits that `PATH`; an `apparatus` `env:` entry is checked, not
applied), with a relative `PATH` component taken against that same `cwd`. A file
found that way is read the same as a named one, and the detail line says it was
found along `PATH`. **On Linux on aarch64 or x86_64 — the builds that have `--observe
supervised` — a statically linked 64-bit ELF refused under
`--observe wrappers` or `syscalls` takes the step naming `--observe supervised`,
whether the operation names it by path or by a bare name found on the engine's
`PATH`**: that mode counts such a target from outside it, and the sentence names
its conditions (Linux 5.19 or later, aarch64 or x86_64, a cgroup v2 the engine can
create cgroups in). A 32-bit static ELF, a static ELF off Linux or on a Linux build for
another architecture, a Mach-O not linked
against dyld, and one whose code directory carries the library-validation or
hardened-runtime flag without naming a platform take the class wall. One whose
code directory names a platform — the marker Apple's own binaries carry, whatever
flags sit beside it — takes `non_system_build`, which names a build of the tool
that is not part of macOS (#710, ADR 0097; measured on `/bin/cp`, an ad-hoc
re-signed copy of it, which the system killed as it started, and Homebrew's `xz`). A file that was
read and could not be recognised as an executable image — first four bytes
unreadable, a magic none of the three families claims (where a `#!` script lands,
named by path or by a bare name), an ELF magic followed by a class or data byte
outside the two each admits, or a Mach-O slice whose own magic is neither — takes
`operation_not_an_image`, whose sentence names the define: nothing there is a thing
a library is inserted into, so `--shim` and the environment are not what to look
at (#481, #482). Everything else — a bare name with `PATH` unset (the engine does
not pick one libc's default list) or found in no `PATH` directory, a file that
could not be read, one whose structure ran outside itself — is silent about
linkage and keeps the shim step, which is the honest default rather than a
diagnosis. Under `--observe supervised` the step is `environment` whatever the
image: that mode loads no shim, and a trace without the start record the engine
writes itself means the engine could not write its own trace. The second site is
`preflight --twice`'s second observed run, and it keeps the shim step whatever the
image says: the first run's marker already answered every signing and linkage
question about that file, so its absence the second time is not about the image.

`oracle_missed_operation` chooses its `next_step` from the observation mode
(#599, ADR 0069). Under `--observe wrappers` on Linux it is `observe_syscalls`:
the oracle saw an operation that did not pass through the interposed libc entry
points, and that mode counts most operations at the kernel boundary, those
included. The sentence promises neither a verdict nor a cause — the same
refusal, with the same thread account, was measured PASS under that mode for one
zstd input and `multiple_threads_detected` for another — and before the flag is
reached for it names the README entry under 'What the target has to be' that
begins 'Under `--observe syscalls`, a process whose `SIGSYS` is blocked or reset',
and this page's 'What `--observe syscalls` does not see': that mode changes what
some targets do. Under `--observe syscalls`, or off Linux, the step is the class
wall — except, on Linux in a build that can supervise and outside a replay, for an
operation whose image was read as a statically linked 64-bit ELF while the shim
announced itself from another process, which takes `observe_supervised_static_parent` under either
shim mode (#685, ADR 0108); a Linux kernel without the trap answers the flag with
`platform_unsupported`. The failures a process that mode killed produces follow
the mode as well: where the default mode sends the reader to the define or to
run the operation by hand — the recording run's exit status nobody declared and
its signal (`run_then_expect_status`, `run_by_hand_signalled`), its success marker
that never appeared, and the baseline world's checker rejecting the state
(`fix_define`) — a run under `--observe
syscalls` takes `syscalls_may_have_killed`, because following the site's own
sentence (declare a different success convention, check the marker string, check
the operation and the checker against each other) would have a broken run
judged. The branches that exit 126 keep `environment`. `preflight --twice`'s
second run (`second_run_diverged`), the baseline's exit and the baseline's marker
layer (`fix_define`) keep their own steps: each compares against a recording the same mode already completed,
so a kill that happened in both runs does not reach it. The checker is the
exception because it judges the state from outside rather than against the
recording, and the baseline is the first clean state left by the operation that it sees.

A define read from a toml that declares no `cwd` takes `declare_cwd` where `recording_run_failed` would say `run_then_expect_status` or
`run_by_hand_signalled`, where `marker_never_observed`, `checker_not_falsified` (the corrupted state accepted),
`checker_rejects_initial_state` (the starting state rejected) and
`baseline_violates_invariant`'s checker layer would say `fix_define` — and where `nothing_could_fail` with no crash point would say `nothing_in_state` — when the command that failed
carries an argument the engine found under the toml's directory and not under the one it ran in (or a
directory above an argument that is under neither); `message` gains that observation as its last
clause (#700, ADR 0093). Where a site's step under `--observe syscalls` is
`syscalls_may_have_killed` — the recording run, the marker, the baseline's checker layer — that
step stays, and `message` carries the line to add as well, as `setup_failed`'s does, having no
`next_step`.

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

**The `next_step` follows which condition refused the run** (#634, ADR 0076).
This refusal stands at two walls. A writer **the shim was loaded into** — the
trace holds an `exec` or a `shim_ready` from it and no operation of its own, so
its writes went around the interposed entry points — is counted at the kernel
boundary, and a run in the default mode on Linux is sent to `--observe
syscalls`, the step `oracle_missed_operation` already uses; a run already in
that mode, or off Linux, is not. A static parent whose child carried the shim
can reach this arm — when the child that announced first is the one that wrote, its
operations were counted as the first announcer's, so "no operation of its own" does
not describe it — and there takes `observe_supervised_static_parent` on the
conditions the `next_step` section gives (#685, ADR 0108). Every other shape keeps the step it had,
including the one the mode would **kill**: a writer whose image holds no shim —
an `exec` recorded after its last `shim_ready`, or no record of its own at all,
which is a child that never loaded the shim or loaded it without Sideeye's
environment (case 4(g) above) — and case 4 is what happens to such a child under
that filter. Writers whose operations overlap and a child nothing waited for
keep it too, because two processes writing at once are ordered by the scheduler
wherever their operations are counted. Measured on three targets in both modes
(`spike/followup-child-touch-modes/`): `lbdb`, whose child announces itself and
flushes a buffered stdout at `exit()`, moved to PASS; `pacpl` and `mail-expire`
produced byte-identical reports.

## The account (always present)

Free-form strings whose *presence* is stable and whose prose may improve
between releases. They exist so a PASS states what it did not look at — the
report refuses to be reassuring without an account.

| Field | Type | Meaning |
|---|---|---|
| `l0` | string | What the built-in atomicity form judged (file counts, forms applied) — and, when the define declared scratch paths, how many recorded paths that declaration matched, with the declaration itself in parentheses: `; K path(s) matched by scratch, not judged (declared: …)`. A define that declared everything reads `0 path(s) judged pre-or-post` here, which is what its PASS is about. **Its leading numbers count the same set `l0_judged_paths` names**: the first is that set minus the files under the history form, and a second appears only when some file took that form, counting those. So the opening number equals the set's size on a run with no history file, and is smaller than it otherwise — larger than `l0_judged_paths.len` only where a ceiling truncated the array. Two things the line carries are not about this set — the scratch clause counts recorded paths the declaration matched, which by construction are the paths that are *not* in it, and a run that reconciled a rename from outside the judged root appends a third count that is about an unexamined subtree. On a run that never classified, the line reads `not classified (…)` and both fields below are absent. |
| `l1` | string | The success-marker layer's account (`"no marker configured"` when unused). A run that declared a marker and stopped before the recording run was scanned says the marker is configured; a run that stopped while its arguments or define were still being read says nothing was established (#352). |
| `case` | string | Path of the saved counterexample this run wrote or replayed; `"(none)"` when no case exists; `"(not saved)"` when a FAIL's case could not be written. |
| `replay` | string | The exact replay command for the saved case; `"-"` when there is none. Each path in it is single-quoted where a shell would split or expand it (#711), so it pastes as written — an ordinary path reads as it always did. |
| `evidence` | string | Path of the evidence bundle written beside the saved case (#607, ADR 0071) — the measured consequence, boundary, checker evidence and caveats, as a document `sideeye evidence` renders for a reader who has never used Sideeye ([docs/evidence.md](evidence.md)). The text report prints the command itself on its `evidence` line, `sideeye evidence <this path>` (#709); this field stays the path. `"-"` when none was written, which includes every run that saved no case and every replay. A path rather than a rule for deriving one from `case`: the two names are related today and a consumer that encoded that relation would be holding a copy of a rule only the engine should own. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |
| `oracle` | string | The completeness account, one of: how many operations the two witnesses agreed on; that the oracle ran and the comparison did not complete; that an oracle was named and this run stopped before the comparison; that nothing checked the shim's account (`--allow-unverified` with no oracle); that no oracle was named; or, on a run that stopped while its arguments were still being read, that nothing was established. The account describes what the run was asked to do, so a run that named an oracle never reads as one that did not (#352). |
| `metadata_writes` | string | Ownership/permission/timestamp writes on the state directory (#121, #190): observed by the oracle and excluded from judgement — the chown/chmod and utime families change none of the judged state (names, bytes, link targets). Without an oracle the note says they are not observable at all (the shim does not interpose them); absence of a note is never absence of writes. Like `oracle`, the note says which state the run was in: no oracle named, an oracle named but the run stopped before its metadata account was completed, or the arguments not yet read to the end (#352). |
| `checker` | string | The declared invariant's account (`"none configured"` when unused). A run that declared a checker and stopped before it ran says so — a run with no crash point among them, which is refused `nothing_could_fail` whatever was declared (ADR 0091); a run that stopped while its arguments or define were still being read says nothing was established (#352). |
| `recovery` | string | The declared recovery's account (#606, ADR 0072), **present only when the define declared one** and the run read it — a define without `[recovery]` gets no recovery field and no recovery line anywhere in its report (a FAIL's and a PASS's JSON and text reports were compared byte for byte against the build before this field existed, on macOS). Two refusal messages name the recovery whatever the define declares: `--config` beside the define-surface flags, and an unknown config section. Says whether the recovery checker was trusted — it must reject a probe that writes distinct junk to every file (so a checker comparing two files with each other is not handed two equal ones), and accept what the recovery leaves on the completed, uncrashed state — each saved exhibit's result with its reason and time, how many of the run's failing worlds that was (only the saved ones are recovered, and a saved world does not stand for the others), and the total time; when the controls did not trust the checker, why, `0 of N` failing worlds, and the controls' time. `configured; not run (no world was saved as a FAIL)` on a PASS and on every run that stopped before saving one, except `preflight`'s, which never starts a recovery: its refusals and its own document (below) carry `declared; preflight runs no recovery`. The recovery runs after the exploration, so the state directory afterwards holds what the last recovery left, not the baseline's result. |
| `processes` | string | The process-boundary account: what each witness observed, and whether anything else touched the state. The shim sees only libc's own entry points (`fork`, `vfork`, `posix_spawn`, the `exec` family, `pthread_create`, `pthread_join`, `pthread_detach`, `setsid`, `setpgid`), so a child created through a raw syscall is not observable to it at all; where nothing that could have seen a boundary looked, the note says the question was not established rather than answering it. `fs_usage` drops whole processes by name (ADR 0031), so its silence is not an observation of absence either, and where the two witnesses disagree the note reports both rather than preferring one. Absence of a boundary from the note is never absence of a boundary. The UNKNOWN text block prints it too (#123), so a run stopped by another process still says whether the engine followed the subject across an image change and a reader can tell which slice stopped them. Not every text block carries it: `SETUP_ERROR` prints a single line (the zero-operation PASS also rendered a shorter block of its own until ADR 0091 made it a refusal), and the MCP summary carries verdict, message, case and next step only. The JSON is where this field is unconditional. Since v15 it also says whether another process's operations were **admitted** as crash points — the two witnesses named the same writers, no two writers' operations overlapped, and every writing child was reaped — or refused for want of one of those, and it says that an explored world inherits that finding rather than re-deciding it (a world runs without an oracle). Since v16 a judged run that created threads says so in a clause of its own — how many threads the shim saw created (a floor: a raw `clone` leaves no record) and how many thread ids wrote the judged directory — so "single process" is never read as "single-threaded"; since v18 the same clause says how many times the write passed between threads in causal order and how many joins and detaches the shim recorded, because two thread ids writing is a judged run when a creation or a join orders their writes (ADR 0067) and the clause has to say what made it one. **What that clause covers, stated since #543 because the sentence above used to promise more than the trace can carry**: the threads the shim recorded, and a thread it did not record that *wrote* the judged directory — every record names the thread that made it, so a writer which is not the initial thread is visible even when its creation was not, and the clause then says the count is a floor. Two cases stay outside it, both because the trace cannot answer them rather than because the clause declines to. A thread that was neither recorded nor wrote leaves nothing to name: same pid, no `.thread` record, no crash point — a run holding one reads as a single process because nothing observed otherwise. And on a run where the shim **did** record at least one thread, a writer that is not the initial thread may be one of those or one the shim missed, with nothing to separate them: a `.thread` record carries the id of the thread that *called* `pthread_create`, never the id of the thread it created. Such a run gets the counting clause and not the floor sentence. A thread is not a process boundary in this field's sense, and a run whose only boundary is a thread reads as one process with that clause after it. Since #544 that clause can appear on a run verified by `fs_usage` too: the subject's writing thread ids come from the trace, which names the process and the thread on every record, so a single-process run whose state-directory writes come from one recorded thread is judged on macOS as it is on Linux (ADR 0060) — unless it replaced its own image, which is refused under that oracle (ADR 0018). A writer that is on neither side of that map is still refused, and under a witness that names threads the refusal calls it an id rather than a process. Since #559, a process that left the process group (`setsid`, `setpgid`) in a run the engine held in a cgroup of its own (ADR 0065) is accounted for as any other child is, and nothing in the field singles it out; in a run the engine did not hold, the field names that process leaving the containment group — or, where only the oracle saw it, the syscall the oracle's account reports — where nothing outranks it: another process's operations on the judged directory are named first, as they always were, and preflight's second run is named by the same rule. The subject leaving its own process group, which it can under `--oracle`, is never counted as a second process; the field names it only where no witness's account was read. |
| `not_tested` | array of strings | Fault classes this run does not claim to have tested (power loss, torn writes, concurrent processes, …), widened by what the run declared: appended tails when a file took the history form, post-only file contents when a marker made L1 apply, and `declared scratch paths (neither bytes nor presence judged)` when the define declared any (ADR 0043). Read it before trusting a PASS. |

## The account as data

The figures the `oracle`, `checker` and `processes` sentences state, as numbers and booleans
beside them (#711, ADR 0096), so a caller reads them without parsing prose. Each is written from
the value its sentence prints, and **each is present only where it was measured**: a field
absent is not a zero or a false, and none is ever written as one standing for "not known". The
process figures are the **recording run's**: the `processes` sentence also says what an explored
world showed — a thread created there, a boundary that appeared there — and these fields do not
carry that. None is a closed set. Eight fields added after the v1.0 tag, under the additive
allowance surface 2 of `docs/contract-freeze.md` keeps open. The sentences are unchanged.

| Field | Type | Present | Meaning |
|---|---|---|---|
| `oracle_witness` | string | an oracle flag was read | Which second witness was asked for: `"strace"` (`--oracle`) or `"fs_usage"` (`--oracle-fs-usage`). Present from the argument that names it, whether or not the comparison then ran — the `oracle` sentence says which. An open set: a consumer must tolerate a value it does not know. |
| `oracle_operations_agreed` | integer | the comparison completed and agreed | How many operations the two witnesses agreed on — the N of the `oracle` sentence's "agreed on N operations". **Not a gate**: on a run whose writing children were admitted it is present while `oracle_verified` stays `false` (the row for `oracle_verified_subject_only` above says why); gate on `oracle_verified`. |
| `checker_declared` | bool | every source of a checker has been read, or `--check` has | Whether a checker was named. Absent on a run that stopped while its arguments or define were still being read, where the `checker` sentence says nothing was established. `true` from the line that reads `--check`, so a command that then refuses the flag (a replay, whose case carries the define, or `--config`) reports it named, as the sentence does. |
| `checker_worlds` | integer | the exploration ran every world it had to, with the checker | How many worlds the checker ran in — the N of the `checker` sentence's "ran in N world(s)". Absent on a run refused part way through the worlds, whose sentence names no N either. |
| `processes_children_admitted` | bool | the recording run's trace passed every check on it — the condition `l0_judged_paths_touched` has | Whether another process's operations were admitted as crash points in the recording run (contract v15): the two witnesses named the same writers, no two writers' operations overlapped, and every writing child was reaped. `false` on a run with nothing to admit, too. Absent on every refusal raised on the recording's own trace or before it — for example a trace cut short, renumbered or never announced (`no_shim_marker`), or one whose writers the recording refused (`multiple_threads_detected`, `child_touched_state_dir`) — the rule `l0_judged_paths_touched` follows; a refusal raised later, in an explored world or preflight's second run, carries the recording's figures. |
| `processes_image_changes` | integer | as above | How many times the subject replaced its own image in the recording run with the chain of observation followed — the N of the sentence's "image replaced N time(s)". A run whose chain of observation broke is refused before the figures are measured, and carries none. |
| `processes_threads_created` | integer | as above | How many thread creations the recording run's account recorded — a floor: a raw `clone` leaves no record (the `processes` row above). |
| `processes_writer_threads` | integer | as above | How many thread ids of the subject's own process wrote the judged directory in the recording run, counted from the records the observer left. Every record names its thread, so no recorded write is missed; a write the observer never saw — a raw syscall under `--observe wrappers` — leaves no record and is not counted. `1` is one recorded writing thread. |

## The judged set (runs that reached classification)

Which paths the built-in atomicity form judged, as data rather than as a count
(#638, ADR 0079). `l0` above says how many and in which two forms; these say
which. Two fields added after the v1.0 tag, under the additive allowance
surface 2 of `docs/contract-freeze.md` keeps open.

Both are present on any run that reached L0 classification and absent together
on any run that did not — a SETUP ERROR raised before the define was read, or a
refusal ahead of the classification. A run whose judged set is legitimately
empty, which is what a define declaring everything `scratch` produces, carries
an empty array rather than no field: "nothing was judged" and "nothing
classified" are different facts and the report does not spell them the same way.

| Field | Type | Present | Meaning |
|---|---|---|---|
| `l0_judged_paths` | string[] | the run reached L0 classification | The paths the built-in atomicity form judged, relative to the state directory, in the snapshot's sorted order — read from the same plan the judgement reads (ADR 0004), so the report cannot name a set other than the one that ran. **It is not "everything under the state directory":** a path enters only where the pre and post snapshots BOTH hold it and both kinds are ones the built-in invariants compare, and never where `scratch` declared it. So a file the operation created, a file it deleted, and a FIFO or socket are all outside it — the first two legitimately (they may be absent mid-flight), the third because a comparison of unreadable content would be agreement about nothing. **At most 1000 entries and at most 64 KiB of path names, whichever binds first**, with the rest counted by the field below. The byte ceiling is the one that bounds the document: a thousand names may be four megabytes before escaping, and the MCP server answers a report over 4 MiB with a tool error rather than a verdict. |
| `l0_judged_paths_omitted` | integer | the run reached L0 classification | How many judged paths `l0_judged_paths` does **not** list. Zero is the common case and says the array is the whole set. Non-zero is the reading that matters: the array is then a **prefix** of the set in that same sorted order — as far as the two ceilings allowed, or empty if the report could not allocate the names at all — and **this report does not name the judged set**. A number rather than the absence of a phrase, for the reason `paths_attributed_to_rename` is one. A define judging more than a thousand paths is not one a person is authoring by reading the list; the remedy the number points at is narrowing the state directory, not paging through the array. |
| `l0_judged_paths_touched` | integer | the recording's trace passed every check on it — measured after the last of them (the per-path reconciliation and, for a contained run, the cgroup's account), so a refusal on a trace cut short, too large, of another contract or not finished carries none | How many of the judged paths a crash world could have shown changed: those that ended other than they began, or that a crash point other than an `fsync` or a `mkdir` named, or whose directory a `rename` named (ADR 0091). **Zero beside a non-empty `l0_judged_paths` is the reading this exists for** (#683): the atomicity invariant held over paths the operation never touched, and on an exploration's PASS it was the checker or the marker that judged the run (a replay's PASS is not gated this way and can carry zero with neither) — the headline says so in a clause ("but the operation touched none of the N path(s) it judged"). On an exploration with nothing else to judge, zero is why the run was refused `nothing_could_fail`. Written after the two fields above, so it moves none of their bytes. A field added after the v1.0 tag, under the additive allowance surface 2 of `docs/contract-freeze.md` keeps open. |

## Reading it from the MCP surface

`sideeye_explore_config` and `sideeye_replay_case` return this same document as
the tool result's `structuredContent`, minified. `isError` is derived from
`verdict`: a real verdict (PASS/FAIL) is `isError: false`; every refusal
(UNKNOWN, SETUP_ERROR) is `isError: true` — retry after doing what `next_step`
says and fixing what the `message` names, don't parse the error text (ADR 0010).
`observe_syscalls` (#599) names `--observe syscalls`, which an agent can follow
through the MCP server as well: `sideeye_explore_config` takes an optional
`observe` (#617, `docs/mcp.md`).
A SETUP_ERROR says which class it is in `setup_error_reason` (#518), and a
failing setup's status in `setup_exit_code` / `setup_signal`; branch on those,
never on the sentence. The text block's first line carries the class the way it
carries `unknown_reason` — `SETUP_ERROR (setup_failed):` — ahead of the marked
region, since it is a closed set the engine spells. It carries `next_step` too,
as a `next:` line after the marked region and before `case`/`replay`.

## Preflight's document (`preflight --json`)

<!-- schema: sideeye/preflight -->

`sideeye preflight --json <path>` writes one of two documents (#717, ADR 0102). When
preflight **refuses** or **cannot set up**, it writes the report above, `sideeye/report`,
carrying the refusal its text block shows — `verdict`, `unknown_reason` or
`setup_error_reason`, `message`, `next_step`. That is usually the refusal `explore` reaches
on the same define, and not always: with no crash point and neither `--oracle` nor
`--allow-unverified`, `explore` answers its completeness gate first and preflight, which has
none, answers `nothing_could_fail`
([docs/cli.md](cli.md)); a recovery reads `declared; preflight runs no recovery`; and some
messages name preflight's own limits. When it **accepts
the recording**, or when `--twice`'s two runs **differ**, it writes the document below:
preflight produces no verdict, and `verdict` is a closed set of four, so these two
outcomes are not a report. Branch on `schema` first, as the envelope says to.

The document is written the way the report is — whole or not at all, sealed on stderr with
the same `sideeye: json sha256=…;` line — and it carries what the text block prints as data:
the account sentences under the report's own names (`expected_status`, `command_cwd`,
`command_cwd_declared`, `l0`, `oracle`, `recovery`, `processes`, the figures beside them
from `oracle_witness` to `processes_writer_threads`, and `apparatus`, `scratch`,
`define_warnings` when the define declared them), each meaning what its row above says,
and the judged set (`l0_judged_paths` and the two counts after it), last, as in the report.
The `note` and `next` lines are advice for the command line and are not in it.

**No byte of a differing stretch is in it.** Under `--twice` the text block quotes where
two runs' bytes first differ; this document carries the same line without the quotes —
where, how long and what kind — because what a CI log or an MCP answer keeps is where a
per-run token or secret would sit. A path is still named, as the refusal names one.

| Field | Type | Always | Meaning |
|---|---|---|---|
| `schema` | string | yes | The literal `"sideeye/preflight"`. |
| `schema_status` | string | yes | `"frozen"` from its first release, under the same rule as the report's: fields may be added, none removed or redefined (`docs/contract-freeze.md`, surface 2). |
| `outcome` | string | yes | `"recording_accepted"`, or `"runs_differ"` when `--twice`'s two runs left different state. |
| `exit_code` | int | yes | The process's own: 0 accepted, 1 runs differ — the negative answer to the question `--twice` asked, not a FAIL. |
| `crash_points` | int | yes | The state-changing operations the recording observed — the count the headline names. Never 0: a recording with none is refused `nothing_could_fail`, and that refusal is a report. |
| `marker_observed` | bool | no | `true`, present only when the define declared a `marker`: a marker that never appears is refused before this document is written. |
| `not_checked` | string[] | yes | What only an exploration runs, as the text's `not checked` line lists it. |
| `repeat_gap_ms` | int | `--twice` | Milliseconds between the two runs' starts, measured. |
| `differences_total` | int | `--twice` | How many paths differ, including any past the ones listed. |
| `differences` | object[] | `--twice` | One `{path, how, shape?}` per differing path the comparison stored: `how` is `only_in_first`, `only_in_second`, `kind_differs` or `content_differs`; `shape`, on the first eight `content_differs` paths, is where the two runs' bytes first differ, how long each differing stretch is and what kind of bytes it holds — the text's `bytes` line without its quotes, and never a byte. The text names paths up to a byte budget, so this list can name more. Empty when the runs agreed. |
