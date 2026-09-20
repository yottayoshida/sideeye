# What an exhaustive exploration costs, 10 to 1000 crash points (#621, ADR 0081 declared it, ADR 0082 concludes)

A record, held by review (ADR 0039). `PROTOCOL.md` beside this file was committed before any of
these numbers existed, with the reading it expected and the rule it would apply. **This page
sets the measurement beside that declaration and applies the rule.** It does not re-write either.

The instrument, the target and the pilot are the first merge. This is the second.

## Conditions

| | |
|---|---|
| where | `debian:bookworm-slim` under Docker Desktop, on macOS 15 / Apple M4 / 32 GiB. `--cap-add SYS_PTRACE` |
| engine | this branch, cross-built `-Dtarget=aarch64-linux-gnu` |
| oracle | `/usr/bin/strace` on every cell. Every row reports `oracle_verified: true` |
| target | `spike/toys/toy_scale.c` — N create-write-unlink cycles on a temporary path, judged state one file |
| grid | 6 crash-point requests × 2 state sizes × 2 observation modes × 2 checker legs × 3 repetitions = 144 timed cells, plus 6 sampling cells |
| records | `grid-2026-09-20-quiet.tsv` (150 rows) and `grid-2026-09-20-loaded-host.tsv` (150 rows). **No refusals in either**: the engine reached a verdict on all 300 |

**This is one machine's figures, and it is not a CI runner.** `RESULTS.md` in the parent
directory says the same about its own. What that costs the conclusion is at the end of this page.

## The two runs, and why there are two

The first grid was measured while this machine was also running review subagents. It shows it:
across the 48 cells with three repetitions, repetition 3 — the last to run, after the other work
had finished — is the fastest in **32 of 48** (67%, against 50% if order did not matter; the
declaration said "almost every one", which this count corrects), and the
within-cell spread has a **median of 1.58× and a maximum of 2.38×**. On the quiet run the same
count is 24 of 48, exactly chance. All spreads on this page are ratios of `per_world_s`, the
column the comparisons use; by `wall_s` they are 1.59× / 2.38× and 1.02× / 1.09×.

`PROTOCOL.md` then declared, **before the second run**, that both would be kept, that the quiet
run would be the record for absolute figures, that ratios would be computed within a run so that
contention cancels, and that if the quiet run were no better that would be the answer.

| run | within-cell spread (median / max) | repetition medians (1 / 2 / 3) |
|---|---|---|
| loaded host | 1.58× / 2.38× | 1.13 / 1.52 / 1.00 |
| quiet host | **1.02× / 1.08×** | 1.01 / 1.01 / 1.00 |


Everything below is the quiet run. **The loaded run is kept and is itself a finding**: this
benchmark is sensitive to host load at the 2.4× level, which is a fact for anyone who would run
an exploration beside other work in CI.

## 1. The declared reading against the measurement

`PROTOCOL.md`'s table, written before the grid, and what the grid measured. Small state, one
file; `wrappers`; no checker; the three repetitions individually.

| worlds | declared | measured (median) | the three repetitions |
|---|---|---|---|
| 103 | 0.2 s | **0.204 s** | 0.203 0.204 0.204 |
| 502 | 1.5 s | **1.460 s** | 1.455 1.460 1.463 |
| 1003 | 4 s | **4.170 s** | 4.128 4.170 4.206 |

On the large state (200 files × 100 KiB), declared as "about thirteen times":

| worlds | declared | measured (median) | actual multiplier over the small state |
|---|---|---|---|
| 103 | about 3 s | **2.779 s** | 13.6× |
| 502 | about 20 s | **14.152 s** | 9.7× |
| 1003 | about 50 s | **30.057 s** | 7.2× |

The multiplier **falls** as the world count rises, which the declaration did not predict: the
state tree's fixed cost per run is amortised over more worlds. The declaration was an
over-estimate on the large state and accurate on the small one.

## 2. Per-world across the envelope

Small state, `wrappers`, no checker, median of three.

| crash points | worlds | per-world |
|---|---|---|
| 12 | 13 | 0.00266 s |
| 51 | 52 | 0.00199 s |
| 102 | 103 | 0.00198 s |
| 252 | 253 | 0.00230 s |
| 501 | 502 | 0.00291 s |
| 1002 | 1003 | 0.00416 s |

Per-world **dips and then rises**: the fixed cost of a run dominates at 13 worlds, and from 103
worlds onward it grows with the world count — 2.1× over 9.7× the worlds, which is the factor the
pilot measured and the declaration used. **Over the whole measured range total wall grows as the
world count to the 1.10** (least-squares on the six points; 13→1003 gives 1.100). The exponent is
not constant, which is the same fact as the dip: 13→103 is 0.85 and 103→1003 is 1.33. A single
exponent quoted for the whole range should be 1.10; 1.3 describes only the upper decade.

## 3. The second clause: resources against the world count

`PROTOCOL.md` declared, before the grid, that trace and work bytes were expected to be quadratic
because the engine keeps one trace per world, that this is the designed consequence rather than a
discovery, and that **it counts as a problem only when the absolute size becomes one**. It also
declared what the memory reading was expected to look like: *"peak RSS rises with the state tree,
not with the world count … a rise with worlds instead would be the second clause firing."*

Small state, `wrappers`, no checker, **medians of the three timed repetitions** — not the
sampling cells, which are separate runs of the same cell (the byte figures come from the same
`dir_bytes` call in both legs, so the third-significant-figure difference is run-to-run
variation, not method):

| worlds | trace bytes | work dir (final) | report bytes |
|---|---|---|---|
| 13 | 9,928 | 25,255 | 913 |
| 103 | 499,528 | 586,033 | 917 |
| 1003 | 45,787,528 | 46,605,234 | 922 |

- **Trace and work bytes are quadratic, as declared**, and reach **45.8 MB (43.7 MiB) at a thousand crash
  points**. That is not a size a CI job cannot hold — **and that judgement is an eyeball, not the
  test the declaration promised.** `PROTOCOL.md` narrowed this clause to absolute size and said
  "the threshold is stated as bytes so that the grid can fail it"; **no number appears anywhere
  on that page**. So the one clause that was supposed to be mechanically failable was not, and
  the pre-registration bought less here than it did for the wall-time table. Recorded rather than
  patched: writing a threshold now, with 45.8 MB in hand, is the move the whole page exists to
  prevent.
- **The report does not grow**: 913 to 922 bytes — nine bytes — across **77×** the worlds.

**Memory needs its own paragraph, because the first draft of this page got it wrong.** The RSS
column is missing from the table above deliberately: **all 75 small-state rows carry the
instrument's own note** saying *"the engine's `version` probe reached the same peak, so this
figure is a floor rather than the exploration's own"*. The figure those rows carry — 11,708 to 11,724 KiB, and 11,724 at each of the
three cells §3 first quoted — is the probe's, not the exploration's. `PROTOCOL.md` built that disclosure precisely so a floor could not be published
as a measurement, and this page did exactly that until review caught it.

**The rows where RSS is the exploration's own are the large-state ones, and there it does rise
with the world count.** `wrappers`, no checker, medians of three:

| worlds | peak RSS (large state) |
|---|---|
| 13 | 70,156 KiB |
| 103 | 69,364 KiB |
| 1003 | 73,704 KiB |

**+5.1% over 77× the worlds.** So the pilot's sentence — RSS rises with the state tree *instead
of* with the world count — is too strong, and this page says so rather than rounding it to
agreement. Read as that sentence's shorthand ("a rise with worlds instead"), something did move.
Read as the rule's own text in the conclusion — *"a resource growing faster than the world
count"* — it does not fire, and not marginally: memory grows at **0.07% of the rate the world
count does**. **The rule's text is what this page applies**, and the shorthand it contradicts is
recorded here rather than quietly dropped. Over all **75** large-state rows in the quiet run the whole range is
**66.9 to 73.0 MiB**, against a step from the small state to the large one of **at least 6.0×**
at a fixed world count — "at least" because the small side of that division is the floor above,
so the true step is larger. The state tree still dominates by two orders of magnitude.

- The six sampling cells put `work_max` **equal to** `work_final` in every one, so nothing
  transient spikes above the final size. **Three of the six could not have seen it if it had**:
  the sampler takes one reading at the start and then every 0.25 s, and the small-state 13-world
  (0.035 s) and 103-world (0.204 s) cells and the large-state 13-world cell (0.393 s) finish
  inside one or two intervals. The finding rests on the other three — small 1003 worlds (16
  readings after the first), large 103 (11) and large 1003 (120) — and the short cells are
  agreement, not evidence.

## 4. Observation mode and the checker

`PROTOCOL.md` declared, before the grid, that three repetitions could not separate the pilot's
1.10× mode difference from noise, and that this page would report both and **claim neither**.

That declaration stands, and so this page claims no cost for either. What it reports:

| comparison | direction | ratio (median / min / max) |
|---|---|---|
| `syscalls` against `wrappers` | **slower in 24 of 24 pairs** | 1.089× / 1.013× / 1.195× |
| cheap checker against none | **slower in 24 of 24 pairs** | 1.069× / 1.018× / 1.171× |

**The direction is unanimous and does not depend on the repetition count** — twenty-four
independent pairs, each a different crash-point count, state size and other axis. The
**magnitude** is what three repetitions cannot carry: the median ratios sit near the measured
within-cell maximum of 1.077×, so this page reports the numbers and leaves the claim unmade. The
declaration's stated basis was the earlier record's 1.08–1.58× spread; the quiet run's spread is
smaller than that, and saying so does not license taking the claim back after the fact.

## 5. The real target, and the one FAIL

#621 asks for at least one existing real target "as a sanity anchor … that the toy has not
omitted a dominant cost present in ordinary use". `anchor-2026-09-20.tsv`, same container, same
`strace` oracle, same row format and same rules as every grid cell, three repetitions each.

| target | crash points | worlds | per-world | verdict | case bytes | oracle |
|---|---|---|---|---|---|---|
| timewarrior 1.4.3, no checker | 19 | 20 | 0.00357 / 0.00364 / 0.00366 s | PASS | 0 | verified |
| `toy-bug`, planted delete-before-rename | 5 | 6 | 0.00431 / 0.00377 / 0.00412 s | **FAIL** | **538** | verified |

The define is `spike/dogfood-timew.sh`'s first leg as `../measure-targets.sh` re-paths it: one
`timew track` for the setup, one for the operation, no checker, and `TIMEWARRIORDB` pointing at
the state directory. **A target with no checker was chosen deliberately** — the alternatives in
that script compare against a backup file outside the state, which would have meant either
changing what is judged or declaring apparatus, and neither belongs in an anchor whose job is to
be an ordinary run.

**The answer to the anchor's question: the toy is the cheaper side — by 1.37× against the
nearest measured point.** timewarrior costs 0.00364 s per world at 20 worlds. The toy's own curve
is U-shaped (§2), so *which* toy figure this is divided by decides the answer, and the honest
choice is the nearest world count, not the cheapest point: 13 worlds gives 0.00266 s and
**1.37×**; 52 worlds — the curve's minimum, and the number an earlier draft of this page used —
gives 1.83×. Both are the same conclusion in direction: **a real target costs more per world than
the toy at a comparable size**, which is the safe direction, because it means the envelope in §1
is not flattered by a target chosen to be cheap.

**What this does not license is a multiplier for real targets in general, and the repository's
own record says so.** `../RESULTS-AT-SCALE.md` timed seven defines over five programs on one
macOS host, **two of which are its own toys**. Across the five real ones per-world runs **0.088
to 0.259 s — 2.9×** (timewarrior's checker-less leg at the bottom, `xz` at the top); that page's
own headline figure, "18× across these defines", spans its toys as well and is not a spread
across real targets. The comparison that matters here is toy-to-real on one machine: on that
host the same timewarrior define cost **about five times** that record's toys (0.088 against
0.014–0.017 s), where on this one it costs **1.37×** this toy. The two readings are not in
conflict about anything measured — different host, different oracle and, above all, a different
toy: `toy_scale` does real create-write-unlink work per crash point where that record's toy does
almost none, which is the property #621 asked the synthetic target to have. But the gap between
1.37× and five is **not measured here**, and no factor carrying the §1 envelope over to real
targets in general is claimed by this page. What one anchor establishes is the thing #621
asked it to: the toy has not omitted a dominant cost. It does not establish that the toy is
within a small factor of every real target.

**The FAIL leg exists because the grid cannot produce one.** The scale toy PASSes by
construction, so `case_bytes` is 0 in all 150 grid rows, and #621 asks for the saved case's size
"when the run is configured to produce one deterministic FAIL". It is **538 bytes**, identical
across three repetitions. What this record does **not** carry is the evidence bundle's size: the
harness reads the report's `case` and not its `evidence` (ADR 0071), so that figure is absent
rather than zero, and this sentence is here so it is not read as zero.

**Both legs are reproducible from the tree**: `run-anchor.sh` beside this file runs them. It was
written after these figures were first published — they existed only as typed commands, which
blind review caught — and the rows above are the ones that were measured, not a re-run.

## The conclusion

**Applying the rule `PROTOCOL.md` declared before the numbers:**

1. *"An operation a project would plausibly run in CI taking longer than its other checks."*
   A thousand crash points costs **4.2 seconds** on a one-file state and **30 seconds** on a
   20 MB one, inside the declared table. Where a thousand sits against real use: this
   repository's dogfood corpus has a median of 5 crash points and a **p90 of 18**, so a thousand
   is **fifty-five times the p90** — and about **three-quarters of the largest run on record**
   (virtualenv, 1,381), which `../RESULTS-AT-SCALE.md` timed at about seven minutes on the macOS
   host. The envelope covers real use with a wide margin at the top rather than a narrow one.
   **The clause as written is a ratio, and this page does not compute it** — see below.
2. *"A resource growing faster than the world count."* Trace and work bytes are quadratic and
   reach 45.8 MB at the top of the envelope; the declaration narrowed this clause to absolute
   size before the numbers, and 45.8 MB does not meet it. Memory rises 5.1% over 77× the worlds — a
   rise, which the pilot's shorthand said there would not be, but 0.07% of the world count's own
   rate, so it does not grow faster than the world count. The report does not grow.

**So the conclusion is the one #621 said was allowed: exhaustive exploration remains practical
over the measured envelope, and no feature follows.** No budget, no sampling, no `--max-worlds`,
no quick mode — not because one was anticipated and declined, but because the cost that would
justify one was measured and is not there.

## What this does not establish

- **It is not a CI runner.** Every figure is from Docker Desktop on an M4, and the first merge
  measured that container at about seventeen times faster than the macOS host beside it. A
  GitHub-hosted runner is slower than this machine by an unmeasured factor, and the conclusion
  above is therefore "practical on hardware of this class" rather than "practical on any runner".
- **The first clause was never run in the form it was written.** It says "longer than its other
  checks" — a **ratio** against what else runs on that machine. This page compares against its
  own declared table instead, which tests whether the estimate was right, not whether the cost is
  acceptable to a project. The conclusion rests on seconds being small in absolute terms, and
  that substitution is the largest single gap in it.
- **No multiplier from the toy to real targets in general.** One anchor says the toy is the cheap
  side by 1.37× at a comparable world count, while on the earlier record's host the same define
  cost about five times *its* toys. The two readings are not reconciled here (§5).
- **Memory on a small state was not measured at all**, only floored: every small-state row's RSS
  is the engine's `version` probe's peak. The memory reading in §3 is the large-state rows'.
- **Three of the six sampling cells were too short to observe a transient peak** (§3), so
  "nothing spikes above the final size" rests on the other three.
- **The toy's own work is fixed.** A target whose per-operation cost grows with N would add its
  own curve on top of this one; that is what the real-target anchor is for.
- **Nothing about `wrappers` versus `syscalls` beyond this toy's syscall mix**, and no magnitude
  for either difference.
- **One machine, one container image, one engine build.** The records carry the host in every row.
