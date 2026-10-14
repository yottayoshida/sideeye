# 2026-10-14 mechanisms — the ordered candidates (#861)

This page is committed **before any `sideeye preflight` of this run**, and it does not change after
that commit. Every preflight transcript of the run starts with this file's sha256, so a reader can
check that the order, the operations and the invariants below were fixed before the engine had
said anything about any candidate. `SELECTION.md` (committed before the first explore) takes the
targets from this page by the rule below and adds nothing a reader could not derive from it except
the measured gate results and the known-issue searches.

## What the run asks

#861: whether Sideeye v1.12.0, under its existing process-crash model, finds **causal failure
mechanisms other than the two that dominate this project's reports** — content written over the
only copy at the user's name, and a name replaced non-atomically. The targets are chosen for an
**old/new contract the user relies on** (related files, a recovery path, a state transition), not
for any write primitive: nothing about how a candidate writes was looked at to place it here.

## The mechanism classes (the one yardstick for the baseline and for this run)

A FAIL is classified by **why** the state at its crash point is wrong, read at the report's
`checker_earliest` world (for the baseline, at the finding the report describes):

| Class | The cause |
|---|---|
| M1 | content written directly at the user-visible name: truncate then write, an overwrite in several writes, or a create then write at the final name |
| M2 | a name replaced non-atomically: the old name unlinked, renamed aside or a symlink removed before the new one is in place |
| M3 | several files disagree, each of them whole on its own |
| M4 | the tool's recovery, undo or journal replay damages a state that was recoverable |
| M5 | one logical operation left part-done, every individual write correct |
| M6 | another cause, with one line on why it is not M1 or M2 |
| unclassifiable | the record does not say enough to decide |

**What this run counts.** Only a FAIL whose report has a `checker_earliest` (the declared checker
caught it; a FAIL on the built-in layers alone is not counted). Two counts, both reported:
**primary** — classes other than M1, M2 and `unclassifiable`; **strict** — classes in which the
baseline holds no row whose provenance is `sideeye`. M4 against M1/M3 is decided by replaying the
`checker_earliest` world, reading the state **before** the recovery, then running the recovery.
The baseline also counts FAILs found by the built-in layers alone, so the strict comparison leans
against this run; that asymmetry is deliberate and is said again in `SYNTHESIS.md`.

## The rule that turns this page into the targets

- In each category, candidates are taken **in the order below**; the **first three that clear the
  gate** (`apparatus/entry.sh`, gate `0`, including its FOLLOW and SUPERVISED marks) are the
  targets. Once a category has three, its remaining candidates are not prepared.
- A candidate the gate answers `DEFINE` (the define is wrong) may be fixed **once**, the reason
  recorded; a second `DEFINE`, a red (`1`) or a could-not-measure (`2`) puts it out.
- A candidate whose package does not install at the pinned snapshot is out before the gate.
- A category with fewer than three is left short; no other category's candidate fills it.
- The order inside a category is the forecast of reach made on 2026-10-14 before any measurement:
  a single-process C tool first, an interpreter next, a tool with children or threads last.

Versions are Debian trixie's at the snapshot the box pins (`apparatus/Dockerfile`), as a user who
runs `apt install` gets them on that date; `dpkg-query -W` is kept in the build transcript.

Every checker runs **the recovery a user would run** first and then reads the state back for its
meaning, so a world the tool's own recovery heals is a PASS. Each leg below gets one hand-made
broken state that the checker must reject (`SELECTION.md` maps leg to state one to one). Every
path the tool writes — `HOME`, its configuration and its databases — is placed inside the judged
state, because only the state is rebuilt between worlds.

## Category 1 — related files (a primary object and its index, metadata or references)

| # | Candidate (Debian trixie) | Operation | Legs of the invariant | Recovery a user runs | Reading recovers? | Wall forecast |
|---|---|---|---|---|---|---|
| 1.1 | shadow-utils 4.17.4 (`passwd`) | `useradd --prefix <root> -G staff -p <hash> alice` over a root holding users `root` and `carol` | (a) passwd and shadow agree (`pwck -r` on the pair); (b) group and gshadow agree (`grpck -r`); (c) alice is in all four files with staff membership, or in none; (d) root's and carol's entries unchanged | the same `useradd` again (an "already exists" refusal is accepted) | no | lock files keyed by pid |
| 1.2 | dpkg 1.22.22 `update-alternatives` | `--altdir <s>/alt --admindir <s>/admin --install <s>/bin/editor editor <s>/opt/ed2 50` over an auto group holding ed1 at 40 | (a) `--query editor` reads; (b) `<s>/bin/editor` resolves through `<s>/alt/editor` to the alternative the admin file names as current; (c) ed1 still registered | the same `--install` again | no | none expected |
| 1.3 | dpkg 1.22.22 `dpkg-divert` | `--admindir <s>/admin --root <s>/root --rename --divert /usr/bin/tool.distrib --add /usr/bin/tool` | (a) the diversions file lists the diversion exactly when the original was moved; (b) the original bytes exist under exactly one of the two names | the same `dpkg-divert` again | no | none expected |
| 1.4 | fossil 2.26 | `fossil commit -m … --no-warnings` in a checkout with one edited file | (a) `fossil test-integrity` passes on the repository; (b) the checkout's current version exists in the repository; (c) the working file holds the edit; (d) the edit is either committed and checked out, or uncommitted and shown as edited | opening the repository (SQLite rolls back a hot journal) | yes | random check-in salt or time |
| 1.5 | notmuch 0.39 | `notmuch new` after two messages are delivered into the maildir | (a) message count equals the maildir's files; (b) each new message is found by id; (c) older messages keep their tags | `notmuch new` again | no | Xapian's database UUID is random |
| 1.6 | darcs 2.18.4 | `darcs record -a -m …` with one change | (a) `darcs check` passes after `darcs repair` if it needs one; (b) the change is recorded or still pending; (c) earlier patches all present | `darcs repair`, then `darcs check` | no | the Haskell runtime's threads |

## Category 2 — recovery (restart, rollback, undo, journal replay, repair)

| # | Candidate (Debian trixie) | Operation | Legs of the invariant | Recovery a user runs | Reading recovers? | Wall forecast |
|---|---|---|---|---|---|---|
| 2.1 | sqlite3 3.46.1 CLI | one transaction moving an amount between two accounts and appending a journal row (rollback-journal mode) | (a) `PRAGMA integrity_check` is `ok`; (b) the balances sum to the same total; (c) the journal holds the transfer exactly when the balances show it | opening the database (a hot journal is rolled back) | yes | none expected |
| 2.2 | dpkg 1.22.22 `dpkg -i` | upgrading a local package from 1.0 to 2.0 under `--admindir`/`--instdir` in the state | (a) `dpkg --audit` reports nothing; (b) the package is installed at 1.0 or 2.0 and `dpkg --verify` finds its files matching that version | `dpkg --configure -a`, then the same `dpkg -i` if the package is left half-installed | no | `dpkg-deb` as a child |
| 2.3 | vim 9.1.1230 | an ex-mode edit and write of a notes file with a swap file (`vim -es -u NONE -i NONE`) | (a) the file holds the old or the new text whole, or `vim -r` recovers the new text from the swap file; (b) no line of the old text is lost unless the edit removed it | `vim -r` on the file, written back | no | none expected |
| 2.4 | isync 1.5.1 `mbsync` | one sync between two local Maildir stores, each with a new message and one flag changed | (a) both sides hold the same Message-IDs; (b) no Message-ID twice on a side; (c) every message present before is present; (d) the flag change is on both sides | `mbsync` again (it replays its journal) | no | pid and hostname in Maildir names |
| 2.5 | vdirsyncer 0.19.3 | one `sync` of a pair of filesystem storages, each with a new item | (a) both sides hold the same UIDs; (b) no UID twice; (c) every item present before is present | `vdirsyncer sync` again | no | asyncio threads |
| 2.6 | apk-tools | `apk add` of a local package with `apk fix` as recovery | — | — | — | not packaged in Debian trixie (measured 2026-10-14): out before the gate |

## Category 3 — state transitions (migration, rotation, checkpoint, compaction)

| # | Candidate (Debian trixie) | Operation | Legs of the invariant | Recovery a user runs | Reading recovers? | Wall forecast |
|---|---|---|---|---|---|---|
| 3.1 | logrotate 3.22.0 | a forced rotation (`rotate 3`, `create`, `nocompress`) with a state file | (a) every line of `app.log` and its rotations before the run is in exactly one file after; (b) `app.log` exists; (c) the state file reads (the next unforced run exits 0) | the next unforced `logrotate` run | no | the date in the state file |
| 3.2 | sqlite-utils 3.38 | `transform` renaming a column, changing a type and dropping a column | (a) `PRAGMA integrity_check` is `ok`; (b) the table's schema is the old one or the new one; (c) every row survives with its values | opening the database | yes | none expected |
| 3.3 | Alembic 1.13.2 | `alembic upgrade head` from revision 1 to 2, a batch migration that recreates a table on SQLite | (a) `alembic current` names revision 1 or 2; (b) the schema is that revision's; (c) every row survives; (d) `alembic upgrade head` again succeeds | `alembic upgrade head` again | yes | none expected |
| 3.4 | Django 4.2.28 | `manage.py migrate app 0002`, an altered and a renamed field on SQLite | (a) `django_migrations` names 0001 or 0002 applied; (b) the schema is that migration's; (c) every row survives; (d) `migrate` again succeeds | `manage.py migrate` again | yes | none expected |
| 3.5 | sqlite3 3.46.1 CLI | `VACUUM` of a database with deleted rows | (a) `PRAGMA integrity_check` is `ok`; (b) the remaining rows are identical | opening the database | yes | none expected |

## Out before this page

Already measured by this project, so not among the new targets: Mercurial, Borg, Jujutsu,
taskwarrior, todoman, khal, timewarrior, topydo, rdiff-backup, unison, git, newsboat. timewarrior's
recovery misfire stays the reference for an M4 the instrument can see; its replay legs run in CI
on an engine built from main, not on v1.12.0.
