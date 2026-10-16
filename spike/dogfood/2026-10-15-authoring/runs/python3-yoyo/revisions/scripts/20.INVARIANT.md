# Invariant: `yoyo apply` of two pending migrations over SQLite

Operation, run in the state directory (`/home/user/yoyo-state`):

    python3 -m yoyo apply --batch --database sqlite:///app.db migrations

yoyo 9.0.0+dfsg1-3 (Debian), Python 3.13 `sqlite3`, SQLite's default rollback journal.
`migrations/` holds `0001-create-notes` (applied), `0002-add-body-len` (`ALTER TABLE notes
ADD COLUMN body_len INTEGER; UPDATE notes SET body_len = length(body)`) and
`0003-index-body-len` (`CREATE INDEX idx_notes_body_len ON notes (body_len)`), 0003 depending
on 0002 and 0002 on 0001.

The contract shape: a migration is a multi-step change of logical state. The logical state is
what yoyo records as applied, together with what the database holds. They have to agree, and
the user's next step has to work.

## The four legs (each judged after recovery)

- **a, record.** `yoyo list` (yoyo's own reader of its record) exits 0, names each of the three
  migrations once, and the applied set is `{0001}`, `{0001, 0002}` or `{0001, 0002, 0003}` —
  a prefix in dependency order.
- **b, schema agrees with record.** The user tables (everything in `sqlite_master` that is a
  table, minus `sqlite_*` and yoyo's four tables) are exactly `{notes}`; notes' columns
  (name, declared type, NOT NULL, primary key) and indexes (name, unique, columns) are one of the
  three shapes — 0001's `(id, body)` with no index, 0002's `(id, body, body_len)` with no
  index, 0003's with `idx_notes_body_len` — and, when leg a's record is one of the three
  prefixes, it is the shape for that prefix. (When the record is not a prefix, b only asks
  for one of the three shapes, so b does not go red merely because a did.)
- **c, data.** notes holds exactly ids 1..100 with `body = 'note N'`; where `body_len`
  exists, every row has `body_len = length(body)` (the backfill is all there or the column
  is not).
- **d, the next run goes through.** On a copy of the recovered state, the same `yoyo apply`
  exits 0 and `yoyo list` then shows all three applied.

## Valid before

The start setup.sh builds: record `{0001}`, 0001's shape, 100 rows, no lock row. All four
legs hold (`accept-start.sh` in `controls.txt`).

## Valid after

The completed run: record `{0001, 0002, 0003}`, 0003's shape, every `body_len` backfilled, the
lock row deleted (`accept-completed.sh`).

## Acceptable after a crash (after recovery)

yoyo commits each migration on its own, so a crash may stop between migrations. After
recovery, any of the three prefix states is acceptable — `{0001}`, `{0001, 0002}` or all three
— as long as record, schema and data agree for it and the next apply completes the rest.
Not acceptable: a record and a schema that disagree (a migration's DDL committed without
its record, or the reverse), a half-done backfill, lost or changed rows, an extra table, or
a state the next `yoyo apply` cannot get past.

**Recovery** (`recover.sh`): `yoyo break-lock`. A killed apply leaves its row in `yoyo_lock`,
and the next `yoyo apply` or `yoyo list` waits 10 s and stops with "run yoyo break-lock to
remove this lock" — the tool names that step itself. The open break-lock makes is also
SQLite's documented recovery: a hot journal is rolled back by the first opener (cookbook
recipe 4). `accept-recovered.sh` kills a real apply after 0002 is marked and shows the list
failing on the lock before recovery and all legs holding after it.

## What the checker does not claim

- Nothing about the bytes of `app.db` or `app.db-journal`: they are `scratch` in the define,
  because yoyo writes times, uuid1 ids and the host name into them on every run, and SQLite
  leaves the journal torn by design. The built-in byte layer judges only `migrations/`.
- Nothing about yoyo's own bookkeeping beyond what `yoyo list` reads: not `_yoyo_log`,
  `_yoyo_version`, the `applied_at` times, or record rows for migrations not in
  `migrations/` (list does not show them).
- Nothing about triggers, views or indexes on tables other than notes; leg b reads tables,
  notes' columns and notes' indexes only (control-nextrun.sh relies on that gap).
- No `PRAGMA integrity_check` leg: I could not build a corrupt-but-readable database that
  breaks only that leg, so it is not a leg. A corruption that leaves the rows readable and
  the next apply working would pass.
- Not that the recovery is needed or harmless in general: only that after it the legs hold.
- Not power loss, torn writes or lost fsyncs (sideeye kills the process; the page cache
  survives), not concurrent appliers, not other SQLite journal modes (WAL), not other yoyo
  versions or other backends.
- Leg d runs on a copy; it says the next apply would work, not that the user has run it.

## Result (explore.txt, replay.txt)

FAIL, 80 of 157 worlds (strace oracle agreed on 156 operations). In worlds 44-83 the DDL and
backfill of 0002 are committed but the record says only 0001; in worlds 97-136 0003 is
committed and the record says 0001+0002. Only legs b and d are red there: the next apply
stops on "duplicate column name: body_len" or "index idx_notes_body_len already exists".
yoyo runs a migration's steps on a connection of their own and commits them, then writes
_yoyo_log and _yoyo_migration in a later transaction (backends/base.py, apply_one). The replay
of case 000001 (crash point 44) reproduced it.
