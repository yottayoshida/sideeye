# Results — 2026-10-09 follow-ups 5

The fifth "おわり？". The fourth recount had checked that the five upstream fix PRs measured in follow-ups 2
still had the heads measured; this one read every filing's tracker against the funnel's row for it, all
forty. Three rows had gone stale, and one measurable item was found. Released **v1.10.0** in one box
(`apparatus/Dockerfile`: Sideeye and the two tombi releases). Predictions committed first (`e14c25a`).

## tombi-toml/tombi#2265: the fix, measured

The maintainer's PR #2266 (merged 2026-10-02 as `55b8549e53`, the whole of v1.7.1's difference from v1.7.0)
stops cutting the file to zero before the write: it seeks to 0, writes the formatted text over the old one,
flushes, and then calls `set_len` with the new length. 2026-10-02's seed grows when formatted (36 → 37 bytes);
a padded seed shrinks (108 → 37 bytes, `transcripts/lab-1.txt`). The page's path, the next step being
`--observe supervised` (tombi is static):

| tombi | the report's seed (grows) | a seed that shrinks |
|---|---|---|
| 1.7.0, the release the report measured | **FAIL** 1/4, crash point 3 of 3 — 0 bytes. Replayed twice | **FAIL** 1/4 — 0 bytes. Replayed twice |
| 1.7.3, carrying the fix | **PASS** 4/4, and 5 of 5 repeated explores (`transcripts/repeat.txt`) | **FAIL** 1/4, crash point 3 of 3, and 5 of 5 repeated — the formatted 37 bytes at the head and 71 bytes of the old file after them. Replayed twice |

So the fix holds for what was reported, and leaves a narrower window: a kill between the write and `set_len`,
reachable only when formatting shortens the file. The text is not lost — the formatted file is whole at the
head — but the file no longer parses, and tombi refuses it on the next run (`expected key`); deleting the tail
restores it. Reproduced without Sideeye with strace's injection on `ftruncate` (`transcripts/lab-2.txt`).

**Not measured by the owner's ruling of 2026-10-02**, which said neither to reply nor to measure the fix, and
which `docs/target-classes.md` records on tombi's row. This recount read the funnel's `fixed` and missed it;
the owner was told after the runs and chose to keep the record (2026-10-09). No reply was posted: the maintainer
closed the report as "extremely rare", and its PR calls itself "a partial mitigation", which is what this
measured.

## The other rows the recount moved

| filing | the row said | the tracker says | now |
|---|---|---|---|
| qpdf/qpdf#1773 | awaiting | closed 2026-09-07 by its maintainer: a crash in that spot "vanishingly unlikely" | `declined` |
| python-poetry/poetry#11019 | awaiting | closed 2026-08-22 by this project: the manifest write is tomlkit's, "not planning to take this further" | `withdrawn`, and `withdrawn` in `spike/upstream-reports.tsv` |
| ocrmypdf/OCRmyPDF#1762 | awaiting | a contributor offers a fix and asked for the report's PDF, which the report had offered | the PDF posted as base64 with its sha256, decoded and checked on Linux (`reply-ocrmypdf.md`); still `awaiting` |

Every other filing's tracker agreed with its row: no new commit, PR, comment or close since 2026-10-08 beyond
SubtitleEdit's, which follow-ups 3 had re-measured.

## What the round says

- **A ledger row's stop goes stale when the tracker moves and nothing re-reads it**: qpdf for a month, poetry
  for seven weeks. The status script reads state and comments, not which way a close went.
- **An owner ruling lives in prose on the class table, not in the funnel's columns**: a recount that reads the
  funnel alone sees `fixed` with no `revalidated` and calls it measurable.
