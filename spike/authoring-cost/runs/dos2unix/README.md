# runs/dos2unix — a real session, void, published because it happened

This is not one of the four measured runs. It is a complete authoring session that started by
accident, and it is here because the protocol says so: *"A run that starts is published in one
of these forms. There is no fifth outcome and no unpublished run."*

## What happened

While exercising `run-authoring.sh`'s refusal paths — the checks that are supposed to stop a
session from being spent on a target the study should not measure — one case was written as
`run-authoring.sh dos2unix`, expecting the refusal "a run directory already exists". That check
came after the one for `selection.tsv`, which at the time matched the package against the wrong
column and refused everything; fixing the column removed the refusal that was standing in front
of a real run, and the launcher did what it is built to do. Seven minutes, 449 transcript
events, two defines caught by the watcher, the session's own exit 0.

**`disposition: void`**, for the reason in `meta.json`: it was started by an apparatus test
rather than by the study's procedure, and before the protocol was committed. Committing a run
in the same commit as the answer key that grades it is the thing the seal exists to make
visible, and this run cannot be one of the four.

## What it is evidence of anyway

Two things worth keeping, neither of them a figure:

- **The repository-trace detector fires on the apparatus's own handout.** `audit.py` lists two
  traces — `github.com/yottayoshida/sideeye` and `checker-cookbook` — and both sit in a single
  event whose command is `cat /home/user/authoring/README.md`: the front page this apparatus
  copies into the box, which quotes both strings. The box runs `--network=none` and the
  session's usage record shows `web_fetch_requests: 0`, `web_search_requests: 0`. **The subject
  did not reach this repository**, and an earlier version of this file said it did. What the run
  measures is the detector: as first written it cannot tell a subject that read the handout from
  one that fetched a raw URL, which is what `audit.py`'s needles were narrowed for afterwards.
- **It produced no verdict.** `runnable_elapsed_s` is null: the session ended without an
  exploration exiting 0 or 1. What a fresh subject did in seven minutes with this target is
  itself a reading, and merge 2's runs will be read beside it.

## For merge 2

`dos2unix` remains the selection's atomic target — swapping it now would be the post-hoc
substitution the selection rule exists to prevent. Its measured run is a second directory, with
a second session that shares nothing with this one, and the adjudication step reads **this
transcript's presence in the repository** as part of what a later subject could reach.
