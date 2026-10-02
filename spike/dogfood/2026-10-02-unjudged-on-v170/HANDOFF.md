# Handoff — 2026-10-02 unjudged-on-v170 (stopped at the usage limit, 2026-10-02 ~17:10 JST)

**Done.** All 31 rows of `LEDGER.md` measured both ways (`run.sh`, `modes.sh`) in the box
`sideeye-uj170`; transcripts, `SELECTION.md`, `RESULTS.md` (every section but upstream),
`PREDICTION.md` (committed before the runs, 26 of 32 held), `transcripts/prediction-check.txt`,
the no-kill reproduction over the nine FAILs, and 31 rows appended to `spike/outcome-funnel.tsv`
with `docs/outcome-funnel.md` regenerated (`outcome-funnel.py check` and `--check-doc` pass).

**Not done.**
1. The upstream section of `RESULTS.md` ("Novelty and reporting"). Two read-only research
   agents were launched and had not reported: E (git-cliff, js-beautify, ktlint, ormolu) and
   F (mutool/MuPDF — the correct tracker is probably Artifex's Bugzilla, not GitHub). Their
   findings are not on disk; re-run them if needed (prompts are in the session, shape as
   `../2026-10-02-gate-cleared-twelve/transcripts/receipts/after-the-fail.txt`).
2. Whether to file any of the nine FAILs upstream is the owner's call, not yet asked. The
   candidates with the most to say: **mutool** (the file is gone, not emptied; the first verdict
   on a target no engine could judge) and git-cliff (a CHANGELOG, usually in git).
3. Funnel rows for the seven A/B FAILs are `judged fail - -` pending the novelty check; move to
   `novel`/`filed` when it is done. The B rows (oxfmt, pg_format, php-cs-fixer) are not new
   findings — their dispositions sit on the gate-cleared-twelve rows.
4. `docs/target-classes.md` rows (mutool's row 118 needs the verdict; chezmoi/gopass/lefthook,
   metaflac/fontforge "re-measured on a release"; 4 A rows), `spike/dogfood/RUNS.md`,
   `CHANGELOG.md`. Then the fresh-reviewer pass (R1, R2), push, PR, CI, merge.
5. Unmeasured and worth a sentence: `lefthook` on the page's path stops at syscalls because its
   first refusal is `oracle_missed_operation`, not `no_shim_marker`; ADR 0090 on `main` may or
   may not cover it.

Branch `dogfood/2026-10-02-unjudged-on-v170`, worktree `.claude/worktrees/sideeye-unjudged-v170`,
not pushed. Host scratch: `~/.cctmp/sideeye-unjudged-mtqtqo/` (raw outputs, swept after 7 days).
