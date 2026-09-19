# The grading rubric — sealed before the first run

A grader receives: one sealed contract card, this rubric, and a target's define revisions **in
shuffled order** with their revision numbers removed. It returns one verdict per revision and
one friction class per revision that changed something. It never sees the other grader's answer,
the run's transcript, or which revision came last.

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
`unresolved by card` first, "if the card cannot answer, nothing else can be said". Three
graders read the planted trap — which contradicts a `documented` claim AND rests on an
`unspecified` one — and two called it `wrong question` while the third called it `unresolved by
card`, each following the text. Under the old order a define could escape a contradiction by
also touching an unspecified line, which is the opposite of what the verdict is for. Round 1's
agreement had hidden the ambiguity: two graders choosing the same reading is not the same as
one reading being available.)*

## The four friction classes

For every revision that differs from the one before it in the sequence as given, say which class
the change belongs to. This is the classification #618 asks for, and it is what the study's
conclusion is drawn from.

- **`mechanical`** — a state path, a command spelling, a working directory, an environment
  variable, an apparatus detail. Nothing about what the target guarantees.
- **`observational`** — which observation mode or oracle the run needs: a refusal naming the
  shim, a wrapper, a child process, `--observe syscalls`.
- **`semantic`** — what is durable, what is scratch, whether recovery is part of the contract,
  what the checker should assert. **The class this study exists to size.**
- **`checker quality`** — the intended assertion was already right; the change made the checker
  able to fail for that reason.

A revision may carry more than one class. A revision that changes nothing a class names is
`none` — say so rather than forcing a class.

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
and the define did or did not reflect. That sentence is the study's raw material; the verdicts
are how it is counted.
