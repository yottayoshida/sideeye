# 0045 — The sensitivity leg asks what the trace says about a path, not whether it names it

Status: Accepted (2026-09-04)

Closes #344. The FSEvents survey's L7a precondition changes from "the planted path never
appears in the shim's trace" to "the trace names it as an `open`, and carries no operation
that would account for the bytes it now holds". The mutation changes with it, from
`clonefile(2)` to an `mmap` store flushed with `msync`.

## Context

L7a exists to make one thing measurable rather than assumed: that the mutation the
sensitivity leg plants is invisible to the shim's account. Without it a silent capture
cannot be told from a capture of something the shim already saw, and the leg proves nothing
in either direction.

Trace contract v12 (#333) added the clone family to the interpose table. The planted
`clonefile` became visible, L7a refused itself by design with its own "pick another
mutation" message, and the recorded 15/15 sensitivity result became a v11 measurement that
stands on its date and cannot be re-taken. This is the second apparatus in this repository
to be retired by the wall it was built on — cohort 4's `no-accel-copy.so` went one contract
version earlier.

`#344` named the replacement class: mmap+msync, where the store is a memory write with no
syscall behind it. `spike/check-macos-coverage.py` already records that as a deliberate
non-interposition rather than an oversight — interposing `msync` would record *some* of the
writes and lend the account a completeness it does not have.

What the filing did not say, and what turns out to decide the shape: **a file must be
opened before it can be mapped, and the shim records that open.** The old predicate is
therefore unavailable to any probe in this class, not merely inconvenient. Nor is there a
way around it: `ftruncate` is interposed too, so sizing the file inside the traced run adds
a `.truncate` for the same path.

## Decision

**Change the predicate with the mutation, and keep both halves.**

L7a now asks two things: (a) the trace names the planted path as an `open`, and (b) it
carries no `write`, `truncate` or `fsync` for that path. The first is the control. Without
it the absence in the second is equally satisfied by a shim that never loaded — measured:
with `DYLD_INSERT_LIBRARIES` unset the leg refuses on "the shim wrote no trace" before the
absence is read at all.

**Create and size the mapping target outside the traced run.** `survey.sh` writes the file
before launching the probe under the shim, so the traced run performs `open`, `mmap`, the
store, and `msync` — and nothing that would record a write.

**Read the operations through `contract.decodeRecord`, not through `strings`.** The
question is no longer "does this name appear" but "what was done to it", which `strings`
cannot answer. `spike/fsevents/trace-ops.zig`, built by `zig build -Dtrace-ops` and never
shipped, prints one `<op> <path>` line per record. `src/contract.zig` opens by stating
there is deliberately no second definition of the wire format anywhere; a Python reader
would have been exactly that, correct until one side moved.

## Alternatives considered

**`aio_write`, the filing's fallback.** Declined: it needs an open too, so the predicate
problem is identical, and the completion/issuance split adds apparatus for nothing gained.

**Keep `strings` and find another mutation.** Not available. The two write-shaped classes
the shim deliberately does not interpose are mmap/msync and aio, and both open the file
first.

**Leave the leg refusing and record it.** This was the standing state, and the owner
declined it: the leg's precondition being unmeasurable is a different thing from the
hypothesis being unmeasured, and only the first is fixable here.

**Add the reader in Python.** Declined on `contract.zig`'s own rule. The cost of the Zig
route is one gated build target; the cost of the Python route is a second definition of a
binary format, which is the failure `contract.zig` was written to prevent.

## Consequences

- **L7a's claim is weaker, and the weakening is the honest part.** It no longer says the
  shim is silent about the path — it says the shim is silent about the *change*. The
  header of `spike/fsevents/bypass.c` and the leg's own banner both say so; leaving either
  reading "provably does not report" would have been false.
- The falsification is three-way and was measured on 2026-09-04, macOS 15.3.1 arm64,
  contract version 13: the shipped probe is green; the same probe with an ordinary
  `pwrite` added refuses on "the shim DOES record a write"; the same probe with the shim
  unloaded refuses on "the shim wrote no trace".
- `trace-ops` carries a `--selftest` that encodes a trace containing an `open` and a
  `write` on the same path and requires the walk to return both with their tags. A reader
  that printed paths and ignored the op would pass a test that only checked names, and
  that reader is the one this program exists not to be.
- **This restores a precondition, not a result.** The 15/15 sensitivity numbers stay v11's,
  taken on 2026-08-23, and are not re-run. Route B is still declined on price (ADR 0035),
  and nothing here revisits that — what changes is that the leg can measure again if
  someone does.
- **L7c runs the same probe and needed the same preparation.** The mapping target is
  created by a `plant_target` function both legs call, before the watcher starts in L7c's
  case so that the file's creation is not itself in the capture. Writing the creation into
  L7a alone — which the first draft did — left every L7c run failing on the missing target
  and the survey exiting 1.
- **L7a will not print `ok` for a probe that died before mutating.** A zero-length target
  takes the mmap store down with SIGBUS, and the trace then reads exactly like a clean run:
  the open present, no write. The ok branch is gated on the probe's exit status, and
  `plant_target` verifies the size it wrote.
- **The reader fails rather than answering partially.** The header goes through
  `contract.decodeHeader`, so a trace from another contract version is refused instead of
  read with today's meanings; a record that will not decode ends the walk with an error
  rather than a `break`, because the caller reads absence as evidence and a walk that
  stopped in the middle produces a false one. Both are in `--selftest`.
- **`judge.py`'s reasoning changed even though its code did not.** Its sensitivity leg
  still refuses when the planted path is inside the probe's declared account, and that is
  still satisfied. But "outside the account" no longer implies "the shim never saw it" —
  the shim records the `open` — and the docstring says so, because that inference held
  under the old mutation and someone will make it again.
- **The event L7c counts is produced by the mapping, not by the store**, and the leg that
  says so is L7d. Measured three runs each on macOS 15.3.1 arm64: mapping read-write with
  a store, mapping read-write without one, and mapping `PROT_READ` so a store is
  impossible all yield an event naming the target 3 of 3; opening and closing without
  mapping yields none. The `clonefile` probe did not have this property — the event
  followed the file's creation — so the change of mutation moved what an L7c count is
  evidence *of*. It is now evidence that FSEvents reported activity the shim's account
  does not carry (the account holds an `open` and a `close` and nothing about the
  mapping), which is what a veto needs, rather than evidence that the veto saw a
  mutation. Read the other way it is a finding about FSEvents: `ItemModified` for a file
  nothing modified.
- That is written as a leg rather than as prose deliberately. An apparatus fact recorded
  once decays silently — which is the whole history this ADR sits in — so L7d re-measures
  it every run and names `RESULTS.md` and this ADR as the documents to correct if the
  attribution ever changes.
- The leg remains macOS-only and outside CI, as it was: CI is Linux and FSEvents is not
  there. The reader it depends on is built and selftested on every push, so it does not
  rot between the rare runs of the leg.
