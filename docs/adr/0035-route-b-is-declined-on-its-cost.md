# 0035 — Route B is declined on its cost, not on a proof that it cannot work

Status: Accepted (2026-08-31)

Supersedes nothing. Closes #293. Sibling of ADR 0031, which chose the route that stands.

## Context

`#286` surveyed what verification macOS can buy without demanding root on every run and
named three routes. Route B is FSEvents. `#291` measured it and split the question:

- **H1** — can a capture be rebuilt into the `OpClass` sequence `src/oracle.zig`
  compares? **Measured, dead.** A failed attempt produces no event at all, so the
  shim's account carries an entry the capture never will.
- **H2** — can it act as an independent *veto*, catching a mutation the shim failed to
  report? That is `#293`, and it is a weaker contract: a veto orders nothing and
  attributes nothing, it only notices that the state directory changed in a way the
  account never mentioned.

Two halves of H2 were to be measured. **The false-positive half is done.** `#433` took
three sets of 330 runs and the numbers are in `spike/fsevents/RESULTS.md`.
`spike/check-veto-rate.py` recomputes them from the transcripts and asserts them against
that record's table. It does **not** read this ADR: the table below is a second
transcription, correct at the time of writing and held by nothing.

| | outside on a clean run |
|---|---|
| `link` | 90 / 90 |
| the other ten modes | 7 / 900 = 0.78% [0.38%, 1.60%] Wilson |
| three sets | 2, 1, 4 — chi-squared 2.02 against a 5% critical value of 5.99 |

The homogeneity test is weak evidence at these counts: the expected outside count per
set is 2.33, below the ≥5 the asymptotic approximation usually wants, so it has very
little power against real heterogeneity. It says the three sets do not visibly disagree,
which is the observation `#311` could not make, and not much more.

**The sensitivity half cannot be measured on this build.** Its planted mutation was
`clonefile(2)`, chosen because the shim did not interpose it; trace contract v12 does,
so `L7a` refuses with its own "pick another mutation" message and `L7c` reports 30/30
about a mutation both observers now see. Recovering it needs a mutation v12 cannot
see — the mmap/msync class — which is `#344`, open and untouched by this decision.

So `#293` asks a question that cannot be answered from here. What is left is a choice.

## Decision

**Do not take route B. Close #293.**

**This is not a finding that FSEvents cannot veto.** The half that would say what
fraction of *unreported* mutations it catches is unmeasured, and nothing here makes it
less likely to work. The decision is about price, and the price has three parts.

1. **The relation that can be implemented fails on clean runs.** Path-set containment —
   every path the capture reports must be one the account already names — is the one
   relation that survives the coalescing and reordering H1 died of — though what killed
   H1 outright was narrower: a failed attempt produces no event at all. It is
   outside on 90 of 90 `link` runs and on 7 of 900 for the other ten modes. A veto built
   on it refuses a `link`-using target every time.
2. **Widening it removes the reason to have it.** "An account path *or an ancestor of
   one*" passes every measured run whose outside path the transcripts record, because
   every one of those was the state directory itself. The transcripts print at most
   three outside runs per mode, so that is 16 classifications of the 97 made; the
   remaining 81 are `link` runs and exist nowhere in the record. Widening also excuses
   a neighbour writing into the parent directory — which is precisely the case a veto
   exists to catch. The measurement printed both numbers and deliberately chose
   neither; this chooses.
3. **Attribution is a cost, not an impossibility.** FSEvents cannot say which process
   acted: two runs performing the same operation on the same absolute path, one by the
   probe and one by `/bin/sh`, agree in path and in flags, and `MarkSelf`/`IgnoreSelf`
   separate only the watcher itself. So a veto cannot supply the `child_touched`
   predicate `src/main.zig` takes from the oracle. **A conservative veto that refuses on
   every outside event needs no attribution at all** — it is simply the veto in point 1,
   at the rate in point 1. An earlier draft of this ADR argued attribution made a veto
   impossible; review broke that, and the corrected reading is that it collapses into
   the same cost.

**No acceptance threshold was pre-registered.** Nobody wrote down what false-refusal
rate would be acceptable before the survey ran. The figures above therefore *inform*
this ruling and do not compel it, and stating them as though they forced the conclusion
would be a tidier story than the true one.

## Alternatives considered

**Widen the relation and ship a veto.** Rejected — point 2. It would pass every measured
run and excuse the one case the mechanism exists for.

**Wait for #344, then decide.** Rejected. This is the alternative that would *answer*
`#293` rather than close it, and it stays available: nothing here forecloses it, and
`#344`'s premise now has this ruling written under it. What it costs is a ticket sitting
open on a judgement nobody has made, which is the shape this repository has resolved to
stop producing.

**Give a veto its own report vocabulary.** Rejected. A claim weaker than
`oracle_verified` needs a name, and naming one reopens the contract (`#201`, `#202`,
`#156`). Nothing measured licenses that, and the closed set is frozen.

## Consequences

- **The coverage gap route B was aimed at is carried by route C**, `--oracle-fs-usage`
  (ADR 0031), which reads the syscall layer and does not care how a call was resolved.
  Its acceptance leg is quoted here by what it **asserts**, not by its heading:
  `spike/fsusage/acceptance-local.sh`'s Check 2 runs an ordinary `mkstemp` target under
  a real `fs_usage` and requires exit 2 with either `oracle_missed_operation` or
  `oracle_saw_phantom` — a divergence. **Two lines above it claim more than that.** The
  heading says "the oracle catches what the shim missed", and the `predicate:` line
  printed under it says "exit 2 AND oracle_verified false AND a divergence reason" while
  the code checks the exit status and the reason and never checks `oracle_verified`,
  which it only echoes. Both are quoted accurately here rather than relied on loosely;
  neither is fixed by this change, and the pull request records why.
- **Without an oracle, nothing covers it, and that is already documented.** The README's
  limits say a single-process target with no oracle reaches PASS only under
  `--allow-unverified`, "and the report says the weaker claim out loud". Unchanged.
- **`#344`'s premise now depends on this ruling.** It exists to restore route B's
  sensitivity leg; with route B declined, whether it is still worth doing is a question
  for whoever picks it up. Its state is **not** changed here — it belongs to another
  batch and this decision does not reach into it.
- **No vocabulary, no contract movement.** The `unknown_reason` closed set stays at
  thirty-four members and `docs/contract-freeze.md` is untouched.
- **The apparatus stays.** `watcher.c`, `probe.c`, `judge.py`, `survey.sh` and every
  transcript remain committed. A declined route's measurements are still measurements,
  and `spike/check-veto-rate.py` now recomputes the record's rate table on every pull
  request — a standing obligation this ADR creates in place of the one it declines.
  Its reach is the table and the chi-squared sentence beside it — not this document,
  whose copy of these figures is held by nothing; the record says so where the checker
  is named.
