# The grading rubric — sealed before the first run

A grader receives: one sealed contract card, this rubric, a target's define revisions **in
shuffled order** under given ids, **and what the subject wrote beside each revision** —
every file it put in the define's own directory. In the recorded runs that is the `check` and
`setup` the define names and what those call, and also the data they build the case from. Three
things are not in it: a script the define names **outside** that directory, anything in a
subdirectory, and **Sideeye's own report** — the last deliberately, because this page tells you
to judge the define against the card and not against what the tool would report, and two of the
recorded runs wrote a report straight into the define's directory. A capture too large to hand
over is named with its size rather than dropped. It returns one verdict per revision and
the friction classes that revision turns on. It never sees the other grader's answer, the run's
transcript, or which revision came last.

**The order is hidden by the shuffle and by the instruction not to read filenames, not by
renaming the files.** A grader is handed repository paths — `revisions/NN.toml`, and
`revisions/scripts/MM.<name>` beneath them — so the numbers are visible and are not the order
they were written in. `grader-prompt.md` says so to the grader in as many words.

*(Amended 2026-09-21, #639, after the first four runs were graded. Two changes. **The scripts**:
until now the material was the `*.toml` snapshots alone, so `vacuous checker` — defined below
entirely in terms of the checker's behaviour — could not be reached from what a grader held, and
every grader in that round said so unprompted. **The four published runs were graded without the
scripts**; their sheets carry each grader's own note saying which class was undecidable, and
`RESULTS.md` records what that leaves standing. This changes what a grader is handed from here
on; it does not change a verdict already given. **The order clause**: this page said revisions
were handed over "with their revision numbers removed", which was never true of any round —
`RESULTS.md` has said the opposite since it was written, and the numbers are in the paths. The
sentence is corrected to what the apparatus does rather than the apparatus to the sentence,
because four graded rounds relied on the behaviour and none on the wording.)*

## The four verdicts

Judge the define **against the card**, not against what the tool would report.

- **`semantically valid`** — the define's judged state, its checker and its declared scratch
  together ask the question the card describes. Every `documented` and `measured` claim in the
  card is either respected or irrelevant to this define. A define may be valid while being
  narrower than the card: asking about one of two durable files is a smaller question, not a
  wrong one. It may **not** be valid while contradicting a graded claim.
- **`wrong question`** — the define contradicts a graded claim: it judges state the card calls
  scratch, ignores state the card calls durable, asserts byte equality where the card says the
  contract is recovery, or asserts recovery where the card says the bytes are the contract.
- **`vacuous checker`** — the assertion is right but the checker cannot fail for the reason it
  names: it exits 0 regardless of the state, reads a path the define does not judge, tests only
  that a file exists where the card's contract is about its contents, or would accept the
  corrupted state the card's `measured` procedure produced.
- **`unresolved by card`** — the define turns on something the card marks `unspecified`. This
  is **not** a defect of the define. It is a defect of the card, recorded so the study can say
  how often its own answer key ran out. A grader who reaches for this verdict must name the
  card line it needed and did not find.

Order of application: `wrong question` first, then `vacuous checker`, then `unresolved by card`,
then `semantically valid`.

**`unresolved by card` is for a define no graded claim decides** — one that turns *only* on
lines the card marks `unspecified`. A define that contradicts a `documented` or `measured`
claim is `wrong question` even if it also rests on an unspecified line, because the card did
answer the question that decides it.

*(Amended 2026-09-19, before the first run, by the rehearsal: the first ordering put
`unresolved by card` first, "if the card cannot answer, nothing else can be said". Four graders
read the planted trap — which contradicts a `documented` claim AND rests on an `unspecified`
one — and split two against two, `wrong question` against `unresolved by card`, each side
following the text (`rehearsal/grades/`). Under the old order a define could escape a contradiction by
also touching an unspecified line, which is the opposite of what the verdict is for. Round 1's
agreement had hidden the ambiguity: two graders choosing the same reading is not the same as
one reading being available.)*

## The four friction classes

For each revision, say which classes **the properties it turns on** belong to — what the define
asserts, what it declares scratch, which mode it needs, how its checker can fail. Not what
changed from a neighbour: the revisions are shuffled, so "the one before it" is a position in
this sheet rather than a step the subject took, and a grader who classes differences is reading
an order that may not exist.

*(Amended 2026-09-19, before the first run, by the rehearsal: the first version said "for every
revision that differs from the one before it in the sequence as given", three lines above a rule
forbidding the grader to infer the order. Of the six graders' sheets, five put `none` on one of
their two rows and one classed both, which is the same split read through a two-revision sheet;
neither reading was wrong under the text. The study's figures count classes per revision, so the instruction now asks for
a property of the revision.)*

This is the classification #618 asks for, and it is what the study's conclusion is drawn from.

- **`mechanical`** — a state path, a command spelling, a working directory, an environment
  variable, an apparatus detail. Nothing about what the target guarantees.
- **`observational`** — which observation mode or oracle the run needs: a refusal naming the
  shim, a wrapper, a child process, `--observe syscalls`.
- **`semantic`** — what is durable, what is scratch, whether recovery is part of the contract,
  what the checker should assert. **The class this study exists to size.**
- **`checker quality`** — the assertion the define names is the card's, and what is at stake is
  whether the checker can actually fail for it: a test of existence where the contract is
  contents, an exit code that is 0 whatever the state.

A revision may carry more than one class. A revision that turns on nothing any class names is
`none` — say so rather than forcing one.

## What a grader must not do

- Do not run Sideeye, the target, or any command. Grade from the card and the text.
- Do not reward a define for matching this repository's existing defines; the card is the only
  reference.
- Do not infer the revision order. It is shuffled deliberately: a grader who "sees improvement"
  is reading a sequence that may not exist.
- Do not soften a verdict because the define is close. `wrong question` with a one-line note is
  more useful than a hedged `semantically valid`.

## Output form

One row per revision, then one line of prose:

```
<given-id>  <verdict>  <friction classes or none>  <the card line it turns on, or ->
```

The prose line says, in one sentence, what the target's author had to know that the card states
and the define did or did not reflect. It is about that define, not about a neighbour. That sentence is the study's raw material; the verdicts
are how it is counted.
