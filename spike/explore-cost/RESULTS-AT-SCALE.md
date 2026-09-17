# A whole exploration, and how much of it repeats

A record, held by review (ADR 0039), and the second one in this directory. `RESULTS.md`
measured what **one world** costs against the size of the state tree (#262, ADR 0042) and
ended by naming what it could not say:

> Nothing about a total. The number of crash points is the number of state-changing
> operations the recording saw, which the operation sets; a run costs the per-world figure
> times crash points plus one, and the file count does not predict the multiplier.

This is the multiplier, the product, and a first look at how much of the product is spent
on worlds that end up saying the same thing. The question it answers came from outside the
project: *when Sideeye scales to more targets, how redundant and expensive is exhaustive
crash injection at recorded state-changing operation boundaries?*

**The short answer.** At the scale this project actually runs, exhaustive boundary
exploration is not a material bottleneck: the median judged run has 5 crash points, and a
whole run of a real target on this laptop takes between 0.1 and 5 seconds. Redundancy is
measurable and it is not uniform — one of the six defines walked crash point by crash point
collapses 17 of its 18 worlds onto a single maintainer-facing consequence, and another
collapses none of its 19. Nothing here justifies building a pruner yet; the section at the
end says what measurement would.

Three things this record does **not** do: it does not propose pruning, it does not change
exploration semantics, and it does not touch recovery (#606, a second-stage judgement over
an already materialised crash world — a different question that must not be mixed into an
exploration-cost figure).

## Where the numbers come from

| Source | What it gives | Script |
|---|---|---|
| Every report this repository has committed under `spike/dogfood/` | crash-point counts, worlds, violations, where the first failing crash point sits | `corpus.py` → `corpus-out.txt` |
| Seven runs of six defines, timed, on this host | whole-run wall clock and per-world cost | `measure-targets.sh` → `targets-run-{1,2,3}.txt` |
| Six of those defines walked crash point by crash point | how many crash points give the same observable outcome | `collapse.sh` → `collapse-*.txt` |

The defines measured with a clock are ones this repository already committed elsewhere,
re-pathed for this host and named in `measure-targets.sh`'s header beside their sources.
The committed transcripts have this machine's home directory replaced by `~`; nothing else
in them was edited.

## Conditions

- Host: macOS 15.3.1, Apple M4, 32 GiB. Engine and shim built from `d2f9e5f`,
  `sideeye 1.4.0 (trace contract v18)`, Zig 0.16.0. Load average 2.7–3.4 across the runs
  (the machine was not idle; `RESULTS.md`'s runs were at 10–14, so the two records' absolute
  figures are not comparable — the shapes are).
- `--observe wrappers` (the default) and `--allow-unverified` on every timed row: there is
  no strace on macOS, and `--oracle-fs-usage` needs a privilege this measurement will not
  ask for. The committed runs of the same defines were made in a Linux container **with** an
  oracle, so a crash-point count here can differ from the committed one; both are printed.
- Every timed figure is the median of three consecutive runs. Spread (largest over
  smallest) was 1.0×–1.5×.

## 1. The multiplier: crash points per judged run

From 200 committed reports — 126 judged, 74 refused; 123 of the judged explored at least one
crash point, over 48 defines and 43 distinct programs, for **3,843 worlds** in total.

| | crash points per judged run |
|---|---|
| min / median / p90 / max | 1 / **5** / 18 / 1,381 |
| 1 | 4 runs (3%) |
| 2–4 | 57 runs (46%) |
| 5–9 | 29 runs (24%) |
| 10–19 | 25 runs (20%) |
| 20–99 | 6 runs (5%) |
| 100+ | 2 runs (2%) |

`explored == crash_points + 1` in 123 of 123, so nothing in the corpus explored a subset
already.

**The distribution has one long tail and it is a single target.** virtualenv's two runs are
1,381 crash points each: 2,764 of the 3,843 worlds this project has ever explored — 72% —
are those two runs. Both PASSed. No committed record says what either cost in wall clock,
and that is the first thing a follow-up would measure.

## 2. The product: what a whole run costs

Median of three runs, this host. `engine` is the wall clock around the engine process, so
`per-world` is an upper bound: start-up, `setup`, the recording run and its snapshots are
in the total and are not worlds.

| target | language | verdict | crash points | worlds | violations | earliest | engine | per world |
|---|---|---|---|---|---|---|---|---|
| toy-fixed | C | PASS | 4 | 5 | 0 | – | 0.1 s | 0.017 s |
| toy-bug | C | FAIL | 5 | 6 | 1 | 5 | 0.1 s | 0.014 s |
| jpegtran | C | FAIL | 2 | 3 | 1 | 2 | 0.7 s | 0.226 s |
| bsdtar | C | PASS | 2 | 3 | 0 | – | 0.7 s | 0.221 s |
| timew (no checker) | C++ | PASS | 19 | 20 | 0 | – | 1.8 s | 0.088 s |
| timew (undo contract) | C++ | FAIL | 19 | 20 | 2 | 14 | 2.9 s | 0.145 s |
| xz | C | PASS | 18 | 19 | 0 | – | 4.9 s | 0.259 s |

Seven runs, 76 worlds, 11.2 seconds of engine time in total.

Per-world cost varies 18× across these targets (0.014 s to 0.259 s) and the driver is the
work per world, not the count: xz restores and snapshots a 7 MB tree nineteen times, the toy
restores two small files. This is the same relationship `RESULTS.md` measured against
padding size; what is new is that it holds on real targets, and that the whole-run totals
are seconds.

Read against the corpus: 3,843 worlds at these per-world figures is roughly **9 minutes** of
engine time for every exploration this project has ever run (median per-world 0.145 s), and
between 1 and 17 minutes at the extremes of the measured range. The two virtualenv runs are
72% of that.

## 3. How much of an exploration repeats

The report names at most two crash points — the earliest violating world, and the earliest
world whose violation includes the checker — so nothing committed says what the other worlds
produced. `collapse.sh` re-materialises every world of a define from outside the engine,
through the `reproduce` line a FAIL report itself prints, and groups them two ways:

- **strict** — byte-identical state trees, plus the same checker result. What cannot be
  established as equivalent stays distinct.
- **coarse** — the same set of changed paths and the same checker exit and first line. The
  reading a maintainer-facing consequence would take.

| define | crash points | strict outcomes | coarse outcomes | shape |
|---|---|---|---|---|
| bsdtar | 2 | **1** | **1** | both worlds are the pre-state: nothing reaches `a.tar` before either kill |
| jpegtran | 2 | 2 | 2 | world 1 unchanged; world 2 the empty file the checker rejects |
| toy-fixed | 4 | 3 | 2 | worlds 3 and 4 are byte-identical |
| toy-bug | 5 | 4 | 3 | worlds 3 and 4 identical; world 5 the planted loss |
| timew (undo) | 19 | 15 | 15 | 14 of 19 worlds are singletons; the two failing worlds fail *differently* |
| xz | 18 | **16** | **2** | 17 of 18 worlds change the same path; only the byte count differs |

Two findings, and they point opposite ways.

**xz is where pruning would pay.** Seventeen of its eighteen crash points produce the same
changed-path set and the same checker result — a partial `f.bin.xz` beside the intact
`f.bin`. Under the strict reading those seventeen are sixteen different states, because each
one holds a different number of bytes. The gap between 16 and 2 *is* the risk in pruning: an
engine that skipped fifteen of those worlds would be right almost always, and the judgement
that they are "the same" belongs to the checker, not to the engine.

**timew is where it would not.** Nineteen crash points, fifteen distinct outcomes, and the
two failing worlds carry different diagnostics — world 14 removes the wrong change under
`timew undo`, world 15 leaves a tag count that undo cannot decrement. A pruner that assumed
adjacent worlds are alike would have had to explore both anyway.

**One world per run is empty by construction.** In all six defines, the world killed before
the first state-changing operation leaves the pre-state exactly: the kill lands *before*
operation 1, so no counted operation has run (ADR 0003). That is 123 of 3,843 worlds in the
corpus — 3% — and it is the only redundancy in this record that holds for every target
rather than for a shape.

## 4. Where the first counterexample sits

Over the 87 FAIL runs in the corpus, every one of which names an earliest crash point:

- As an address: median **2**, max 55.
- 54 of 87 (62%) fail at crash point 1 or 2.
- As a fraction of the run the median is 0.88, which is an artefact: 39 of the 123 judged
  runs have exactly two crash points, where the fraction can only be 0.5 or 1.0. Read it
  where there is room — over the 36 runs with five or more crash points the median earliest
  is address **3**, fraction 0.37, minimum 0.17.
- The exceptions are real and they are the long runs: rdiff-backup 55 of 68, newsboat 26 of
  43, timew 14 of 19 (measured here).
- 52 of 87 FAIL runs (60%) have exactly one failing crash point; the median FAIL run has one
  violating world, the largest has 15.

A stop-at-first-failure strategy would therefore save most of a FAILing run's worlds — and
nothing at all on a PASSing one, which is where the worlds actually are: **36 PASS runs hold
3,100 of the 3,843 worlds and the 87 FAIL runs hold 743**, so the strategy with the clearest
saving applies to the fifth of the corpus that is already cheap.

## The five questions

1. **Distribution of crash-point counts.** Median 5, p90 18, 46% of runs in 2–4. One target
   at 1,381 holds 72% of all worlds ever explored.
2. **Wall-clock cost at those counts.** 0.1–5 seconds per whole run on this laptop; 11.2
   seconds for seven runs. Per-world 0.014–0.259 s, driven by tree size, not by count.
3. **How often crash points collapse.** Shape-dependent and wide: 1 outcome from 2 worlds
   (bsdtar), 2 from 18 (xz), 15 from 19 (timew). The strict and coarse readings agree on
   timew and disagree 8× on xz.
4. **How early the first counterexample is found.** Address 2 (median); address 3 over runs
   with ≥5 crash points; 62% at crash point 1 or 2. Three measured exceptions past the
   halfway mark.
5. **Material bottleneck, or plausible future one?** Not material at the measured scale.

## Conclusion

**Exhaustive boundary exploration is not currently a material bottleneck at the measured
scale, and redundancy is measurable but not dominant.** Both statements are needed: the
first is about cost (seconds per run, ~9 minutes for the project's entire exploration
history), the second about waste (one define in six shows heavy collapse, one shows none).

What the measurement cannot settle is the tail. The single biggest consumer of exploration
in this project's history — virtualenv, 1,381 crash points, 72% of all worlds — has never
been timed, and it is exactly the case where a per-world figure gets multiplied by a large
number. It was not re-run here because it needs its Linux container, and rebuilding that was
outside this campaign's budget.

## What would justify a pruning or prioritisation issue

Not this record. Three measured results would, and the first is a prerequisite for the
others:

1. **A timed run of a target in the 100+ crash-point class** (virtualenv is the one in
   hand) showing an exploration that takes longer than the workflow waiting on it tolerates.
   Concretely: more than ~10 minutes of engine wall clock inside something someone waits
   for — the `timew-regression` CI job, a dogfood slate, a re-record after a contract bump.
   Everything measured here is two orders of magnitude below that.
2. **A coarse collapse ratio at that size of 5:1 or better**, measured the way section 3
   measures it. Pruning only pays where many worlds give one consequence; timew's 15-of-19
   is the counterexample that says the ratio must be measured per target class rather than
   assumed.
3. **A statement of what a pruner may throw away**, checked against the strict/coarse gap.
   xz's 16 strict states behind 2 coarse outcomes is where a pruner would be wrong if it is
   ever wrong, and the decision that those states are equivalent is the checker's.

If a follow-up issue is filed, it should carry those three as its acceptance, and it should
be filed after (1) is measured, not before.

## What this record does not say

- Nothing about an idle machine, another filesystem, or Linux. Every timed figure is this
  laptop's, under the load the header records, with no oracle. An oracle adds a second
  witness to the recording run and does not change the world count.
- Nothing about refusals. 74 of the 200 committed reports refused; a refused run may have
  refused before exploring, and `corpus.py` excludes them from every figure rather than
  counting them as cheap explorations. The cost of *reaching* exploration — screening,
  building images, finding a define a target accepts — is not measured here at all, and on
  the evidence of the dogfood records it is the larger cost by far.
- Nothing about the 100+ crash-point class, which is where the cost question actually lives.
- Nothing about recovery. A recovery leg (#606) would run *after* a crash world is judged
  and would be counted separately; mixing it into these figures would be measuring two
  things with one clock.
- `collapse.sh` does not judge. It groups states and checker results; the built-in
  invariants live in the engine and are not reachable from a shell, so a world's L0/L1
  verdict is not part of the grouping. Two worlds grouped together here might still be one
  violating world and one clean one if the difference is something only L0 reads.
