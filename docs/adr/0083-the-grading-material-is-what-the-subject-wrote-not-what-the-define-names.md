# 0083 — The grading material is what the subject wrote, not what the define names

Status: Accepted (2026-09-21)

## Context

The authoring-cost study (#618, ADR 0077 and 0078) hands each of two graders a sealed contract
card, `grade-rubric.md`, and a target's define revisions in shuffled order. One of the rubric's
four verdicts is defined entirely in terms of behaviour that material does not contain:

> **`vacuous checker`** — the assertion is right but the checker cannot fail for the reason it
> names: it exits 0 regardless of the state, reads a path the define does not judge, …

`watch-defines.py` snapshotted `*.toml` and nothing else, so the `check` script a define names
was never in the grading material. Every grader in the first round said so unprompted and none
asserted a class it could not see; four published verdicts carry that note (#639).

Three facts constrained the fix, each measured rather than assumed:

- **`check` and `setup` are command strings, not paths.** Of the eight recorded revisions, five
  spell them relatively (`./check.sh`) or with an interpreter in front (`/bin/sh /path/check.sh`),
  and `--cwd` defaults to the engine process's own working directory, which a file watcher
  cannot know. `[world] state` is the same shape — six of eight are relative.
- **A checker's dependencies are not named by the define either.** `genisoimage`'s checker calls
  `mksrc.sh` to rebuild the tree it diffs against; a grader holding `check.sh` alone still cannot
  read it.
- **The watch root is the whole home** (`/home/user`), so any "capture everything except …" rule
  reaches the shell dotfiles, the image's README, the engine tarball, and the watcher's own
  `index.tsv` — the last growing a row per second forever.

## Decision

**The unit is the subject's own directory, not the define's named files.** A file is captured
when it is a **direct child** of a directory holding a define the watcher has snapshotted, is not
a `*.toml`, is not under that define's `[world] state`, is under a size ceiling, and **either did
not exist when the watcher started or has changed since**.

The last two clauses were not in the first draft, and blind review produced a tree that defeated
each of them:

- Recursing into subdirectories captured the target's own data whenever the state could not be
  resolved — and a define that parses while naming no `[world] state` is enough. Direct children
  only: every recorded run keeps its scripts beside the define and its data under `state/`.
- The image's files are not excluded "by construction" by the directory rule, which the first
  draft of this ADR claimed. `prompt.md` points the subject at `/home/user/authoring`, which is
  where the image's README and the engine tarball already are; a define written *there* swept
  both in. The watcher is the container's first process, so what is on disk at its start is the
  image's, and only a change to it is the subject writing.

The exclusion by `[world] state` survives both, deciding one shape: a define naming its own
directory (`state = "."`), where everything beside it is the target's.

**`[world] state` is resolved against the define file's own directory** — the watcher's rule,
not the engine's, written down as such in the docstring because the two could disagree on a
define nobody has written yet.

**The scripts are a second column, never a second revision.** They land in
`revisions/scripts/MM.<name>` with their own index carrying the revision each capture was in
force for. `audit.py` requires `revisions/`'s `*.toml` to be a gapless `1..N` whose count equals
`index.tsv`'s rows; numbering a script edit as a revision breaks all of that and voids every run.
A script is rewritten more often than its define is (three script states to two revisions in one
recorded run, four to two in another), so they cannot share a sequence anyway.

**The scripts reach the grader through the printed brief, and never through the sheet.**
`audit.py` refuses a `grades/*.tsv` whose `# map` names anything that is not a revision number,
in both directions. They ride the revision's own given id — a separate id would be a second
ordering hint in a sheet whose order is deliberately shuffled — and `grader-prompt.md`'s "do not
use the filename as a clue" now covers the capture numbering too.

**The four published runs are not re-graded.** Their material was what it was; the amendment is
dated in both sealed pages so nobody reads those verdicts as having been reached with the
scripts in hand. `RESULTS.md` prints, per run, where the checker can be read in the committed
transcript and the condition each grader wrote for changing its mind — and stops there, because
deciding it would be the self-assessment the two-grader protocol exists to avoid.

## Alternatives considered

- **Resolve the `check` command string and capture that file.** Rejected: five of eight recorded
  spellings do not resolve without the engine's working directory, and it would still miss
  `mksrc.sh`, which no define names.
- **Capture everything under the watch root except a list.** Rejected: measured to include the
  watcher's own index, which makes the capture self-amplifying. The directory rule that replaced
  it is not sufficient on its own either — see the two clauses above.
- **Number script edits as revisions.** Rejected: breaks `audit.py`'s three conditions on
  `revisions/` and makes the `revisions` column incomparable with the four published runs.
- **Reconstruct the four runs' scripts into their grading material and re-grade.** Rejected. The
  containers are gone, so a reconstruction has nothing to be checked against, and a first
  extractor erred in both directions on the committed transcripts — finding no checker at all
  for `lmdb-utils` (its heredoc hangs off `docker exec -i`, not off the inner `sh -c`) and
  collecting a `check-debug.sh` no define names. Before this was decided the four checkers were
  recovered and set beside what the graders wrote; no verdict was found that would move.
- **Add `grader-prompt.md` to the sealed set**, since "what a grader receives" is now defined
  both inside the seal (`grade-rubric.md`) and outside it (the brief and `assign-grading.py`).
  Rejected here and recorded as a known gap: `check-sealed.sh` hashes a fixed four-name list and
  applies the same function to every pre-image, so adding a fifth name makes **every** existing
  pre-image hash to something it never contained, and the only repair is editing a pre-image —
  the one thing a seal exists to forbid. (Recomputed while this was decided, when the ledger held
  nine rows: nine mismatches out of nine.)

## Consequences

- A run recorded before this change has no `scripts/` directory; `assign-grading.py` reads that
  as "no scripts" rather than as an error, so the four published runs stay readable.
- The `revisions` count keeps its old meaning and stays comparable across rounds.
- The watcher now parses TOML, which is new work in the container's PID 1. The whole poll body
  is wrapped: a half-written define at one poll per second is the ordinary case, and an
  exception there would kill the box and void the session rather than lose one snapshot.
- **"What a grader receives" is still defined in two places**, one sealed and one not. The seal
  stays green while the brief changes. That is the gap #639 itself grew in, and it is open.
