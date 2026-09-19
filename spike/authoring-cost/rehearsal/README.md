# The rehearsal — the apparatus, exercised against a planted trap, before anything real runs

ADR 0012's first operating rule is that the pipeline is rehearsed on synthetic targets with
planted defects before a real one is touched, because blindness is the non-renewable resource.
This study's equivalent is smaller, because only one piece of it can be wrong in a way the
selftests cannot see: **the grading**. `audit.py --selftest` covers the evidence reader and
`check-sealed.sh` covers the seal; neither can say whether the rubric and a card, together,
separate a define that asks the right question from one that does not.

So: a synthetic target, a card carrying a deliberate `unspecified` line, and two defines — one
that contradicts a graded claim and one that does not. Both are handed to two graders under the
sealed rubric, shuffled, with no hint of which is which.

**What must come out**, and this is the falsifiable part of check 2:

| define | required verdict |
|---|---|
| `define-trap.toml` | `wrong question` |
| `define-fixed.toml` | `semantically valid` |

A rubric that accepts everything fails the first row; one that rejects everything fails the
second. The `unspecified` line is in the card on purpose: a rubric that only works when the
answer key is complete would pass a rehearsal built on a complete card and then meet a real card
that is not.

This is one sample of a probabilistic grader, not a proof. It is recorded as such in
`RESULT.md`, and both graders' raw answers are committed beside it.

**The rehearsal never touches a selected target.** `synthetic-target.sh` is written for this
directory and is not a package; nothing here installs, runs or reads any of the four.
