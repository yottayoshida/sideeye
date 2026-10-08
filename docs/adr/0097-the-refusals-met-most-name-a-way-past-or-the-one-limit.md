# 0097 — The refusals met most name a way past them, or the one limit they stand at

Status: Accepted (2026-10-08)

Closes #710. Amends ADR 0040, whose framework this keeps: the step is chosen at the site that
raises the refusal, from what that site observed, as a payload-free member of
`contract.NextStep` with a comptime sentence. Numbered 0097 by agreement with the session working
#688–#690 at the same time (it takes 0098 onward).

## Context

Two members of `NextStep` name no action. `fix_define` says "the detail above names the
declaration this run contradicted" where, at several sites, the detail names none; `class_wall`
says "'What the target has to be' in the README names each limit", which is the whole list.
#710 measured both on a first-time operator's path, and asked that the refusals met most be
ranked and given a step that names a flag, a key or a command.

**Counted for this change** from the reports the dogfood records point at
(`spike/outcome-funnel.tsv`, every row whose outcome is UNKNOWN: 89 rows, 73 readable reports; the
other 16 point at selection notes). Each reading was taken back to the site that raised it on
today's build, since the records hold the sentence of the build that ran them:

| Reason (count) | Site, today | Step before | Step after |
|---|---|---|---|
| `multiple_threads_detected` (37) | recording, world, second run | `class_wall` | `threads_limit`; under `--observe supervised`, `class_wall` |
| `unsupported_syscall_observed` (10) | xattr reads and `inotify_add_watch` (read as reads since #684), a shared mapping (#689), `setxattr` (refused on purpose, unruled) | `class_wall` | unchanged — exception |
| `baseline_violates_invariant` (6, all the byte layer) | baseline world | `class_wall` | `scratch_or_twice` |
| `oracle_missed_operation` (5) | recording: 4 in the default mode on Linux; 1 under `--observe syscalls` (lefthook, a static parent whose dynamic child announced the shim) | `observe_syscalls`; `class_wall` | the first unchanged — already names a flag; the second an exception, #685's |
| `unresolvable_path` (4) | a write through a file the target removed; a target that closed the trace | `class_wall` | unchanged — exception |
| `kill_did_not_land` (3) | 2 where the operations before k differ, 1 where no landing was recorded | `fix_define` | `not_repeating`, `kill_not_landed` |
| `recording_run_failed` (3) | 2 in `preflight --twice`'s second run, 1 under `--observe syscalls` | `fix_define`, `syscalls_may_have_killed` | `second_run_diverged`; the syscalls one unchanged |
| `no_shim_marker` (2) | a static ELF on Linux | `observe_supervised` | unchanged — already names a flag |
| `child_touched_state_dir` (2), `child_process_detected` (1) | | `unwrap_or_class_wall` | unchanged — already a question and a way past |

The operator pass (2026-10-05, macOS arm64, the brew v1.8.0 binary) met `recording_run_failed`,
`baseline_violates_invariant` and `no_shim_marker`. Two of its three shapes were closed by
siblings before this change (#700's `declare_cwd`, #701's refusal before the run); the third, an
Apple-signed image, and the recording run's own two endings are in the decision below. Measured on
this machine, 2026-10-08, with v1.9.0: `/bin/cp` refuses `no_shim_marker`; an ad-hoc re-signed
copy of it is killed by the system as it starts, and the run said "Change the define: the detail
above names the declaration this run contradicted" beside a detail that named none; Homebrew's
`xz` is accepted.

## Decision

**Every site those refusals were met at says what this run observed to do next: a flag, a define
key or a command where this build has one, and otherwise the one README limit the run stands at.**
Eight members, each chosen from an observation the site already holds and from one fact about
the restore (it rebuilds the names, kinds and bytes under `--state`, not their modes, owners or
timestamps, and nothing outside it):

- `run_then_expect_status` — the recording run's exit status nobody declared (126 aside): run it
  by hand first, then `--expect-status` if that status is the tool's success. The order is the
  point: declaring a failure's status would have the failure judged, the reasoning that keeps 126
  off the flag.
- `run_by_hand_signalled` — the recording run ended without an exit status. The detail now names
  the signal; the step says nothing a define declares accounts for it, names the README's limit
  'A clean run exits its declared success status', and says that on macOS a SIGKILL at start can be
  the system refusing an image's signature.
- `second_run_diverged` — `preflight --twice`'s second run ended differently from the first,
  from a state the restore rebuilt: what differed is a mode the tool checks, something outside
  `--state`, or something that does not repeat. Both records (upx, argocd) were the first.
  The diff's first review caught a wording that said "outside `--state`", which those two
  contradict; `not_repeating` and `kill_not_landed` say the same about modes for the same reason.
- `scratch_or_twice` — the baseline's byte layer: `scratch` for a path whose bytes are not the
  verdict's business, `preflight --twice` to name the paths that differ.
- `kill_not_landed` — no landing recorded at k. Only that, so the step names the measurement and
  keeps Sideeye's own side open; it does not say the world did fewer operations.
- `not_repeating` — the world reached k through other operations: observed, so the step can say
  the operation does not repeat itself.
- `threads_limit` — names the README's threads limit. No flag: the targets the records met here
  (node, Go, Python) have none that runs them on one thread.
- `non_system_build` — a Mach-O whose code directory names a platform: a build of the tool that is
  not part of macOS. Library validation and the hardened runtime on a third-party image were not
  measured and keep `class_wall`.

Precedence is unchanged: under `--observe syscalls` the recording run keeps
`syscalls_may_have_killed`, and a toml with no `cwd` whose command read an argument from the
toml's directory takes `declare_cwd` over the recording run's two new steps, as it did over
`fix_define` (`refuse.cwdStep`).

**Four exceptions, named rather than left to look covered**, where this build's step names no way
past and no README line names the limit: `unresolvable_path`, `unsupported_syscall_observed`,
`multiple_threads_detected` under `--observe supervised`, and `oracle_missed_operation` under
`--observe syscalls`. Two of them hold a shape with a way past this build does not yet choose: a
static parent whose writer is a dynamic child — lefthook under `oracle_missed_operation`, judged
PASS 5/5 under `--observe supervised` on 2026-10-02, and roswell under `unresolvable_path`
(2026-10-07) — which #685 is to send to `--observe supervised` from the image the engine already
read. The diff's first review found the lefthook row, which the first wording of this decision
had read as the default mode's; the owner kept #685 its own issue (2026-10-08).

## Alternatives considered

- **Remove `fix_define` and `class_wall`**, so the compiler makes every one of their sites choose.
  Not taken: most of those sites appear in no record, and a step written for a refusal nobody has
  met is written without an observation — the guess about causes ADR 0030 declined. This change
  covers what the records met; a site the records meet next gets its step the same way.
- **One sentence per reason.** Declined in ADR 0040 and still wrong: two of the reasons above
  were met at two sites each with different observations.
- **"Add a flag that runs it on one thread"** for `multiple_threads_detected`. Not taken: it names
  a flag most of the targets do not have.
- **"Report the call to Sideeye's tracker"** for `unsupported_syscall_observed`. Not taken: a
  shared mapping is a recorded limit and `setxattr` a deliberate refusal awaiting a ruling, and
  neither is Sideeye's gap in the sense the sentence would claim.

## Consequences

- Eight `NextStep` members; `next_step` is not a closed set (ADR 0069), so the report schema
  gains nothing to freeze. `docs/report-schema.md` says where each applies.
- `recording_run_failed`'s message names the signal on a run that ended on one, after the words
  it always began with.
- The dogfood entry gate (`spike/dogfood/*/apparatus/entry.sh`, ADR 0085) sorts a refusal by the
  start of its `next` line; the new sentences start differently, so the next campaign's copy of
  that script has to learn them. The committed campaigns' copies are records and stay as they ran.
- The walls the records met most now name their limit; the exceptions above are the next places
  a step would come from, once the build has something to name there.
