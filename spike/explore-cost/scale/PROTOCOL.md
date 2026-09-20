# The scale benchmark: what is measured, and what the numbers will not say (#621, ADR 0081)

`run-cell.py` runs one `sideeye explore` and writes one TSV row. **Every figure in that row is
read back from the engine's own report or from the filesystem afterwards; nothing is the number
the harness asked for.** This page is committed before the grid runs, because #621's first
acceptance condition is that "a deterministic scalable target and benchmark protocol are
committed before final numbers are published".

The grid itself, and the conclusion about whether crash-point budgeting is warranted, are the
second merge. **Nothing here says exploration is or is not affordable.**

## The target

`spike/toys/toy_scale.c`. `rotate <N>` performs N create-write-unlink cycles on one temporary
path; `init` leaves one file. Temporaries appear in neither snapshot, so the judged state stays
at one file however large N is — the world count and the state size are separate axes, which is
what #621 requires ("so `worlds` and `state bytes` are not conflated"). The state-size axis is
padding the operation never touches, the shape `../measure.sh` already uses.

Measured: **crash points come out at exactly 3N**. The harness asks for `ceil(requested/3)`
cycles and records both the request and the report's count. The two columns differ whenever the
request is not a multiple of three, and **none of the six grid points is one** — 10, 50, 100,
250, 500 and 1000 all report a different number (12, 51, 102, 252, 501, 1002). There is no cell
in which writing down the request would pass unnoticed.

## What each column is, and what it is not

| column | how | what it cannot say |
|---|---|---|
| `wall_s`, `per_world_s` | `time.monotonic()` around the engine process | It covers engine start-up, `setup`, the recording run and two snapshots as well as the worlds, so `per_world_s` is an **upper bound** on one world — the same reading `../RESULTS.md` gives its figure. The recording run is not separable; the engine emits no timings (the report carries none but `recovery.seconds`). |
| `maxrss`, `maxrss_unit` | `resource.getrusage(RUSAGE_CHILDREN).ru_maxrss` | The **maximum over waited-for descendants**, never the sum of processes alive at once. One cell is one process and the script refuses to start if the figure is already non-zero, because it is a high-water mark that never decreases. The engine's `version` probe is itself a waited child, so a cell whose exploration never exceeds the probe reports the probe's peak — **measured on every small-state container cell in the pilot**, and the row says so rather than presenting a floor as a measurement. The unit is **bytes on macOS and KiB on Linux**; the row carries which. |
| `work_final_bytes` | walk of the work directory after the run | — |
| `work_max_bytes`, `sample_interval_s` | a sampler walking the work directory on an interval | A **lower bound**: a peak between two samples is not seen. Taken on a repetition of its own, because the walk is heavy enough to pollute the wall clock — a sampling leg leaves `wall_s` empty rather than reporting a time it disturbed. |
| `trace_bytes` | the `trace-*.bin` files alone | Not the work directory: the engine keeps one trace per world, and the directory also holds captured stdout and any saved case. The first version of this script summed the whole directory into both columns, which is two labels over one number. |
| `report_bytes`, `case_bytes` | the `--json` file; the saved case when one exists | `case_bytes` is 0 on a PASS. The deterministic-FAIL leg is what makes it a figure. |
| `crash_points_reported`, `worlds`, `verdict`, `oracle_verified` | the report | — |
| setup time, checker time | **not separable** | The engine publishes no timings. Setup can be timed on its own; a checker's cost is the difference between two legs, and a difference carries whatever else differs. The grid runs a checker leg rather than claiming to isolate a checker cost. |

**A run that did not explore produces no figures.** A refusal recorded as `0 worlds, 0 seconds`
drags every average it lands in, so such a row is `not-counted` with the reason and every
figure column empty — `../measure.sh`'s rule, kept. This is not hypothetical: the pilot's
checker cell was refused (below), and an earlier version of this script would have published it
as free.

## The pilot, measured 2026-09-20

Nine cells. Rows 1, 2, 5, 6, 7, 8 and 9 are at 100 requested crash points (102 reported, 103
worlds); rows 3 and 4 are at 1000 (1002 reported, 1003 worlds), which is where the rise in
per-world cost with the world count shows.
Host: macOS 15 / Apple M4. Container: `debian:bookworm-slim` under Docker Desktop on the same
machine, `--cap-add SYS_PTRACE`. Engine built from this branch.

| # | where | state | mode | checker | per-world | peak RSS | work max | note |
|---|---|---|---|---|---|---|---|---|
| 1 | host | 1 file | wrappers | none | 0.03443 | 5865472 | — |  |
| 2 | host | 200 × 100 KiB | wrappers | none | 0.47680 | 68370432 | — |  |
| 3 | host | 1 file | wrappers | none | 0.07110 | 12075008 | — |  |
| 4 | host | 1 file | wrappers | none | — | 12156928 | 80801520 | sampling leg |
| 5 | container | 1 file | wrappers | none | 0.00205 | 11712 | — | floor |
| 6 | container | 1 file | syscalls | none | 0.00225 | 11724 | — | floor |
| 7 | container | 1 file | wrappers | check-kept.sh | 0.00224 | 11712 | — | floor |
| 8 | container | 1 file | wrappers | true | — | — | — | not-counted |
| 9 | container | 200 × 100 KiB | wrappers | none | 0.02685 | 69320 | — |  |

RSS is **bytes on the host and KiB in the container**; the file's `maxrss_unit` column says
which, and the two are not comparable without it. Every row above was generated from
`pilot-2026-09-20.tsv` by the command in this page's history, not transcribed — an earlier
draft of this page claimed the same thing while the table had in fact been typed out, which is
the one claim a page about measurement must not get wrong.

**Two of the notes are findings, not bookkeeping.** Rows 5–7 say the engine's `version` probe
reached the same memory peak as the exploration, so **the RSS figure on a small-state container
cell is a floor rather than that run's own**; the harness discloses it instead of presenting the
probe's number as the measurement. Row 8 is the refused checker (below).

**The three multipliers the grid needed, and one surprise.**

- **State size: 13.1× in the container** (0.02685 / 0.00205), **13.8× on the host**
  (0.47680 / 0.03443), for 200 files × 100 KiB against one file. That shape was chosen by
  working back from a half-second-per-world budget using `../RESULTS.md`'s table, and it lands
  inside the budget on both.
- **Observation mode: 1.10×** (0.00225 / 0.00205) and **a cheap checker: 1.09×**
  (0.00224 / 0.00205), each at one repetition — inside the spread `../RESULTS.md` reports
  across repeated runs of one cell, so neither is a slope. Three repetitions are what the grid
  takes. Both modes reached `oracle_verified: true`.
- **Per-world rises with the world count**: on the host, 0.03443 s at 103 worlds against
  0.07110 s at 1003 (rows 1 and 3), a factor of **2.1** for ten times the worlds. Both rows are
  in the record, so this is the series a reader can check rather than one quoted from drafting.
- **The container is 16.8× FASTER than the host, not slower** (0.03443 / 0.00205). This was assumed the other
  way round while planning — a virtual filesystem was expected to cost. Per-world work is
  dominated by restoring and snapshotting a tree, and Linux does that far more cheaply here
  than macOS does. The grid runs in the container, so this is the direction that matters.
- **Sideeye refuses a checker it cannot falsify.** `/bin/true` as the cheap checker produced
  `UNKNOWN / checker_not_falsified` and no figures. The checker leg therefore needs a checker
  that *can* fail — one that reads the kept file and rejects a wrong value — and the grid
  supplies one. Found by running it, not by reading about it.

## The grid

| axis | values |
|---|---|
| crash points | 10, 50, 100, 250, 500, 1000 (requested; reported 12, 51, 102, 252, 501, 1002) |
| state | 1 file; 200 files × 100 KiB |
| observation | `wrappers`, `syscalls` — both under `--oracle /usr/bin/strace` |
| checker | none; one cheap falsifiable checker |
| repetitions | 3, with the individual values published, not only a median |

24 legs of **1,926 worlds** each (12+51+102+252+501+1002 crash points, one baseline world
apiece). **From the pilot: about 47 seconds for the twelve small-state legs
(1,926 × 0.00205 × 12) and about 10 minutes for the twelve large-state legs — roughly a quarter
of an hour in total, before the rise in per-world cost with the world count, which rows 1 and 3
put at about a factor of two over ten times the worlds.** Six sampling cells ride on top.

That number replaces the estimate this work started from, which was "about three and a half
hours" and rested on host figures. **The runtime is therefore no longer a reason to split this
into two merges**; the reason that stands is #621's acceptance condition 1, that the protocol is
committed before the numbers.

Two legs sit outside the grid, both required by #621: one deterministic FAIL (so `case_bytes`
and the evidence bundle are figures rather than zeroes), and one existing real define as an
anchor, to check the toy has not omitted a cost ordinary targets pay.

## The reading, declared before the run

#621 asks for "the CI-use reading rather than a pass/fail threshold", up front. Extrapolating
the pilot to the grid's container, small state, with a strict oracle:

| worlds | expected wall | basis |
|---|---|---|
| 100 | about 0.2 s | pilot row 5, measured |
| 500 | about 1.5 s | per-world rising with the world count: rows 1 and 3 of the record measure a factor of about two over ten times the worlds |
| 1000 | about 4 s | same |

On the large state, multiply by about thirteen: roughly 3 s, 20 s and 50 s.

### The second clause, declared before the grid's rows are read

The decision rule below has two halves, and the first draft of this page gave an expectation
only for the first (wall time). That is not enough to apply it: the second half is "a resource
growing faster than the world count", and **the pilot already shows one**. Rows 1 and 3 of
`pilot-2026-09-20.tsv` put `trace_bytes` at 881,520 over 103 worlds and 80,801,520 over 1,003 —
**91.7× for 9.74× the worlds**, where a square would predict 94.8×. Per-world trace goes from
8.6 KB to 80.6 KB, because the engine keeps one trace per world and each trace holds the whole
operation, which is itself N.

So this is written now, **while the grid is still running and before any of its rows have been
looked at**, rather than after:

| resource | expected shape | how it will be read |
|---|---|---|
| wall time | rises with worlds, per-world flattening (pilot: 2.1× per-world over 10× worlds) | inside the table above → not a problem |
| `trace_bytes`, `work_final_bytes` | **quadratic in the world count**, ~80 MB at 1,000 crash points on this toy | **this is the designed consequence of one-trace-per-world, not a discovery.** It is a problem only if the absolute figure reaches a scale a CI job cannot hold — the test is the number of bytes, not the exponent |
| peak RSS | rises with the **state tree**, not with the world count (pilot: 11.7 MB at one file, 69.3 MB at 20 MB of padding, at the same world count) | a rise with worlds instead would be the second clause firing |

**What this concedes:** the second clause, read as written, is satisfied by a resource that was
always going to grow that way, and saying so afterwards would have been reading the rule to fit
the numbers. The clause is therefore narrowed here, in public, before the numbers: growth faster
than the world count counts as a problem **when the absolute size becomes one**, and the
threshold is stated as bytes so that the grid can fail it.

### Repetitions, and what three of them cannot separate

The pilot put `syscalls` at 1.10× of `wrappers` and a cheap checker at 1.09×. `../RESULTS-AT-SCALE.md`
records the spread of three consecutive runs of one cell at **1.08× to 1.58×**. The spread is
larger than either effect, so **three repetitions cannot tell these two apart from noise**, and
this page says so before the grid rather than concluding "no difference was found" afterwards.
The grid reports both with their individual values; what it does not do is claim a mode or a
checker cost.

### The first grid ran on a loaded host, and what happens to both runs is decided here

The first full grid (`grid-2026-09-20-loaded-host.tsv`, 150 rows, no refusals) was measured
while this machine was also running other work — review subagents, in this same session. It
shows it. Across the 48 cells with all three repetitions, **repetition 3 is the fastest in
almost every one** (median 1.00 of the cell's fastest, worst 1.26) while repetition 2 sits at
1.52 and repetition 1 at 1.13. The within-cell spread has a **median of 1.58× and a maximum of
2.38×**; `../RESULTS-AT-SCALE.md` reports 1.08× to 1.58× for three consecutive runs of one cell,
so the median here is the old record's worst case.

**Decided before the second run, so that re-running is not a search for a better answer:**

1. **Both runs are kept and both are published.** The loaded one is not deleted and not
   described as a mistake: it is the measurement of this benchmark under host contention, which
   is a fact a CI user shares.
2. **The quiet run is the record for absolute figures** — wall time, per-world, and the
   comparison against the declared reading. It is a second run on the same machine with nothing
   else of this session's running.
3. **Ratios are computed within a run, never across the two.** The state-size multiplier, the
   observation-mode difference and the checker difference all divide two cells measured under
   the same conditions, so contention cancels; the absolute seconds do not.
4. **If the quiet run's spread is no better, that is the answer** and the absolute figures are
   reported as upper bounds with the spread beside them. There is no third run.

Repetition 3 of the loaded run already matches the declared reading closely, and **that is not
the reason for re-running** — picking it would be choosing a subset after seeing the result.
The reason is that a figure taken while the machine was doing something else is not the figure
this page said it would publish.

**What would make this a problem**, stated now rather than after the numbers: an operation a
project would plausibly run in CI taking longer than its other checks, or a resource growing
faster than the world count. **If the measured envelope stays inside these figures, the correct
outcome is that no feature follows** — #621 says so, and neither this page nor ADR 0081 reserves
the right to add one anyway.

## What this will not establish

- One machine's figures, as `../RESULTS.md`'s are. The host is in every row.
- The cost of a target whose own work grows with N. This toy's per-cycle work is fixed on
  purpose; the real-target anchor is what keeps that honest.
- Anything about `wrappers` versus `syscalls` beyond this toy's syscall mix.
