# 0018 — Self-exec chains are judged when the count survives the image change

Status: Accepted (with the implementing PR; the slice was ruled at plan approval, 2026-08-15)
Date: 2026-08-15
Issue: #123

## Context

A target that replaces its own image (`execve` of the same pid) was refused as
`child_process_detected` from v3 on, because crash points are addressed by an
operation count and the counter died with the image. The #118 assisted cohort
measured the cost: pass — a shell CLI whose first act is replacing itself with
its interpreter — went UNKNOWN at that first exec, and the cohort's scoring
named the judge's reach as the binding constraint. Shell-driven CLIs hit this
as a class: a shell must exec what it runs.

The pre-implementation measurement (plan, 2026-08-15) sharpened the goal: in
`pass mv`, the primary self-execs (`pass`→`bash`), but the state mutations are
performed by fork+exec children (`mkdir` pid 62, `renameat2` pid 65). So this
slice does NOT take pass to a verdict — it takes pass past the exec refusal to
the precise child refusal, and takes tail-exec chains (a wrapper that ends in
`exec real-binary`; the toy's TOY_SELFEXEC shape) to full verdicts.

## Decision

Judge a single-pid exec chain when — and only when — the operation count
provably survived the image change (trace contract v10):

- The shim's exec wrappers (`execve`, `execv`, `execvp`) carry the current
  count in `SIDEEYE_SEQ_BASE`. Subject only: the carry is gated on
  `getpid() == armed_pid`, which structurally excludes forked and vfork'd
  children (the vfork child POSIX restricts to `_exit`/exec never reaches the
  environment mutation; `execve` rebuilds envp in a stack frame — no heap, no
  shared global). Overflow or formatting failure carries NOTHING rather than
  truncating the target's environment; a missing carry refuses downstream.
  A failed exec unsets the variable on the way out.
- The re-run `init()` continues numbering from the base, and `shim_ready` —
  whose seq was always 0 through v9 — re-announces it.
- The engine opens a continuation window at a subject exec record and closes
  it only on a same-pid `shim_ready` carrying exactly the count the chain left
  off at. Wrong base or end of trace: the chain broke, and the refusal names
  the ways an image change escapes observation (execl family and `fexecve` are
  not interposed; a static image loads no shim; a stripped environment carries
  nothing). **This clause said "a second exec while the window is open" as a
  third way until 2026-09-07; see the amendment below, which removes it.**
- A new numbering-integrity refusal (`sequence_numbering_broken`) compares the
  subject's kill-point record COUNT with its highest sequence number, in the
  recording and in every world. A restarted counter is a duplicate number, and
  `prefixHash` provably cannot see duplicates (it probes 1..k and stops at the
  first match) while `logicalAddress` takes the last match — renumbering could
  produce a confident verdict about the wrong operation. TOY_EXECL (an
  uninterposed exec) is refused structurally by the double-announcement rule
  before this check runs; the numbering refusal is the second net behind it,
  and R1 measured why the second net alone was not enough: with zero in-scope
  operations before the exec its two sides are trivially equal, and the run
  reached a verdict until the structural rule existed. With both numbering
  instances disabled AND the structural rule absent, the renumbered run exits
  0 — a false PASS (the mutant that saw the check red).
- The oracle's own primary-exec refusal is REMOVED. Chain integrity is the
  shim's evidence to give, and the engine holds it structurally: a second
  same-pid `shim_ready` with no exec record before it IS an image change (the
  constructor runs once per image), and an open window that never closes is a
  broken chain — both refuse without needing the oracle. The oracle's
  completeness comparison additionally refuses when a post-exec in-scope
  operation escaped the shim. (The oracle keeps refusing raw threads,
  shared-fs clones and unshare, and keeps its child-touch witness.)

## Alternatives considered

- **Per-image segments** — address crash points as (exec-generation, index).
  Replay-stable too, but it changes the case format, the report's address
  language and every consumer, for no additional power over a continued count
  in the single-pid slice. Rejected as over-general for this step.
- **Full multi-process** — the real prize and the issue's stated non-goal for
  a first slice; per-process traces and cross-process ordering are a redesign.
  #123 stays open for it. **(Superseded by the amendment below: #123 closed 2026-09-02, and this slice is held here rather than by an issue.)**
- **Refusal-precision only** — no judging change. Rejected: pass stays parked
  at the FIRST wall and tail-exec chains (measured judgeable with the count
  carried) stay unjudged for no reason.
- **No contract bump** (the plan's initial leaning) — rejected in review:
  `SEQ_BASE` and the `shim_ready` seq are a shim↔engine protocol change, and a
  v9 shim under a v10 engine would restart numbering exactly where the engine
  now tolerates an exec. The version guard exists to turn that pairing into a
  refusal; contract v10. Cost: the four v9 assisted saved cases re-record from
  their committed defines (the #82-class cost the issue priced in), and the
  buku inspection case (#133's investigation record) stays v9 deliberately —
  its claim is carried by its transcript and worlds log, not by replayability.

## Consequences

- TOY_SELFEXEC reaches full verdicts across the image change — the planted bug
  is FOUND at crash point 8 of 8 with the oracle agreeing on all 8 operations
  spanning two images (measured in the container; acceptance pins it).
- pass advances from "the target replaced its own image" to the precise
  child-refusal, with the chain judged up to the children. Its verdict needs
  the multi-process slice; #123 remains open and says which slice.
- macOS is unchanged: SIP strips `DYLD_INSERT_LIBRARIES` from protected
  binaries, the far side of such an exec is never observed, and the broken
  chain refuses — honestly, with the escape named.
- A self-exec sets a boundary, so such targets require `--oracle` on Linux
  (`boundary_without_oracle`), which is the configuration the acceptance and
  the cohort already use.

**Amended 2026-09-02 (#123 closed).** The second half of this decision — "#123 remains open
and says which slice" — is retired. What #123 still asked for was that a refusal say which
slice stopped the run, and that is now true: the `processes` account, which the JSON has
carried on every refusal since #405 and which the ordinary FAIL and PASS blocks both print,
is printed in the UNKNOWN text block too, so a target refused for a child touching the state is told that its
own image change was followed. The multi-process slice is not built and is not filed as an
issue: it fails this repository's threshold for opening one (no hang, crash, data loss,
silently wrong result, or violated documented promise — a refusal is the designed answer,
DESIGN §4.5), so **this ADR is where it lives**. What it would cost, ruled at the same time:
crash points are addressed by one deterministic operation count, and across processes the
engine cannot reproduce the interleaving that count depends on — so the slice is not a
widening of coverage but a wager on the reproducibility the product rests on (DESIGN.md §4.7: "everything that affects a verdict — exploration, violation detection, shrinking, replay — is deterministic"),
It needs its own design work, not a follow-up ticket.

**Corrected 2026-09-02, same day.** The amendment above first added "and it touches a frozen
surface (replay compatibility, surface 4)" to that list of costs. That is the opposite of
this repository's recorded reading, and review caught it. Implementing the slice is a
trace-contract event, and `docs/contract-freeze.md` surface 4 says a future trace-contract
bump is *not* a broken promise, because old cases refuse with the mismatch named and that
refusal is the promised behaviour. The freeze audit's manifest records the same judgement:
`spike/freeze-audit/audit.tsv`'s row for #123 carries a surface forecast of **none**, with
that sentence as its reason. So the freeze is not what stands in the way of the
multi-process slice. What stands in the way is the determinism above.

**Amended 2026-09-07: a second exec record while the window is open is removed from the
ways a chain breaks. It named a failed attempt, not an image change.**

The clause's stated reason was that such a record "means the intermediate image was never
observed". That is false, and the measurement is ordinary: an operation written as
`#!/bin/sh` ending in `exec <name>` resolves the name through `PATH`, and dash issues one
`execve` per entry. Six returned ENOENT before the seventh landed. The shim records before
each call — it cannot know which attempt will succeed — so the trace carried **seven exec
records for one image change**, and the run was refused `child_process_detected` while the
next `shim_ready` carried **exactly the count the chain left off at**. Three real defines
meet this: `spike/unknown-rate/defines-b/hnb` and `.../lbdb` through the uniform protocol's
`op.sh`, and fontforge through a wrapper written for an argument carrying spaces (#506).

**What the three do on this engine, measured 2026-09-07 rather than forecast.** The wall
this removes was one wall of several for two of them, and saying which is the point of
listing them:

| Define | At `4083db2` | With this change |
|---|---|---|
| hnb | `child_process_detected`, 0 crash points | **FAIL, 1 violation over 3 crash points**, oracle agreeing on 3 operations — the verdict and the count `spike/followup-95/artifacts/report-argv.json` recorded for the *argv* spelling of the same question on 2026-08-16 |
| lbdb | `child_process_detected`, 0 crash points | `child_touched_state_dir` — the chain is followed (`the subject's image replaced 1 time(s), chain unbroken`) and then another pid unlinks a temp file in the judged state. The multi-process slice, which this ADR still declines |
| fontforge | `child_process_detected` on the wrapper | the wrapper refusal is gone; the target's own wall is `oracle_missed_operation`, stdio past ADR 0005's flush boundary, measured 2026-09-06 (`spike/dogfood/2026-09-06-userview-2/`) |

So: one of three reaches a verdict, one advances to the next wall, and one advances to a
wall of its own that predates this. The hnb and lbdb runs used `bgroup.sh` under both
engines in a **rebuilt** `sideeye-ur-extra` — image id `9fec97c7`, not the sweep's
`df66b6e1` — so the apparatus is the recipe rather than the sweep's artifact, and the
transcripts are not committed.

**Why a second record cannot be a new image.** Its writer has the shim active and answers
`getpid()` with the subject's pid. Any image that can write a record announces itself
first: the shim sets `active` immediately before writing `shim_ready`, with no statement
between them, and that record's path is the state directory whose length `init` has already
bounded — so the announcement is not the one write that fails while later ones succeed. A
forked or vfork'd child answers `getpid()` differently and is excluded before this point
(the pid is read live per record, ADR 0002 decision 6). So a second record with no
announcement between was written by the image that wrote the first, which is to say the
first attempt returned.

The base is now **refreshed** at each attempt rather than fixed at the first. That is part
of the correction, not a courtesy: the shim carries the count as it stands when `exec` is
*called*, and the call that succeeds is the last attempt, so a wrapper that writes state
between two attempts announces the later count and a fixed base would refuse a chain that
held.

**What the removed net covered, and what still does.** The comparison it stood beside —
does the announced count equal the count the chain left off at — is untouched, and it is
what catches a chain that genuinely broke. The one case where that comparison cannot speak
is a subject with **zero** in-scope operations before the exec: both sides are then
trivially equal, which this ADR already recorded above. Until now a second exec record
refused such a run; from here it does not, so the shape is reachable through repeated
attempts as well as through the single record that already reached it. **Three layers
stand between that and a wrong verdict. The first was run; the other two were read, and
the difference is marked on each rather than dissolved into the count:**

1. A recorded boundary with no oracle refuses `boundary_without_oracle` — and `.exec`
   counts as a boundary for that purpose whether or not the chain held, so a self-exec
   chain requires `strace` on Linux and is refused under `--oracle-fs-usage`.
   **Measured rather than read**: the retried-attempt define run without an oracle
   refuses `boundary_without_oracle` on this change, where the build before it refused
   `child_process_detected` first and never reached the question.
2. With `strace`, an intermediate image that reached the state directory without the shim
   leaves the two accounts short of each other and the run refuses
   `oracle_missed_operation`. An `exec` preserves the pid, so such an image is the subject
   as far as scope is concerned. **Read, not run**: the mechanism is the same one
   metaflac and fontforge met (`docs/target-classes.md`), and no target was built here to
   put an unshimmed image inside a surviving chain.
3. Independently of any oracle, a path that changed with no recorded operation naming it
   refuses `state_changed_unaccounted` (#405). Layers 1 and 2 need an oracle and this one
   does not, which is why all three are listed rather than one standing for the others.
   **Read, not run**, for the same reason as layer 2.

Numbering is also unharmed in that case: zero plus a fresh count is the correct sequence,
not a duplicate, so the `sequence_numbering_broken` check has nothing to catch.

**One case the three layers do not cover, named rather than left out** (review). An
intermediate image that loads the shim and whose `shim_ready` write is *lost* — `writeRecord`
discards `writeAll`'s result — would leave its exec record behind with no announcement, and
the refreshed base would then match whatever the last image announced. The old rule refused
that shape by refusing every repeated record. Two things bound it: the realistic write
failures on an `O_APPEND` regular file (`ENOSPC`, `EIO`) are not transient, so the records
after the lost one fail too and the window stays open to the end of the trace, which refuses;
and an image whose records *do* land has its operations recorded and its numbering
continuous, so no crash point addresses an operation other than the one that ran. What is
genuinely uncovered is a transient loss of exactly that one write, and the structural
argument in `src/engine/trace.zig` does not exclude it — it only excludes the failure modes
of the encode.

**What this does not change.** The trace contract stays at v13 — no record shape, no op
class and no `unknown_reason` moves, so saved cases keep replaying. The uninterposed exec
family (`execl`, `execle`, `execlp`, `execvpe`, `fexecve`) is still an escape and is still
caught by the double-announcement rule.

**The demand for closing that escape was measured on 2026-09-07, and it is zero.** The
question is not whether the escape exists — the double-announcement rule exists because it
does — but whether a real target reaches it. `execl` and its siblings become `execve` at
the syscall layer, so `strace` cannot tell them apart; what can is the engine's own
signature, a second `shim_ready` from one pid with no `exec` record of that pid between the
two. Reading ELF `.dynsym` for undefined `STT_FUNC` entries, **33 of 514 dynamic
executables in the sweep image import one of the five** — among them `tar`, `perl`,
`python3.13`, `git`, `rsync`, the `dpkg` family, `sort`, `split` and `install`. Run under
the shim, **0 of 35 produced the signature**: every one execs exactly once, through a path
the shim already interposes. `tar` was then driven through a real define and reaches **PASS
over 2 crash points**. An import is not a call — the same reading ADR 0036 records for
cargo's `rename@GLIBC_2.17`.

Both controls ran: `TOY_EXECL` produces the signature (`readies=2 execs=0`) and
`TOY_SELFEXEC` does not (`readies=2 execs=1`), so a zero here is distinguishable from an
instrument that stopped working. **What the measurement did not cover**: it invoked each
binary once (`--help`), which reaches a launcher that re-execs itself at startup and does
*not* reach an `execl` on a write path. Closing the escape would cost a shim change and an
account change for targets that are refused today; the reach it buys is unmeasured and, on
this evidence, small. Declined on that basis rather than on a demonstration that it cannot
work — the shape ADR 0034 records for the generated interposer. Both of the report's sentences about this were wrong in ways this change also
fixes: the account said "chain unbroken" over a run whose chain had broken, and it reported
a disagreement between witnesses on a run where the shim claimed no second process. The
second is a `docs/report-schema.md` promise about the `processes` field, which is why it is
here rather than filed.
