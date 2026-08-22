# buku 4.7 — scouting notes

Checkout: `targets/buku`. Single-file program: `buku` (6077 lines, Python).
Targeted reading (function-by-function, not full linear read given length):
`BukuCrypt.encrypt_file`/`decrypt_file` (read in full), `BukuDb.initdb`,
`add_rec`, `mergedb`, `compactdb`, `delete_rec`, `delete_resultset`,
`importdb`, `get_default_dbdir`, plus the CLI argument table and dispatch
tail (`addarg(...)` calls and the `if args.X:` block at end of file). Also
checked `README.md` and `buku.1` for documented promises.

## 1. Persistent state

- **Primary state**: a single SQLite database file, `bookmarks.db`, default
  location `$XDG_DATA_HOME/buku/bookmarks.db` (falls back to
  `$HOME/.local/share/buku/`, `get_default_dbdir`, `buku:412-439`),
  overridable per-invocation for most subcommands via `--db <path>`
  (`buku:5518`, `addarg('--db', nargs=1, ...)`). One table, `bookmarks`,
  schema `id INTEGER PRIMARY KEY, URL TEXT NOT NULL UNIQUE, metadata TEXT,
  tags TEXT, desc TEXT, flags INTEGER` (`initdb`, `buku:501-507`).
- **Encrypted-at-rest variant**: `bookmarks.db.enc` (same directory, `.enc`
  suffix appended to the db path) — mutually exclusive with the plaintext
  `.db` file; the tool's own invariant (enforced by three separate guard
  blocks, `buku:190-201`, `:300-308`, `:476-489`) is that *exactly one* of
  `bookmarks.db` / `bookmarks.db.enc` may exist at a time. This invariant
  is itself checker material — see §3.
- `sqlite3.connect(dbfile, check_same_thread=False)` (`buku:493`) uses the
  Python `sqlite3` module's **default** `isolation_level` (implicit
  deferred-transaction mode: a `BEGIN` is issued automatically before the
  first `INSERT`/`UPDATE`/`DELETE`, and nothing is durable until an explicit
  `.commit()`). **No `PRAGMA journal_mode`/`synchronous` override anywhere
  in the file** (`grep -n PRAGMA buku` → no hits) — buku relies entirely on
  SQLite's own default rollback-journal behavior for the `.db` file's
  internal consistency; it never second-guesses or reconfigures it.

## 2. Commands that write state, especially multi-file

Two structurally different write patterns coexist in this codebase:

- **Unprotected, temp-free file rewrites** — `BukuCrypt.encrypt_file`/
  `decrypt_file` (`buku:161-362`, read in full). These operate *outside*
  SQLite entirely, as raw file I/O: `decrypt_file` opens the destination
  `dbfile` directly with `open(dbfile, 'wb')` (`:335`) and streams decrypted
  bytes straight into it — there is no temp file, no rename-into-place.
  Both functions are two-file operations (`bookmarks.db` and
  `bookmarks.db.enc` coexist transiently) that finish by deleting one of the
  two (`os.remove(dbfile)` at `:253` for encrypt; `os.remove(encfile)` at
  `:351` for decrypt) — see P1.
- **SQLite-transaction-batched multi-row operations** — several APIs
  deliberately defer `.commit()` across many statements so that N rows
  change as one SQLite transaction:
  - **`mergedb(path)`** (`buku:2676-2713`): reads every row from another
    buku `.db` file (opened read-only via a `file:...?mode=ro` URI, `:2692`)
    and calls `self.add_rec(..., delay_commit=True, fetch=False)` for each
    one (`:2703`) — `add_rec`'s commit is conditional on `delay_commit`
    (`buku:656-657`), so **no row is individually committed** — followed by
    exactly one `self.conn.commit()` after the loop (`:2705`). Reachable
    non-interactively via `buku --db <path> -i <other>.db` (`.db`-suffixed
    import files are routed to `mergedb`, `importdb`, `buku:2573-2575`). See
    P2.
  - **`delete_rec(..., is_range=True)` + `compactdb`** (`buku:1479-1643`,
    `:1445-1477`): a single `DELETE ... WHERE id BETWEEN low AND high`
    (`:1592-1593`), followed by a loop calling `compactdb(index,
    delay_commit=True)` once per deleted id (`:1601-1602`) — each
    `compactdb` call itself does `SELECT` the current max-id row, `DELETE`
    it, then re-`INSERT` it at the freed-up lower id (`:1463-1473`, moving
    the last record down to fill the gap, so IDs stay contiguous). All of
    this — the bulk delete plus every compaction's delete+reinsert — stays
    inside one uncommitted transaction, closed by one `self.conn.commit()`
    (`:1604-1605`). Reachable non-interactively via `buku --db <path> -d
    <low>-<high>` (range syntax parsed at `buku:5955-5959`). See P3.

## 3. Documented promises (checker material)

- **`README.md:387` / `buku.1:610`** (identical text): *"The last index is
  moved to the deleted index to keep the DB compact."* — an explicit,
  user-facing description of `compactdb`'s behavior (P3), i.e. the tool
  documents its own ID-renumbering as a feature, not an implementation
  detail, making post-crash ID contiguity a legitimate property to check
  rather than an internal detail nobody relies on.
- **`buku.1:61`**: *"Delete doesn't work with range and indices provided
  together as arguments. It's an intentional decision to avoid extra
  sorting, in-range checks **and to keep the auto-DB compaction
  functionality intact**."* — the manual explicitly flags compaction as a
  correctness-sensitive feature the CLI's own argument-parsing is
  deliberately constrained to protect; a crash that leaves compaction
  half-done is exactly the failure class this sentence is implicitly
  worried about.
- **Mutual-exclusion invariant on the DB pair** (`buku:190-201`, `:300-308`,
  enforced identically in both `encrypt_file` and `decrypt_file`): the code
  itself asserts, and hard-exits if violated, that `bookmarks.db` and
  `bookmarks.db.enc` must never coexist except transiently mid-operation.
  This is an implicit but strongly-enforced (three separate guard sites)
  promise, and directly falls out of P1's crash window.
- **Content-hash round-trip check** (`buku:213-214`, `:239-240` writing the
  hash; `:345-349` verifying it): `encrypt_file` embeds a SHA-256 hash of
  the plaintext DB inside the encrypted file, and `decrypt_file` recomputes
  the hash of what it just wrote and compares — an explicit,
  self-verifying integrity check the tool performs on *itself*, i.e. the
  tool already believes decryption can silently produce wrong bytes and
  builds in detection for it. Whether that detection still works, and what
  it leaves behind, when the *decrypt* is what gets interrupted (rather
  than merely producing wrong output) is exactly P1's question.

## 4. fsck / doctor / verify / undo

**No dedicated `buku --fsck`/`--check`/`--repair`/`--verify` subcommand.**
The closest built-in mechanisms, none of which is a general integrity
checker:
- `-p`/`--print` can dump the full DB for visual inspection, and
  `--sql-database <file>` execution ability (grep hit for reference, not
  read in depth) suggests power users are expected to poke at the SQLite
  file directly with `sqlite3` itself if something looks wrong — i.e. the
  project's implicit position is "it's just SQLite, use SQLite's own
  tooling," similar in spirit to `pass`'s "it's just git."
- The **hash-verification described in §3** is the one built-in
  self-check, but it only fires inside `decrypt_file`'s own success path —
  it is not exposed as a standalone "verify my DB file" command a user can
  run independently, e.g. after a suspicious crash, without also attempting
  a full decrypt.
- The `.db`/`.enc` mutual-exclusion guard (§3) doubles as a crude
  after-the-fact detector: if a crash leaves *both* files present, the
  **very next** `--lock`/`--unlock` invocation refuses outright
  (`LOGERR('Both encrypted and flat DB files exist!'); sys.exit(1)`,
  `buku:200-201`/`:307-308`) rather than attempting any automatic recovery
  — see P1's "what property" for why this makes the crash artifact
  self-blocking rather than self-healing.

## 5. Determinism expectation

**Split determinism profile, cleanly separable by which write pattern
(§2) is exercised.**

- `encrypt_file`/`decrypt_file`: `encrypt_file` draws `salt =
  os.urandom(BukuCrypt.SALT_SIZE)` and `iv = os.urandom(16)` (`buku:220,
  225`) — a fresh, unrecoverable-without-the-file source of nondeterminism
  on every run, exactly like `pass`'s GPG session keys. **`decrypt_file`
  introduces no new randomness of its own** — the salt and IV are *read
  back* from the (already-fixed, pre-recorded) `.enc` file's header
  (`buku:320, 325`), so decrypting a byte-identical, pre-existing `.enc`
  fixture is expected to be fully byte-reproducible across baseline
  recordings. **Recommendation**: build the `.enc` fixture once, outside
  the recorded crash window (e.g. by running `--lock` once during fixture
  setup and keeping that exact output), and only ever record/replay
  `--unlock` against it — this sidesteps the nondeterminism entirely,
  mirroring the "avoid the randomized half of the operation" pattern found
  in the `pass` scouting notes.
- `mergedb` (P2) and `delete_rec`+`compactdb` (P3): no randomness anywhere
  in these code paths — row content comes from a pre-existing fixture `.db`
  file (P2) or is already resident in the target DB (P3), IDs are
  deterministically assigned by SQLite's `INTEGER PRIMARY KEY` autoincrement
  behavior (or explicit reinsertion at a chosen id, for compaction), and no
  timestamps are written by either path. Both should be strong candidates
  for byte-reproducible baseline recording. One caveat: `add_rec`'s
  non-merge callers do a live HTTP fetch for title/description
  (`network_handler(url)`, `buku:626`) when `fetch=True` — irrelevant here
  since `mergedb` explicitly passes `fetch=False` (`buku:2703`), which is
  worth preserving deliberately in the fixture rather than assuming.

## Proposals

### P1 — `buku --unlock` (decrypt) interrupted mid-write

- **argv**: `XDG_DATA_HOME=<state-dir>/data buku --unlock 100`, run against
  a fixture where `<state-dir>/data/buku/bookmarks.db.enc` already exists
  (produced once, outside the crash window, by a prior successful `--lock
  100` against a known-content `bookmarks.db` with several rows) and
  `bookmarks.db` does not exist. Password supplied via the two `getpass()`
  prompts (`buku:203-204` for lock, a single prompt at `:310` for unlock) —
  pipe a fixed password on stdin.
- **why**: `decrypt_file` (`buku:263-362`) writes the decrypted plaintext
  directly to the final path with `open(dbfile, 'wb')` (`:335`) — no
  temp-file staging — then only *after* the full stream completes does it
  hash-verify (`:345`) and remove the source `.enc` file (`:351`). A crash
  mid-stream leaves `bookmarks.db` truncated/garbage **while
  `bookmarks.db.enc` is still fully intact** (it's never touched until the
  very end). This is the tool's least-protected write path in the whole
  codebase — contrast with `mergedb`/`delete_rec`, which at least inherit
  SQLite's own journal.
- **what property**: from §3/§4 — the tool's own mutual-exclusion invariant
  says exactly one of `.db`/`.enc` should exist, and its own guard code is
  what a checker should invoke to answer "is the store still usable?" Two
  checks: (a) no bookmark data is ever *lost* — the original `.enc` file's
  bytes (and thus the original DB content, per the embedded SHA-256 hash)
  must still be fully recoverable after the crash, i.e. `.enc` must not
  have been touched/removed since it wasn't reached yet; (b) — the sharper
  finding — does the crash leave the store in the self-blocking state
  described in §4, where a stray partial `bookmarks.db` plus the intact
  `.enc` file causes the *next* `--unlock` attempt to hard-refuse with
  "Both encrypted and flat DB files exist!" (`buku:307-308`) with no
  automatic recovery path, forcing a human to manually `rm` the corrupt
  partial file before the tool becomes usable again? That gap between "no
  data was lost" and "the tool still works" is the interesting result here.
- **where from**: `buku:263-362` (`decrypt_file`, read in full),
  specifically the write loop at `:335-342` and the two-file guard at
  `:300-308`; `buku:5591-5594` (CLI wiring, `-l`/`-k` → `encrypt_file`/
  `decrypt_file`); `buku:427-439` (`get_default_dbdir`, the `XDG_DATA_HOME`
  override path used to isolate the fixture, since `--db` is not plumbed
  through to `encrypt_file`/`decrypt_file` — both are called with only the
  iteration count at `:5592, 5594`, so environment plumbing is required
  here specifically, unlike P2/P3 which take `--db` directly).

### P2 — `buku -i other.db` (mergedb) interrupted mid-transaction

- **argv**: `buku --db <state-dir>/main.db -i <state-dir>/fixture-import.db`,
  where `main.db` is a pre-existing, valid buku database with 2-3 rows and
  `fixture-import.db` is a second, separately-fixtured buku database with
  5+ rows and no URL overlap with `main.db` (`add_rec`'s `get_rec_id`
  uniqueness check, `buku:618-622`, would otherwise silently skip
  duplicates rather than erroring, which would muddy the crash-window
  arithmetic).
- **why**: per §2, this drives one `add_rec(..., delay_commit=True)` call
  per imported row — each one its own `INSERT` statement, none individually
  committed — inside a single SQLite transaction closed by one `.commit()`
  at the very end (`buku:2700-2705`). This is, in effect, asking the engine
  to interrupt SQLite's own rollback-journal machinery mid-transaction
  across N inserts, which SQLite's documentation claims is safe (the
  journal should roll the partial transaction back on next open) — a
  genuine "does the underlying engine's own advertised guarantee actually
  hold, in this real call pattern" test, distinct from P1 and P3.
- **what property**: **all-or-nothing** row visibility — after a crash at
  any point during the `mergedb` loop, followed by recovery (simply opening
  `main.db` again with `buku --db <path> -p`), the set of rows present must
  be *exactly* the pre-merge set (transaction rolled back, none of
  `fixture-import.db`'s rows visible) or *exactly* the pre-merge set plus
  all of `fixture-import.db`'s rows (transaction fully committed) — never a
  partial subset. This directly exercises SQLite's rollback-journal
  contract through buku's real usage pattern, rather than testing SQLite in
  isolation.
- **where from**: `buku:2676-2713` (`mergedb`, read in full),
  `buku:576-663` (`add_rec`, specifically the `delay_commit` conditional at
  `:656-657`), `buku:2573-2575` (`importdb`'s `.db`-extension dispatch to
  `mergedb`), `buku:493` (the plain `sqlite3.connect` call with no PRAGMA
  overrides, meaning default rollback-journal semantics apply).

### P3 — `buku -d <low>-<high>` (range delete + compaction) interrupted

- **argv**: `buku --db <state-dir>/main.db -d 3-5`, against a fixture
  `main.db` with at least 8 rows (ids 1-8), so that deleting ids 3-5 leaves
  a real, checkable compaction: `compactdb` needs to move ids 8, 7, 6 down
  into the freed slots 3, 4, 5 (per the ascending-order compaction
  comment at `buku:1598-1600`).
- **why**: per §2, this is the structurally richest transaction in the
  codebase — one bulk `DELETE...BETWEEN` statement, then three
  (`high - low + 1` = 3) separate `compactdb` calls, **each of which is
  itself a SELECT + DELETE + INSERT** (`buku:1463-1473`) that both removes
  a row and re-creates it under a different primary key — a total of 1 + 3
  + (3×2) = 10 individual SQL statements, all uncommitted until one final
  `.commit()` (`buku:1604-1605`). Unlike P2 (pure appends), this path
  mutates existing rows' identity (their `id`), which is the kind of
  operation most likely to interact badly with a partially-applied
  transaction if SQLite's isolation guarantee has any gap in this specific
  delete+reinsert-at-explicit-id pattern.
- **what property**: the documented compaction promise from §3
  (`README.md:387`/`buku.1:610`) — after a crash and recovery (reopening
  `main.db`), the id sequence must be **exactly** `1..(N-3)` with no gaps
  and no duplicates, and every surviving row's `(URL, metadata, tags, desc,
  flags)` tuple must be byte-identical to its pre-delete content (only the
  `id` column may have changed, and only for rows that were originally
  above the deleted range) — or, if the transaction rolled back entirely,
  the original 8-row state with ids 1-8 intact. A state with a gap in the
  id sequence (partial compaction) or, worse, a duplicate id (two rows
  claiming the same primary key, which SQLite's `UNIQUE`/`PRIMARY KEY`
  constraint should prevent but the delete-then-reinsert pattern briefly
  exposes if interrupted between the two halves of one `compactdb` call)
  are the specific failures this targets.
- **where from**: `buku:1479-1643` (`delete_rec`, read in full, specifically
  the range branch `:1566-1605`), `buku:1445-1477` (`compactdb`, read in
  full), `buku.1:61` and `README.md:387`/`buku.1:610` (documented
  compaction behavior and its stated rationale), `buku:5955-5959` (CLI
  range-syntax parsing, `low-high` → `delete_rec(0, low, high, True)`).
