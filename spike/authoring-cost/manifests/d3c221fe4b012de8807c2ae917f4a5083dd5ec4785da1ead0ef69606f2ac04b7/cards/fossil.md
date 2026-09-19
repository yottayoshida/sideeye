# Contract card — `fossil` (shape: disposable state mixed into the same tree as the durable state)

Sealed before the run for this target. Backings: `documented` / `measured` / `unspecified`;
`unspecified` is excluded from grading. Package version in the box: **1:2.21-1+deb12u1**.

## What the tool does

`fossil init REPO.fossil` creates a repository (one SQLite file). `fossil open REPO.fossil` in a
directory makes that directory a checkout, and `fossil commit` records the files in it into the
repository.

## Claims

| # | claim | backing | evidence |
|---|---|---|---|
| 1 | The durable state is the repository file; the checkout directory holds the working files plus `.fslckout` | `measured` | in the box: after `fossil open /tmp/r.fossil`, `ls -a` in the checkout shows `.fslckout`; after `fossil add` + `fossil commit`, it shows `.fslckout` and `f.txt` |
| 2 | `.fslckout` is **rebuildable but not optional**: without it the directory is not a checkout, and `fossil open --force` rebuilds it with the committed content intact | `measured` | in the box, with `.fslckout` moved aside: `fossil status` answers `current directory is not within an open check-out`. `fossil open --force /tmp/r.fossil` then restores `.fslckout`, and `cat f.txt` still prints `x`. **An earlier version of this card said "the checkout works without it", which this measurement contradicts** — it had been inferred from the fact that `f.txt` survives the removal |
| 3 | The repository has a checker of its own, and its answer — not a byte comparison — is what says the repository survived | `measured` | `fossil test-integrity /tmp/r.fossil` prints "3 non-phantom blobs (out of 3 total) checked: 0 errors" and "low-level database integrity-check: ok" |
| 4 | A commit is a transaction in the repository's SQLite database, so the file's bytes change with every commit while older commits stay readable | `documented` | the repository is a single SQLite database (`fossil` documents its one-file repository), and SQLite's own contract is transactional, not byte-stable |
| 5 | Whether the working files in the checkout are part of the promise — whether a crash mid-commit may leave `f.txt` in the tree while the repository has no record of it | `unspecified` | a checkout is by design a place where uncommitted files live, so the tool's documentation does not make the tree's contents a guarantee either way |
| 6 | Whether `.fslckout`'s own contents must agree with the repository after a crash (it is a SQLite database too) | `unspecified` | claim 2 shows it is rebuildable, which says nothing about whether a stale one is a defect |

## What a checker should assert

That the repository still opens and its own integrity check passes — claim 3 — and, where the
run committed, that the committed content reads back. `.fslckout` belongs in `scratch`
(claim 2).

A define that treats `.fslckout` as the durable record contradicts claim 2 — the durable record
is the repository — and is `wrong question`. A define that declares it `scratch` is respecting
claim 2 as measured: the file is derived from the repository and is rebuilt by `fossil open`,
and losing it costs a command rather than data. A
define that asserts byte equality of the repository file contradicts claim 4. A checker that
only tests that the repository file exists is vacuous. A define that turns on whether an
uncommitted working file may survive turns on claim 5 and is `unresolved by card`.
