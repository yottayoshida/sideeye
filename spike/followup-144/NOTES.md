# Follow-up #144: triage the bogofilter-sqlite counterexample

The #84 sweep's B-group produced a fresh FAIL on bogofilter-sqlite (3 of 26
worlds, oracle agreed on 25 operations, L0: `wordlist.db` "holding neither
the old nor the new content" between two writes —
`spike/unknown-rate/artifacts/b-bogofilter-sqlite/`). The shape is exactly
the buku lesson in `docs/target-classes.md`: a sqlite-backed store judged
by file bytes is judged more strictly than its journal contract. The sweep
ran no checker, so recovery was unmeasured and the disposition stayed
new-this-sweep.

**This directory is the labeled follow-up, outside the #84 corpus.** Its
run is not a corpus trial, joins no table on `docs/unknown-rate.md`, and
writes nothing into any path the corpus manifest hashes (R2 of the batch
plan measured that adding a file under
`spike/unknown-rate/defines-b/bogofilter-sqlite/` breaks check 12's define
digest — so nothing lands there; the committed define files are *read*
verbatim, never modified).

## The question, and the two pre-declared outcomes

One question: **does bogofilter's own reader survive every crash world** —
i.e. does sqlite's journal recover the wordlist the way buku's did?
The apparatus is the git precedent (BUILDLOG 2026-08-11, the
COMMIT_EDITMSG entry): re-run the same define with the target's own reader
as the L2 checker. L0 still applies and will still flag the torn bytes.
The report's `earliest.invariant` field only records the earliest
violating world, so the checker also appends **one line per invocation to
a log outside the judged state** (`check.sh`; a log inside the state would
join the L0 comparison) — that log, committed with the artifacts, is the
every-world instrument, and `run.sh` pins its shape (the falsification
gate's red first, then one pass per explored world):

1. **Recovery holds** — the log shows the checker passing in every
   explored world (the violating ones included) and no world's invariant
   names the checker. Then the reader recovered everywhere, the finding is
   the buku-shaped class lesson (L0 is stricter than a journaled store's
   contract), and the disposition becomes withdrawal-shaped: recorded,
   no upstream claim.
2. **Recovery fails** — the log shows a world's checker failing (or an
   invariant names the checker). Then bogofilter itself can be left unable
   to read its own wordlist, this is a real crash-consistency finding on a
   fresh target, and the novelty / reporting gates
   (`spike/assisted/PROTOCOL.md`) apply before anything leaves this
   repository — deliberately not part of this batch.

## The checker

`check.sh` asks the store's own tools, nothing else: `bogoutil` must dump
the wordlist (it opens the db through bogofilter's sqlite backend), and
`bogofilter-sqlite` must classify a fresh message using it (exit 0/1/2 —
spam/ham/unsure — are all "the reader works"; anything else is not). The
engine's falsification gate corrupts the store before the run and requires
this checker to go red — a reader that cannot fail is not a checker.

## Provenance

Assisted-class throughout (the define was authored from man pages for the
#84 sweep; this follow-up adds only the reader-checker). The define's
setup and operation are the committed corpus files, read in place:
`spike/unknown-rate/defines-b/bogofilter-sqlite/setup.sh` and the op.txt
template, expanded against this run's own state root by `run.sh`.
