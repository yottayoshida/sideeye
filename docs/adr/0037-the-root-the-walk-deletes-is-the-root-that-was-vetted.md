# 0037 — The root the walk deletes is the root that was vetted

Status: Accepted (2026-09-01)

Promotes the alternative ADR 0024 filed as "not done" and closes #338. Sibling of ADR
0024, which holds the root open, and of ADR 0010, which fixes the destructive entry
points this applies to.

## Context

Three functions empty or overwrite a directory the operator named: `restore`, `freshDir`
and `corruptState`. Each vets the root first — `assertSafeRoot` for the name, then
`assertRootResolvesToItself` for its resolution — and each then opens it. The vet and the
open are separate syscalls, so a swap landing between them was undetected, and the walk
would empty whatever the name reached by the time of the open. `assertRootResolvesToItself`
said so in its own doc: "the check and the `opendir` are two syscalls, and a swap between
them is not detected."

ADR 0024 described the fix and deferred it: a `stat` at resolution time, an `fstat` after
the open, one struct threaded through. It called the cost cheap because #327 had already
made one side of the comparison a descriptor.

## Decision

The vet returns the identity of what it approved, and the open refuses any descriptor that
is not that object.

`assertRootResolvesToItself` returns `RootVet`, a union of `identified: posix.Identity`
and `absent`. `openRootDir` takes a `RootVet` — not an optional — and after a successful
open compares the descriptor's identity against the approved one. `posix.Identity` is a
device and inode pair, read through `statx` on Linux and `fstat`/`fstatat` on Darwin, the
same split the file's other stat wrappers already make.

Three consequences follow from the union's second arm:

- A vet that found nothing, followed by an open that found something, is a refusal. The
  thing appeared after the vet looked and nobody approved it. `freshDir` reaches this with
  its own `mkdir` already failed; `corruptState` when the tree `restore` built has gone.
- `restore` is the one caller that legitimately creates the root — the first run of every
  world arrives with nothing there — so it takes a fresh identity after its own `mkdir`.
  That step is `createRoot`, which also refuses `EEXIST` when the vet was empty: a
  directory that arrived in that window is someone else's, and `O_NOFOLLOW` will not
  refuse it because it is a real directory.
- `deleteTree`, reachable only from tests, takes an identity of its own rather than a
  caller's vet. It gets the swap window closed and not the name checks, which is the
  accurate statement about a function that takes a raw path.

## What this does not cover

**A swap that happened before the vet, including a bind mount established before it.** The
vet approves whatever was there when it looked, and no comparison anchored to the vet can
question the vet. #338 says the same thing in its own words, and the sentence is now in
`assertRootResolvesToItself`'s doc rather than only in an issue.

ADR 0024's Alternatives claimed the device/inode pair "would catch a bind mount established
inside the window, though not one established before the check". The first half is true only
in the sense that a change of the underlying object inside the window is caught **when it
leaves a different device/inode pair behind** — a mount is not special there, and the
qualifier is not decoration, because of the reuse case below. The second half stands.

**And an inode that was freed and handed out again.** If the vetted directory is *unlinked*
rather than renamed aside, and the filesystem allocates the same inode number on the same
device to a new directory at the same path, the pair compares equal and the walk proceeds.
Review found this; it is a property of the primitive, not of the wiring. Renaming — the
ordinary way a directory is swapped, and what the tests do — keeps the old inode alive and
keeps the numbers apart. Closing it needs a descriptor held from the moment of the vet, or a
per-inode generation number, and neither platform offers the second through a portable stat.
Taking the first would mean the vet opening the root, which is a second descriptor held
across the whole call for the sake of a narrower window than the one this ADR closes.
Recorded rather than attempted, and named in `posix.Identity`'s doc so a reader of the
comparison sees it.

## Alternatives considered

- **Compare the descriptor against what the pathname resolves to *now*, after the open.**
  This was the plan of record after first-look review, which argued that recording an
  identity at vet time lets a swap *before* the vet record the attacker's object as the
  vetted one. That is true and is the uncovered half above; it is not an argument against
  anchoring to the vet, because "vetted" can only mean "what the vet looked at".
  **Rejected on measurement, not on argument**: implemented, it accepted the swap. Move the
  vetted directory aside inside the window and put another at the same name, and the
  descriptor and the name both reach the new one, agree, and the walk proceeds. That
  comparison can only see a swap landing between the open and the stat — a window the
  comparison creates itself. The permanent test asserts both halves, so the rejected shape
  cannot come back quietly.
- **Put the comparison at the three call sites.** Rejected. It was written that way first,
  one conditional each, which is the shape where a fourth caller gets one of them wrong —
  and the reason `openRootDir` exists at all is that `opendir` used to be called from
  several places with several different amounts of care.
- **Make the parameter optional so `deleteTree` can pass nothing.** Rejected. An optional
  is an opt-out, and the opt-out would be invisible at the call site. `deleteTree` produces
  a `RootVet` of its own instead.
- **Refuse whenever the vet found nothing.** Rejected: it passes every swap test and breaks
  every first run, since `restore` legitimately creates the root. The regression test for
  that failure is why the distinction between `freshDir` and `restore` is written down.
- **Cover the bind-mount half.** No method available. Recorded rather than attempted.

## Consequences

A false positive here is not a test failure: `restore` runs once per world, and `UnsafeRoot`
becomes SETUP_ERROR before exploration or UNKNOWN during it. This tool's subject is the
UNKNOWN rate, so the acceptance suite on Linux is a merge precondition rather than a
formality.

`RestoreError` gains no member. Mismatches land on `UnsafeRoot`, whose operator-facing
message is extended here: it named three causes and now names a fourth, because a path that
is still a readable directory and still resolves to itself, and is simply not the one that
was checked, reads nothing like the other three. An earlier draft of this ADR claimed the
existing wording already covered it. It did not.

Five mutations were run and each was killed by the test written for it. Three of the five
are refusals — the identity comparison, the `.absent` arm, and the `EEXIST` rule. The other
two are the conditions those refusals rest on: `restore` taking its identity after its own
`mkdir`, which is what lets a first run succeed, and the conditional that keeps the vetted
identity, which is the evidence the mismatch refusal compares against. The `EEXIST` rule cannot be reached from a
single-threaded call to `restore` — it lives between two calls `restore` makes back to back
— which is why it is a separate function; it is reachable in the world, by another process,
which is the case it exists for.

**The fifth refusal was found by review, not by the tests.** `createRoot` re-read the name
unconditionally, so `restore` — the main caller — still accepted a swap: the vet identifies
A, A is replaced by B, `mkdir` answers `EEXIST` as it always would, the `.absent` rule does
not apply, and the fresh reading hands B to a comparison against B. The swap test passed
throughout because it drives `openRootDir` directly and never comes through `createRoot`.
