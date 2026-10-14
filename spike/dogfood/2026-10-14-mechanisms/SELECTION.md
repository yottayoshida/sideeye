# 2026-10-14 mechanisms — selection (#861)

This page, `tally.py`, `screen.tsv`, `baseline.tsv` and every define under `apparatus/defines/` are
committed together **before the first explore of this run**. Every explore transcript starts with
this file's sha256 and one over every file under `apparatus/defines/` (`apparatus/explore.sh`), so a
reader can check that the slate, the checkers and the decision table were fixed before any target
was explored. `CANDIDATES.md` (committed before any preflight, sha256 `95906a89…`) holds the order,
the operations and the legs of each invariant; this page adds only what the rule there derives from
measurements.

## The nine targets, by `CANDIDATES.md`'s rule

The gate is `apparatus/entry.sh` (2026-10-12's, the box's name changed), run by `apparatus/gate-run.sh`;
every gate transcript prints `CANDIDATES.md`'s sha256 first (`transcripts/entry-out/candidates.sha256`).
`screen.tsv` is the full record, one row per candidate.

| Category | Target | Version (Debian trixie, snapshot 2026-10-14) | Gate |
|---|---|---|---|
| related files | `useradd --prefix` | shadow-utils (`passwd`) 1:4.17.4-2 | 0, FOLLOW `--observe syscalls` |
| related files | `update-alternatives --install` | dpkg 1.22.22 | 0, FOLLOW `--observe syscalls` |
| related files | `dpkg-divert --rename --add` | dpkg 1.22.22 | 0, 11 operations |
| recovery | `sqlite3` one transfer in a transaction | sqlite3 3.46.1-7+deb13u2 | 0, 25 operations |
| recovery | `mbsync` between two Maildir stores | isync 1.5.1-1 | 0, FOLLOW `--observe syscalls` |
| recovery | `vdirsyncer sync` of two filesystem storages | vdirsyncer 0.19.3-3 | 0, 52 operations |
| state transitions | `sqlite-utils transform` | sqlite-utils 3.38-1 | 0, 46 operations |
| state transitions | `alembic upgrade head`, a batch migration | python3-alembic 1.13.2-4 (SQLAlchemy 2.0.40) | 0, 42 operations |
| state transitions | `manage.py migrate app 0002` | python3-django 3:4.2.28-0+deb13u2 | 0, 26 operations |

**Out, in each category's order.** `dpkg -i` (2.2): `unsupported_syscall_observed`, `sync_file_range`
(`transcripts/entry-out/entry/dpkg-upgrade.preflight.txt`). vim (2.3): measured by this project on
2026-10-09 (follow-ups 3, FAIL), so out under `CANDIDATES.md`'s own rule for measured tools — **that
page's list of measured tools left it out; the omission was found before any preflight, by matching
every candidate against `spike/outcome-funnel.tsv`, and no other candidate matched**. apk-tools (2.6):
not packaged. logrotate (3.1): `unsupported_syscall_observed`, `fsetxattr`
(`transcripts/entry-out/entry/logrotate.preflight.txt`). fossil, notmuch, darcs and `VACUUM` were not
prepared: their categories had three.

## What each define declares

Each define's directory holds `sideeye.toml`, `seed.sh` (rebuilds the state and the files the
operation reads from outside it), `check.sh`, `legs.sh` and, where needed, `env.sh`.

- **Everything the operation writes is inside the state.** Configuration, logs and sync status are
  given paths under it (`--log`, `--admindir`, `status_path`, `SyncState`, `HOME`); Python's bytecode
  is kept from being written beside the projects outside it (`PYTHONDONTWRITEBYTECODE=1`, declared).
- **`scratch`** names the files a tool leaves torn by design and repairs itself: the SQLite
  database and its rollback journal for `sqlite3`, `sqlite-utils`, Alembic and Django, and
  vdirsyncer's `status`. Their correctness is the checker's.
- **Clocks** are pinned where a tool writes the time (`preload:libfaketime`): shadow's last-change
  day, the alternatives log, mbsync's Maildir names (left running, `@`, because mbsync sleeps until a
  second has passed).
- **Recovery is in the checker, not in `[recovery]`** (#861's plan, D5): `[recovery]` runs on the two
  saved exhibits only, and a recovery that damages another world would go unseen. Every checker runs
  the recovery `CANDIDATES.md` names for that candidate, wrapped in `timeout`, and prints the legs
  before it and after it; it judges after.

## Checker controls (`transcripts/controls.txt`, `apparatus/controls.sh`)

For every target, the checker — the toml's `check` string itself — accepted the seeded state and the
completed state, and rejected one hand-broken state per leg of `CANDIDATES.md`, each made by
`legs.sh` from the completed state. Each broken state breaks its own leg alone, with two exceptions
the tools impose: Alembic's leg (a), an `alembic_version` naming two revisions, also fails leg (d),
because Alembic cannot upgrade from a version table it cannot read — no state breaks (a) alone.
vdirsyncer's leg (a), two sides holding different items, is healed by any sync that runs, so its
broken state also stops the recovery (the status directory replaced by a file).

Three broken states were changed on the way, each recorded so a reader does not take the first form
for the measured one: update-alternatives' leg (b) first pointed `alt/editor` elsewhere, which the
recovery's `--install` puts back; `sqlite3`'s leg (a) first edited `sqlite_schema` through the CLI,
whose defensive mode refused it; `dpkg -i`'s leg (a) first removed the list file, which failed
`--verify` too. Django's checker first chose the expected table by the number of migrations
recorded, so an unknown migration failed leg (b) as well as (a); it counts the known ones.

## How a FAIL is classified, and what is counted

As `CANDIDATES.md` says, at the report's `checker_earliest` world, with the mechanism classes there.
Two choices that page left open are fixed here:

- **Provenance for the strict count is `baseline.tsv`'s machine column** (`sideeye` only where a
  committed engine report says FAIL). The strict count by the read column is printed beside it: by
  the read column every class already holds a Sideeye find (trash-cli for M3, timewarrior for M4),
  so that count is zero by construction, which is itself part of the answer.
- **A FAIL is replayed twice** (`apparatus/run.sh`) and its `checker_earliest` world replayed once more
  by hand to read the state before the recovery; that reading, and the recovery run by hand on it, is
  what decides M4 against M1 or M3, written in `results.tsv`'s basis.

## The decision table (implemented in `tally.py`; the first row that holds is taken)

"Tried" is the candidates out at the screen for reach (`screen.tsv`, `out-reach`) plus the fixed
targets; a refusal "counted twice" is one `unknown_reason` value among those outs and the fixed
targets' UNKNOWNs.

| # | Condition | Binding constraint | Next investment | Why |
|---|---|---|---|---|
| 1 | primary ≥ 1 | — | make semantic invariants easier to write | given a semantic checker, Sideeye found one; the cost is writing the checker |
| 2 | outs for reach plus fixed UNKNOWNs are half of tried or more, and a refusal is counted twice | reach | the reach fix for that refusal | one fix opens two or more |
| 3 | the same, no refusal counted twice | reach (dispersed) | no further expansion | no single fix moves it |
| 4 | a judged target FAILed, every FAIL in M1 or M2 | target and invariant selection | measure third-party use | targets chosen for other contracts still broke the old way; the value is in the old class, so measure use rather than widen |
| 5 | otherwise (every judged target PASSed) | no counterexample in judgeable worlds | no further expansion | nothing else to find where the engine can judge |

With nothing explored, `tally.py` already reads row 2: the two outs share
`unsupported_syscall_observed` (with different calls, `sync_file_range` and `fsetxattr`). That is
recorded here so a later reader sees it was known when the table was fixed.

## Known issues searched (2026-10-14, before any explore)

- shadow-maint/shadow, pimutils/vdirsyncer, simonw/sqlite-utils, sqlalchemy/alembic: GitHub's issue
  search for an interrupted, crashed or killed run of the operation, and for "atomic" — nothing on
  the operation measured here (sqlite-utils #795 is about foreign keys inside a transaction).
- dpkg (update-alternatives, dpkg-divert): the web; nothing on an interrupted run. **dpkg-divert's own
  manual says `--rename` makes the original file disappear briefly** (the reason `--no-rename` exists
  for Essential files), so a FAIL there with the file missing between the two steps is documented,
  not novel.
- isync: the web; nothing on mbsync after a kill.
- Django: Trac via the web; #29182 (closed, fixed) left a rebuild's `__old` table behind, the nearest.
- SQLite: its atomic-commit design is the documented contract the checker reads; not searched.
