# 2026-10-14 mechanisms — the baseline (#861)

What this project had found before this run, classified by **why** each state was wrong, with
**who judged it**. `baseline.tsv` is the record, one row per filed report and one per unfiled
target; this page is its reading. The classes are `CANDIDATES.md`'s (M1–M6 and `unclassifiable`).
`tally.py` holds `baseline.tsv` to the repository: every row of `spike/upstream-reports.tsv` once, and
each filed row's provenance equal to what the rule below gives.

## Provenance, decided by a rule and then read

The rule (the machine column) looks at every `spike/outcome-funnel.tsv` row carrying the report:
`sideeye` when one of their evidence files is an engine report whose verdict is FAIL; `other` when
every one of their notes starts with the ledger's own words for a finding the engine did not make
("Not a Sideeye verdict", "Not an explore"); `unclear` otherwise. An `unclear` row carries what was
found by reading its evidence (the read column). The rule decides the headline counts; the reading
is beside them. This is an audit of the record, not #825's correction of it: `docs/found.md` and the
funnel are left as they are.

| | Rows | M1 | M2 | M3 | M4 | M5 | M6 | unclassifiable |
|---|---|---|---|---|---|---|---|---|
| Filed, `sideeye` | 40 | 33 | 7 | | | | | |
| Filed, `other` | 3 | 1 | | | | | 2 | |
| Filed, `unclear` | 5 | 2 | | 1 | 2 | | | |
| Unfiled targets, `sideeye` | 133 | 118 | 11 | | | 2 | 1 | 1 |

**#825's three rows come out `other` by the rule**: dotenvx/dotenvx#1016 and #1017 (plain scripts) and
mhx/dwarfs#388 (a plain run). The five `unclear` rows, read:

- GothenburgBitFactory/timewarrior#778 — the engine's replay legs (`spike/dogfood-timew-replay.sh`, in
  CI on an engine built from main) judge it; the funnel's evidence is `BUILDLOG.md`. Read: Sideeye.
- topydo/topydo#341 — reached by post-seal analysis of the blind campaign's crash states
  (`spike/blind-hunt/ledger.md`), not by an engine verdict on `revert`. Read: other.
- andreafrancia/trash-cli#414 — an engine FAIL 2/7 recorded only in `docs/target-classes.md`. Read: Sideeye.
- SubtitleEdit/subtitleedit#15829 and dotenvx/dotenvx#1012 — the funnel row points at the PASS
  re-measure after the upstream fix; the filing's FAIL report is committed
  (`2026-10-09-user-data-4/transcripts/explore/seconv/explore.json`,
  `2026-10-09-followups-3/transcripts/explore/dotenvx-check/explore.json`). Read: Sideeye.

## What the classes say

**172 of the 181 rows are M1 or M2** — the two mechanisms #861 names. The other nine:

| Row | Class | Provenance | Why it is not M1 or M2 |
|---|---|---|---|
| timewarrior#778 | M4 (and M3) | unclear → Sideeye | `undo.data` and the data files desync across `finalize_all`'s renames; `timew undo` then deletes the wrong interval |
| topydo#341 | M4 | unclear → other | `revert` after an interrupted write undoes an older command |
| trash-cli#414 | M3 (and M5) | unclear → Sideeye | the `.trashinfo` entry is written before the file moves: an info entry with nothing in `files` |
| f2 (unfiled) | M5 (and M4) | Sideeye | a half-renamed batch, and the undo record written after the renames |
| SwiftLint (unfiled) | M5 | Sideeye | each rule's correction saved atomically; between two saves only the earlier rules applied |
| dotenvx `.env.keys.<n>` (unfiled) | M6 | Sideeye | a temporary left holding a key, outside a name-only ignore — a leftover, not a torn write |
| dotenvx#1016 | M6 | other | not a durability failure: an escape's backslash dropped on decrypt |
| dotenvx#1017 | M6 | other | two processes at once: outside the process-crash model |
| dotter (unfiled) | unclassifiable | Sideeye | the ledger does not state the cause |

Three M1 rows carry a second class that is not M1 or M2: mapshaper#706 (M3: `.shp` truncated while
`.shx`/`.dbf` stay old), sndfile and chdman (M5: an appended chunk and a stale header pointer, the
data intact). A report is counted once, by its first class.

**Read against #861's question.** Before this run the engine had judged rows in M5 with committed
reports (f2 and SwiftLint, both `sideeye` in the machine column), and in M3 and M4 only in prose
(trash-cli and timewarrior, `unclear` in the machine column, Sideeye when read). No row's first class
is M3 with a committed report; mapshaper#706 carries M3 as its second. That is why `SELECTION.md`
fixes the strict count to the machine column and prints the read one beside it.

## How the classes were assigned

A first pass by keywords in the funnel's notes (a truncating open or an empty file → M1, a rename or
an unlink before the replacement → M2), then every row the keywords could not settle, every row
naming more than one shape and every M2 read by hand, with the target's own record opened where the
note was too short (jbang and pyenv in `2026-09-16-outside-git/RESULTS.md`, dotter in
`docs/target-classes.md`). Each row's `basis` says what decided it. easy-rsa is M2, not M3: the
cause is `index.txt` replaced by two renames, whatever the second file holds.
