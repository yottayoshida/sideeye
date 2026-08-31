# 0036 — The trigger for interposing a libc convenience is a proof, not an encounter

Status: Accepted (2026-08-31)

Replaces the standing rule recorded in PR #38 and quoted on `docs/target-classes.md`
("the interpose-on-first-contact policy stands"). Closes #39. Sibling of ADR 0005,
which measured the mechanism, and of ADR 0034, which named this class as the residual
one on macOS.

## Context

A libc convenience function that changes state through a call made *inside* libc
crosses no PLT, so no `LD_PRELOAD` export and no `__DATA,__interpose` entry for `open`
or `mkdir` sees it. Two members were closed one at a time: stdio's buffered writes
(ADR 0005, contract v5) and `remove(3)` (PR #38, contract v7). Both were closed
**after a real target demonstrated them** — timewarrior for `remove` — and PR #38 wrote
that sequence down as a rule: interpose on first contact with a measured target, never
speculatively.

The rule's stated reason was not cost. It was faithfulness: `remove`'s fall-through
errno differs by platform (glibc retries a directory on EISDIR, Apple's BSD libc on
EPERM), and the PR recorded that a reimplementation written from memory would likely
have got it wrong. First contact was the proxy for "someone has looked at what this
function actually does".

Three things have happened since.

1. **The proxy stopped tracking the thing it stands for.** `spike/toys/toy_mkstemp.c`
   measured `mkstemp` on 2026-08-22 and it was not interposed, because a toy is not
   "a real target". So the repository had a measured member and a standing refusal to
   act on the measurement — the rule was gating on the encounter, not on the knowledge.
2. **The cost of waiting is a class of targets, not a class of bugs.** The canonical C
   atomic replace is `mkstemp` + write + fsync + rename. With an oracle such a target
   refuses (`oracle_missed_operation`); without one it reaches PASS only under
   `--allow-unverified`. Measured 2026-08-31: that PASS covered **four crash points
   where the program has five** — the creation was never explored. The report said
   `NOT VERIFIED`, which is true, and is a different sentence from "one crash point
   fewer than this program has". Nothing said the second one.
3. **The measurement that would settle faithfulness is cheap and repeatable.** Running
   the target under `--oracle` compares the shim's account against strace attempt by
   attempt. A reimplementation that gets the sequence wrong desynchronises and the run
   refuses. That is a *proof obligation a replacement can discharge*, and it does not
   need a real-world encounter to be discharged.

## Decision

**Interpose a member of this class when its reimplementation is proven against the
oracle on a committed toy that exercises it — not when a real target first demonstrates
it.**

The trigger moves from an event to a property. Concretely, a member may be taken when
all three hold:

1. What the real function issues is **measured**, not recalled, and the measurement is
   committed.
2. The replacement reimplements that sequence through the recorded wrappers, one
   recorded attempt per attempt, so a failed attempt counts on both sides.
3. A committed check runs the member under the oracle and requires a verdict; the check
   has been seen red against a build without the replacement.
4. **A committed check compares the replacement's answers against the real function's,
   on the platform it is installed on**, for inputs a successful run does not reach —
   because a replacement that gets the contract wrong does not add an observation, it
   changes what the target does.

Clause 4 was not in the first draft of this rule, and the review that added it found
why it has to be: **the two platforms do not agree on this family's contract.** glibc
clears the access mode out of `mkostemp`'s caller flags; Apple's libc rejects anything
outside `{O_APPEND, O_CLOEXEC, O_SHLOCK, O_EXLOCK}` with EINVAL, `O_RDWR` included.
glibc wants exactly six `X`s before the suffix; Apple takes the whole trailing run and
treats none as a literal name. A replacement written from one platform's reading and
installed on both would have made calls succeed on macOS that the real libc refuses.

`spike/measure-libc-internal.sh` carries clauses 3 and 4 for this class —
`spike/toys/toy_temp_rules.c` is run twice, once plain and once under the shim, and the
outputs must be identical — and `spike/libc-internal/RESULTS.md` is the measurement.
Five members were taken under this rule in the change that carries this ADR: `mkstemp`,
`mkostemp`, `mkstemps`, `mkostemps`, `mkdtemp` (contract v13).

**What these clauses prove, stated narrowly, because the first draft of this paragraph
overstated it and review said so.** Clause 3's toy drives one *successful* attempt per
member, so "the accounts agree attempt by attempt" is verified for the attempt a clean
run makes. Clause 4's differential covers template rejections and one non-EEXIST
failure (a read-only directory), comparing return values and `errno` rather than the
oracle's account. **The EEXIST retry itself is exercised by neither**: forcing a
collision means filling the candidate space, which is 62⁶ for a normal template. That
branch is held by reading the code, and this sentence is where that is admitted rather
than in nobody's head.

**What does not change**: a replacement still reimplements rather than forwards, still
records before it calls, and is still written from a measurement rather than from
memory. Clause 1 is PR #38's reason, kept and made explicit; only its proxy is dropped.

## Alternatives considered

**Keep first contact and wait.** Rejected. It is the status quo whose cost is item 2
above, and the 2026-08-22 measurement shows the proxy no longer tracks knowledge: the
repository would have gone on refusing to act on a member it had already measured.

**Take every member of the class at once.** Rejected, and the change that carries this
ADR does not do it. `dprintf`/`vdprintf` fail clause 1 in a way no toy can repair:
glibc splits a large write at 8192 bytes, so a replacement writing once would delete a
crash point the real program has, and one that split would hard-code an undocumented
libc internal that differs by platform. They stay a wall with the number that makes
them one. Blanket coverage would have quietly taken them.

**Detect rather than interpose** — refuse when the target's import table names a member.
Rejected. An import does not imply a call: cargo imports libc `rename` and issues a raw
syscall instead (#217), which is the same argument running the other way. This would
refuse targets that are fine.

**Wait for `--oracle-fs-usage` to carry it on macOS.** Rejected as a substitute. That
route costs root on every run and covers a different edge — libSystem calling its own
export (ADR 0034). The replacements here work on both platforms because a target's own
call into libc is the edge dyld *does* rewrite.

## Consequences

- **Contract v12 → v13.** No new op class and no new `unknown_reason`: the attempts
  record as `.open` and `.mkdir`, which both observers already classify, so the closed
  set stays at thirty-four and `docs/contract-freeze.md` is untouched. The version moves
  because the account of an unchanged target moves, and crash-point numbering does not
  carry across versions — **every saved case from v12 replays as
  `case_no_longer_applies`**. That cost is real and is not paid for here: migrating
  saved cases across a bump is #279, open, in another batch. This change adds one more
  bump to the population that issue is about.
- **`#39` closes**, and the lookout it carried becomes this rule plus the standing
  check. What used to be "watch for a target that demonstrates a member" is now "a
  member is taken when its replacement can be proven", which nobody has to remember.
- **The class row moves on `docs/target-classes.md`** from "Not yet measured" to the
  measured walls, and says which members are walls and which are not.
- **A future member costs a toy subcommand and a declaration line**, not a dogfood run.
  If one is added and left undeclared, the drift check in `--selftest` fails: the
  declared list is held against the toy's own dispatch.
- **sunset**: if clause 3 ever becomes unenforceable — a member whose oracle comparison
  cannot be run in CI — this rule has no teeth for that member and the member stays a
  wall, recorded, rather than being taken on the first two clauses alone.
