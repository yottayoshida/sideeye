# Card — python3-yoyo 9.0.0+dfsg1-3, `python3 -m yoyo apply --batch`

**Operation.** `python3 -m yoyo apply --batch --database sqlite:///app.db migrations` applies two
pending migrations to a SQLite database with one already applied: one adds a column and backfills
it, one adds an index.

**Documented contract** (yoyo's documentation, "Transactions", "Migrations"): each migration runs
in a transaction and is recorded in `_yoyo_migration` when that transaction commits; `apply` run
again applies what is not recorded. SQLite rolls back an unfinished transaction when the database
is next opened.

**Legs, read after the recovery a user would run** (opening the database; `apply` again where the
checker's contract includes it).

- **(a) Recorded means done.** Each migration `_yoyo_migration` records has its change in the
  schema and data: the column exists and is backfilled; the index exists. *Broken alone:* the
  second migration recorded and its column absent.
- **(b) Rows survive.** The rows present before the operation are present with their values.
  *Broken alone:* the schema and the records agree and a pre-existing row is gone.
- **(c) The next run goes through.** `apply --batch` again exits 0 and leaves the final schema.
  *Broken alone:* schema and records agree with the second migration not applied, and its column
  already exists, so applying it again fails.

**Admissible after a crash:** zero, one or both pending migrations applied and recorded, each
whole, with (c) holding.

**Not claimed:** yoyo's locking between concurrent `apply` runs; rollback (`yoyo rollback`).
