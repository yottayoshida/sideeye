# 0082 — The measured envelope warrants no crash-point budgeting

Status: Accepted (2026-09-20)

## Context

ADR 0081 built an instrument and, before it ran, wrote down the reading it expected and the rule
it would apply: a problem is *"an operation a project would plausibly run in CI taking longer
than its other checks, or a resource growing faster than the world count"*, and *"if the measured
envelope stays inside these figures, the correct outcome is that no feature follows"*. #621 is
explicit that the outcome may be either — practical, or **one** follow-up product issue naming a
measured bottleneck — and equally explicit that budgeting must not be added because it was
anticipated.

The grid has run. `spike/explore-cost/scale/RESULTS.md` holds it; the two 150-row records and the
anchor are committed beside it. The numbers that decide this ADR, on one file of judged state
with `wrappers` and no checker, median of three repetitions in `debian:bookworm-slim` under
Docker Desktop on an Apple M4:

| worlds | wall | per-world | trace bytes | report bytes |
|---|---|---|---|---|
| 13 | 0.035 s | 0.00266 s | 9,928 | 913 |
| 103 | 0.204 s | 0.00198 s | 499,528 | 917 |
| 1003 | 4.170 s | 0.00416 s | 45,787,528 | 922 |

Peak RSS is deliberately absent from that table: every small-state row's memory figure is the
engine's own `version` probe's peak, which the instrument labels as a floor, and a first draft of
the record published those floors as the measurement. The rows where memory is the exploration's
own are the large-state ones — 70,156 KiB at 13 worlds to 73,704 KiB at 1003.

A thousand crash points is **fifty-five times the p90** of this repository's dogfood corpus
(median 5, p90 18) and about three-quarters of the largest run on record (1,381). On a 20 MB
state tree the same run is 30 seconds. A real target — timewarrior 1.4.3, measured in the same
container under the same oracle — costs **1.37×** the toy per world at the nearest measured world
count; no multiplier from this toy to real targets in general is established. On the earlier
`spike/explore-cost/RESULTS-AT-SCALE.md` host the same timewarrior define cost about five times
*that* record's toys, and its five real defines span 2.9× among themselves.

## Decision

**Apply the rule as written: exploration is practical over the measured envelope, and no feature
follows.** No crash-point budget, no sampling, no `--max-worlds`, no quick mode, and no
follow-up product issue — there is no measured bottleneck for one to name.

The second clause is answered the same way, against the reading declared for it rather than
against a fresh one. Trace and work bytes **are** quadratic, which is the designed consequence of
keeping one trace per world; the declaration said in advance that this counts as a problem only
when the absolute size becomes one, and 45.8 MB at the top of the envelope is not that — a
judgement by eye, because the declaration promised a byte threshold and states none. The report
does not grow: nine bytes across 77× the worlds, which is ADR 0079's bounded judged set behaving
as designed.

**Memory is where the declaration's expected reading was wrong, and this ADR records that rather
than smoothing it.** The pilot's summary row predicted RSS would rise with the state tree
*instead of* with the world count, and named "a rise with worlds instead" as the clause firing.
Measured on the rows where the figure is the exploration's own, it rises **5.1% over 77× the
worlds**. Something moved, so the shorthand is false. The rule's own text — "a resource growing
faster than the world count" — is what is applied, and memory grows at 0.07% of that rate against
a 6.0× step from the state tree at a fixed world count. Choosing the rule's text over the
shorthand is a judgement made in public with both readings stated, not a threshold moved.

Two figures are reported and **claimed for nothing**, because the declaration said three
repetitions could not carry them: `syscalls` over `wrappers`, and a cheap checker over none. Both
are slower in 24 of 24 independent pairs — a unanimous direction that does not depend on the
repetition count — at median ratios of 1.089× and 1.069×, which sit near the run's own
within-cell spread. The direction is recorded; no cost is attached to either.

## Alternatives considered

- **Add a budget or a sampling mode anyway**, since the quadratic trace growth is real and will
  eventually bite. Rejected: #621 forbids exactly this, and the declaration fixed the threshold
  before the numbers so that "eventually" could not be smuggled in as "now". The growth is
  documented, and the number at which it would matter is a measurement nobody has taken.
- **File the follow-up issue anyway**, on host-load sensitivity (the loaded run is 2.4× the quiet
  one at worst). Rejected: that is a property of measuring on a shared machine, not of the
  engine, and #621 asks for a bottleneck in the thing being shipped. It is written into
  `RESULTS.md` as a finding for anyone running an exploration beside other work.
- **Re-measure on a GitHub-hosted runner before concluding.** Not taken here, and the cost is
  stated below rather than hidden: it is the one thing that would let the first clause be a
  comparison instead of a count.

## Consequences

- **The first clause is narrowed, in public, twice over.** Every figure is from Docker Desktop on
  an M4, and the first merge measured that container at ~17× the macOS host beside it, so the
  claim this ADR supports is "practical on hardware of this class", not "practical on any
  runner". And the clause as written is a **ratio** against a project's other checks on the same
  machine; the record compares against its own declared table instead, which tests whether the
  estimate was right rather than whether the cost is acceptable. The conclusion therefore rests
  on the seconds being small in absolute terms. That substitution is the largest gap in it.
- A future proposal to add budgeting, sampling or a quick mode starts from this record rather
  than from an intuition, and has to say which figure moved.
- `RESULTS.md`, the two grid records, the anchor and `PROTOCOL.md` are kept as a closed record.
  The instrument stays runnable (`run-grid.sh`, `run-cell.py --selftest`) but nothing here enters
  standing CI — it is an apparatus, the position `spike-fsusage.yml` states about itself.
- The evidence bundle's size is still unmeasured: the harness reads the report's `case` and not
  its `evidence` (ADR 0071), so `RESULTS.md` records 538 bytes for a saved case and says the
  bundle figure is absent rather than zero.
