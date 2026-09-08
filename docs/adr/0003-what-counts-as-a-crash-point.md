# ADR 0003 — What counts as a crash point: state-changing operations only

- **Status:** Accepted (2026-08-11)
- **Supersedes:** nothing. Narrows the addressed operation set that ADR 0001 and the
  v0.1 design treated as "every file operation in the state directory"
- **Scope:** the shim's observation predicate for `open`, the oracle's class extraction,
  and the completeness comparison; trace contract v3 → v4

## Context

The first real target cleared the boundary gate (#18) and stopped at
`oracle_missed_operation`: its dependency tree includes rustix, whose Linux backend opens
the state directory via raw syscalls — `O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY`,
between taking a lock and reading a secret. The shim cannot see a call that never enters
libc; the oracle can; the two accounts diverge and the run is refused (#19).

The operation the shim missed cannot change state. That is the lever: a world killed
immediately before a write-incapable open is byte-identical to the world killed at the
next address — between the two addresses there is no state-directory mutation, because a
mutation would itself be the next address. Judging the extra world adds nothing; every
verdict (L0 and L2 alike) evaluates the same bytes. The address was never information.

Measured before decided: replaying both recorded accounts of the omamori run under the
rules below takes them from divergence at index 3 to **142 vs 142, aligned**. Read-only
open exclusion alone is not sufficient — the close of the raw-opened descriptor stays
stranded in the oracle's account, which is what forced decision 2.

## Decision

### 1. A write-incapable open is not an observed operation

The predicate, identical in meaning on both sides:

> An open is **write-capable** iff `(flags & O_ACCMODE) != O_RDONLY` **or**
> `flags & (O_CREAT | O_TRUNC)` is non-zero. Only write-capable opens are recorded,
> addressed, and compared. `creat` is always write-capable.

- `O_RDONLY|O_CREAT` — creates but cannot write — **stays addressable**: creation can
  change the tree. Addressable is not the same as *credited*, and the difference is
  deliberate and pre-existing: `OpClass.open` has never counted toward `isMutation()`
  (excluding it makes `state_changed_without_ops` stricter — see `src/contract.zig`), so
  a target whose **only** state change is creating files via open is refused by that
  structural detector, before and after this ADR. What this ADR guarantees is only that
  such an open keeps its crash-point address and stays in the comparison.
- `O_APPEND` is deliberately not in the set: append without write access cannot write,
  and append with it is already caught by the access mode.
- `O_PATH` gets no special case. An `O_PATH|O_WRONLY` open is counted by both sides —
  harmlessly conservative — rather than special-cased into a second place the two
  implementations could disagree.
- An access mode of 3 (invalid) is `!= O_RDONLY` and therefore write-capable:
  the unparseable errs toward being counted. strace spells that case `O_ACCMODE`
  (its `open_access_modes` xlat), and the token is in the oracle's write set so the
  invalid case cannot be the one place the two predicates split.

The shim evaluates this bitwise in the open wrappers and simply does not observe a
write-incapable open — the same treatment as a path outside the state directory. The
oracle evaluates it textually and **fail-closed**: an open is excluded only when its
flags argument contains at least one symbolic `O_` token and none of
`{O_WRONLY, O_RDWR, O_ACCMODE, O_CREAT, O_TRUNC}`. Numeric-only flags, a missing
argument, or an unrecognised shape are counted as before; if that miscounts, the run
ends UNKNOWN, which is the direction a parser failure must fall.

### 2. `close` leaves the completeness comparison, and stays in the trace

Matching closes across the two views requires knowing which descriptor each close
belongs to. The oracle sees descriptors the shim never saw born (the raw-opened
directory), and fd-provenance tracking leaks on `dup`, `dup2` and inheritance — a class
of bookkeeping with no honest fixpoint. `close` is neither a kill point nor a mutation;
its only role in the comparison was positional corroboration. It is now excluded from
both class sequences.

The shim keeps recording `.close` (the contract meaning — "recorded, never a crash
point" — is unchanged) for trace forensics, and the acceptance suite pins that recording
so the exclusion cannot silently become a removal. A stale-descriptor defect that close
matching might once have hinted at still surfaces as a phantom or missed **write**.

A child that only closes inherited state descriptors is tolerated under #18's rule —
closing changes no persistent state. Lock-release timing and descriptor-capability
inheritance are outside the crash model, and this ADR says so rather than implying
otherwise.

### 3. Trace contract v4

No format change, no new classes — but the recorded set changes meaning: a v3 trace
contains read-only opens that a v4 engine would count as addresses. A v3 shim paired with
a v4 engine must refuse loudly (`contract_version_mismatch`) rather than drift, which is
the documented purpose of the version field.

Old `reproduce` lines shift meaning: `SIDEEYE_KILL_AT=k` counts state-changing
operations from v4 on, so a k printed by v0.2.0 may name a different operation. Pre-1.0,
recorded in the CHANGELOG.

## What the equivalence claim covers

The redundant-world argument is about the state sideeye models: file contents and tree
structure, as captured by its snapshots. atime and other metadata, special files (FIFOs,
devices), and side effects observable through FUSE or network filesystems are outside the
model — the snapshots never captured them, and no verdict ever depended on them. The
claim is not "a read-only open has no effects"; it is "it has no effects on anything any
verdict reads".

> **Superseded in part, 2026-08-17 (#5):** the special-files half of the paragraph above
> no longer describes the code. Snapshots *do* record a FIFO, socket or device (as an
> opaque `other` entry), and since #5's demotion a run refuses (`unsupported_state_entry`)
> rather than explore a tree `restore` cannot recreate — so no verdict depends on their
> *content*, exactly as argued here, but their *presence* now stops a run instead of
> passing unmentioned. The metadata and FUSE/network sentences stand.

## Alternatives considered

- **Record open flags in `Record.aux` and project at judgement time.** Keeps forensics,
  but `aux` would mean "second path" for rename and "flags" for open — a type pun in the
  contract — and the predicate would need to agree in three places (shim recording,
  engine projection, oracle projection) instead of two. The fail-closed oracle plus the
  mutation pair in acceptance covers the drift risk this bought. Rejected.

  > **Narrowed, 2026-09-06 (#485):** `aux` now carries a *reason* on `.unresolved`
  > records, which is the same type pun this paragraph rejected. What does not carry
  > over is the second half of the reason: `.unresolved` is a marker
  > (`OpClass.isMarker`), so the snapshot walk drops it before the name matching that
  > reads `aux` as a path, and no predicate has to agree anywhere — the engine prints
  > the bytes and nothing compares them. The rejection stands for classes that reach
  > judgement, which is every class this ADR is about. The vocabulary lives in
  > `contract.unresolved_kind` rather than as literals on the shim side, for ADR 0006's
  > reason.
- **Track fd → open flags to pair closes.** Leaks on `dup`/`dup2`/inheritance; the
  oracle additionally sees descriptors born outside libc. Rejected.
- **Exclude `O_RDWR` opens too.** The open itself mutates nothing, but it is the birth
  of a write-capable descriptor and the conservative side keeps it addressable. Rejected
  for now; revisit only with a measured target that needs it.

## Consequences

- Targets that read their state before changing it get fewer, denser crash points; no
  verdict changes, because every removed world was byte-identical to its neighbour.
- The two predicate implementations (bitwise in the shim, textual in the oracle) can
  drift. The acceptance suite carries a mutation pair — disable either side alone and a
  read-first toy must go UNKNOWN in the corresponding direction — as the standing
  drift detector.
- The completeness comparison loses close-position corroboration. Accepted: it
  contributed no verdict information, and the recording is still pinned.

## Amendment 2026-09-08 — the same sentence settles the refusal path

**§2's decision is unchanged.** It was about the *completeness comparison*: `close` leaves
it because matching closes across two views needs descriptor provenance neither observer
keeps. This amendment adds that the sentence §2 rests on — "`close` is neither a kill point
nor a mutation" — also settles a question §2 did not name: whether a `close` the shim
could not **place** should refuse the run.

It should not, and the refusal's own words are why. `main.zig` says an unplaceable
operation "cannot be placed among the crash points" — and a `close` was never going to be
placed among them. The bytes under `--state` are identical either side of it, so no world
is lost by having no address for it. Refusing on that ground was refusing for a reason
that does not hold.

**Measured**: `mutool clean a.pdf a.pdf` opens the input, unlinks it while still open,
creates the output at the same name, and closes the original descriptor last. Under
`strace -y`, after the `unlinkat` that descriptor receives fifteen `read`s and one
`close` — and read-only calls are not recorded at all (§1), so the only recordable
operation on it is that close. **Sixteen runs of sixteen refused identically** under the
default observation mode with an oracle (`spike/followup-522/`), and the same refusal
with the same kind was recorded in four further arrangements before that measurement:
`--observe syscalls` with an oracle, and `explore` and `preflight` each without one — so it
is not the oracle's two-run arrangement producing it. **The wall this rule put up was one
`close` wide.**

**A second wall stands behind it, and this decision does not move it.** With the
exemption in place the same target refuses `oracle_missed_operation` under the default
observation mode, sixteen runs of sixteen: mutool writes its output from inside libc, which
`--observe wrappers` does not see and ADR 0005 declines by design. Under
`--observe syscalls` both walls are down and the target reaches a verdict — **FAIL, two of
four explored worlds, earliest crash point 2 of 3, after the `unlink` and before the
`open`**, identical in all sixteen runs. So an unplaceable close is no longer a *ground*
for refusal, which is what this amendment claims; whether a given target is judged is a
question about every other limit as well.

**Scope: the `unlinked-fd` kind only.** `fd-without-path` keeps refusing whatever the
operation was, because there the path query itself failed and where the descriptor pointed
is unknown — ADR 0013's "a failed measurement never passes as a clean one". An unlinked
descriptor reaches *that* kind too when `fdPath` fails, which is why the exemption is keyed
on the recorded kind rather than on "the descriptor was unlinked".

**The other reader already behaved this way.** `src/fsusage.zig`'s descriptor bookkeeping
`continue`s on a `.close` line before any unresolvable check runs, so the macOS oracle has
skipped unplaceable closes since #406, the change that created it. Two readers were disagreeing about a rule both cite;
the shim path now agrees. (The `if (c != .close)` guards further down that file are
unreachable for `.close` because of that `continue`, and are removed here rather than left
looking like the mechanism.)

**Where the exemption stops, and what would reopen it.** The predicate is
`!isKillPoint() and !isBoundary() and !isMarker()` — not `== .close`. The property belongs
to the class, and anything that changes state is a kill point by construction (this
document's own `isMutation` ⊆ `isKillPoint` invariant). If that invariant is ever weakened
— a state-changing class that is not a kill point — this exemption must be re-read before
that class ships, because it would be exempted silently.
