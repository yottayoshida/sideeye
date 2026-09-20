# 0081 — The scale benchmark separates crash points from state size, and declares its reading first

Status: Accepted (2026-09-20)

## Context

#621 asks how `explore` scales in wall time, memory, work-directory growth and report size as
the number of state-changing operations grows, and forbids adding sampling, `--max-worlds` or a
quick mode until that is measured. Two records already exist and neither answers it:
`RESULTS.md` (#262, ADR 0042) varied **state size** at a fixed four crash points, and
`RESULTS-AT-SCALE.md` (#613) measured real targets at their natural scale and said in as many
words that "the sample … insufficient to say what happens in the 100-plus class."

The issue's first acceptance condition is that "a deterministic scalable target and benchmark
protocol are committed **before final numbers are published**", so the apparatus and the numbers
are two merges by the issue's own requirement rather than by convenience.

## Decision

**The synthetic target scales crash points without scaling the judged state, and the state size
is a separate axis supplied by padding the operation never touches.**

The first draft did the opposite — N operations over N files — and measured, per-world cost came
out about six times higher and rising. That is the conflation #621 names ("so `worlds` and
`state bytes` are not conflated"), and it would have attributed the slope to the wrong resource.
The target performs N create-write-unlink cycles on a temporary path: temporaries appear in
neither snapshot, so the judged set does not grow with N, the run PASSes, and no case is saved.
Measured on the drafting machine: crash points are exactly **3N**, state stays one file.

**The requested N travels as a command argument, not an environment variable.** The benchmark
records the crash-point count the engine reported, never the number that was asked for, and the
row carries the two in separate columns so a reader can see them disagree — which they do at
every one of the six grid points, none of which is a multiple of three.

*A correction to this paragraph's first draft*, which said the argument "lands in the report's
`operation` field" and that this made the claim checkable from one report. **The report has no
`operation` field** — measured against `src/report.zig`'s emitter and the field list in
`docs/report-schema.md`. That was the only stated reason for preferring an argument over an
environment variable, and it was false. The reason that stands is smaller and real: an argument
is visible in the process table and in any transcript of the command, where an ambient variable
is not, and a benchmark's parameters should be readable from the command that ran it.

**Peak RSS comes from `resource.getrusage(RUSAGE_CHILDREN).ru_maxrss` in the Python that already
launches the engine**, not from `/usr/bin/time -v`. GNU time is a separate Debian package and is
not in `spike/Dockerfile`; adding it would run apt inside an image whose own comment pins its
versions for the blind-hunt candidates. The rusage field also settles by definition what the
issue asked to be stated — it is the maximum over waited-for descendants, never the sum of
processes alive at once. **Its unit differs by platform** (bytes on macOS, KiB on Linux), which
the protocol states because the drafting measurements hit it.

**The reading is declared before the run.** #621 asks for "the CI-use reading rather than a
pass/fail threshold" up front, so the protocol publishes what a 100-, 500- and 1000-world
operation is expected to cost, extrapolated from the drafting measurements, and the second merge
sets the measurement beside it. A reading written after the numbers is a description, not a
prediction.

**Timing and sampling are different legs.** The maximum work-directory size is sampled, and a
`du` over a large padding tree is heavy enough to pollute the wall clock it would be recorded
next to. The wall-clock legs carry no sampler; the sampled maximum is taken on its own
repetition and labelled a lower bound with its interval.

## Alternatives considered

| rejected | why |
|---|---|
| **A new mode inside `spike/toys/toy.c`** | 1,778 lines and some sixty modes; a benchmark's per-operation work has to be auditable at a glance, and `spike/toys/` already holds one toy per question. |
| **N operations over N files** (the first draft) | Couples the two axes the issue requires be kept apart. Measured six times the per-world cost, all of it attributable to the state tree rather than to the world count. |
| **N through an environment variable** | Works. Rejected for a weaker reason than the first draft of this ADR gave (see the correction above): an argument is visible in the command that ran the cell, an ambient variable is not. The claim about reported-versus-requested counts rests on the two columns either way. |
| **`/usr/bin/time -v`** | Not in the container, and adding it edits an image whose versions are pinned for another campaign. |
| **Extrapolating the grid's runtime from one large-state, small-N cell** | Proposed in review on the premise that per-world cost is independent of N. Measured false: rows 1 and 3 of the committed pilot put per-world at 0.034 s over 103 worlds and 0.071 s over 1,003, so that shortcut underestimates. The pilot takes the state, mode and container multipliers from single cells and the N dependence from those two rows. |
| **Exact maximum work-directory size** (inotify or similar) | Heavier than the sampler it would replace, and it would sit inside the measurement it is trying to observe. |
| **Three merges** (apparatus / numbers / conclusion) | Nothing here is sealed, so there is no blindness to protect by separating the conclusion from the numbers; #613 put its conclusion in the same record as its figures. |

## Consequences

- The benchmark measures Sideeye's orchestration cost, not an application's. What it therefore
  cannot say is what a target whose own work grows with N costs — the issue asks for that
  deliberately, and the real-target anchor is what keeps the toy honest about it.
- The figures will be one machine's, as `RESULTS.md`'s are. The host is recorded in each run
  header and the record says so rather than generalising.
- The grid is 2 observation modes × 2 checker legs × 3 repetitions × 2 state sizes = 24 legs of
  **1,926 worlds** each, plus six sampling cells. The large state size is **chosen from a
  per-world budget** rather than picked and then costed. **The pilot put the whole grid at about
  a quarter of an hour**, not the three and a half this ADR's draft estimated from host figures:
  the container turned out to be about seventeen times faster than the host, the opposite of the
  direction both the plan and its review assumed. **That removes runtime as the reason for
  splitting this into two merges**; the reason that stands is #621's first acceptance condition,
  that the protocol is committed before the numbers.
- If the result is that exhaustive exploration stays practical across the envelope, **that is a
  complete answer** and no feature follows. The issue says so, and this ADR does not reserve the
  right to add one anyway.
