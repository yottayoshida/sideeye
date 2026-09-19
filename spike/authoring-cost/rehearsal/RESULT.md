# The rehearsal's result — three rounds, and what each one found

What this had to show: the sealed rubric and a card, together, separate a define that asks the
card's question from one that does not, **including when the card carries an `unspecified`
line**. A rubric that accepts everything fails one leg; one that rejects everything fails the
other.

It found two apparatus defects before any real run, which is what a rehearsal is for.

## Round 1 (2026-09-19) — the graders agreed, and one of them found the leak

Two fresh graders, each given the card, the rubric as first sealed, and the two defines under
IDs carrying no order — with the two graders' ID→file mappings **deliberately opposite**:

| grader | ID → file | verdict |
|---|---|---|
| A | `X` → `define-fixed.toml` | `semantically valid` |
| A | `Y` → `define-trap.toml` | `wrong question` |
| B | `P` → `define-trap.toml` | `wrong question` |
| B | `Q` → `define-fixed.toml` | `semantically valid` |

The required pair, twice, with the mapping reversed. **And grader B reported a defect in the
rehearsal**: both define files opened with a comment naming their own verdict (`# The planted
trap`, `# … asking the card's question`). Shuffling IDs does not blind a grader when the file
text says which is which. B said it graded from the `state` / `scratch` / `check` lines only;
that cannot be verified, so round 1 is published as **contaminated** rather than as evidence.

## Round 2 — the leak removed, and the rubric split 2–2

The comments were replaced with one neutral line in both files (the rehearsal files are not in
the sealed set, so no answer key moved), and two *different* graders were asked, again with
opposite mappings and the **same rubric text as round 1**:

| grader | ID → file | verdict on the trap | verdict on the fixed define |
|---|---|---|---|
| C | `M` → trap, `N` → fixed | **`unresolved by card`** | `semantically valid` |
| D | `T` → trap, `S` → fixed | **`unresolved by card`** | `semantically valid` |

Both named claim 4 — the `unspecified` line the trap's checker rests on — as the card line they
needed and did not find. Both also said, in prose, that the trap contradicts claim 3.

So four graders read one sentence two ways, 2–2: *"Order of application: `unresolved by card`
first (if the card cannot answer, nothing else can be said), then `wrong question` …"*. A and B
read "the card can answer, via claim 3, so the first clause does not apply". C and D read the
order literally. Both readings are in the text.

**Round 1's agreement had hidden this.** Two graders choosing the same reading is not the same
as one reading being available, and the study's whole semantic point rests on that distinction
— a define that contradicts a documented claim could have escaped into `unresolved by card` by
also touching an unspecified line, which is the opposite of what that verdict is for.

## The amendment, and round 3

The rubric's ordering was amended (dated, with a new ledger row and its pre-image, 2026-09-19,
before any run): `wrong question` first, and `unresolved by card` reserved for a define **no
graded claim decides**. Then two more graders, the fifth and sixth of the rehearsal, under the amended text:

| grader | ID → file | verdict on the trap | verdict on the fixed define |
|---|---|---|---|
| E | `G` → trap, `H` → fixed | `wrong question` | `semantically valid` |
| F | `K` → trap, `J` → fixed | `wrong question` | `semantically valid` |

E cited the amendment in its reasoning — the trap contradicts claim 3 *and* rests on claim 4,
and the ordering now decides that pair — which is the seam closing. It also named a weakness in
the corrected define that no round had raised: its blank-line test reads a truncated final line
(no trailing newline) as a line of length one and lets it through, and it drops the card's
line-count bound. The verdict stands (`semantically valid`: narrower than the card is not
wrong, and the checker still fails on a missing or empty file), but the note is the kind of
thing the study exists to collect.

Both graders of round 3 reached the required pair, with opposite mappings, and both cited the
amended ordering as what decided the trap. **That is the check this rehearsal exists for**: a
rubric that accepted everything would have failed the first column, one that rejected everything
would have failed the second, and the card carried an `unspecified` line throughout, so the
result is not the artefact of a complete answer key.

F added a second observation of its own: the trap's `notes.txt` assertion is `test -f`, which
tests existence where the card's contract is contents — a `vacuous checker` trait that the
ordering rule absorbs into `wrong question`. It classed that face of the change as `checker
quality` beside `semantic`, where E classed the pair as `semantic` alone. The study's figures
count classes per revision, so that disagreement is data, not noise, and both sheets are kept.

Every grader's answers are committed under `grades/`, including round 1's contaminated pair.

## What this is and is not

Each round is one sample per grader of a probabilistic process, and the protocol says so. What
three rounds showed is not that graders agree — they did not — but that the rubric had a seam
where two readings were available, and where that seam was. The study's design already assumes
disagreement: a run where the two graders disagree publishes as `contested`, with no semantic
point.

**The rehearsal touched no selected target.** `synthetic-target.sh` is written for this
directory; nothing here installs, runs or reads `dos2unix`, `genisoimage`, `lmdb-utils` or
`fossil`.
