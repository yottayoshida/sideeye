# The libc-internal-call class, member by member (#39) — 2026-08-31

The class is libc functions that change state through calls made *inside* libc, which
never cross the PLT and so reach no `LD_PRELOAD` or `__DATA,__interpose` replacement of
`open`, `mkdir` and friends. `docs/target-classes.md` has carried it since 2026-08-17,
with two members measured on 2026-08-22 (`spike/cohort4/mkstemp-class.txt`) and the
rest projected from the mechanism.

This is the run that measured every member the page names, and the change that followed
from it. Reproduce with `sh spike/measure-libc-internal.sh` inside the Linux container.

## Provenance

| | |
|---|---|
| engine | `sideeye 1.0.0`, trace contract **v12** before and **v13** after |
| libc | `ldd (Debian GLIBC 2.36-9+deb12u14) 2.36` |
| compiler | `gcc (Debian 12.2.0-14+deb12u1) 12.2.0` |
| arch | `aarch64` |
| oracle | `/usr/bin/strace` |
| toy | `spike/toys/toy_mkstemp.c`, sha256 `2230d50f0517dea116033a58ec4c689611dab0dbb93fb7d366cc4a7a036e6da3` |

The toy hash is the *source*, and a source hash alone does not pin a measurement: the
compiler, its flags and the libc are all above for the same reason. `rotate` is
unchanged from the 2026-08-22 run; the per-member subcommands are new.

## What the real functions issue

Measured with `strace` on a plain C program, not recalled from documentation:

| member | syscall | note |
|---|---|---|
| `mkstemp` | `openat(AT_FDCWD, path, O_RDWR\|O_CREAT\|O_EXCL, 0600)` | one attempt |
| `mkostemp` | the same, plus the caller's flags (`\|O_APPEND` observed) | |
| `mkstemps` | the same; the six X's sit before the suffix | |
| `mkostemps` | the same, plus the caller's flags | |
| `mkdtemp` | `mkdirat(AT_FDCWD, path, 0700)` | **`mkdirat`, not `mkdir`** |
| `dprintf` | `write` — **8192 then 807** for a 8999-byte payload | one write for a short one |
| `vdprintf` | one `write` for a short payload | |
| `tmpfile` | `openat(AT_FDCWD, "/tmp", O_RDWR\|O_EXCL\|O_TMPFILE, 0600)` | ignores `TMPDIR`; no directory entry; no `unlink` |

Two of these contradict what this repository said before the run:

- **`tmpfile` does not honour `TMPDIR`.** `spike/toys/toy_mkstemp.c` carried the
  parenthesis "(it honours TMPDIR)" and nothing had ever measured it. With `O_TMPFILE`
  there is no name anywhere, so `tmpfile` cannot mutate a state directory at all — it
  is not a member of the class. The comment is corrected in place.
- **`mkdtemp` issues `mkdirat`.** The plan for this change said `mkdir`. Both reach the
  same replacement, so nothing rested on it, but the page now says the measured one.

## The verdicts, before and after

Same toy, same declarations; only the engine and shim change. `sideeye explore
--oracle /usr/bin/strace`, one member per run:

| member | v12 (before) | v13 (after) |
|---|---|---|
| `mkstemp` | `UNKNOWN oracle_missed_operation` | **PASS, 5/5 explored worlds** |
| `mkostemp` | `UNKNOWN oracle_missed_operation` | **PASS, 5/5 explored worlds** |
| `mkstemps` | `UNKNOWN oracle_missed_operation` | **PASS, 5/5 explored worlds** |
| `mkostemps` | `UNKNOWN oracle_missed_operation` | **PASS, 5/5 explored worlds** |
| `mkdtemp` | `UNKNOWN oracle_missed_operation` | **PASS, 2/2 explored worlds** |
| `dprintf` | `UNKNOWN oracle_missed_operation` | `UNKNOWN oracle_missed_operation` |
| `tmpfile` | PASS, "performed nothing that can change the judged state" | unchanged |

Five members move from a refusal to a verdict. `dprintf` is unchanged **by decision**
(below) and `tmpfile` is unchanged because it was never a member — which is what makes
the two of them a control this measurement did not have to invent: they say the change
is about the five replacements rather than about the harness.

## What the refusal was hiding, without an oracle

The refusals above are the *oracle's* doing. Run the same members with no oracle and
`--allow-unverified` — the weaker claim a caller can choose — and the shape of the gap
appears:

| member | v12 | v13 |
|---|---|---|
| `mkstemp` | **PASS, 4/4 explored worlds** | **PASS, 5/5 explored worlds** |
| `mkdtemp` | `UNKNOWN state_changed_without_ops` | PASS, 2/2 explored worlds |

The `mkstemp` row is the one to read twice. v12 answers PASS over **four** crash
points where the program has **five**: the creation is not among them, so no world ever
asked what happens if the machine dies between the temp file existing and the first
byte reaching it. The report said `NOT VERIFIED (--allow-unverified) — nothing checked
what the shim reported`, which is true and is not the same sentence as "one crash point
fewer than this program has". Nothing said that one.

`mkdtemp` refuses in v12 instead, and the difference is not a second mechanism: the
directory is that run's *only* operation, so `mutation_count` is zero and the
structural detector fires. Put any other recorded mutation beside it and the detector
goes quiet — the shape ADR 0026 names, and the same one #405 exploited.

## The change

`shim/src/ops.zig` reimplements the five creators through the recorded wrappers, the
way `remove` has since contract v7 and for the same reason. Each attempt is recorded
before it runs, so a failed attempt counts on both sides and the two accounts cannot
desync. Contract v12 → v13: no new op class and no new `unknown_reason` (the attempts
record as `.open` and `.mkdir`, which both observers already classify), but the account
of an unchanged target moves, and crash-point numbering does not carry across versions.

## macOS, measured rather than inferred

The same replacements install on macOS, where interposition reaches a target's own call
into libc — the edge ADR 0034 measured as reached — and not libSystem calling its own
export, the edge that stays open and belongs to `--oracle-fs-usage`. Run on the host
(macOS 15, arm64) with `--allow-unverified`, since there is no free oracle here:

| member | v12 | v13 |
|---|---|---|
| `mkstemp` | PASS, 4/4 explored worlds | **PASS, 5/5** |
| `mkostemp` | PASS, 4/4 | **PASS, 5/5** |
| `mkstemps` | PASS, 4/4 | **PASS, 5/5** |
| `mkostemps` | PASS, 4/4 | **PASS, 5/5** |
| `mkdtemp` | PASS, 2/2 | PASS, 2/2 — **unchanged** |

The four file creators gain the crash point they gain on Linux. **`mkdtemp` did not,
because on macOS it was never missing**: v12 already recorded its directory, which is
not what the Linux side does — there v12 refuses the same run with
`state_changed_without_ops`, having recorded nothing at all.

That asymmetry is an observation, not an explanation. `libsystem_kernel.dylib` exports
`_mkdir` and `_open`, so a call from `libsystem_c`'s `mkdtemp` into it would cross an
image boundary and be interposed, which would account for it — but **this run did not
measure which image the call leaves from**, and the reading that would settle it
(`dyld_info -imports` on `libsystem_c`) returned nothing for either name, which is as
likely to be the query being wrong as the answer being no. Recorded as unexplained.
The replacements are correct either way: after this change the record comes from the
shim's own `mkdir` on both platforms rather than from whichever inner call happened to
be visible.

## The contract, and where the two platforms disagree

A replacement that gets this wrong does not add an observation — it changes what the
target does, which is the same objection that keeps `dprintf` out. Measured both ways
on 2026-08-31, by running each case rather than by reading a header:

| | glibc 2.36 | Apple libc (macOS 15) |
|---|---|---|
| `mkostemp` flags | **clears the access mode** out of the caller's flags, passes the rest | **rejects** anything outside `{O_APPEND, O_CLOEXEC, O_SHLOCK, O_EXLOCK}` with EINVAL — **`O_RDWR` and `O_WRONLY` included** |
| six `X`s | required, and exactly those six are replaced | replaced |
| five `X`s | EINVAL | all five replaced |
| eight `X`s | last six replaced, the leading two survive (`c.XXXXXXXX` → `c.XXrZr5DH`) | **all eight replaced** |
| no trailing `X` | EINVAL | **succeeds under the literal name** (`d.XXXXXXn` unchanged) |
| `mkstemps` with a suffix | same rule before the suffix | same rule before the suffix |

`shim/src/ops.zig` branches on the platform for both halves.
`spike/toys/toy_temp_rules.c` is the standing check: it prints one line per case and is
run twice, once plain and once with the shim loaded, and the two outputs must be
identical. Twenty-four cases on Linux, more on macOS where `O_SHLOCK`/`O_EXLOCK` exist.
Names are random, so a case reports the *shape* of the answer rather than the name.

**That shape needed eight repeats, and finding out why is the point.** The first version
ran each case once and marked a position "replaced" when the character changed — but a
replacement draws from 62 letters, so a position filled with a literal `X` reads as
untouched. On `c.XXXXXXXX` under glibc that turned a correct run into a reported
difference. A position is marked replaced if it differed in **any** of eight runs, which
needs all eight to draw `X` to stay wrong.

Seen red the way the rule requires: with the Darwin branch applied on glibc
(`if (is_darwin)` → `if (true)`), the differential reports the flag cases glibc accepts
and Apple refuses, and two members fail their declaration beside it — three failures,
attributed. An earlier attempt at that red changed a length guard the second condition
already covered, and the check stayed green: **a mutant that compiles and changes
nothing is not a mutant**, and it was replaced rather than counted.

## One defect the reimplementation had, and how it was caught

The first version ORed the caller's flags into the open raw. `mkostemp` and `mkostemps`
take caller flags, and **the real ones clear the access mode out of them** — measured
rather than read, because no man page for it is installed here:

```
mkostemp(t, O_WRONLY|O_APPEND)
  → openat(AT_FDCWD, "…/wronly.NPfsEU", O_RDWR|O_CREAT|O_EXCL|O_APPEND, 0600) = 3
```

Raw ORing would have produced access mode 3 rather than `O_RDWR`, and the create would
have failed where libc's succeeds. Masking `O_ACCMODE` off the caller's flags fixes it.

The toy's `mkostemp` and `mkostemps` subcommands pass `O_WRONLY` on purpose so the
measurement leg covers it: with the mask removed, **exactly those two members go red**
and the other five stay green — the attribution that makes it a mutation rather than a
coincidence. Without the flag the leg would have passed either way.

## The two the change does not take, and why

**`dprintf` / `vdprintf` stay a wall.** glibc splits at 8192 bytes (measured above).
A replacement is free to issue whatever syscalls it likes — the oracle sees the
replacement, not glibc, so the accounts would agree either way — but agreement is not
the whole bar. Writing the payload once would delete a crash point the real program
has: a machine dying between glibc's two writes leaves a partial file, and a target
judged under a one-write replacement would never be asked about it. Matching the split
means hard-coding 8192, which is an undocumented libc internal that differs by platform
and version, and guessing at libc internals from memory is the specific failure PR #38
was written to stop. So the honest state is a wall, recorded, with the number that
makes it one.

**`tmpfile` is not a member on Linux, and is one on macOS.** glibc's `O_TMPFILE` route
creates no directory entry, so there is nothing in a state root for either observer to
miss. Apple's does the opposite — measured with `F_GETPATH` on the returned descriptor:

```
TMPDIR unset        nlink=0 path=/private/tmp/tmp.tGiWUe
TMPDIR=state root   nlink=0 path=<state root>/tmp.oprM80
```

A real name inside the judged directory, unlinked immediately (`nlink=0`), and a crash
between the two leaves it behind. So on macOS `tmpfile` is a member and stays a wall;
taking it would mean choosing one of the two platforms' behaviours for both, which is
the thing this change refuses to do everywhere else. **The first draft of this record
said flatly that `tmpfile` "cannot mutate a state directory", generalising one
platform's measurement to both — review caught it, and the measurement above is the
correction.**

## What a green `measure-libc-internal.sh` does not mean

- Not that the class is closed: `dprintf` is declared `wall` and a green run **includes
  it refusing**.
- Not anything about macOS: the oracle here is strace. **What the macOS CI leg gives is
  narrower than "the same thing over there"** — it runs the contract differential
  (plain against shimmed, with the resolved-image control), not an oracle comparison.
  No CI leg drives a temp-name creator under `--oracle-fs-usage`; the acceptance check
  that used to name `mkstemp` now names `dprintf`, because its job is to pin a member
  the shim still misses and `mkstemp` stopped being one. The macOS creator numbers in
  this record were taken by hand.
- Not anything about members nobody has named. The check holds its list against the
  toy's dispatch so the two cannot drift, but neither list can notice a member that was
  never written down.
- Not that the reimplementations are byte-for-byte what libc does. What is measured is
  that both observers see the same operations; the *name* generation differs
  deliberately (no `arc4random_buf`, which reached glibc only in 2.36 while this
  repository pins no glibc floor — #161).

## The check being red

Required before it is trusted, and it is two different reds.

**Synthetic, in `--selftest`** (seven predicates, all shown red by construction): a
non-class refusal (`no_shim_marker`) must not be read as the wall; the reason appearing
inside prose must not either; an inert line with a non-zero exit is neither; and a
mutated declaration must be reported.

**Real, against the pre-change build**: with the same toy and the same declarations and
only the engine and shim swapped to `main`'s, the five creators measure `wall` against
a declared `judged` and the check exits 1 — while `dprintf` and `tmpfile` stay green.
That last part is what says the red belongs to the replacements rather than to the
harness.

The first attempt at that red was invalid and is recorded because the shape recurs:
pointing `SIDEEYE_ROOT` at the older build moved the *toy source* with it, so every
member came back `other` with "unknown command". It was red, loudly, for a reason that
had nothing to do with what the check measures. The script now takes the engine, the
shim and the toy as separate overrides so the contrast can move one axis at a time.
