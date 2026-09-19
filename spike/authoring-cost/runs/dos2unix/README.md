# runs/dos2unix — a real session, void, published because it happened

This is not one of the four measured runs. It is a complete authoring session that started by
accident, and it is here because the protocol says so: *"A run that starts is published in one
of these forms. No run goes unpublished, and a run's form is never left blank because grading
was inconvenient."* (That sentence used to end "There is no fifth outcome and no unpublished
run", and the fifth outcome arrived with the first measured run — `none-valid`. The rule this
page rests on, that a run which starts is published, is the half that held.)

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
- **It reached a verdict at 217 s, and this page said for a while that it never did.** The
  sentence here used to read "it produced no verdict — `runnable_elapsed_s` is null", written
  straight off the audit's output. The null was the detector, not the session: `audit.py` looked
  for a verdict at a line start, and every line in a normalised transcript carries its newlines
  as the two characters `\` and `n`, so the anchor never matched. Corrected in merge 2 with the
  detector; the run's own event at `07:02:59.920Z` is `PASS  11/11 explored worlds satisfied the
  built-in atomicity invariant`, 217 s after the session started. The reading that hung off the
  null — "what a fresh subject did in seven minutes without getting there" — was a reading of an
  instrument, and it is withdrawn. What stands is that this session reached a runnable define
  faster than any of the four measured runs did.

## For merge 2

`dos2unix` remains the selection's atomic target — swapping it now would be the post-hoc
substitution the selection rule exists to prevent. Its measured run is a second directory, with
a second session that shares nothing with this one, and the adjudication step reads **this
transcript's presence in the repository** as part of what a later subject could reach.
