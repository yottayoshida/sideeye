# 0052 — Writes are observed at the syscall boundary on request

Status: Accepted (2026-09-07)

## Context

ADR 0005 decided to observe buffered stdio at *flush* granularity, on the reasoning that a
flush normally issues exactly one `write(2)`, and it named the case that breaks the
reasoning: a large `fwrite` writes from **inside** libc, past every function an
`LD_PRELOAD` shim can interpose. The same ADR argued the consequence was acceptable
because it fails toward refusal — "on Linux everything outside this reaches
`oracle_missed_operation`. No failure mode of this design reaches a wrong verdict."

That argument still holds. What changed is how much it costs. `docs/target-classes.md`
records metaflac 1.5.0 and fontforge 20230101 refusing there, and the shape is not exotic:
`fwrite` past the buffer is the ordinary way a C program writes a file of any size. The
refusal is honest and the reach is narrow, so the question is not whether the boundary was
drawn correctly — it was — but whether a second observation path can be added without
disturbing the first.

Measured on this branch, with the engine's own defines:

| target | `--observe wrappers` | `--observe syscalls` |
|---|---|---|
| metaflac 1.5.0 | `UNKNOWN oracle_missed_operation`, 0 crash points | **PASS over 12 crash points**, oracle agreeing on 12 operations — in 3 of 5 runs |
| fontforge 20230101 | `UNKNOWN oracle_missed_operation`, 0 crash points | **FAIL, 183 of 185 worlds**, 184 crash points, oracle agreeing on 184 operations over 40187 syscall lines — in 2 of 3 runs |

The runs that do not reach a verdict refuse `unresolvable_path` (a descriptor whose file was
unlinked while open) rather than answering wrongly. An earlier revision of this paragraph called that the class recorded for mutool; it is not — `docs/target-classes.md` records mutool's cause as unattributed, and its write path is `unlinkat` then a fresh `openat`, which is a different descriptor. The default mode is
itself non-deterministic on metaflac — 2 of 3, with `kill_did_not_land` for the third — and
`preflight --twice` reports equal state in both modes with stable operation counts, so what
varies is the operation path rather than the bytes. Unattributed, and stated rather than
smoothed: what these numbers support is that the mode **reaches** verdicts the default path
cannot, not that either target is stable under it.

fontforge's is a real defect in a real tool: `Generate()` rewrites the font in place, so a
crash inside the write leaves a file its own `Open()` cannot read.

## Decision

**A flag, `--observe wrappers|syscalls`, default `wrappers`.** The syscall path installs a
seccomp filter answering `SECCOMP_RET_TRAP` for `write`, `pwrite64`, `writev` and
`pwritev`, and the shim's `SIGSYS` handler counts each trapped call **through the same
`noteFd` the interposed wrappers use** before re-issuing the syscall itself. Contract
version 14; `shim_ready`'s `aux` — empty through v13 — carries the installation result.

Four decisions inside that, each bought with a measurement:

**1. The trap set stops at the write family.** A set containing `openat` kills the process:
the new image's `ld.so` opens libraries before any constructor has installed a handler, and
an unhandled `SIGSYS` is fatal (measured: exit 159). It is also unnecessary —
`target-classes.md` records precisely what is missing for the stdio targets, "the shim
recorded the `open` and no `write`". So raw `openat`, `rename` and `unlink` stay refused in
both modes, and cargo (#217) is **not** released by this work.

**2. The re-issue is marked in an argument register, not by its address.** The thunk leaves
a 64-bit sentinel in the sixth argument register and the filter allows any call carrying
it. The address-keyed alternative was measured dying across `execve`: seccomp filters are
inherited and cannot be replaced, so a filter holding the old image's thunk address makes
the new image's handler recurse to a stack overflow (exit 139). A `MAP_FIXED` thunk was
rejected for a worse reason — it silently unmaps whatever already lives there, which after
an exec is the target's own memory, and `oracle.zig` treats `mmap` as read-only so no
witness would see it. None of the four trapped syscalls takes six arguments, which is what
makes the register free; a comptime check in `syscalls.zig` refuses a fifth member that
would take it.

**3. `SECCOMP_RET_USER_NOTIF` was declined.** It would put the engine itself in the
supervisor's seat, and `oracle_verified` — frozen by name in `docs/contract-freeze.md`
surface 2 (#94) — would quietly go from "two observers agreed" to "one observer agreed with
itself". Syscall User Dispatch was declined for a duller reason: the development kernel has
no `CONFIG_SYSCALL_USER_DISPATCH`, measured, so the design could not be built where it
would be worked on.

**4. Under an oracle, the two witnesses come from two runs — and the claim gets its own
name.** A trapped write is not executed by the kernel, so strace sees each one twice (once
refused, once re-issued) plus the handler's own record writes: four real writes came back as
thirteen strace lines, and `oracle.compare` is positional, so every oracle-attached run in
this mode would refuse. The oracle therefore watches an **untrapped** run and the trace
comes from a trapped one, restored to the same initial state in between. Measured: the
untrapped and trapped runs of the stdio toy, a raw-syscall toy and the planted-bug toy
produced identical operation sequences, and the planted-bug toy reaches the same verdict,
the same crash-point count and the same earliest address in both modes.

What that leans on is the reproducibility the exploration already requires of every target
it judges — `SIDEEYE_KILL_AT` is an index into the recording's sequence, replayed in each
world — and `preflight --twice` is how a caller measures it for their own target. But "two
witnesses of the same execution agreed" and "two witnesses of two executions agreed" are
different claims, so the weaker one is reported as **`oracle_verified_across_runs`** and
`oracle_verified` stays false. Surface 2 says a machine field would change name before it
changed meaning, ADR 0035 already decided that a claim weaker than `oracle_verified` needs
a name, and the shim states the same rule from the other side: a discovered strace is named
and never attached, because "a second witness joining on its own would silently strengthen
what a flagless verdict claims".

## Alternatives Considered

- **Make it the default.** Declined. Not because of the 38 committed cases — a version bump
  drops those whatever the default is — but because the default path's behaviour is what
  every existing caller measured, and a new observation path should not move it.
- **Wrap `fwrite` and reimplement glibc's splitting rule.** Declined for the reason ADR
  0036 declined the same shape for `dprintf`: the 8192-byte split is undocumented libc
  internals, and reimplementing it means owning a copy of another project's private
  decision.
- **Have the handler write two records so the oracle's doubled account matches.** Declined:
  it doubles every crash-point number, which is the one thing this work promised not to
  move for targets the default path already handles.
- **Key the oracle's exclusion on the trapped write's return value.** Declined. The only
  available key is the errno, and cohort 4's `seccomp-enosys.json` profile returns the same
  one; the runs that currently agree for himalaya and unison would start refusing.
- **Drop the oracle in this mode and require `--allow-unverified`.** Declined, and it is
  the closest call here. The property would still hold — a FAIL stands without an oracle —
  but the trap set is a hand-written list, and a missing member means writes go uncounted,
  the kill lands somewhere else, and the verdict is silently wrong. The oracle is the only
  thing that catches that at runtime, and this is the mode where the trap set's completeness
  is least established. `spike/check-shim-coverage.py` holds the list to the oracle's own
  classification table as the static half.
- **Probe the filter's availability with a run of the target under the shim.** Declined in
  favour of asking the kernel directly: `SECCOMP_GET_ACTION_AVAIL` answers the same
  question in the engine's own process, with no spawn and without the target's side effects
  landing in the state directory before the engine has decided it can proceed. The probe
  would also have been the weaker measurement — it observes the engine's context, not the
  target's — so the shim announces its own result and the engine checks that too.

## Consequences

- **`pwritev2` is refused rather than counted in this mode, and it took two wrong answers
  to get there.** Six arguments leave no free register for the sentinel, so it cannot be
  trapped. Counting it in the wrapper double-counts on a kernel that lacks `pwritev2`,
  because glibc falls back to `pwritev`/`writev` and both of those are trapped; silencing
  the wrapper counts it nowhere on a kernel that has it, which is every kernel since 4.6 —
  and under `--allow-unverified` that is a silently wrong verdict where the default mode was
  correct. Neither is right without knowing which kernel this is, so the wrapper records
  `.unsupported` (v12's marker, `unsupported_syscall_observed`, already in the closed set)
  and the run refuses on either kernel with no oracle required to notice. `copy_file_range`
  and `sendfile` stay counted at the libc boundary for a milder reason — libc never issues
  them from inside stdio, so the wrapper sees every call that is not raw. All three are in
  `check-shim-coverage.py`'s `NOT_TRAPPED` with what they cost, where forgetting fails
  closed.
- **This mode's sharpest cost: an image the shim cannot be loaded into dies on its first
  write.** A seccomp filter is inherited across `exec` and cannot be replaced, and `exec`
  resets the `SIGSYS` disposition to default — so a statically linked helper, or any image
  the preload does not reach, takes an unhandled `SIGSYS`. Measured on `toy-static` exec'd
  from a shimmed parent: **exit 0 under `wrappers`, exit 159 under `syscalls`**. There is no
  mitigation available: nothing of ours runs in that image to install a handler, and the
  filter cannot be lifted. This is the one limit here that changes what the target *does*
  rather than what Sideeye can *see*, which is why it is in the README's limits list and not
  only in this ADR — ADR 0002's vfork lesson is that the target has to survive being
  observed. What bounds it: a child the shim IS loaded into installs its own handler and is
  unaffected (measured: a `fork` + `exec /bin/sh` define reaches the identical
  `child_touched_state_dir` refusal in both modes), and a child that touches the judged
  state is already refused in both modes whatever it does.
- **A process executing in another syscall ABI (32-bit compat) is allowed through
  uncounted**, because the filter cannot read `nr` in an ABI it does not know. The oracle
  sees those writes and the comparison refuses.
- **A target that itself issues one of the four syscalls with the marker already in its
  sixth argument register** would be allowed uncounted. 2^-64 per call, disclosed in
  `docs/report-schema.md` — **and that figure was not true until the thunk started clearing
  the register.** The sixth argument register is caller-saved and nothing sets it for a
  three-argument call, so the marker survived the thunk's return and the next `write(2)`
  libc issued inherited it. The shim's own trace writes go through that thunk, so the shim
  was producing the collision itself, systematically: a record is written, and the write it
  was recording about becomes invisible. **Found by CI, not locally**: every syscalls-mode
  acceptance leg failed on x86_64 while the same legs passed on aarch64, and the divergence
  named exactly one missing operation — the direct `write(2)` immediately after a recorded
  `open`. The register survives on one architecture's allocation and not the other's. The
  thunk zeroes it before returning, which is what makes the disclosed odds the real ones.
- **A target that manages `SIGSYS` itself is outside what this mode accounts for**, and
  far likelier than the marker collision above: installing its own `SIGSYS` handler,
  blocking the signal, or installing a `SECCOMP_RET_TRAP` filter of its own. Nothing
  interposes `sigaction`/`sigprocmask`, and interposing them would mean overriding the
  target's own choice rather than observing it — the opposite of what this tool does.
  Disclosed in `docs/report-schema.md` rather than guarded.
- **The handler runs on the target's own stack**, with two `max_path` buffers in
  `noteFd`'s frame, and no `SA_ONSTACK` — which would need an alternate stack this shim
  installed, replacing whatever the target had. Left alone: threads are refused by this
  tool, so the subject is on its main stack, and a target that shrinks that stack far
  enough to matter is a narrower case than the one an installed altstack would break.
- **`--observe syscalls --allow-unverified` is accepted.** The reasoning above says the
  oracle is the only runtime net for a hand-written trap set, which argues for refusing the
  combination — but `--allow-unverified` is the caller's explicit consent to a weaker claim
  everywhere else, and macOS depends on it. The report says which claim was made, which is
  the same answer this tool gives everywhere else consent is offered.
- **A saved case does not record which mode produced it.** Replaying one from this mode
  without the flag refuses — `case_no_longer_applies`, because the operation count will not
  match — so no wrong verdict is possible, but the remedy the refusal suggests is
  `re-record` where the real remedy is `--observe syscalls`. Not fixed here: the case format
  is a frozen surface and giving it a new field is its own version bump.
- **`PR_SET_NO_NEW_PRIVS` is set on the target**, which is required to install a filter
  unprivileged and which stops setuid from taking effect. Only in this mode.
- **Cost: 1.6–1.8µs per trap**, including the `/proc/self/fd` resolution the handler does on
  every one. Against a world's 0.17s (ADR 0042) that is +2.1% for a target that writes 2000
  times, and a doubling at 100000 writes. Linear, and the loud shape — a target that prints
  progress to stdout pays for every line, because contract v8 forbids exempting fd 0/1/2.
- **`macOS` has no equivalent** and the flag is refused there as a setup error.
