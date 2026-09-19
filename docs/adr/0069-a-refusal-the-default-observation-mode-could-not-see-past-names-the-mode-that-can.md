# 0069 — A refusal the default observation mode could not see past names the mode that can, and a run under that mode is not sent to change its define

Status: Accepted (2026-09-16)

## Context

Under `--observe wrappers`, `oracle_missed_operation` means the oracle saw a state-directory
operation the shim did not record. Its `next_step` was the class wall — "This target does something
Sideeye refuses by design" — and #599 records what that cost: a zstd run was read as the stdio wall,
and the cause only appeared after re-measuring under `--observe syscalls`. `docs/report-schema.md`
says the step is "chosen at the site that raised the refusal, where the cause is known", and lists
passing a flag among the actions it may name.

The issue offered two directions: name `--observe syscalls` when the diverging operation's thread was
never recorded writing and more threads were created than recorded writing, or leave the step and add
the distinction to the message. Both were measured against, not argued, on `d5911cd` (contract v18,
strace oracle):

| input to `zstd -q --rm` | wrappers | thread account | `--observe syscalls` |
|---|---|---|---|
| 300 KB of `/dev/urandom` (`spike/followup-item4`) | `oracle_missed_operation` | 2 created, 1 wrote | PASS 9/9, the oracle agreeing on 8 operations |
| 400 KB of repeating text (#599's define) | `oracle_missed_operation` | 2 created, 1 wrote | `multiple_threads_detected` |

The two refusals read the same and carry the same thread account. In both, the operation the shim
missed is a write issued from inside `fwrite` — ADR 0005's far side. A second thread's write through
the PLT is recorded under `--observe wrappers` with its thread id, and stops at `main.zig`'s
`second_writer_thread` check before the oracle comparison, so the wrappers-mode refusal is about an
operation that bypassed the interposed entry points, not about which thread made it. What differs is
what `--observe syscalls` finds behind it, and nothing the wrappers observation holds says which.

## Decision

1. **`oracle_missed_operation` under `--observe wrappers` on Linux takes `observe_syscalls`**: run
   explore or preflight again under that mode, which counts most operations at the kernel boundary,
   including ones that do not pass through libc's interposed entry points — not all: a raw
   `copy_file_range` or `pwritev2`, a syscall ABI the filter cannot read, an image the shim is not in.
   Under `--observe syscalls`, or off Linux, the step stays the class wall.
   `boundary.missedOperationNext` chooses it from whether this is Linux, not from asking the kernel
   whether it offers the trap. Asking is a `seccomp(2)` call, which the default mode had never issued,
   and it would be issued on a refusal path: under an outer filter that kills on `seccomp` the engine
   would die before the report was written. A Linux kernel without the trap answers the flag with
   `platform_unsupported`, which says what is missing. (The first implementation asked the kernel;
   review found the new syscall.)

2. **The sentence promises neither a verdict nor a cause**, and says nothing about what a refusal
   under that mode would name. Of a run that then fails, it says the mode *may* have killed a process
   or otherwise changed what the target does: a helper that loses privileges to the
   `PR_SET_NO_NEW_PRIVS` the mode sets, and a target that does not repeat, fail the same way with
   nothing killed (review caught a first draft that said "a process was killed"). `docs/report-schema.md`'s section on what that mode does not see says
   of the processes it kills that "None of this has a refusal of its own", and a subject that dies of
   `SIGSYS` is `recording_run_failed`, which names nothing it could not see.

3. **The caution rides in the same sentence, every time.** That mode changes what some targets do: a
   child that execs an image the shim is not loaded into dies at its first state-changing call, and so
   does a `posix_spawn` child whose file action opens for writing — before it execs, so nothing about
   the image is there to read. No field of the account says a run has such a child
   (`parsed.children` counts children that were fine; `shim_boundary` is set by a thread, which #599's
   own zstd has; `children_admitted` is set only when a child wrote; `exec_continuations` is the
   subject's own exec). A step that added the caution only when it could tell would drop it exactly
   where it is needed. The sentence names the README entry under 'What the target has to be' that
   begins "Under `--observe syscalls`, a process whose `SIGSYS` is blocked or reset", and
   `docs/report-schema.md`'s section on what that mode does not see, instead of restating them: every
   paraphrase drafted was narrower than the list, and a narrower list reads as "the shim is loaded
   into mine". The README entry is the one that names the processes the mode kills;
   `docs/report-schema.md`'s section does not describe the most common of them (a child that execs an
   image the shim is not loaded into), which is why the second step below names the README entry and
   not the section.

4. **The failures a process the mode killed produces under `--observe syscalls` take
   `syscalls_may_have_killed`** where they would take `fix_define` (`boundary.fixDefineUnder`): the
   recording run's undeclared exit status, its signal and its missing success marker, and the
   baseline world's checker rejecting the state. A child the mode killed produces each: the parent
   exits with the child's status, or ignores it and exits as declared with the child's marker never
   printed or its work missing from the state. Each site's own sentence points at the define —
   declare a different success convention, check the marker string, check the operation and the
   checker against each other — and a reader sent to `--observe syscalls` by decision 1 who followed
   it would have a broken run judged. Today that reader stops at the class wall; decision 1 opens the
   path, so it closes here. The comparison the step asks for is partly by hand: an explore under the
   default mode refuses `oracle_missed_operation` before its checker runs, so the checker is run on
   the state that mode leaves.

   Not the 126 branches (`environment`, the engine's fork stub). Not `preflight --twice`'s second
   run, the baseline's exit or the baseline's marker layer: each compares against a recording the same
   mode already completed, so a kill that happened in both runs does not reach it, and what does is
   repeatability — the marker layer judges the baseline against the recording's own final state. The
   checker is the exception because it judges from outside: the falsification probe shows it only a
   corrupted state, so the baseline is the first clean state it sees, and a gap present in both runs
   is red there. A first implementation took the second run too, and a second left the baseline's
   checker out with a reason that did not hold for it; review found both. The sentence does not
   branch on the subject's own `SIGSYS`: that one is detectable, a child's is not.

## Alternatives considered

- **The issue's first direction, by thread account or thread id.** The two measured runs share the
  account, and the missed operation is the same kind in both; an id read back out of the oracle's raw
  line (strace's starts with a thread id, fs_usage's with a timestamp — the parse #337 avoided) cannot
  separate what the wrappers observation does not contain. And the action it would choose is this one.
- **The issue's second direction, the message only.** The promise in `docs/report-schema.md` is about
  `next_step`.
- **A different `unknown_reason`.** The wrappers observation cannot decide between the rows above, and
  which member a run refuses with is a machine field's meaning (`docs/contract-freeze.md`, surface 2).
- **The caution only on runs with children or an image replacement.** Decision 3.
- **The caution in `observe_syscalls` alone.** A caller that branches on `next_step` reads each report
  on its own, so a caution in the wrappers report does not reach the syscalls one. Decision 4.
- **The wrappers mode seeing inside libc.** ADR 0005's boundary; `--observe syscalls` (ADR 0052) is
  the answer to it.

## Consequences

- Two `NextStep` members, `observe_syscalls` and `syscalls_may_have_killed`. `next_step` is not a
  closed set (`docs/contract-freeze.md` closes `unknown_reason` and `setup_error_reason`); no
  `unknown_reason` changes.
- Not taken here, with the reason each stays out: `childrenMayBeJudged`'s unattributed writer — strace
  treats the subject's threads as the subject, so what remains at that site on Linux is another
  process the shim did not record, a raw fork or a child the shim is not loaded into, and the second
  is the process `--observe syscalls` kills **(narrowed by ADR 0076, 2026-09-19: the site gets the
  step for the one shape where the writer's own shim announced itself and recorded no operation —
  measured on lbdb — and keeps the class wall for the writer with no shim in its image, which is
  the process this sentence is about)**; `state_changed_unaccounted` and
  `state_changed_without_ops`, which see a change without its origin, so another process's write
  looks the same; `oracle_saw_phantom`; macOS, which has no such mode.
- The MCP server passes no `--observe` and a `sideeye.toml` has no key for it, so through the server
  `observe_syscalls` is advice for the command line (`docs/mcp.md`). **(The first half is superseded
  by ADR 0074, 2026-09-18: `sideeye_explore_config` takes an optional `observe`, so an agent can
  follow this step through the server. The second half still holds — the config format has no key
  for the mode.)**
- `--observe syscalls` also sets `PR_SET_NO_NEW_PRIVS`, which a setuid or file-capability helper
  would notice; no document lists it and it was not measured. The sentence is written so it does not
  read as a complete list.
- The acceptance suite reads the steps off real runs: the wrappers-mode stdio toys, which the
  following legs judge under `--observe syscalls`; a `/bin/sh` wrapper that runs the static toy under
  that mode, which the filter kills — the leg asserts the `exited 159` it is killed with, not only the
  refusal it lands in; and the same toy behind a wrapper that records its child's status (159) and
  exits 0, whose marker the kill suppresses. The baseline's checker layer has no such leg — it needs a
  child killed before its first state operation behind a parent that exits as declared, with a
  checker that sees the missing work — so a grep holds that the engine still asks `fixDefineUnder`
  there, the second opinion #544 uses, to be deleted when a leg drives it. The suite also holds that
  the places the steps quote exist as the steps quote them, with backticks and bold removed.
- Not taken, besides those listed above: the other `fix_define` sites. `checker_not_falsified`'s
  empty state counts the state before the operation runs; its other two branches are about a checker
  the engine starts, outside the target's filter; `kill_did_not_land` (the operation numbering
  differs between runs, or a world did not die where it was asked to) compares runs of one mode.
- A define with no checker and no marker can still be judged without a killed child's work, as
  `docs/report-schema.md` says of this mode; no step is raised there to change, and it was not
  measured.
