# 0090 — A static target named by a bare name is read off `PATH`, and its refusal names `--observe supervised`

- **Status:** Accepted (2026-09-29)
- **Amends:** ADR 0040's `no_shim_marker` bullet (which images take the wall), and ADR 0089's
  Alternatives entry "A `next_step` naming this mode for a static target" and its Consequence 7
  ("no new `next_step`"). Both amendments are recorded on those pages as dated notes pointing here.
- **Refs:** the 2026-09-28 dogfood (`spike/dogfood/2026-09-28-shipped-v170/RESULTS.md`, revision 1)
  and the 2026-09-29 measurement of hashicorp/terraform#39303 (`transcripts/terraform-39303/default-*.txt`),
  where the same refusal was met again.
- **Scope:** `src/image.zig`, `src/posix.zig` (`isExecutableRegular`), `src/supervise_linux.zig`,
  `src/boundary.zig`, `src/contract.zig`, `src/main.zig`, `spike/acceptance.sh`,
  `docs/report-schema.md`.

## Context

`docs/cli.md` says of `--observe supervised`: "A statically linked target, which the other two
modes refuse as `no_shim_marker`, is counted and reaches a verdict under this mode." The refusal
does not send anyone there.

- Named by a bare name, as a user writes it (`terraform fmt`), the operation's image is never read.
  `image.observe` returns `not_resolved` for a first word without a slash, and `noShimNext` keeps
  the shim step — the behaviour `docs/report-schema.md` documents ("a first word resolved through
  `PATH` … keeps the shim step"). The next sentence says to check `--shim`.
- Named by path, the image is read, and the detail line names `--observe supervised`, but
  `next_step` is `class_wall`: "This target does something Sideeye refuses by design". The two
  lines of one refusal disagree.

Two decisions produced this, and each had a reason.

1. `image.zig` does not search `PATH`, so that `execvp`'s rule has no second copy in the tree that
   could drift and name the wrong file with confidence. Since #217 it has one:
   `supervise_linux.zig`'s `resolveExecutable`, which `__filter-exec` uses to find what it execs.
2. ADR 0089 declined a `next_step` for this mode because "the step set is closed (frozen surface
   2)". It is not. `docs/contract-freeze.md` surface 2 closes `unknown_reason`, and
   `setup_error_reason` is the other closed set; `next_step` is neither. ADR 0069 recorded the same
   ("`next_step` is not a closed set") when it added `observe_syscalls`.

## Decision

1. **One `PATH` search, used by both callers.** A function taking the name, the `PATH` value and a
   directory for relative components, returning the first regular file with execute permission;
   an empty component is `.`. `getenv` stays with the callers. `__filter-exec` passes its `PATH` or
   its existing six-entry default, and no directory (it has already changed into the operation's
   cwd). `image.observe` passes the engine's `PATH` — the operation inherits it; the engine sets
   only its own variables in the child, and `apparatus` `env:` entries are checked, not applied —
   and the define's `cwd`. **With `PATH` unset, `image.observe` does not search**: glibc and musl
   default differently and the engine does not know which one will exec.
2. **What the search finds is read the way a path is read**, with the same rule that the reading is
   not a claim about what ran. The detail line says the file was found along `PATH`. A name the
   search does not find stays `not_resolved`, with two sentences instead of one: `PATH` was unset
   and nothing was searched, or it was searched and nothing was found.
3. **`NextStep.observe_supervised`.** `noShimNext` takes the observation mode and whether this
   build can supervise (`supervise.available`: Linux on aarch64 or x86_64, a compile-time fact),
   much as `missedOperationNext` takes whether it is Linux. Under `--observe supervised` the step
   is `environment`: a trace without a start record there means the engine could not write its
   own trace, which the detail line says. A statically linked 64-bit ELF under `wrappers` or
   `syscalls`, in a build that can supervise, takes `observe_supervised`; its sentence says to run
   the same command again with the flag, since a replay reaches this refusal too. Everything else
   keeps its step: a 32-bit static ELF (supervised does not see i386-compat or x32 calls,
   `docs/cli.md`), a static ELF in a build without the mode, and the Mach-O walls take
   `class_wall`. The kernel is not asked for its version, for ADR 0069's reason; below 5.19 the
   flag answers `platform_unsupported`.
   **Amended 2026-10-10 (ADR 0108):** `no_shim_marker` is not the only refusal sent to that mode for such an
   image. When a dynamic child carried the shim past the gate, `oracle_missed_operation`, the recording run's
   `unresolvable_path` and `child_touched_state_dir` take `observe_supervised_static_parent` in the shapes
   ADR 0108 measured, through the same image predicate.
4. **The detail line states the linkage and no longer names the mode.** The clause was there
   because the step could not say it.

When `--oracle` is given the child execs strace, and strace searches `PATH` for the operation;
that search is strace's, and this one agrees with it only as far as both follow the `execvp` rule.
`refuse.zig`'s `findStraceForHint` is a third search with another purpose (a hint naming strace)
and is left alone.

## Alternatives considered

- **A sentence on the bare-name detail line: name the image by path to have it examined.** The
  user runs again to learn what the engine could have read the first time.
- **Fix only `class_wall` and keep the mode in the detail line.** The bare name still gets the shim
  step.
- **Add the search to `image.zig` alone.** Two copies of the rule in the tree, the drift
  `image.zig` was written to avoid.
- **Ask the kernel whether it can supervise.** A new call on a refusal path.

## Consequences

- Bare names are read on every platform, so other arms move to what the image shows: on macOS an
  Apple-shipped binary named bare (`git`) takes `class_wall` instead of the shim step; a bare name
  that is a `#!` script takes `operation_not_an_image`; `preflight --twice`'s second-run detail can
  report that a bare name's file reads differently now. Listed in CHANGELOG.
- One `NextStep` member; no `unknown_reason`, no report field, no `contract_version` change.
- `docs/report-schema.md`'s `no_shim_marker` paragraph is rewritten to say what the step is for a
  bare name.
