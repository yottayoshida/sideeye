# 2026-10-14 mechanisms — results (#861)

Nine targets fixed before any explore (`SELECTION.md`, commit `0a8590f1`), each measured with the
released Sideeye v1.12.0 installed by the page's installer (digest matched, `transcripts/build-2.txt`),
in one box per target (`apparatus/Dockerfile`, Debian trixie at the 2026-10-14 snapshot),
`--network none`. The explore is `apparatus/run.sh` (2026-10-12's): the page's command, a FAIL
replayed twice and its evidence written, an `--observe syscalls` next step followed once. Every explore
printed the frozen `SELECTION.md`'s sha256 (`d99c8d39…`) and one over the defines (`9e18aebe…`)
(`transcripts/explore-batch-1.txt`, `transcripts/explore/<target>/selection.sha256`).

**Four FAIL, five PASS, no UNKNOWN.** Three of the FAILs were caught by the checker, and none of the
three is a truncate-then-write or a non-atomic replacement: two leave several files each whole and
out of step with one another (M3), one commits half of a migration (M5). The fourth is mbsync's,
caught by the built-in layer alone and healed by mbsync's next run; it is not counted.

| Target | Mode | Verdict | Where | Class | What the user is left with |
|---|---|---|---|---|---|
| shadow-utils 4.17.4 `useradd --prefix … alice` | syscalls (followed) | **FAIL** 21/71, replayed 2/2 | earliest crash point 46 of 70: after `rename(passwd+)`, before `open(shadow-)` | M3 | alice in `passwd` and nowhere else; the same `useradd` changes nothing ("already exists" in the state rebuilt by hand) |
| dpkg 1.22.22 `dpkg-divert --rename --add` | default | **FAIL** 1/12, replayed 2/2 | crash point 11 of 11: after `rename(diversions-new)`, before `rename(tool)` | M3 | the diversion listed, the file never moved; the same command says "Leaving" and moves nothing |
| Alembic 1.13.2 `upgrade head` (SQLite batch migration) | default | **FAIL** 28/43, replayed 2/2 | earliest crash point 15 of 42: after the first `unlink(app.db-journal)` | M5 | revision 1 and every row whole; `alembic upgrade head` fails with an `OperationalError` ("table _alembic_tmp_notes already exists" in the state rebuilt by hand) |
| isync 1.5.1 `mbsync` | syscalls (followed) | **FAIL** 28/46, built-in layer only, replayed 2/2 | earliest crash point 6: after `.uidvalidity`'s write, before its truncate to length | not counted | nothing: the checker, after mbsync runs again, passed in every world |
| dpkg 1.22.22 `update-alternatives --install` | syscalls (followed) | **PASS** 10/10 | — | — | — |
| sqlite3 3.46.1 one transfer in a transaction | default | **PASS** 26/26 | — | — | — |
| vdirsyncer 0.19.3 `sync` | default | **PASS** 53/53 | — | — | — |
| sqlite-utils 3.38 `transform` | default | **PASS** 47/47 | — | — | — |
| Django 4.2.28 `migrate app 0002` (SQLite) | default | **PASS** 27/27 | — | — | — |

**Four of the PASSes rest on the checker alone.** For `sqlite3`, `sqlite-utils` and Django the
database and its journal are scratch (`SELECTION.md`), and each report says the built-in layer "had
no path to judge"; their PASS is the checker's, after SQLite's own recovery, in every world. vdirsyncer's
says the operation touched none of the 12 paths the built-in layer judged — its items were written
under new names — and its PASS is the checker's too.

Out at the screen, for reach: `dpkg -i` (`unsupported_syscall_observed`, `sync_file_range`) and
logrotate (`unsupported_syscall_observed`, `fsetxattr`); apk-tools is not packaged in Debian trixie.
vim was out as a tool this project had measured (`SELECTION.md`).

## useradd — four files, each replaced whole, one at a time

`useradd` writes `passwd`, then `shadow`, then `group`, then `gshadow`, each through `<file>+` and a
rename, under four lock files. Killed between two of those renames, every file is whole and they
disagree: from crash point 46 alice is in `passwd` alone (worlds 46–52, `pwck` red); from 53 in
`passwd` and `shadow` but not in staff (53–59); from 60 in `group` and not `gshadow`. The evidence
table (`transcripts/explore/useradd/syscalls.evidence.md`) has `passwd` at the new 84 bytes and the
other three at their old sizes, and all four `.lock` files left behind. **The checker printed the
same legs before and after the recovery**, so the recovery did not damage anything (not M4); it
refused. Rebuilt by hand (`transcripts/lab-1.txt`): `pwck -r` offers to add alice to `shadow`, the
same `useradd` exits 9 "user 'alice' already exists", and `userdel` removes alice from `passwd`
again — the user must notice and undo by hand. Searched on shadow-maint/shadow: nothing on an
interrupted `useradd`. **Novel as far as that search reaches.** Not filed: #861 files nothing.

## dpkg-divert — the record first, the move second

`dpkg-divert --rename --add` writes the new `diversions` file and renames it in, then renames the
file aside. Killed between them (crash point 11, the only failing world), the diversion is recorded
and `/usr/bin/tool` is still the original; `--truename` names `tool.distrib`, which does not exist.
The same command again prints "Leaving 'local diversion …'" and moves nothing; `--rename --remove`
then removes the record and leaves the file where it is (`transcripts/lab-1.txt`). dpkg-divert's
manual documents a different window of `--rename` — the original file briefly gone — which is the
reason `--no-rename` exists; this one has the file present and the database wrong. Nothing found on
the web on an interrupted `--rename`. Not filed.

## Alembic — a batch migration committed in two pieces

The batch migration recreates the table: `CREATE TABLE _alembic_tmp_notes`, the copy, `DROP TABLE
notes`, the rename, and the version update. SQLAlchemy's log shows one transaction around all of it
(`transcripts/lab-1.txt`), but the explore's own record shows two commits: the checker's listing of
the state has `app.db-journal` up to world 14 and none at 15, after which a new journal starts
(`transcripts/explore/alembic/explore.txt`; the oracle's capture, kept on the machine, has two journal
deletions). Python's `sqlite3` driver sends no `BEGIN` before the `CREATE TABLE`, so it commits alone,
and the rest commits together. Killed between (crash point 15 onward, 28 of 43 worlds), revision 1,
its schema and all 100 rows are whole — legs a, b and c pass — and leg d, the next `alembic upgrade
head`, fails with an `OperationalError`. **Which error the world's record does not say**: the checker
keeps the run's last line, SQLAlchemy's link. "table _alembic_tmp_notes already exists" is what the
same state rebuilt by hand gives (`transcripts/lab-1.txt`); the user drops that table to go on. The driver behaviour is documented in SQLAlchemy's SQLite
dialect ("Serializable isolation / Savepoints / Transactional DDL", with a workaround in an event
listener); the env.py here is the minimal one and does not apply it. Nothing on
sqlalchemy/alembic's tracker about an interrupted batch. Not put forward as novel: the cause is
documented.

**Django on the same SQLite, migrating the same way, PASSed 27/27**: its schema editor rebuilds the
table inside one transaction it opens itself.

## mbsync — torn on disk, whole after its next run

The built-in layer counted `far/.uidvalidity` written and not yet truncated to its length, holding
neither the old nor the new content (M1 in shape); the checker,
which runs mbsync again first, passed in every world: mbsync rebuilds it. A FAIL with nothing for the
user to lose, kept as such and not counted (`CANDIDATES.md`: only a FAIL the checker caught counts).

## Where the run did not do what `CANDIDATES.md` and `SELECTION.md` said

- **The operations gained flags while their defines were written, before the gate**: `useradd` has
  `-M -d / -s /bin/sh` (no home directory to create; a home and shell `pwck` accepts), and
  `dpkg-divert` takes `--instdir` with `--admindir` where `CANDIDATES.md` wrote `--root`, because
  `--root` moves the admin directory under the root as well (measured in the box). The legs are the
  ones `CANDIDATES.md` wrote.
- **vim's exclusion has no transcript of its own.** It was found while classifying the baseline,
  before the first gate (`transcripts/entry-out/candidates.sha256` starts at 05:03:48Z); nothing but
  this page's word records the order.
- **"Replayed by hand" became "rebuilt by hand".** A replay leaves the completed run behind, so the
  crashed state was read from the explore's own record (each checker's line before the recovery, and
  the evidence table) and rebuilt for `transcripts/lab-1.txt` from the evidence table.
- **The SQLite targets print the files' sizes before the recovery, not the legs**: opening the
  database is the recovery, so there is no reading of the legs before it.
- **Alembic's leg-d broken state** (a leftover `_alembic_tmp_notes`) was written from Alembic's batch
  naming before any preflight of Alembic, and it is the state the FAIL then left.

## What this run measured about Sideeye

- **Every target reached a verdict once past the gate**; the two refused there were both
  `unsupported_syscall_observed`, on two different calls.
- **The checker is where these FAILs were**: in all three counted FAILs the built-in layer had nothing
  to say about the worlds the checker rejected — the files were each whole.
- **`[recovery]` was not used.** The checkers ran each tool's recovery themselves in every world; the
  M3/M4 distinction came from the checker's reading before the recovery and from rebuilding the
  state by hand.
