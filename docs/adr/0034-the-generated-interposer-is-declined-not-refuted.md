# 0034 — The generated interposer is declined, not refuted

Status: Accepted (2026-08-31)

Supersedes nothing. Closes #299. Sibling of ADR 0031, which gave macOS the second
observer this decision leans on.

## Context

The macOS shim wraps a hand-listed set of libSystem functions. Its real-world failure
mode is coverage: a target calls something the list does not name, the account comes
back short, and any other recorded mutation carries the run to PASS. That has happened
twice — `fs::copy` reaching the clone family (#333), and the `guarded_*` family
`/usr/lib/libsqlite3.dylib` imports (#428).

#299 proposed removing the list. Generate the interposer from libSystem's exported
symbol table instead, so "exported and touching a path or descriptor, but not wrapped"
becomes a mechanical diff that can be asserted empty in CI rather than a class of bug
found one cohort at a time. The ticket set its own gate: three measurements before any
design — whether interposition reaches `dlsym`-resolved calls and libSystem-internal
calls; the size of the file-touching export surface and the runtime cost of wrapping it;
and a static `svc` scan's false-positive rate on real targets.

#428 answered part of the second — the size of the surface, not its cost. The
reachability question is answered now
(`spike/generated-interposer/RESULTS.md`), and it came back the way that helps least:

- **Calls resolved at runtime are reached.** `spike/toys/toy_reach.c` runs `mkdir` and
  `open` resolved five ways — the image's own binding, `RTLD_DEFAULT`, `RTLD_NEXT`, a
  handle on the libSystem umbrella and a handle on the defining image — and records
  three state-changing operations in every one,
  with `dladdr` reporting that each resolved pointer lives in the shim. So this is not a
  hole the generator would close.
- **libSystem-internal calls are not reached**, which was already measured (ADR 0005,
  and `RESULTS-mkstemp.md` on macOS). A generated wrapper set does not close this either:
  the call does not cross an image boundary, so no wrapper on either end sees it.

What remains unmeasured is the cost side: what bracketing a much larger wrapper set does
to the timing a crash-consistency tool judges, and how often a static `svc` scan cries
wolf on a real binary. The shim brackets every operation with `fstat64` and
`fcntl(F_GETPATH)` today; multiplying that across the export surface is a perturbation
of the thing being measured, which is why #299 asked for the number before any design
rather than after.

## Decision

**Do not build the generated interposer. Close #299 as not planned.**

The reason is the price of the two remaining measurements, not a demonstration that the
design cannot work. Both only pay off if the design is taken, and neither is cheap: the
cost measurement needs a benchmark harness and a wrapper set that does not exist, and
the `svc` scan needs a corpus of real targets assembled for the purpose.

**Two arguments that this decision explicitly does not rest on**, because both were
drafted as refutations and both are false. They are recorded here so a later reader does
not rebuild the decision on them:

1. *The generator has no input.* The export table carries names without types, but the
   SDK's `Kernel.framework/Headers/sys/sysproto.h` carries named argument structures
   for the syscall families — including the `guarded_*` one whose absence from
   `usr/include` produced the original claim. It is the field *names* that would let a
   generator decide "touches a path": in `guarded_open_np_args` the address-carrying
   fields are `user_addr_t`, an opaque address type that says nothing about what is at
   the other end, so the types alone discriminate nothing.
2. *Export coverage would still miss `mkstemp`.* `mkstemp` is itself an export; a
   generator covering file-touching exports would wrap it. The mkstemp measurement says
   something narrower — wrapping `open` does not see the call libSystem makes to it.
   With one qualification the original correction glossed: `mkstemp` lives in
   `libsystem_c.dylib`, not in `libsystem_kernel.dylib`, which is the only export table
   this repository's tooling reads. So this holds for a generator over the re-export
   closure and not for one built on the table already in use here — a wider input than
   the ticket's phrasing suggests, and part of what pricing the design would have meant.

## Alternatives considered

**Take the remaining two measurements first, then decide.** Rejected on cost, by the
owner, on 2026-08-31. This is the alternative that would have answered the ticket rather
than closing it, and it stays available: nothing here forecloses it, and the
reachability measurement it needed is now taken.

**Build the generator and see.** Rejected. Deciding "touches a path or descriptor"
mechanically needs the argument types, which live in two places with different shapes
(userland prototypes for the convenience functions, kernel argument structures for the
syscall families), so a first implementation would carry a hand-written bridging table.
That is the shape #428's review broke twice — a table anyone can extend to make a
failure disappear, which `check-shim-coverage.py` refuses on Linux for the same reason.

**Leave #299 open pending the measurements.** Rejected. A ticket whose next step is a
judgement nobody has made is a judgement nobody will make; this repository's rule is to
take it and record it.

## Consequences

- **The completeness claim keeps its current anchors, and they are narrower than the
  export namespace.** `check-macos-coverage.py` ratchets a curated set — its own output
  reports 15 watched write-capable exports against 1502 kernel exports parsed.
  `check-fsusage-coverage.py` (#428) compares two real observers rather than a list, and
  reports 31 classified calls. Neither claims the namespace and both say so in the
  section they keep for what a green run does not mean; each gains one line there naming
  this measurement.
- **The reachability result narrows nothing and widens nothing.** It removes a suspected
  hole rather than opening one: a target that resolves symbols at runtime — through
  `RTLD_DEFAULT`, `RTLD_NEXT`, or a `dlopen` handle on either the umbrella or the
  defining image, all measured — is recorded like any
  other. What the measurement cannot show is that a given run took the branch its name
  says; once the answer is yes, every form returns the same pointer and the arms are
  observationally identical. The CI leg asserts the pair that remains assertable: a
  the two calls resolve into the shim, and a symbol the shim does not wrap does not.
- **The residual is #39's class**, and it is unchanged: a call libSystem makes to its own
  export is invisible to any wrapper set. On macOS the thing that sees it is
  `--oracle-fs-usage` (ADR 0031), which reads the syscall layer and does not care how the
  call was resolved. Without an oracle a single-process run reaches PASS only under
  `--allow-unverified`, and the report says the weaker claim out loud — unchanged by this
  decision, and already documented.
- **No report vocabulary is added and no contract surface moves.** The closed set stays
  where it is and `docs/contract-freeze.md` is untouched.
- **`spike/toys/toy_reach.c` becomes a standing pin.** The measurement is a fact about
  this dyld, not about dyld; a CI leg on the macOS runner re-derives it, so a future
  platform change that stops interposing `dlsym` results is a red run rather than a
  sentence in a record that quietly went stale.
