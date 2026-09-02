# 0039 — Quoted figures are held by review, not by a check

Status: Accepted (2026-09-02)

Closes #357. Sibling of ADR 0034 and ADR 0035, which decline a mechanism on its cost rather
than on a proof that it cannot work; this one declines on measured value and on the
repository's own pattern for holding a page to its source.

## Context

Two of the three pages acceptance check 11 sweeps quote figures from other records —
`docs/kill-criteria-review.md` and `docs/target-classes.md`; the third,
`docs/checker-cookbook.md`, is rendered from the checkers and quotes none. What holds them
today is check 11 in `spike/acceptance.sh` ("the docs pages' repo paths exist"): every
backticked token containing a slash must resolve to a repository path, and nothing more.
Its own comment says the rest — claim-vs-transcript verification "stays a review-time
axis" — and the review page says the same about itself: the numbers are quotations, and
"the quotations themselves are held by review". Check 11 also carries a sunset of its own
("never fired by the v1.0 freeze -> removal list"), so the rule cannot live in that
comment. It lives here; check 11 is cited as where a reader meets it.

#357 asked whether a check should verify that a quoted figure is the *right* figure, not
merely one that exists somewhere in a source. It was filed from #240 (PR #355), where a local
script — never committed, as that PR's Verified says — extracted every fraction and
percentage from the appended prose and matched each against a declared source. A mutant that
swapped one sourced figure for another (`2/36` for `3/7`, both on `docs/unknown-rate.md`)
passed the first version of that script. The fix applied there was narrow: the two
rate/fraction pairs were required to travel together. That fix is not in the tree either.
**No committed check has ever read a figure on these pages**: the only code that names
`docs/kill-criteria-review.md` is check 11's page list, and the figure strings themselves
(`1/28`, `3.6%`, `2/36`, `5.6%`, `42.9`) appear in no `.py`, `.sh` or `.yml` file. The mutant
did not "pass check 11"; check 11 reads no figures at all.

Two things were measured while deciding, and both weigh against building it:

- **What review caught in #240 was five claims wider than their sources, and none of them
  was a quoted figure.** One was numeric in form — "six of the seven" for a reproduction
  gap that did not exist — and it was a count the writer made, not a figure quoted from a
  page. The miscount underneath it (a line-oriented `grep -n` found four reproduction
  phrases where a normalised count finds five) was caught before any reviewer saw it, by
  the writer's own recount — the recompute pattern below, not a figure check. The writer
  was the source. A check that re-extracts a figure from a named anchor cannot reach a
  figure whose source is the sentence it sits in. #318 is the same class one record over:
  "three became two in two documents" — a count carried by memory, caught in one place by
  review and in the other by a sweep, corrected by hand where review found it and left as
  written where the sweep did, and answered in CI by the script's own self-test rather than
  by any check on the quotation.
- **Most quotations on the review page are held by nothing at either end.** The page draws
  figures from at least six records: `spike/assisted/RESULTS.md` and
  `spike/assisted/REMEASURE.md`, `spike/followup-144/artifacts/checker.log`,
  `spike/unknown-rate/outcome-map.tsv`, `spike/cohort2/RESULTS.md` with
  `spike/cohort2/borg-r3/RUNLOG.md`, `spike/cohort3/RESULTS.md`,
  `spike/cohort4/himalaya-r2/RESULTS.md` and `docs/unknown-rate.md`. Only the last is
  recomputed by a check (check 12, `spike/unknown-rate/count.py`). `outcome-map.tsv` is
  checked for shape — column count, enum membership, duplicate keys — and never for a
  number; the RESULTS and RUNLOG records are named by no check at all beyond check 11's
  existence test. A figure check comparing a quotation against an unheld source would be
  comparing two hand-written things and calling one of them the truth.

## Decision

**Do not build a figure check. Quoted figures stay held by review. Close #357.**

This is a ruling on value and cost, not a finding that such a check cannot work.

What an anchored-declaration check — a figure carrying the page and anchor it came from,
re-extracted and compared — would catch is bounded: a transcription error, and a source that
later overwrites a published figure. What it would not catch is the class the mutant
imitated: a figure read from the wrong row. That class is caught only when the anchor is
chosen before the figure is read, and a format cannot enforce the order in which a writer
works. The measured record is one mutant against a first-version script, and five real
errors of which the figure-shaped one had no source but the writer.

The cost is a format change to the two pages that quote, on top of a trap the pages already
carry: check 11 reads a backticked ratio as a path and goes red, so any figure-marking
convention has to live outside backticks.

And the repository has a pattern for the case where a page must agree with its source:
**generate the block, or recompute it.** Check 12 recomputes `docs/unknown-rate.md`'s
results from the committed artifacts; `spike/render-cookbook.py check` (check 11b) renders
`docs/checker-cookbook.md`'s recipes from the checkers; `spike/freeze-audit/render-audit.sh`
renders the audit page's rows from its manifest; `spike/check-veto-rate.py` and
`spike/check-report-schema.py` hold their pages the same way. No check in the tree verifies
a quotation inside prose. The review page is scoring judgement with figures inside
sentences; it cannot be generated, and a check that read its prose would be the first of its
kind here.

Vocabulary, so the two ADRs that touch this agree: ADR 0035 says its own copy of a table is
"held by nothing". "Held by review" here means the same thing — no check holds it — with the
reviewer named as what does.

## Alternatives considered

**An anchored declaration and a check that re-extracts** — the issue's proposal. Declined,
above.

**Commit the narrow pair rule** (`1/28` with `3.6%`, `2/36` with `5.6%`, each pair travelling
together). Declined. It kills one mutant, the issue itself calls it narrower than the
problem, and it would let a reader believe figures are checked when two pairs are.

**A numeric parser over prose.** Declined; the issue considered it and called it worse than
the problem.

**A BUILDLOG paragraph and two sentences on the page, no ADR.** The repository has declined
a check that way before (BUILDLOG 2026-08-30 (sixteenth), "No new acceptance check is
added, deliberately"). Declined here because the rule spans more than one page, a reopen
condition needs a place a reader can find, and ADR 0034 and 0035 set the form of a decline
— Context, Decision, Alternatives, Consequences, `Closes #N` — to which this one adds the
list of what would reopen it, which neither of them carries.

**A comment on the issue, then close.** Declined; the reasoning would sink into a closed
issue.

## Consequences

- **The pages keep quoting figures, and review keeps holding them.**
  `docs/kill-criteria-review.md`'s "What holds this page" paragraph and check 11's comment
  now cite this ADR. The review page cites it by path, so check 11 holds the citation
  against renumbering; the comment cites it by number and is held by nothing.
- **This ADR reopens on evidence, and the evidence has a place to land.** Any of:
  1. A review round catches a wrong *quoted* figure that an anchored check would have caught
     first. It is recorded in the pull request's same-class scan table, or in BUILDLOG, and
     the entry names this ADR.
  2. A source page overwrites a published figure and the page quoting it is not touched in
     the same pull request. The one measured instance so far — #239, `5ad0513`, when the
     A-group's g1 figure aged — was handled inside the same PR by a dated note on row 8 of
     the review page; that discipline is what this ADR relies on. `docs/unknown-rate.md`
     appends generations rather than overwriting, so a recomputation there ages a quotation
     without falsifying it.
  3. The pages stop quoting figures from other pages. Then there is nothing for review to
     hold, and this ADR retires.
- **The freeze audit's row for #357** (`spike/freeze-audit/audit.tsv`, class C, `defer`)
  still gives the count of review-caught errors as three. This ADR supersedes that count
  with five. The row itself moves when a sweep re-reads the surfaces, which is that ledger's
  rule and not this change's.
- **No check, no CI job, no contract movement.** `docs/contract-freeze.md` is untouched.
