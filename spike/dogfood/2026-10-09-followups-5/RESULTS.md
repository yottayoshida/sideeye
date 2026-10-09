# Results — 2026-10-09 follow-ups 5

The fifth "おわり？". The fourth recount had checked that the five upstream fix PRs measured in follow-ups 2
still had the heads measured; this one read every filing's tracker against the funnel's row for it, all
forty. Three rows had gone stale, and two kinds of measurable item were found: one fix never measured, and
eleven reports awaiting a reply that had been measured on a release older than the project's latest. Released
**v1.10.0** in one box (`apparatus/Dockerfile`, built three times). Predictions committed first (`e14c25a`,
`654a409`).

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

## The awaiting reports on their projects' latest releases

Each report's own steps, run as written on the latest release apart from paths (`apparatus/latest/<name>.sh`,
`transcripts/latest/<name>.txt`); trash-cli's report is a Sideeye crash point, so it was explored with the
invariant it was measured with, beside the release it measured. WP-CLI is left out: the 2.12.0 it measured is
still its latest release. **All eleven still reproduce**, as predicted.

| report | measured on | latest, measured here | result on the latest |
|---|---|---|---|
| Exiv2/exiv2#9482 | 0.28.5 (Debian) | 0.28.9 | `pic1.jpg` at 0 bytes, unreadable |
| andreafrancia/trash-cli#414 | 0.24.5.26 | 0.26.9.29 | **FAIL** 1/7, crash point 5 of 6: `doomed.txt.trashinfo` at 0 bytes, `trash-list` cannot parse it; 0.24.5.26 the same in the same box. Replayed twice. Without the checker both answer `nothing_could_fail`: every path `trash-put` writes is new |
| aspiers/stow#139 | 2.3.1 | 2.4.1 | `grace.txt` gone after the kill at the first `mkdirat` |
| aws/aws-cli#10648 | 2.23.6 (Debian) | 2.37.11 | `credentials` 166 → 0 bytes under `ulimit -f 0` |
| beancount/beancount#1051 | 3.1.0 (Debian) | 3.2.3 | the ledger at 0 bytes, under `ulimit -f 0` and killed at its first write |
| dotenvx/dotenvx#1012 | 2.32.4 | 2.34.1 | `.env` at 0 bytes beside a written `.env.keys` |
| hashicorp/terraform#39299 | 1.16.4 | 1.16.5 | `main.tf` at 0 bytes under `ulimit -f 0` |
| lfos/calcurse#529 | 4.7.1 | 4.8.2 (from source) | `apts` at 0 bytes |
| ocrmypdf/OCRmyPDF#1762 | 16.7.0 (Debian) | 17.13.0 | `myfile.pdf` at 0 bytes, with the PDF posted to the issue |
| softhsm/SoftHSMv2#908 | 2.6.1 | 2.7.0 (from source) | `token.object` at 0 bytes, the token no longer initialized |
| topydo/topydo#341 | 0.14 | 0.16 | `todo.txt` emptied by `revert` |

Five of these were older than the project's latest even on the day they were filed: dotenvx (2.34.1 was out
that morning), stow, calcurse, SoftHSM and topydo. None of the reports is wrong for it, but each could have been
measured on the release a maintainer would first try.

## The other rows the recount moved

| filing | the row said | the tracker says | now |
|---|---|---|---|
| qpdf/qpdf#1773 | awaiting | closed 2026-09-07 by its maintainer: a crash in that spot "vanishingly unlikely" | `declined` |
| python-poetry/poetry#11019 | awaiting | closed 2026-08-22 by this project: the manifest write is tomlkit's, "not planning to take this further" | `withdrawn`, and `withdrawn` in `spike/upstream-reports.tsv` |
| ocrmypdf/OCRmyPDF#1762 | awaiting | a contributor offers a fix and asked for the report's PDF, which the report had offered | the PDF posted as base64 with its sha256, decoded and checked on Linux (`reply-ocrmypdf.md`); still `awaiting` |

Every other filing's tracker agreed with its row: no new commit, PR, comment or close since 2026-10-08 beyond
SubtitleEdit's, which follow-ups 3 had re-measured.

## What the round says

- **A report measured on an older release than the project's latest is a weaker report**, even when it still
  holds: five of the eleven were filed that way. Measuring the latest release before filing is cheap.
- **`nothing_could_fail` answers trash-cli without a checker**, where the checker the report used finds the FAIL
  — the refusal is right, and its next step is the one to read.
- **A ledger row's stop goes stale when the tracker moves and nothing re-reads it**: qpdf for a month, poetry
  for seven weeks. The status script reads state and comments, not which way a close went.
- **An owner ruling lives in prose on the class table, not in the funnel's columns**: a recount that reads the
  funnel alone sees `fixed` with no `revalidated` and calls it measurable.
