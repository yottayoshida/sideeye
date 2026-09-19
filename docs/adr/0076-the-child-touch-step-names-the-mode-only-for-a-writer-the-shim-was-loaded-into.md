# 0076. The `child_touched_state_dir` step names `--observe syscalls` only for a writer the shim was loaded into

Status: Accepted (2026-09-19)

## Context

`child_touched_state_dir` stands at two walls (#634). Measured on the three targets the g3
sweep refused this way, each run once per observation mode
(`spike/followup-child-touch-modes/`, #628): `lbdb` reaches PASS over 8 crash points under
`--observe syscalls`, while `pacpl` and `mail-expire` refuse in both modes with byte-identical
reports. The engine knows which condition stopped a run — `childrenMayBeJudged` returns the
sentence for it — and until now said the same step to both.

**ADR 0069 declined exactly this step at exactly this site**, and its reason is still true:

> `childrenMayBeJudged`'s unattributed writer — … what remains at that site on Linux is
> another process the shim did not record, a raw fork or a child the shim is not loaded into,
> and the second is the process `--observe syscalls` kills

The kill is not a nuisance. A filter is inherited across `exec` while the `exec` resets the
handler that makes it survivable, so an image the shim cannot be loaded into dies at its first
state-changing call (`src/cli.zig`, measured: exit 0 under wrappers, SIGSYS under this mode).
`docs/report-schema.md` case 4 says what follows: a child whose death the target survives ends
without a refusal, and **a child whose work was inside the state directory would leave the run
judged without that work** — a case that page marks as not measured. Sending an operator there
would trade an honest UNKNOWN for a possibly silent verdict.

A second promise stands on the unchanged step. `spike/acceptance.sh` holds two legs to it
(#506): this refusal is the published wall for the "Shell CLIs over helper processes" class,
whose members *are* shell scripts, so the step has to keep asking whether the operation is a
wrapper.

## Decision

The step names `--observe syscalls` only when the writer is running an image **the shim is
in**: its last `exec`-or-`shim_ready` record is a `shim_ready`, and it recorded no operation of
its own. Everything else keeps the step it had — a writer with no records, and one that
announced itself and then exec'd away.

The discriminator is the trace, read as a question about the **image** rather than the pid.
Every record the shim writes reaches `engine.TraceInfo.ops`, kill point or not. `exec` is
recorded by the image that calls it, *before* the call, so an `exec` from a pid says only that
some image in it called one — the next image may be the one the mode kills. `shim_ready` is
written by a shim that has initialised. So the shim is in the writer's current image iff the
last of the two, in trace order, is a `shim_ready`.

`lbdb`'s child is the positive case: the shim records its `exec` and then its `shim_ready`,
and no operation, because it flushes a buffered stdout at `exit()`, which leaves libc without
crossing the PLT (ADR 0005) — measured 2026-09-08 and recorded in `docs/target-classes.md`'s
row for that target. (`spike/followup-child-touch-modes/NOTES.md` said that child "never loads
the shim"; that sentence is wrong and now carries a correction.) `TOY_SPAWN_WRITES` is one
negative case — `posix_spawn` of `/bin/sh` with an **empty environment**, so no shim and no
records — and a child that announces itself and then execs a static helper is the other: the
first draft of this rule asked only whether the pid appeared, and would have sent that one to
the mode.

The guard `missedOperationNext` uses stays on top of that: not when the run is already in the
mode, not off Linux, where the flag answers `platform_unsupported`.

## Alternatives Considered

**Name the mode for every unattributed writer.** The first implementation of #634, and what
ADR 0069 declined. It sends the shell-script population to a mode that kills the helper the
refusal is about, drops the wrapper question the class needs, and turns two acceptance legs
red — the legs are the detector that caught it.

**Change nothing and leave the finding in prose.** The wall `lbdb` crossed is crossed by a
flag this repository ships and documents, and the refusal would still not say so.

**Split the reason instead of the step.** Two `unknown_reason` values, or a field naming the
condition, is the fuller answer. `unknown_reason` is closed by `docs/contract-freeze.md`
(surface 2), so it is a separate decision; `next_step` is not closed, and `observe_syscalls`
is an existing member named at a second site. #634 keeps that question open.

## Consequences

- A refusal at the measured wall names the step that crosses it; every other shape keeps the
  wrapper question, so #506's promise and its two acceptance legs are untouched.
- `spike/unknown-rate/launchers/bgroup.sh` runs a second leg whenever leg 1's step opens with
  that sentence, so a future sweep will now measure such a target in both modes by itself.
  That is the behaviour the g3 sweep already had for `oracle_missed_operation`.
- "The shim is in this image" is evidence about the child at the moment the trace ends, not a
  guarantee about the whole target: the mode's other requirements still apply, and the step's
  own sentence sends the reader to them before running it. An image that loses the shim after
  the last record this test reads is outside what the trace can say.
- The refusal's sentence follows the wall too: telling a reader the child "never loaded the
  shim" while the step says to count its writes at the kernel boundary would be two answers to
  one question.
- The rule is pinned by three fixtures that differ by one record each — the writer with no
  records, the same writer announcing itself, and that one exec'ing away afterwards — and by
  the step's table. The call site is covered by the acceptance legs for the unchanged shapes
  only; nothing here exercises the changed step end to end, because no toy produces `lbdb`'s
  shape.
