# 2026-10-14 mechanisms — synthesis (#861)

**This page's three answers are recomputed by `tally.py` from `baseline.tsv`, `screen.tsv`,
`results.tsv` and the committed engine reports, by the decision table fixed with the slate before
any explore (`SELECTION.md`, commit `0a8590f1`), with the repository's ledgers as they stand at the
commit that adds this page.** `python3 tally.py --check` fails if the block below is not its output.
A later filing adds a row to `spike/upstream-reports.tsv` that `baseline.tsv` does not carry, and
`tally.py` then stops rather than count against a baseline it was not fixed with; to recompute, check
out that commit.

<!-- tally:begin -->
```
baseline: 48 filed reports, 133 unfiled targets
baseline by class: M1 154, M2 18, M3 1, M4 2, M5 2, M6 3, unclassifiable 1
classes with a sideeye row (machine): M1, M2, M5, M6, unclassifiable
classes with a sideeye row (read): M1, M2, M3, M4, M5, M6, unclassifiable
tried: 12 (out at the screen for reach: 3; fixed targets: 9)
fixed targets: 5 PASS, 4 FAIL, 0 UNKNOWN, 0 not measured in the time box
FAILs the checker caught: 3; by class: M3 2, M5 1
primary (not M1, M2 or unclassifiable): 3 ['useradd', 'dpkg-divert', 'Alembic']
strict, machine provenance: 2 ['useradd', 'dpkg-divert']
strict, read provenance: 0 []
refusals counted twice or more: ['unsupported_syscall_observed']
decision row 1: binding constraint -; next investment: make semantic invariants easier to write
```
<!-- tally:end -->

## Did Sideeye produce a new causal failure mechanism?

**Yes, three FAILs whose cause is neither truncate-then-write nor a non-atomic replacement**, on
targets chosen for their contracts before any explore:

- **useradd** and **dpkg-divert** (M3): every file is replaced atomically, one after another; killed
  between two replacements, each file is whole and they contradict each other — a user in `passwd`
  alone, a diversion recorded for a file never moved — and running the same command again refuses
  to repair it ("already exists", "Leaving").
- **Alembic** (M5): a SQLite batch migration commits its temporary table alone and the rest later,
  because Python's `sqlite3` sends no `BEGIN` before DDL; killed between, nothing is lost, and the
  migration cannot be run again until the user drops a table by hand.

They are not the old mechanisms with worse consequences: in none of the three is any file torn or
any name missing. **How new depends on the record it is measured against.** No committed engine
report in the baseline has M3 as its first class (the strict count, 2: useradd and dpkg-divert;
mapshaper#706 carries M3 second). M5 was there already with committed reports — f2's half-renamed
batch and SwiftLint's intermediate state — so Alembic is new by neither column. The project's prose
record had an M3 too, trash-cli#414, so by the read column Sideeye had met each class before; what is
new here is that they came from targets chosen for that contract.
172 of the baseline's 181 rows are M1 or M2.

## The binding constraint

The table's first row holds, so none is named. What the run shows about each candidate constraint:
**reach** took 3 of the 12 the fixed table counts as tried — two `unsupported_syscall_observed` at
the gate, and apk-tools, which `screen.tsv` files under reach although Debian simply does not carry
it — and no fixed target came back UNKNOWN, though three of the nine (useradd, update-alternatives,
mbsync) reached a verdict only after following the engine's `--observe syscalls` next step once; **selection** is what changed — the same engine and release that
produced 172 M1/M2 rows produced M3 and M5 once the targets were picked for a multi-file, recovery or
migration contract and the checker read that contract.

## The one next investment supported

**Make semantic invariants easier to write.** In all three counted FAILs the built-in layer found
nothing: the worlds the checker rejected had every file whole. Each define needed a checker that runs
the tool's own recovery and then reads meaning across files, plus one hand-broken state per leg to
show it can fail; three broken states and one checker had to be changed before they tested what
they claimed (`SELECTION.md`). That authoring is where this run's cost and its findings both were.

## What this does not say

- **Nine targets, one campaign, one day.** A rate of M3/M5 per target is not measured; this says
  they are findable, not how common they are.
- **Five PASSes are about the declared invariant and the explored worlds only.** Four of them rest
  on the checker alone: `sqlite3`, `sqlite-utils` and Django, whose databases were scratch, and
  vdirsyncer, which touched none of the paths the built-in layer judged.
- **mbsync's FAIL is not counted**: the built-in layer's, healed by mbsync's next run.
- **Nothing was filed.** Alembic's cause is documented by SQLAlchemy; dpkg-divert's manual documents a
  neighbouring window; useradd's was not found on its tracker. A report would need its own novelty
  and user-impact review (#861).
- **Versions are Debian trixie's**, not each project's latest release.
- **Provenance.** The strict count uses the machine column; reading the five `unclear` rows by hand
  moves trash-cli and timewarrior to Sideeye and the strict count to 0 (`BASELINE.md`).
