# The runs

One directory per authoring session. Each holds what the apparatus collected, not what anyone
remembered afterwards:

| file | written by |
|---|---|
| `meta.json` | the launcher — target, the sealed manifest the run was graded under, the session's start and end, the target's installed version, the subject's model, the disposition |
| `transcript.jsonl` | the launcher, normalised (home path to `~` at a boundary, credential shapes redacted, `SIDEEYE_*` kept because it is apparatus configuration) |
| `revisions/NN.toml` + `index.tsv` | the watcher inside the box, one snapshot per define the subject wrote |
| `revisions/scripts/MM.<name>` + `index.tsv` | the watcher, one snapshot per file the subject wrote beside a define — its checker, its setup, and what those read. Absent from a run recorded before #639 |
| `grades/*.tsv` | the two graders, independently, against the sealed card and rubric |
| `box.txt`, `normalisation.txt`, `session-stderr.log` | the apparatus's own account of what it built and what it dropped |

`audit.py <run>` derives the figures from those files and refuses when they do not line up.

`meta.json` also carries **`judged_sets`** — every set the subject actually had the engine
judge, in order, read from the engine's own `l0` line in the transcript. That is not the same
list as `revisions/`: a define handed to the engine on the command line never becomes a file.
The conclusions drawn from these runs are in [`../RESULTS.md`](../RESULTS.md).

## The four measured runs (2026-09-19)

All four ran under manifest `228c73b6…`, one session each, `claude --safe-mode -p` on
`claude-opus-5[1m]`, graded by two fresh graders on the same model with no conversation history
and no sight of each other's answers.

| run | judged states | revisions | runnable | outcome | semantic point |
|---|---|---|---|---|---|
| `dos2unix-measured` | 1 | 1 | 235 s | `contested` | none published |
| `genisoimage` | **2** | 1 | 358 s | `graded` | revision 01 |
| `lmdb-utils` | **4** | 2 | 404 s | `none-valid` | none — neither revision accepted |
| `fossil` | **3** | 2 | 485 s | `graded` | revision 01 |
| `genisoimage-scripts` | 2 | 3 | 657 s | `ungraded` | — (apparatus, not a measurement: `RESULTS.md`) |

**Four runs, four different outcome shapes**, including one the protocol had no name for:
`lmdb-utils` is a session that reached a define the engine would run and never reached one that
asked LMDB's question — both graders agreeing exactly, on the verdict and on the deciding card
line. `none-valid` was added for it (PROTOCOL.md, Amendments 2026-09-19), after all four runs and
before any grade became a figure.

The elapsed figures are the session's, not a person's, so a count is what matters — but **the
count is `judged states`, not revisions**, and this table said otherwise until the sequence was
read out of the transcripts. A define handed to the engine on the command line never becomes a
file, so the watcher never sees it, and three of these four runs reached a judged set no
snapshot caught. What a reader should not take from the table is a ranking by difficulty:
`dos2unix` is fastest *and* contested, and `genisoimage`'s accepted revision is a transcription
of a decision already made and checked on the command line a minute and a half earlier.

**Where the two graders split.** Only `dos2unix-measured`, and on the same reading of the same
define: the judged state is rooted at the directory dos2unix assembles its `d2utmp*` temporary
in, with no `scratch` declared. One grader called that `semantically valid` — a file present in
only one of the two snapshots is unconstrained, so the leftover cannot move the verdict — and
the other `unresolved by card`, because the card assigns this fork in advance and this define is
not the branch it names valid. The protocol publishes the disagreement and no semantic point.

**The write order is requested, not hidden.** The per-grader shuffle removes the *given id* as a
cue, and the brief asks the grader not to read the filename as one — but the paths handed over
are `revisions/NN.toml`, so the ordinal is visible. Nothing in the apparatus prevents a grader
from reading it. Only `fossil` has both more than one revision and two different draws, so it is
the one run where a verdict following the id would surface as a disagreement the maps explain;
each run's `grader_assignment_note` says which case it is.

**A limitation that applies to every row.** The graders received the define TOML and nothing
else: the watcher snapshots `*.toml`, so the `check` script a define names is not in the grading
material. The rubric's `vacuous checker` verdict is defined entirely in terms of what that script
does, so **it could not be reached in this round and the verdicts skew high.** Every grader
raised it unprompted. It is not fixed here — the earlier runs' containers are gone, so a later
run measured with the checker in hand would not be comparable to them — and it is recorded in
each run's `grading_limitation`.

## The void run

- **`dos2unix/`** — **void**, and published because the protocol says a run that starts is
  published. It began during a refusal-path test of the launcher; its own README says how, and
  it is excluded from every figure. It is also the only place the whole launcher ran before the
  measured runs, which is why the apparatus was known to work end to end. `dos2unix` was measured
  properly as `dos2unix-measured`, since a run never edits another's directory.
