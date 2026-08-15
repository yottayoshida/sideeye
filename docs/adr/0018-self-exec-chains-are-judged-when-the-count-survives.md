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
  off at. Wrong base, a second exec while the window is open, or end of trace:
  the chain broke, and the refusal names the ways an image change escapes
  observation (execl family and `fexecve` are not interposed; a static image
  loads no shim; a stripped environment carries nothing).
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
  #123 stays open for it.
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
