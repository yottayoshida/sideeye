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

**The short answer, in two halves that rest on different evidence.**

*Cost:* at the scale this project runs, exhaustive boundary exploration is not a material
bottleneck. The median judged dogfood run has 5 crash points; a whole run of a real target on
this laptop takes 0.1 to 5 seconds; the heaviest exploration anyone has timed — virtualenv,
1,381 crash points — took about seven minutes. The one time on record that exploration cost
changed a plan, it did so through an estimate about eight times the measured time.

*Redundancy:* in the six defines walked crash point by crash point — C and C++ tools with 2 to
19 crash points, 50 worlds — it is large as a share of worlds and absent from the failures. Read
by the paths a world changes, half the worlds repeat an outcome already seen (two-thirds once
temporary names carrying a process id are read alike, which timewarrior's are); read byte for
byte, 18% do. But **every repeat is a world that did not fail**: the four failing worlds walked are
four distinct outcomes, none sharing one with another world. At this scale the repeats cost
seconds. Where pruning would actually pay, the 100-plus crash-point class, nothing was walked, and
**this sample cannot say** what happens there.

Nothing here justifies building a pruner; the last section says what would. Three things
this record does **not** do: propose pruning, change exploration semantics, or touch recovery
(#606, a second-stage judgement over an already materialised crash world — a different
question that must not be mixed into an exploration-cost figure).

## Where the numbers come from

| Source | What it gives | Script / file |
|---|---|---|
| Every report committed under `spike/dogfood/` | crash-point counts, worlds, violations, where the first failing crash point sits | `corpus.py` → `corpus-out.txt` |
| The rest of `spike/`, counted once for scope | how much of the record the dogfood corpus is | this page, section 1 |
| Committed prose that recorded a wall clock | one virtualenv explore; ansible's | `spike/dogfood/2026-09-16-threads-take-turns/RESULTS.md`, `spike/dogfood/2026-09-13-cgroup-559/RESULTS.md` |
| Seven defines timed on this host | whole-run wall clock and per-world cost | `measure-targets.sh` → `targets-run-{1,2,3}.txt` |
| Six of those walked crash point by crash point | how many crash points give the same observable outcome | `collapse.sh` → `collapse-*.txt` |

The defines timed here are ones this repository already committed elsewhere, re-pathed for
this host and named in `measure-targets.sh`'s header beside their sources. The committed
transcripts have this machine's home directory replaced by `~` and the checkout's path by
`<checkout>`; nothing else in them was edited.

**No report carries a wall clock, and no transcript's structured lines do.** The first draft
of this record went from there to "virtualenv was never timed", which was false: that run's
prose says an explore "took about seven minutes". The reports were searched and the prose was
not. The prose figures are used below and cited where they are.

## Conditions

- Host: macOS 15.3.1, Apple M4, 32 GiB. Engine and shim built from `d2f9e5f`,
  `sideeye 1.4.0 (trace contract v18)`, Zig 0.16.0. Load average 2.7–3.4 across the runs.
- `--observe wrappers` (the default) and `--allow-unverified` on every timed row: there is
  no strace on macOS, and `--oracle-fs-usage` needs a privilege this measurement will not ask
  for. The committed runs of the same defines were made in a Linux container **with** an
  oracle. Their crash-point counts agree with this host's wherever the dogfood corpus has
  them — xz 18 and 18, jpegtran 2 and 2, bsdtar 2 and 2; timewarrior's define lives in
  `spike/dogfood-timew.sh` and has no committed report to compare with.
- Every timed figure is the median of three consecutive runs. Per-world spread (largest over
  smallest, unrounded) was 1.08× to 1.58×; the three runs' engine totals were 11.8, 12.0 and
  11.0 seconds.

## 1. The multiplier: crash points per judged run

**The dogfood corpus.** 200 committed reports under `spike/dogfood/` — 126 judged, 74
refused; 123 of the judged explored at least one crash point, for **3,843 worlds**, over 39
programs. (`corpus.py` prints 41 programs: two of them are one program spelled twice —
`nvim012` is neovim, `rdiff` is rdiff-backup.)

| | crash points per judged dogfood run |
|---|---|
| min / median / p90 / max | 1 / **5** / 18 / 1,381 |
| 1 | 4 runs (3%) |
| 2–4 | 57 runs (46%) |
| 5–9 | 29 runs (24%) |
| 10–19 | 25 runs (20%) |
| 20–99 | 6 runs (5%) |
| 100+ | 2 runs (2%) |

`explored == crash_points + 1` in 123 of 123, so nothing in the corpus explored a subset.
virtualenv's two runs at 1,381 crash points each are 2,764 of the corpus's 3,843 worlds —
72%. Both PASSed.

**The rest of `spike/`, for scope.** The dogfood corpus is the recent real targets
(2026-09-05 onward), which is what the question is about, and `corpus.py` reads nothing else.
It is not the whole record. The rest of `spike/` holds 297 more reports — the unknown-rate
sweep (188), the follow-up directories, blind-hunt, assisted, cohorts 2 and 3 — 52 of the
judged ones from before the `explored` field existed. Counting every judged report with that
field, byte-identical copies once, the repository holds 252 explored runs and 5,630 worlds;
the 100-plus class there is virtualenv (1,381) and three more — fontforge at 184, borg at
118, hg at 106 — and virtualenv's share is 49%, not 72%. None of this moves the cost
conclusion: the added tail is 106 to 184 crash points.

## 2. The product: what a whole run costs

Median of three runs, this host. `engine` is the wall clock around the engine process, so
`per world` is an upper bound: start-up, `setup`, the recording run and its snapshots are in
the total and are not worlds.

| define | language | verdict | crash points | worlds | violations | earliest | engine | per world |
|---|---|---|---|---|---|---|---|---|
| toy-fixed | C | PASS | 4 | 5 | 0 | – | 0.1 s | 0.017 s |
| toy-bug | C | FAIL | 5 | 6 | 1 | 5 | 0.1 s | 0.014 s |
| jpegtran | C | FAIL | 2 | 3 | 1 | 2 | 0.7 s | 0.226 s |
| bsdtar | C | PASS | 2 | 3 | 0 | – | 0.7 s | 0.221 s |
| timew (no checker) | C++ | PASS | 19 | 20 | 0 | – | 1.8 s | 0.088 s |
| timew (undo contract) | C++ | FAIL | 19 | 20 | 2 | 14 | 2.9 s | 0.145 s |
| xz | C | PASS | 18 | 19 | 0 | – | 4.9 s | 0.259 s |

Seven defines over five programs, 76 worlds; the medians sum to 11.2 seconds.

Per-world cost varies 18× across these defines (0.014 s to 0.259 s) and the driver is the
work per world, not the count: xz restores and snapshots a 5.75 MB file nineteen times, the
toy restores two small files. That is the relationship `RESULTS.md` measured against padding
size, holding on real targets.

**It holds in the tail.** One virtualenv explore "took about seven minutes" for 1,382 worlds
(`spike/dogfood/2026-09-16-threads-take-turns/RESULTS.md`), about 0.3 s per world — on another
host, in a Linux container, under strace, with each world building a Python environment.
Nothing there departs from per-world cost times worlds. The other prose figure, ansible-core
at one crash point, is "2 seconds or less" per explore
(`spike/dogfood/2026-09-13-cgroup-559/RESULTS.md`).

Read against the dogfood corpus: two virtualenv explores at about seven minutes — the prose
times one; the second is assumed alike — and the other 1,079 worlds at this host's
no-oracle per-world figures come to **about seventeen minutes** of engine time. That is not a
bound. Both Linux-under-strace figures on record are at or above this host's highest, so the
real total is more likely above seventeen than below it; five-sixths of it is virtualenv
either way.

## 3. How much of an exploration repeats

The report names at most two crash points — the earliest violating world, and the earliest
world whose violation includes the checker — so nothing committed says what the other worlds
produced. `collapse.sh` re-materialises every world of a define from outside the engine and
groups them two ways:

- **strict** — byte-identical state trees, and the same checker exit and first line. What
  cannot be established as equivalent stays distinct.
- **coarse** — the same set of changed paths, and the same checker exit and first line. The
  reading a maintainer-facing consequence would take.

**The kill landed in front of operation k in all 50 worlds**, read from each world's trace —
the check the engine makes before judging a world (`kill_did_not_land`), and one this
measurement did not make on its first draft. Where a world failed the checker, it is the world
the engine's own report names: timew worlds 14 and 15 (the report: violations 2, earliest 14),
jpegtran world 2.

A third grouping is printed beside the two, because the second one miscounted a real tool.
timewarrior names its temporary files after its process id (`undo.data.59032-3.tmp`), every
world is a new process, and a world that leaves one temporary file therefore changes a path no
other world changes. The third reading is the coarse one with a pid-shaped temporary name read
without the pid — the engine does not treat such paths as identity either (`src/case.zig`'s
prefix hash hashes operation classes, "pid-embedded temp names" its stated reason). Its pattern is
narrow, and the plain coarse count stays the conservative figure. It was found by re-running the
walk: timewarrior's was the only transcript whose digests all moved.

| define | crash points | strict | coarse | pid hidden | failing worlds | shape |
|---|---|---|---|---|---|---|
| bsdtar | 2 | **1** | **1** | 1 | – | both worlds are the pre-state: nothing reaches `a.tar` before either kill |
| jpegtran | 2 | 2 | 2 | 2 | 2 (alone) | world 1 unchanged; world 2 the empty `a.jpg` the checker rejects |
| toy-fixed | 4 | 3 | 2 | 2 | – | worlds 2–4 change the same path; 3 and 4 byte-identical |
| toy-bug | 5 | 4 | 3 | 3 | 5 (alone) | worlds 2–4 change the same path; world 5 the planted loss |
| timew (undo) | 19 | 15 | 15 | **7** | 14, 15 (each alone) | in steps: one temporary file (3–7), two (8–10), three (11–13), the two failures, the finished files (16–19) |
| xz | 18 | **16** | **2** | 2 | – | world 1 unchanged; worlds 2–18 add `f.bin.xz` |
| **all six** | **50** | **41** | **25** | **17** | 4, each alone | |

(`failing worlds` are the engine's: its report's `earliest` and `violations`. toy-bug has no
checker, so its failing world is the one the built-in invariant judged — `collapse.sh` cannot
judge that one itself and shows world 5 as its own outcome by its paths alone.)

timewarrior's no-checker define was not walked: its setup, operation and crash points are the
undo define's, so its trees are the same trees, and every grouping keys on the checker only
where one is declared.

**How much repeats.** Of 50 worlds, 25 outcomes by changed paths (half the worlds repeat one),
17 with pid-shaped names hidden (two-thirds), 41 byte for byte (18%). The two defines with more
than five crash points are where it concentrates: xz 18 worlds to 2 outcomes, timewarrior 19 to 7.

**What repeats is never a failure.** The four failing worlds are four distinct outcomes, and
timewarrior's two are adjacent — world 14 has `timew undo` remove the wrong change, world 15 leaves
a tag count undo cannot decrement. Every repeated outcome belongs to worlds that did not fail. The
brief's question is how often crash points collapse onto the same *failure* outcome; in this
sample, never. And which worlds were repeats, and that they did not fail, is known only after each
one has run.

**xz shows the gap between the readings.** `f.bin` is intact in all eighteen worlds. In the
seventeen after the first, `f.bin.xz` exists beside it — empty at world 2, byte-distinct at worlds
3 through 15, and at 16 through 18 one byte-identical complete stream (the last world's passes
`xz -t` and decompresses to the original) — and the checker accepts every one. Seventeen worlds,
one coarse outcome, fifteen strict states: the judgement that fifteen different states are "the
same" belongs to the checker, not to the engine, and it is where a comparison by paths would be
wrong if it is ever wrong.

**At least one world per run is empty by construction.** In all six defines, the world killed
before the first state-changing operation leaves the pre-state exactly: the kill lands *before*
operation 1, so no counted operation has run (ADR 0003). That is 123 of the dogfood corpus's
3,843 worlds, 3% — a floor, since bsdtar's second world and timewarrior's second are also the
pre-state — and the only repeat in this record that holds for every define rather than for a
shape.

## 4. Where the first counterexample sits

Over the 87 FAIL runs in the dogfood corpus, every one of which names an earliest crash point:

- As an address: median **2**, max 55.
- 54 of 87 (62%) fail at crash point 1 or 2.
- As a fraction of the run the median is 0.88, which is an artefact: 39 of the 123 judged
  runs have exactly two crash points, where the fraction can only be 0.5 or 1.0. Read it where
  there is room — **36 of the FAIL runs** have five or more crash points (of 62 judged runs
  that do), and over those the median earliest is address **3**, fraction 0.37.
- **Twelve of those 36, over five programs, fail past the halfway mark**, and they are not
  only the long runs: cargo at 6 of 7 (three runs), Bun at 10 of 10 — the last crash point
  (four runs), qpdf at 7 of 8, newsboat at 26 of 43 (two runs), rdiff-backup at 51 and 55 of
  68. timew's 14 of 19, measured here, is a thirteenth.
- 52 of 87 FAIL runs (60%) have exactly one failing crash point; the largest has 15.

A stop-at-first-failure strategy would therefore save most of a typical FAILing run's worlds,
less than half on a third of the longer ones, and nothing at all on a PASSing run — which is
where the worlds are: **the 36 PASS runs hold 3,100 of the 3,843 worlds and the 87 FAIL runs
hold 743**.

## The five questions

1. **Distribution of crash-point counts.** Median 5, p90 18, 46% of dogfood runs in 2–4. The
   100-plus class is virtualenv in the dogfood corpus (72% of its worlds) and four targets
   across the repository (49%).
2. **Wall-clock cost at those counts.** 0.1–5 seconds per whole run on this laptop; about
   seven minutes for the one 1,381-crash-point explore on record. Per world 0.014–0.259 s
   here, about 0.3 s there, driven by what a world does rather than by how many there are.
3. **How often crash points collapse.** In the six defines walked (50 worlds): half the worlds
   repeat an outcome by changed paths, two-thirds with pid-named temporaries read alike, 18% byte
   for byte — concentrated in the two longer defines (xz 18 to 2, timewarrior 19 to 7). Onto the
   same *failure* outcome: never; the four failing worlds are four outcomes. Not measured above 19
   crash points.
4. **How early the first counterexample is found.** Address 2 (median); address 3 over the FAIL
   runs with five or more crash points; 62% at crash point 1 or 2 — and a third of the FAIL runs
   with room for it to be late are late, not only the long ones.
5. **Material bottleneck, or plausible future one?** Cost: not material at the measured scale.
   Redundancy: large as a share of the worlds walked, absent from their failures, seconds of cost;
   undetermined in the 100-plus class, where it would matter.

## Conclusion

**Exhaustive boundary exploration is not currently a material bottleneck at the measured
scale.** Seconds per typical run, seven minutes for the largest explore on record, about
seventeen minutes of engine time for the whole dogfood corpus.

**Redundancy is measurable and large as a share of worlds, but not a cost problem at this scale
and not a property of the failures.** In the C and C++ defines of 2 to 19 crash points walked,
half to two-thirds of the worlds repeat an outcome, every repeat is a world that did not fail, and
the runs that hold the most repeats take three to five seconds. **The sample is insufficient to
say what happens in the 100-plus class**, which is where pruning would pay and where nothing was
walked. Those are two statements rather than one because they rest on different samples.

The single case on record where cost changed a plan is worth reading closely, because it is the
shape a bottleneck would take. The 2026-09-16 virtualenv run planned three explores per
observation mode; its preflight showed 1,381 kill points, an explore was estimated at an hour,
and the plan was cut to one per mode. The explore then took about seven minutes, and the run's
own record says three per mode would have fit. What cost that measurement its repetitions was
an estimate about eight times the measured time, not the time itself.

## What would justify a pruning or prioritisation issue

Not this record. Two measured results and one agreement would, and the first is the
prerequisite:

1. **Measured exploration wall clock exceeding a budget the workflow itself states** — a CI
   job's timeout, a campaign's planned time, a re-record's window after a contract bump — so
   that what was planned had to be cut. The virtualenv case does not qualify twice over: it was
   cut on an estimate, and the plan named no budget the measured seven minutes exceeded.
2. **At that target, a coarse collapse ratio of 5:1 or better**, measured the way section 3
   measures it — landed kills checked, and with the pid-hidden reading beside the plain one,
   because timewarrior's 15-of-19 became 7 once its temporary names were read alike. Pruning only
   pays where many worlds give one consequence, and the ratio has to be measured per target
   rather than assumed: the two walked here are 9:1 and under 3:1.
3. **An agreed statement of what a pruner may throw away**, checked against the strict/coarse
   gap. This is not a measurement and the list does not pretend it is one: xz's fifteen strict
   states behind one coarse outcome are where a pruner would be wrong if it is ever wrong, and
   the decision that those states are equivalent is the checker's.

What this record kept running into is itself the obstacle to (1): no report and no structured
transcript line carries a wall clock, so the one case on record had to be found in a sentence
of prose, and the estimate that cut that plan had nothing measured to be checked against. If a
follow-up issue is filed, it should carry those three as its acceptance, and it should be filed
after (1) is observed, not before.

## What this record does not say

- **The clock and the collapse walk are narrow.** Seven defines over five programs —
  timewarrior, jpegtran, bsdtar, xz and the repository's own toy — all C or C++, on one macOS
  host, crash-point counts 2 to 19. The brief asked for roughly ten to twenty real targets
  across languages. That is met by the corpus half — 39 programs in Python, Rust, Go, Java,
  Ruby, PHP, Node, Haskell, C and C++ — for crash-point counts and the first failing crash
  point, and **not** for wall clock or collapse. The reason is what is installed here: these
  five run natively on this Mac (Homebrew or the OS), and the other language families' tools
  exist on this machine only inside the container images their dogfood runs built, which this
  campaign did not rebuild.
- Nothing about an idle machine, another filesystem, or Linux, beyond the two prose figures.
  An oracle adds a second witness to the recording run and does not change the world count.
- **The earlier record's figure is not explained.** `RESULTS.md`'s smallest row measured
  0.17 s per world on the same toy; this record measures 0.017 s. Two things differ and neither
  was isolated: that row carried 20 padding files and this one carries none, and that host was
  at a load average of 10 to 14 against 2.7 to 3.4 here.
- Nothing about refusals. 74 of the 200 dogfood reports refused, and `corpus.py` excludes them
  rather than counting them as cheap explorations. The cost of *reaching* exploration —
  screening, building images, finding a define a target accepts — is not measured here; the
  one committed figure for a whole arc, `spike/assisted/RESULTS.md`'s roughly twenty-five
  minutes for five targets including the image build, is of a different thing.
- Nothing about recovery. A recovery leg (#606) would run *after* a crash world is judged and
  would be counted separately.
- `collapse.sh` is not the engine, in three ways its header lists: it rebuilds the pre-state by
  running `setup` again rather than restoring a snapshot (world 1's tree equals the pre-state
  in all six, so no difference showed); it re-creates a crash point, not a whole world, where a
  run awaited a writing child; and it does not judge — the built-in invariants live in the
  engine, so a world's L0/L1 verdict is not part of any grouping, and two worlds grouped
  together here could still be one violating world and one clean one if the difference is
  something only L0 reads. The failing worlds named in section 3 are the engine's, from its
  report, not this script's.
