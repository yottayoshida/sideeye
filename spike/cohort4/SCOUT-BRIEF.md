# Cohort 4 — the scout's brief

The instrument for proposing candidate targets. **It names no target**, and
it is not the PROTOCOL: the PROTOCOL freezes the chosen list, and it comes
after the engine change this cohort waits on (#231) and after the owner
signs off on the list this brief produces.

Read `PREP.md` first — its §3 register is why several rules below exist,
and its §5 is what the probe will do to whatever this brief proposes.

## What the scout is for, and what it is not

**For**: producing a table of candidates whose rule conformance is
*measured*, together with the candidates that were rejected and why, so the
owner picks from evidence rather than from taste. The owner's sign-off on
the final list is required and is not delegable.

**Not for**: deciding the list, writing defines, running the engine, or
filing anything upstream. `docs/scouting.md`'s "What a scout must never do"
applies in full — in particular, nothing this scout touches may be called
*blind*, and no belief of the scout's may appear in a verdict. A belief
becomes a checker or it stays out of the record.

## Capability floor

Measured, not assumed (#221, recorded in `docs/scouting.md`): **Opus 5 or
better**, with Sonnet 5 the floor. Haiku 4.5 was below the bar — it
invented a target field that did not exist and missed two determinism
hazards out of five. The metadata gate cannot catch that class: it checks
that fields are present, not that they are true, so the falsification and
probe layers are what pay for a weak scout. Run the scout on Opus 5.

One measured hazard specific to running this in the workspace: **the
memory index injects cohort target names into fresh agents** (#221). Any
step that depends on an agent not knowing the candidates has to run out of
band, and the record has to name that channel.

## The rules a candidate must satisfy

Rules 1–13 are #209's, unchanged, and they are conjunctive — *all* must
hold. Rules 14–17 are cohort 4's additions, each bought with a specific
cohort-3 failure (`PREP.md` §3).

1. ≥1,000 GitHub stars.
2. Release or substantive development activity within the last 6 months.
3. Multiple sustained contributors.
4. CLI is the primary interface.
5. Stores primary data locally that users do not want to lose.
6. Main state is plain text / JSON / YAML / TOML / a directory tree / a
   small number of ordinary files.
7. SQLite, an embedded DB or an own transaction engine is **not** the main
   store.
8. Non-interactive mutating commands exist.
9. A checker can be written using the target itself.
10. Dynamic linking and single-threaded-ish behaviour expected within the
    engine's observation range — **verified by probe, never assumed**.
11. Responsiveness: recent **bug reports** show maintainer or contributor
    response within ≤1 week, measured with receipts. State the
    counter-evidence beside it: this project's own four upstream reports
    have stood at zero comments (`spike/upstream-report-status.sh` prints
    the current table). Rule 11 has never been tested on a report of ours.
12. Currently used, not legacy-only — measuring only old architectures
    would predetermine the answer.
13. Language diversity across the cohort: not a single-language slate.
14. **Novelty pre-scan clears it (veto).** See below.
15. **Interior forecast**: the operation must plausibly have more than one
    in-root kill point. Confirmed at probe by condition 9. A single atomic
    mutation is a contrast measurement, not a criterion-1 slot — that is
    the papis shape, and it was frozen into cohort 3 before anyone counted.
16. **Wall forecast against the known list** (`PREP.md` §3F, plus the
    measurement below): a forecast wall enters only with the apparatus that
    lifts it named *before* the probe, or the candidate does not enter.
17. Rule 11 measured on bug reports specifically, per its own text above.

## Rule 14 in detail: the pre-scan is a veto, not a ranking

Run `spike/cohort4/novelty-prescan.sh <owner/repo>` per candidate and
commit the transcript. Read it as **one question only**: is this
operation's write shape already on the tracker? If yes, the candidate is
out. The scan does not rank and must not be used to rank.

Why the distinction is load-bearing rather than pedantic. Tracker silence
has four possible meanings — nobody has hit the defect yet; the defect is
absent; the project's users do not file crash-consistency reports; or the
search vocabulary missed it. Only the first is "novel". Ranking candidates
by silence therefore selects toward projects nobody examines closely, which
is the opposite of what rules 1, 3, 11 and 12 exist to enforce. Used as a
veto, the ambiguity never has to be resolved: the scan only ever asserts
*not already known*.

Two properties of the scan the scout must not misread, both measured
(`novelty-prescan.sh`'s own header and `novelty-prescan-validation.txt`):

- A **space-separated query returns zero** through this API. Multi-word
  terms are refused by the script for that reason; do not work around it.
- A broad term **saturates the page limit** and prints `>=100 SATURATED`,
  with only the top 20 by relevance listed. That is a floor, not a count,
  and the scan cannot prove absence. A clean scan is evidence that a known
  shape was looked for and not found, nothing more.

Order the surviving candidates by **coverage** — a language × class matrix,
the way cohort 3 did — never by expected yield.

## The wall forecast (rule 16), with what is already measured

Do not re-discover these. Each has a recorded run
(`docs/target-classes.md`):

| Forecast | What it looks like | Recorded |
|---|---|---|
| Static linkage | `no_shim_marker` | jj, and Go's default |
| Threads | `multiple_threads_detected` | Bun; libuv predicted, unmeasured |
| Writing children | `child_touched_state_dir` | pass (#123) |
| Raw syscalls past libc | `oracle_missed_operation` | cargo's manifest rename (#217) |
| **Internal libc calls** | same refusal, different cause | **`mkstemp` + write + rename, measured 2026-08-22** (#39, `mkstemp-class.txt`) |
| Nondeterministic writers | `baseline_violates_invariant` | watson |
| Encrypted / memory-locked state | probe-stage refusal | KeePassXC |

The `mkstemp` row is the one most likely to bite this cohort, and it is
new: the canonical C atomic-replace idiom hides its file creation inside
libc, so **a C or C++ candidate whose write path uses `mkstemp` reaches
cargo's wall**. For any C or C++ candidate, say what the write path is and
how that was determined. `preflight.sh visibility` settles it at probe time
with no define spent, but a forecast costs nothing and orders the slate.

## The provenance line the scout must not cross

Criterion 1 requires the invariant to be committed before **this project
observes any failure of the target in execution**, and states explicitly
that *reading a report of a failure while scouting is not observing one*.
So the novelty pre-scan is legal by text, not by charity: reading the
tracker is reading reports. What is forbidden is running the target into a
failure, reading traces of one, or doing crash surgery before the define is
committed. Everything the scout reads is named in the proposal, and the
label is **assisted** — never blind.

## What each candidate row must carry

Measured values with the command that produced them, never recalled ones.
A candidate row missing a measurement is not a weaker candidate; it is an
incomplete row.

- Repository, tool, and the **single operation** proposed for measurement.
- Stars, last push date, release history, contributor count — with the
  `gh` invocation used.
- Rule 11 receipts: specific recent bug issues with their first-response
  times.
- The state root, the state's file shapes, and the non-interactive command
  that mutates it.
- The write path, as far as documentation and `--help` reveal it, and the
  wall forecast that follows (rule 16).
- Interior forecast (rule 15) with its reasoning.
- Novelty pre-scan transcript path and its one-line reading (rule 14).
- The checker sketch: which of the target's own commands would show the
  state is intact, and which documented recovery step precedes the assert.

## Output, and the rejected candidates

One table of survivors ordered by coverage, and **one table of
rejections** with the rule each failed and the measurement that failed it.
The rejection table is the part that makes the selection auditable — a
slate with no visible rejections is indistinguishable from a slate chosen
by taste.

Neither table is a decision. The owner's sign-off on the final list closes
this step (`PREP.md` §9, step 5), and the PROTOCOL freeze that follows is
what makes the outcome — find or honest null — publishable.
