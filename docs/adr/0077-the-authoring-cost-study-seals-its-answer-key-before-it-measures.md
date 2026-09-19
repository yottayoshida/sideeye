# 0077. The authoring-cost study seals its answer key, and its pre-image, before it measures

Status: Proposed (design-first: the protocol of a study that has not run; #618 requires it to be committed before the first measurement)

## Context

#618 asks how much application semantics a user must supply before a Sideeye question is
trustworthy — the gap between a define that *runs* and a define that asks the *right* question.
Its first acceptance condition is that the protocol and the target-selection rule are committed
before the measurements, and its fourth is that every wrong first interpretation is recorded
rather than corrected out of the history.

The repository already measures one authoring-adjacent thing and records thirty authored
defines, and neither answers this:

- `spike/onboarding-clock/` times a context-free driver from the README to a **verdict**. It
  stops at "runnable", which is the half #618 says is already known.
- `spike/unknown-rate/defines-b2/*/NOTES.md` holds thirty authored defines with the
  contract-shaped paragraph this study needs as a card format. But it keeps only final forms:
  `b2-clock.tsv` carries a midpoint for fourteen of the thirty and is self-reported, and two of
  the thirty NOTES mention a revision at all. There is no record of a first wrong reading.

So a new measurement is needed, and the thing that makes it a measurement rather than a
demonstration is an answer key written before the runs — with everything that makes an answer
key falsifiable: whose evidence it rests on, what it declines to answer, and proof that it did
not move afterwards.

## Decision

Four rules, sealed together as one manifest.

1. **The answer key is a contract card per target**, and every claim in it carries one of three
   kinds of backing: `documented` (a citation from the target's own documentation), `measured`
   (an experiment **run with the target's own tools** — its reader, doctor, `strace`, `hexdump`
   — never with Sideeye, whose verdict is the thing under test), or `unspecified`, which is
   excluded from grading. A card written after a run does not grade that run.
2. **The seal keeps its pre-image.** `manifests/<hash>/` holds the protocol, the cards, the
   rubric and the selection as they were; `ledger.md` is appended only through
   `spike/ledger-append.sh`; every run names the manifest hash it ran under; and a protocol
   amendment must appear as both a dated heading and a new ledger row. A list of hashes alone
   is not a seal: it stays green when a card is edited after a run and a row is appended.
3. **Every run that starts is published**, with its revisions as files. A watcher inside the box
   copies every define the subject writes — any TOML under its home whose contents changed — so
   the record does not depend on the subject agreeing to keep one, and the subject is not told
   it is being measured that way. (A `PATH` shim over `sideeye` was the first design and was
   dropped: the subject unpacks the engine itself, so a shim announces the tool is already
   installed and an invocation by path walks around it. Watching the artefact also catches a
   define written and abandoned before it ran, which is the case #618 cares most about.)
4. **Grading is two independent fresh graders**, revision order shuffled, model recorded. The
   semantic clock stops at the first revision **both** accept; where only one accepts, the run
   publishes as `contested` and no semantic time is published.

## Alternatives Considered

**Split the runs into "with the cookbook" and "without".** Rejected: unenforceable. The
onboarding clock's own protocol records that the driver is an API client that cannot be network
isolated, and this repository is public — one `curl` turns a without-cookbook run into a
with-cookbook run, silently. A condition that cannot be held is not declared.

**Seal by the absence of results** (a check that no run directory exists yet). Rejected: it
goes red on the merge that adds the first run, so it would have to be removed exactly when it
starts mattering — the shape `spike/check-sealed-campaigns.sh` exists to avoid.

**Close #618 by analysing the thirty existing records.** Rejected on measurement: no revisions,
no first wrong readings, no semantic judgement, and an author who had the repository open.
They serve as the card format and a self-reported setup-time distribution, not as the study.

**Let Sideeye's own verdict decide whether a define asks the right question.** Rejected as
circular; that difference is the thing being measured.

## Consequences

- The study can be re-derived: any published run names a manifest whose contents are in the
  tree, so a reader can see the answer key that graded it rather than the current one.
- Grading remains probabilistic. Two graders and a sealed rubric bound it; they do not make it
  reproducible, and the protocol says so rather than implying otherwise.
- Shape assignment (which target is the journaled one, which is the scratch one) is our
  judgement, made before the runs. That part of the semantic cost is paid by us and is
  therefore **not** measured — recorded as a limit, not hidden behind the word "selected".
- With four shapes and one target each, "repeated" is defined in advance as a friction seen in
  at least three of the four. A single-shape friction cannot be called repeated afterwards.
- Transcripts are published, which the onboarding clock deliberately does not do, so this study
  carries normalisation and secret-scanning rules the clock does not need.
