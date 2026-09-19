# The authoring-cost study — what the four runs measured

#618 asks how much of a target's own semantics a person must supply before a Sideeye question is
trustworthy, and closes on six conditions. The protocol and the selection rule were committed
before any measurement (condition 1); four semantic shapes have completed authoring records
(condition 2). This page answers the rest.

**What is machine-checked and what is not.** The run table below is held to `audit.py`'s output
row by row, and the row set to the counted runs, by `audit.py --check-page` in CI. The sequence
table, the counts in prose and the quoted timestamps are read from the same records but are
**not** bound by that check — they were verified by hand against the committed transcripts, which
is a weaker guarantee and is said here rather than implied away.

## The runs

| run | judged states | revisions | runnable | outcome | semantic point |
|---|---|---|---|---|---|
| `dos2unix-measured` | 1 | 1 | 235 s | `contested` | none published |
| `genisoimage` | 2 | 1 | 358 s | `graded` | revision 01 |
| `lmdb-utils` | 4 | 2 | 404 s | `none-valid` | none — neither revision accepted |
| `fossil` | 3 | 2 | 485 s | `graded` | revision 01 |

**`judged states` is the primary count, and it is not the revision count.** A judged state is
what the engine's own `l0` line reports — a **count of judged paths plus the scratch declaration
it was given** (`N path(s) judged pre-or-post; K path(s) matched by scratch…`) — not the set of
path names, which the engine does not print. Two adjacent states with the same count and the
same declaration are therefore one state here even if the paths behind them differ; that is a
floor on the figure, not a ceiling. A revision is a define the watcher found *as a file*, and a
define handed to the engine on the command line is never a file, so **three of the four runs
reached a judged state no snapshot caught**.

Some of these states come from `preflight` rather than `explore`, where the line describes the
plan the engine would judge by. The study counts them, because what is being measured is the
question the author posed, not whether a verdict came back from it.

## Condition 3 — "time to a runnable define" separated from "time to a semantically valid question"

Separated, and only the first is a time.

- **Runnable** is an elapsed, from the session's own clock: 235 / 358 / 404 / 485 s.
- **Semantically valid** is published as a revision number and no elapsed. The two clocks (the
  watcher's, inside the container, and the session's, on the host) are not crossed by any figure
  this study publishes. They agree in fact — a container `date` and its host timestamp match to
  the second in all three samples that carry both — but the join between an `l0` line and a
  snapshot is not one-to-one, so the sequence is matched by content and never by time.
- **And it exists for two of four runs.** `lmdb-utils` is `none-valid` and `dos2unix-measured` is
  `contested`, so neither has a semantic point at all. A study of four that answers this
  condition for two is what the sample gives; the gap is not smoothed over.

## Condition 4 — every wrong first interpretation recorded

This condition was **not met by what the second merge published**, and the sequences are what
meet it. Each run's `meta.json` now carries `judged_sets`, and `audit.py` refuses a record that
does not carry its sequence or carries one its transcript does not support. That comparison is
over the judged count and the declaration; the timestamps beside them are carried for reading
and are not what the refusal checks.

| run | the sequence, in order |
|---|---|
| `dos2unix-measured` | `2 judged` |
| `genisoimage` | `14 judged` → `14 judged, 1 matched by scratch (out.iso)` |
| `fossil` | `6 judged` → `2 judged, 4 matched by scratch` → `2 judged, 4 matched by scratch` (a different declaration reaching the same paths) |
| `lmdb-utils` | `2 judged` → `1 judged, scratch lock.mdb` → **`2 judged`** → `1 judged, scratch data.mdb` |

The counts are the engine's own: `N judged` is how many recorded paths the byte rule held, and
`K matched by scratch` is how many the declaration **reached** — not how many patterns it
listed. `fossil`'s two declarations list six patterns and then three, and both reach four paths,
which is why its second move changes the declaration without changing either count.

Two states in that table were nowhere in the published record before this merge:

- **`fossil`'s `6 judged`** — the whole checkout and repository held to byte pre-or-post, which
  is the shape that target's card calls the wrong question. The first interpretation, and the
  most clearly wrong one, was the one being corrected out of the history.
- **`genisoimage`'s accepted revision is a transcription.** The `out.iso` scratch decision — the
  one both graders named as what the author had to know — was made and checked on the command
  line at `07:57:44` (the session's clock); the watcher first saw a file at `07:59:13` (the
  container's). "Right at the first revision" was an artefact of counting files. **That ordering
  crosses the two clocks**, which no published figure does: it is stated here because the two
  agree to the second in all three samples carrying both, and it is an ordering rather than a
  figure. A gap of the size involved does not survive on the other reading.

## Condition 5 — the repeated authoring cost

**The repeated cost is updating the judged set**: deciding, and re-deciding, which paths under
the state root the built-in byte pre-or-post rule is the right question for. Counted from the
records, the set **moved** in three of the four runs — `genisoimage` once, `fossil` twice,
`lmdb-utils` three times — and the one that never moved, `dos2unix-measured`, is the run the
graders split on. The judged **count** fell in only two: `genisoimage`'s stayed at 14 while a
path moved out to `scratch`.

It is **not** a knowledge cost. `lmdb-utils`'s subject worked out LMDB's semantics in four
minutes. At `07:46:13`, in its own reasoning rather than in anything it produced — the string is
in a `thinking` block of the transcript, which is why it is quoted with its location:

> lock.mdb writes go through a shared mmap invisible to file syscalls, recreated as needed

That is the card's claim 2 — the single line both graders named as the reason the run failed —
reached unaided. At `07:46:42` the subject scratched `lock.mdb`. Then it went back to judging
everything, and ended on a define that scratches `data.mdb` and judges `lock.mdb`. **The
sequence is a round trip, and a define scratching both was never written**: the line
`0 path(s) judged pre-or-post; 2 path(s) matched by scratch` does not occur in the transcript.

What the subject saw each time was a count. `1 path(s) judged pre-or-post` — not which path.
A FAIL names the path that broke (`earliest.subject`), so in the first state the subject learned
`data.mdb` was judged and scratched it; nothing ever named the other member of the set, and
`lock.mdb` did not violate, so it stayed invisible while being the whole defect.

**The smallest piece Sideeye can remove without inventing application semantics** is the
bookkeeping, not the judgement: report the judged set as data. Deciding what belongs in it is
the target's semantics and stays with the author; reporting what the engine already decided is
not. Filed as an issue with `lmdb-utils`'s `07:49:50` as its acceptance case, because #618 asks
for the feature to be *filed from* the evidence rather than built alongside its own
justification. See ADR 0078 for what that costs and what was rejected.

## Condition 6 — what was filed

Two issues, each with an acceptance case drawn from a measured failure:

| filed | from | predicate |
|---|---|---|
| **#638** report the judged set as data | `lmdb-utils`, the unnamed `lock.mdb` at `07:49:50` | `reach` — the next step past a wall this study measured. Not a defect: `report-schema.md` describes `l0` correctly as counts and promises no names |
| **#639** the study grades a subset of what the subject authored | every grader raised the missing checker unprompted; three of four runs reached a judged set no snapshot caught | `broken-promise` — `grade-rubric.md` asks for a verdict defined by the checker's behaviour while the apparatus never supplies the checker |

A third was planned and **dropped**: the watcher's blindness to a define handed to the engine on
the command line, as an issue of its own. Its docstring declares it, this merge implements the
refusal that docstring promised, and the states are now published — so what remains is the
grading half, which is #639. Filing it separately would have been filing a declared and
now-surfaced limitation twice.

## What this study does not claim

- **n = 4.** One target per semantic shape, one session each, one model as subject and the same
  model as both graders. Grading is agreement, not truth, and the protocol says so.
- **The verdicts skew high.** `vacuous checker` could not be reached, because the checker's body
  is not in the grading material.
- **The write order was requested, not hidden.** Revisions are handed over as `revisions/NN.toml`.
- **No feature is justified by this page alone.** The one repeated cost it names is filed, not
  implemented, and its acceptance case is a specific measured moment rather than this argument.
