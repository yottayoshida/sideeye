# 0030 — A refusal reports what was observed, not what it thinks caused the failure

Status: Accepted

Numbering note: taken as the highest existing number plus one, which is not exclusion.
`docs/adr/` has no reservation mechanism and two sessions produced an 0028 on the same
day; #373 is that gap. If this file collides on merge, renumber it there — the collision
is a rename, not a redesign.

## Context

`no_shim_marker`'s detail line named four candidate causes: statically linked, hardened,
not injected at all, and on macOS an Apple-shipped platform binary. The engine had
measured none of them. The branch that emits the line tests one thing — `!trace.saw_shim_ready` — and everything after the colon was a list of ways that state
can arise, offered in the vocabulary of properties the target *might* have.

README opens its limits section with "Sideeye refuses to guess". The one message a
refused user actually reads was doing exactly that.

#391 is the cost, measured. A user tried to observe the Command Line Tools git on macOS,
was refused, and checked each named cause against the binary: not statically linked, no
hardened-runtime bit (`flags=0x2000`, and the runtime bit is `0x10000`), and not a
platform binary (`/bin/sh` carries `Platform identifier=16`; this binary carries none).
All three false, honestly checked, and the reader left with no next step — because the
mechanism that applied, library validation, is a fourth one the message never names,
documented in `DESIGN.md:152` and ADR 0001 where the refused user is not looking.

## Decision

**The line reports observations. It offers no causes.**

Three rules, each of which is something the line does not say.

**It does not conclude causation.** The engine reads the operation's executable and
reports field values: "its code directory carries the library-validation flag", never
"library validation refused the insertion". The bit can be lifted by
`com.apple.security.cs.disable-library-validation` and by
`...allow-dyld-environment-variables`; a non-zero `platform` byte is not Apple's full
definition of a platform binary, which also requires the signature to be endorsed. #391
itself declines to claim that removing library validation would let the shim load, and
this decision declines the same claim.

**It does not claim identity with what ran.** The kernel executes an image; the engine
can only open a path. The reading is taken immediately before the spawn — beside
`rec_started_ms`, whose own comment already says "read before the spawn, not after" for
the same class of reason — and taken again at the refusal. What the two readings compare
is the answer itself, size and fields, not an inode: the refusal reports fields, so the
question that matters is whether those fields moved. A disagreement is reported as a
disagreement between two observations, with **no time attached**: a swap before the spawn
produces the same disagreement as one after the run, and nothing here can separate them.
A match is not reported at all, because a same-inode overwrite would leave one.

**It does not resolve `PATH`.** An `argv[0]` with no `/` is not measured; the line says
the OS resolved it and Sideeye did not. `execvp`'s search has rules — empty components
meaning the current directory, relative components resolving against the child's cwd, the
`ENOEXEC` shell fallback, `EACCES` continuing to the next candidate — and a second
implementation of them would be a copy that drifts, whose failure mode is naming the
wrong file with confidence. A relative path *is* resolved, against the declared `[define]
cwd` (ADR 0007, #395), because that is the directory the child will `chdir` into.

Where a fact cannot be established the line says so rather than picking: a universal
binary whose slices do not narrow to one for this CPU type, a signature whose code
directories disagree, a structure that runs outside the file. arm64 and arm64e share a
CPU type, and which one the kernel grades as runnable is not restated here.

## Alternatives considered

**Add library validation to the list.** The cheapest fix, and the one #391 sketches. It
leaves the reader doing the same manual check, and the next unnamed mechanism reproduces
the issue. Rejected as treating the symptom: the defect is that the line guesses at all.

**Say nothing — report the absence of the marker and stop.** Proposed by external review
after it broke the first draft of this decision, and it is the safest option on every axis
except the one that matters: it leaves #391's reader exactly where they were, with a
refusal and no next step. Rejected by the owner, 2026-08-29.

**Read the signature by shelling out to `codesign`.** Puts a developer tool on the
judge's dependency list, absent in containers and on CI.

**`csops(2)` against the live child.** The most accurate answer available — it asks about
the process rather than a path — and it requires the measurement to sit between `fork`
and `exec`, on the hot path, to answer a cold-path question.

**Carry the observation in a new report field.** Surface 2 (report schema fields) is
frozen, and additive fields are allowed but cost a `surface-changes.tsv` row and a
`DECLARATION_PIN` move — machinery that #397 measured as already red and left to #371.
Keeping the observation in the detail prose moves no frozen surface: the member, the
verdict and the exit are unchanged.

## Consequences

The engine gains a parser for two executable formats, reading files the target's own
define names. It reads by offset, never whole; it opens with `O_NONBLOCK`, because a FIFO
at that path would otherwise hold the open until a writer appeared (#5 retired an
open-probe from `posix.zig` for this); every count it walks is bounded by a constant the
file cannot raise; every length the file declares — `sizeofcmds`, `LC_CODE_SIGNATURE`'s
`datasize`, the SuperBlob's and the code directory's own — bounds the reads taken inside
it, so a field read from outside the region refuses rather than being reported as the code
directory's; and a short read is a failure rather than a shorter answer.

Its falsification is fixtures that drive one declared field at a time, plus a walk over
four fixtures (thin Mach-O, both fat layouts, ELF) that takes every truncation and drives
every byte of each to `0x00` and `0xff`, asserting a value comes back rather than a crash.
That walk is a robustness assertion over those four shapes and not a claim of exhaustive
coverage of either format.

The refusal's prose is no longer platform-branched. Both the Linux and macOS lines were
lists of guesses, and neither survives; what differs between the platforms now is which
facts exist to read, which is a property of the file rather than of the message.

`no_shim_marker` continues to cover more than injection being blocked — a trace that
could not be read collapses to an empty `TraceInfo` and arrives here too. The line's
shape admits this: when nothing was found on the image it says the cause lies elsewhere,
which is the honest reading of the branch and was unsayable while the message was a list
of image properties.
