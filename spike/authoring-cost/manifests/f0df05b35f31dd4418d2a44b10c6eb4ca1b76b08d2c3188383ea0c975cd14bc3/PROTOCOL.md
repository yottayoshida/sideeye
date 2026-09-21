# The authoring-cost study — the protocol, declared before the first run

Issue #618 asks how much of a target's own semantics a person must supply before a Sideeye
question is trustworthy: the distance between a define that **runs** and a define that asks the
**right question**. Its first acceptance condition is that this document and the selection rule
exist before any measurement. Everything here was written, committed and sealed before the first
authoring run; amendments are dated in the Amendments section and each one appends a row to
`ledger.md`, so "what graded run N" is always recoverable (ADR 0077).

**This study measures a subject's authoring, not Sideeye's mechanics.** The onboarding clock
(`spike/onboarding-clock/`) already measures the mechanical half — README to a verdict. It stops
where this one starts.

## What is measured

For each target, two points on one authoring session's clock, plus the revisions between them:

- **runnable**: the first `explore` (or `preflight`) in the session that exits 0 or 1 — a real
  verdict. A refusal (exit 2) does not qualify; refusals are named and the subject keeps going.
- **semantic**: the first define revision that **both graders accept** against the sealed
  contract card (below). If only one grader accepts any revision, the run publishes as
  `contested` and **no semantic point is published** — the disagreement is the finding. If
  *neither* accepts any revision, the run publishes as `none-valid`, which is a result and not
  a gap: the session reached a define the engine would run and never reached one that asked the
  target's question.
- **revisions**: every define the session produced **as a file**, in order.
- **judged sets**: every set the subject actually had the engine judge, in order, read from the
  engine's own `l0` line in the transcript. **This, not the revision count, is the study's
  primary figure** — a language model's seconds are not a person's, so the count is what
  matters, but the count has to be of what the subject tried. The revision count is not: a
  define handed to the engine on the command line never becomes a file, and measured across the
  four runs, three of them reached a judged set no snapshot caught (Amendments, 2026-09-19).

**Elapsed figures come from the transcript; revisions are counted rather than timed.** The
watcher runs on the container's clock and the session on the host's, so no figure subtracts one
from the other: `runnable` publishes an elapsed and a revision number, the semantic point
publishes a revision number only. `audit.py` refuses — rather than guessing — on evidence that
cannot be read: a gap in the snapshot sequence, an index row whose digest is not its snapshot's,
or no snapshot at all, which makes the run `void` however fast the transcript looks.

**Outcome forms**, all published with the same detail: `graded` (both graders accepted some
revision), `contested` (at least one grader accepted a revision and they never agreed on one —
including the case where only one of them accepted anything), `none-valid` (both graded and
neither accepted any revision), `no-verdict` (the session ended without a runnable define),
`void` (see Disposition). A run that starts is published in one of these forms. **No run goes
unpublished, and a run's form is never left blank because grading was inconvenient.**

`none-valid` was added by the first measured run (Amendments, 2026-09-19). The list before it
ran to four and said in bold that there was no fifth; `lmdb-utils` was it — both graders agreed
exactly, on the verdict and on the deciding card line, that neither revision asked the right
question, and the audit had no way to say so. It printed `contested-or-ungraded`: the same
string it printed for a run nobody had graded. The forms were closed against a fifth outcome
arriving, which is not something a protocol can close against; what it can close against, and
now does, is a run whose form is never written down.

## The subject

One `claude --safe-mode -p` session per target, given the prompt in `prompt.md`, reaching the
target only through `docker exec` into a container this directory builds. The subject is told
what to produce; it is **not** told that its revisions are being snapshotted, and it is not
asked to commit anything (see Evidence).

**One leg only: the subject may read anything it can reach, including this repository.** An
earlier draft split runs into "with the checker cookbook" and "without". That condition cannot
be held: the onboarding clock's own protocol records that the driver is an API client which
cannot be network-isolated, and this repository is public — one `curl` of a raw URL turns a
without-cookbook run into a with-cookbook run, silently and undetectably. A condition that
cannot be enforced is not declared. What is declared instead is the **Disposition** rule below.

## Evidence

- **Revisions are files.** A watcher (`watch-defines.py`) runs as the container's main process
  and copies every define the subject writes — any `*.toml` under its home whose contents
  changed — to `runs/<target>/revisions/NN.toml`, with `index.tsv` recording the order, the
  digest and the path. **It copies the scripts beside that define too** — every file in the
  define's own directory that is not a `*.toml` and not under its `[world] state` — to
  `revisions/scripts/MM.<name>`, with its own index carrying the revision each capture was in
  force for. A script is rewritten more often than the define file is, so the two are counted
  separately and the revision sequence is unchanged by a script edit.

  *(Amended 2026-09-21, #639. The scripts half did not exist for the first four runs: the
  material was `*.toml` alone, which left `grade-rubric.md`'s `vacuous checker` unreachable from
  what a grader held. **Those four were graded without the scripts** and their verdicts stand as
  given; `RESULTS.md` says what that leaves standing and where the scripts can be read in the
  committed transcripts.)* The subject is not involved, so the record does not depend on its
  cooperation and an in-place edit cannot erase the first wrong reading. **A wrapper around
  `sideeye` was the first design and was wrong**: the subject unpacks the engine itself, so a
  shim on `PATH` announces that the tool is already installed — changing the task — and an
  invocation by path walks around it. Watching the artefact also catches a define that was
  written and abandoned before it ran, which is the case #618 cares most about.
  What the watcher cannot see is stated in its own docstring: two rewrites inside one second
  are one revision, and a define that never becomes a file is not seen at all.
- **The transcript is published**, normalised: the host's home directory is rewritten at a path
  boundary to `~`, and credential shapes — `sk-ant-…`, `sk-…`, `ghp_`/`gho_`, `glpat-`,
  `xoxb`/`xoxp`, a bearer token, `ANTHROPIC_API_KEY=` — are replaced with `[redacted]`.
  **`SIDEEYE_*` values are deliberately kept**: they are apparatus configuration rather than
  credentials, and removing them would delete the observational evidence the rubric's
  `observational` class is about. The onboarding clock deliberately does
  **not** publish raw transcripts; this study must, because #618 requires the wrong first
  interpretations, so it carries the normalisation rule the clock does not need.
- **Nothing is edited after the fact.** A revision file is written by the watcher or not at all.

## The answer key: contract cards

One card per target (`cards/<target>.md`), sealed before the run. Each card states, for that
target, what is durable, what is scratch, whether recovery is part of the contract, and what a
checker should assert. **Every claim carries one of three backings:**

| backing | meaning | graded? |
|---|---|---|
| `documented` | a citation from the target's own documentation, quoted with its location | yes |
| `measured` | an experiment run **with the target's own tools** — its reader, doctor, `strace`, `hexdump`, `sqlite3` — with the procedure **and its output** committed in the card | yes |
| `unspecified` | neither the documentation nor an experiment settles it | **no** |

`measured` may never use Sideeye: this study grades defines written for Sideeye, and taking
Sideeye's verdict as the answer would grade the tool against itself.

A card may not be written or changed after a run it grades. If a card must change, the runs it
already graded are either re-published under the new manifest **with their grades recomputed and
both grades shown**, or voided — never silently re-graded.

## Grading

Two fresh graders, each given the sealed card, the sealed rubric (`grade-rubric.md`), and the
revisions **in shuffled order**, with no access to each other's answers. Each returns, per
revision, one of `semantically valid` / `wrong question` / `vacuous checker` / `unresolved by
card`, plus the issue's four friction classes (mechanical / observational / semantic / checker
quality) for each revision that moved.

Grading is probabilistic and this protocol does not pretend otherwise: the graders' model and
version are recorded per run, agreement is published, and the semantic point exists only where
they agree.

## Disposition

Read in this order, before grading:

1. **`void`** — the run did not measure authoring: the apparatus failed, the container died, the
   target was not installed, or the subject never saw the prompt. A voided run is published with
   its reason and excluded from every figure.
2. **`adjudicate`** — the transcript shows the subject reaching this repository (a raw URL, a
   clone, a define copied verbatim from `spike/unknown-rate/defines-b2/`). The run is **not**
   automatically void: reading the published documentation is what a real user does. The
   adjudication — count it, or void it — is written into the run's record with the evidence, and
   it is made before the grades are read.
3. Otherwise the run is graded.

The audit prints every repository-derived string it found, so step 2 is answered from a list
rather than from memory.

## Targets

Four semantic shapes, one target each, from #618:

1. a single-file operation whose intended contract is old-or-new byte atomicity;
2. a journaled or transactional store whose correct contract includes recovery;
3. a target with disposable scratch or cache state mixed into the declared state tree;
4. a target whose useful invariant is behavioural — its own reader, doctor or diagnostic must
   agree with what was persisted.

**The assignment of a target to a shape is our judgement, made before the runs, and it is
therefore part of the semantic work this study does not measure.** It is recorded here rather
than described as "selected", because a mechanical predicate for "this store is journaled" does
not exist in the package metadata this repository can read. What *is* mechanical is the pool
membership, the exclusion and the order: `select-targets.sh` takes the first candidate in each
pool, keyed on the v1.5.0 tag's commit, that survives the exclusion predicate — **no tracked
file outside the selection names it**, the predicate `b2-author.sh` already uses, because the
answers live in `spike/unknown-rate/defines-b2/<target>/NOTES.md` as much as in any ledger.

A target must install from the container's package index with no network at run time, which
bounds the population to packaged command-line tools. That bound is a limit on what this study
can generalise to, and the results state it.

## Sealing

`check-sealed.sh` recomputes a manifest over this file, `prompt.md`, `grade-rubric.md`,
`selection.tsv` and every card, compares it with the last row of `ledger.md`, requires the
pre-image of that hash to exist under `manifests/<hash>/`, and requires every published run to
name a hash the ledger holds. `ledger.md` is appended only through `spike/ledger-append.sh`,
which proves the new file still extends HEAD's copy. The check prints how many hashes and runs
it scanned and fails when it scanned none.

## Amendments

*(Dated entries only; each one appends a row to `ledger.md`. A change here voids nothing
retroactively, and a run keeps the manifest it named.)*

- **2026-09-19 — `none-valid` named as an outcome form.** The four measured runs had all been
  run, and the first of them produced a form the list did not name: both graders graded, agreed
  with each other, and accepted nothing. The audit reported it with the same string it uses for
  an ungraded run, so the study's primary question — did the session reach a define that asks
  the target's question — was being published as a gap.

  Made **after** the four runs and **before** any of their grades were written into a figure.
  It changes no card, no rubric line and no grade: the graders were never shown this document,
  and each run keeps the manifest it named. The edit was drafted while two runs were still to
  go and **reverted until they finished**, because this file is inside the sealed manifest and
  amending it mid-campaign would have refused those runs and split four measurements across two
  answer keys.

- **2026-09-19 — the primary count is the judged set, not the revision** (ADR 0078). "What is
  measured" above said the revision count was this study's primary figure. Measured after all
  four runs: a define handed to the engine on the command line never becomes a file, so the
  watcher never sees it, and **three of the four runs reached a judged set no snapshot caught**
  — including `fossil`'s `6 path(s) judged`, the shape that target's card calls the wrong
  question, which was therefore absent from the published record while #618's fourth condition
  asks for exactly that state to be kept.

  The engine prints what it judged on every run, so the transcript holds them all. Each run's
  record now carries `judged_sets`, `audit.py` derives the same sequence and refuses a record
  that does not carry it or carries one the transcript does not support, and `revisions` stays
  published beside it as what the watcher saw. **No grade, card or verdict changes** — the
  sequence is a second reading of evidence already committed, not a re-measurement.

- **2026-09-19 — the `contested` wording corrected, by review of the amendment above.** That
  amendment rewrote the parenthetical to "each accepted something, never the same one", which
  **excludes the one contested run this study has**: on `dos2unix-measured` grader A accepted
  nothing and grader B accepted one revision. It matched neither the new wording nor
  `none-valid`, while "What is measured" above — unchanged, and what the code implements — has
  always said that one grader accepting alone publishes as `contested`. A self-contradiction
  three lines under a sentence saying a run's form is never left blank, caught before anything
  was committed. No run's outcome changes: `dos2unix-measured` was `contested` before this line
  and is `contested` after it. Kept as a second row rather than rewritten into the first,
  because the ledger is append-only and because the review finding it is part of the record.
