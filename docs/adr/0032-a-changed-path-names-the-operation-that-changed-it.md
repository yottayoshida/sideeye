# ADR 0032 — A changed path names the operation that changed it, and the freeze is broken once to say so

- **Status:** Proposed (2026-08-30)
- **Supersedes:** nothing. Generalises the detector ADR 0003 describes in passing and
  `src/contract.zig`'s `isMutation` doc comment defines.
- **Scope:** the reconciliation of the judged state's differences against the recorded
  account; the closed `unknown_reason` set, which this moves.

## Context

The zero-ops detector asks whether the state changed while *nothing* was counted. It
goes silent the moment one operation is recorded, and #405 is the shape that exploits
that: a target writes one file through libc — recorded — then forks with
`syscall(SYS_fork)` and has the child write a second file through raw syscalls. Nothing
records the second write. `mutation_count` is one, so the detector stays quiet, and the
run reaches **PASS, exit 0** with the child's file in the judged directory. Measured on
the shipped 1.0.0 and re-measured on `main` after #409.

`README.md` says "a target Sideeye cannot fully observe is UNKNOWN, never a silent
PASS". That sentence was false for this run.

The general form of the zero check is per path: for each way the state differs, is there
a recorded operation that names it? `engine.diffSnapshots` already produces the per-path
difference; `TraceInfo.ops` already holds every record. Nothing new had to be observed.

## Decision

### 1. Reconcile every difference against every record, and refuse on the first that no record names

`engine.reconcile` takes the differences, the operations, and both spellings of the
judged root, and returns the paths nothing accounts for. The engine refuses on a non-empty
result, naming up to four paths and counting the rest.

**The direction is one-way and stated in the function's own doc comment.** "No operation
names this path" is evidence the account is incomplete. "Every path is named" is **not**
evidence it is complete: a failed syscall leaves a record with no change behind it, and a
subtree renamed in from outside is accounted for wholesale (decision 4). A future caller
must not read the absence of the first as the second.

### 2. `open` names a path here, though it is not a mutation

`isMutation` excludes `open` deliberately, and its doc comment says why: excluding it
makes the zero-ops form *stricter*, because a target that only ever opened files and yet
changed the state is a blind spot worth catching. Per path the same exclusion is wrong in
the other direction — a file created by `open` and never written is a change its own
record explains, and refusing on it is a false refusal. The two forms ask different
questions, so they do not share the predicate.

For the same reason the reconciliation reads **every** record, not only the subject's:
a child that left a record has explained its change. *Who* performed it is
`child_touched_state_dir`'s question, and it is asked earlier.

### 3. The join reads the spelling the snapshot holds, not the one the shim wrote

The shim normalises path arguments **lexically** (`contract.normalizePath`), and the
snapshot never follows a symlink (#122 — a link's target is its whole judged identity).
Under `cur -> v1`, an operation on `cur/f` is therefore recorded as `cur/f` while the
difference sits at `v1/f`. The first revision compared those two directly.

Measured, three cells, same file and same operation: the shipped 1.0.0 answers **PASS
exit 0**; the first build of this detector answers **UNKNOWN exit 2**,
`state_changed_unaccounted`, naming `v1/f`; a control operating on `v1/f` directly
passes on both. A regression this change introduced, on a run nothing was wrong with —
and `current -> release-N` is a mainstream layout, with GNU Stow, on this project's own
list of targets, being a symlink farm outright.

So `reconcile` substitutes symlinked prefixes before comparing, **from the snapshots'
own record of link targets, never from the live filesystem**: the tree at reconcile time
is not the tree the operation crossed, and resolving live would answer about the wrong
one. Both snapshots contribute, because a link the operation went through may have been
created after the initial sample or removed before the final one. Chains resolve;
cycles are legal on disk and terminate on a hop bound.

**Both spellings are compared, not just the substituted one.** A path can name a link or
name *through* it, and those are different objects: `unlink("cur")` removes the link and
the difference is at `cur`; `unlink("cur/f")` removes a file and the difference is at
`v1/f`. The first revision of the substitution compared only its own output and so erased
the first — measured, the same PASS-to-UNKNOWN regression one level up, on `unlink(cur)`
and on a `symlink`-then-`rename` generation swap, which is the very layout named above.
A fix that reintroduces the defect it fixes, in the shape it fixes it in, is worth saying
out loud.

**Where the substitution cannot be sure, it does not substitute.** Two cases, both
fail-closed: a link whose target differs between the two snapshots (the reconciliation
holds no ordering between the retarget and the operations, so either reading invents one
— measured, the same records excuse a path under the initial spelling and refuse it under
the final), and a path two links both match (only possible when the tree changed shape
between samples, since the walk does not descend into a link). Declining leaves the
operation matched on its literal spelling, which is the refusing side.

### 4. A renamed-in directory carries its children, and the report says how many

`papis add` builds a document folder **outside the judged root** and moves it in with one
`renameat` (measured: source `/tmp/tmp3p9lj_l7`, one recorded operation, `crash_points 1`).
One record, and the difference holds the directory plus every descendant. Attributing the
descendants to the move is the only rule that does not refuse a committed PASS.

**Both halves of "moved in" are load-bearing, and the first revision checked neither.**
`rel` is taken from either end of a two-path record, and the exemption tested only that
the class was `rename` — so a rename entirely inside the root (`mv a b`, an ordinary
generation swap) and one moving a subtree *out* both took the umbrella. Neither needs it:
for those the source is in `initial`, so the descendants are reconcilable, and absorbing
them hides exactly what this detector exists to find. The exemption now requires the
matched end to be the destination *and* the source to resolve under neither spelling of
the root. That also makes the disclosure sentence true — it asserts the source subtree
was never snapshotted, which was false for the two shapes above.

**This is a window, and it is the same window this ADR closes, at directory granularity.**
An unrecorded writer can add to that subtree after the move and be attributed to it. It
cannot be closed from anything this run holds: the source was never snapshotted, so what
arrived with the move is unrecoverable. Two ways out exist and both are other promises —
carrying the source's contents in the rename record (a contract bump, which orphans every
saved case, #279), or deriving them from the crash world killed at the rename's own point
(which moves the reconciliation after exploration).

So it is disclosed **as a number**, in a report field of its own —
`paths_attributed_to_rename`, present on every report, additive under the allowance
surface 2 of `docs/contract-freeze.md` explicitly keeps open. A run with zero has no
window, and that is a value a caller reads rather than the absence of a phrase it has to
notice. The `l0` account carries the same count in prose for a human reading a PASS; the
number is the copy that cannot be lost to an allocation failure, and it is the one the
argument above leans on.

An earlier revision put the disclosure only in `l0`. That made the claim "machine-readable
rather than a matter of reading the source" false of its own implementation, and it
appended to a field two acceptance legs compare by exact equality.

### 5. The refusal takes a new closed-set member, and the freeze is broken to give it one

`state_changed_unaccounted`. Every existing member was checked against the code rather
than against its name:

- `state_changed_without_ops` spells "zero operations were recorded". #405's run records
  the parent's write. The name would be false.
- `completeness_not_verified` takes no evidence from the run: `if (has_oracle or
  allow_unverified) return;`. #405's reproduction passes `--allow-unverified`, so it is
  structurally unreachable there. It names the *absence of checking*; this detector is a
  *positive finding*. Putting one under the other is the confusion #409 had just removed
  from the `processes` account.
- `oracle_missed_operation` is the oracle's finding, and this detector runs where there
  is no oracle.
- `boundary_without_oracle` requires a boundary the shim recorded — exactly what is
  absent here.

ADR 0026 settled the standard: a refusal whose reason is a lie is worse than no refusal.

**`docs/contract-freeze.md` declared this breaking under either reading, and it is.** The
owner ruled on 2026-08-30 that the detection is worth it. The declaration is amended in
the same commit — not softened, because it correctly states what the tag promised, but
followed by a note saying the promise was not kept. The ledger records the movement with
a new `legality` value, `freeze-broken`, deliberately not folded into
`declaration-amended`: amending the declaration is what happens *after* breaking it, and
a ledger that recorded only the amendment would leave the break unwritten.

### 6. It runs after `refuseUnsupportedEntry` and after the oracle comparison

A `mknod`'d FIFO is a change no operation names — the shim interposes no `mknod` on
either platform — so running first would take three acceptance legs' refusals and answer
them under this name instead of the one that says what is wrong with the entry. And where
an oracle ran, `oracle_missed_operation` names the syscall that went unseen, which is
strictly more than "this path is unexplained".

## Alternatives considered

- **Reuse an existing member.** Rejected above, per member, against the code.
- **Wait for 2.0.** The detection is the half of #405 that matters; #409 shipped the
  other half and left this one open on purpose. Deferring a real silent PASS to a major
  version because the vocabulary is full is a cost argument, and the ruling was that the
  quality question comes first.
- **Refuse only newly created files** (`only_in_second`). Narrower, fewer false refusals,
  and it would still catch #405 — but it leaves content rewrites and deletions
  unexamined, which is a smaller promise than the one the property states.
- **Refuse the directory rename outright.** Closes the window in decision 4 and makes
  `README.md`'s "never a silent PASS" true with no exception — but refuses `papis add`,
  whose entire shape is that rename, and turns a recorded PASS on a real target into
  UNKNOWN. Put to the owner on 2026-08-30 against the option taken, with the third being
  a trace-contract bump (#279) carrying the source subtree's contents; the ruling was to
  name the exception in `README.md` rather than refuse the shape or defer the detection.
  The exception is written into the same sentence the property is quoted from, so a
  reader meets it where the promise is made rather than in an ADR.
- **Skip the reconciliation on trees holding symlinks** instead of resolving them
  (decision 3). One line rather than a substitution, and never a false refusal — but a
  target that plants an interior symlink would switch the detector off, and switching off
  a detector for evasion is what #405 is about.

## Consequences

- A run whose account is incomplete at any path refuses instead of passing. The measured
  case is #405; the class is every unrecorded write, including the same-process raw
  writes #217 describes.
- **The closed set is 33.** A consumer that pinned 32 is entitled to have been surprised.
  The rule for 1.x is unchanged: the next member needs its own ruling, not this precedent.
- A target that renames a directory in from outside the judged root has that subtree
  attributed wholesale, and every report carries the count as
  `paths_attributed_to_rename`. `README.md` names this exception in the sentence that
  makes the promise, per the owner's ruling above.
- Runs with an oracle are unaffected in reason: the oracle's own findings are named
  first, and this detector reaches only what they let through.
- **A path recorded through an interior symlink is not a refusal.** Pinned by
  `spike/acceptance.sh` check 2ai against `spike/toys/toy_symlink.c`, seen red once by
  disabling the substitution (UNKNOWN `state_changed_unaccounted` naming `v1/f`, PASS
  restored).
- The freeze ledger's row for this member (`surface-changes.tsv`) lands in a follow-up
  audit commit together with `DECLARATION_PIN`, the way `2e6f85d` recorded `sc-14..sc-17`.
  A row added in the same PR carries `PENDING` where a commit sha belongs and makes the
  gate's cumulative pin-versus-ledger count disagree — the audit's own convention is that
  the pin and the ledger move together, after the change lands.
