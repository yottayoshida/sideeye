# buku 4.7 — scouting report

Checkout: `targets/buku/`. The whole CLI is one 6077-line Python file, `buku`.
All line numbers below are in `targets/buku/buku` unless another path is given.

## 1. Where the persistent state lives

**A single SQLite file, `bookmarks.db`.** There is no state *directory* in the usual sense —
the directory only ever holds this one file (plus SQLite's own transient `-journal`, plus
`bookmarks.db.enc` when the encryption feature is used).

- Default location: `$XDG_DATA_HOME/buku/` else `~/.local/share/buku/`, filename `bookmarks.db`
  — `get_default_dbdir()` at `buku:413-440`, filename joined at `buku:463-464`.
- **Overridable by an explicit flag: `--db <path>`** (`buku:5518`, threaded to `BukuDb` at
  `buku:5622`). It is hidden from `--help` and the man page warns it is "app-only"
  (`buku.1:98`), but it is a plain path argument and is exactly what the engine wants —
  no environment plumbing needed.
- Read **and** written. Schema is created on connect if absent (`buku:500-508`).
- **Not state**: nothing. buku keeps no cache dir, no lockfile, no index, no config file.
  This is unusually clean — the entire durable surface is one file.

Schema (`buku:501-507`):
`bookmarks(id INTEGER PRIMARY KEY, URL TEXT NOT NULL UNIQUE, metadata TEXT, tags TEXT, desc TEXT, flags INTEGER)`.
Note there is **no timestamp column** — which is what makes buku's DB writes deterministic
(see §5).

## 2. Which commands write that state

| Command | Rows touched | Transactions | Network? |
|---|---|---|---|
| `--delete N` | DELETE 1 + (DELETE 1 + INSERT 1) | one | no |
| `--delete L-H` | DELETE (H−L+1) + up to (H−L+1)×(DELETE+INSERT) | **one** | no |
| `--delete N M ...` | as above, per index | **one per index** | no |
| `--import f.md` | INSERT per line | one, *unless duplicates* | no |
| `--replace old new` | UPDATE per matching row | one | no |
| `--delete --tag t` (index 0) | UPDATE across all rows | one | no |
| `--add URL` | INSERT 1 | one | **yes** — always |
| `--update ...` | UPDATE | one | yes, if no `--title` |

The interesting one is **delete**, because of auto-compaction. `delete_rec` (`buku:1479`)
removes the row, then calls `compactdb` (`buku:1445`), which **moves the highest-id record
down into the freed slot**: `SELECT` the max-id row, `DELETE` it, `INSERT` it back at the
vacated index (`buku:1463-1473`). So a delete of *one* bookmark rewrites *two* rows, and one
of them is a bookmark the user never named. That is the richest crash window in the tool: a
torn delete does not lose the bookmark you asked to remove, it loses **a different one**.

Two distinct atomicity granularities, both worth separating:

- **Range delete** `--delete 2-4` takes the branch at `buku:1566-1605`: one `DELETE ... BETWEEN`,
  then a loop `for index in range(low, high+1): self.compactdb(index, delay_commit=True)`
  (`buku:1601-1602`) with **delayed commit forced**, and a single `conn.commit()` at
  `buku:1605`. Many row moves, one transaction.
- **Multi-index delete** `--delete 2 4` takes the CLI branch at `buku:5963-5974`, which calls
  `bdb.delete_rec(int(idx))` in a loop **with `delay_commit` left at its default `False`** —
  so each index is its **own committed transaction** (`buku:1631-1632`). There is no
  enclosing transaction. A crash between them is a *durable* partial result.
- **Import with a duplicate URL**: `importdb` yields tuples ending `(..., True, False)` —
  positionally `delay_commit=True, fetch=False` (`buku:3212`, matching the `add_rec` signature
  at `buku:576-583`), so the inserts batch up for the single `conn.commit()` at `buku:2669`.
  **But** when a URL already exists, `add_rec` returns −1 and the loop calls
  `self.append_tag_at_index(rec_id, item[2])` (`buku:2665-2667`) — and
  `append_tag_at_index` defaults to `delay_commit=False` (`buku:665`), so it **commits at
  `buku:709`**, flushing every insert accumulated so far. A single duplicate line silently
  converts an atomic import into a partially-committed one.

## 3. What the documentation promises

- **`buku.1:60`** — "When a record is deleted, the last record is moved to the index."
  This is the compaction contract, stated as an unconditional fact about the DB.
- **`buku.1:610`** — "The last index is moved to the deleted index to keep the DB compact."
- **`buku.1:61`** — "…to keep the auto-DB compaction functionality intact. On the same lines,
  indices are deleted in descending order." An explicit ordering promise for multi-index delete.
- **`buku.1:45`** — "Tags are filtered (for unique tags) and sorted. Tags are stored in lower
  case…" An *always-valid* claim about the `tags` column: a good standing invariant to assert
  in every crash world, independent of which operation was interrupted.
- **`buku.1:20`** — "Portable, merge-able database" — implies the file is expected to remain a
  valid, mergeable buku DB.
- **`buku.1:85`** — encryption "is optional and manual… the database file should be unlocked
  (-k) before using buku and locked (-l) afterwards." See §5 for why this one bricks.

**Conservation is not spelled out in one sentence**, but it is the direct consequence of
`buku.1:60`: if the last record is *moved*, it is not *lost*. That is the property to check.

## 4. fsck / doctor / verify / repair

**None exists.** There is no `--check`, no `--verify`, no `--repair`, no undo. I grepped the
argument table (`buku:5468-5520`) and the man page; the closest things are:

- `--print --json` (`buku:5518` area; `--json` flag), which dumps every record as JSON and is
  a perfectly good **checker readout** — one process, no network, no mutation.
- SQLite's own `PRAGMA integrity_check`, available to a checker externally.

So the checker has to be written, and the absence of a repair command *raises* the stakes:
whatever a crash leaves behind is what the user is stuck with.

## 5. Determinism expectation

**Expectation: the `bookmarks.db` file itself is byte-deterministic for the operations I
propose; there is one real refusal risk that lives below buku, in SQLite's journal.**

Basis, in the checkout:

- I grepped the whole file for nondeterministic sources (`time.`, `datetime`, `strftime`,
  `urandom`, `random`, `uuid`). The only hits that reach persistent state are:
  - `buku:220` `salt = os.urandom(BukuCrypt.SALT_SIZE)` and `buku:225` `iv = os.urandom(16)` —
    **encryption only**;
  - `buku:3065`, `buku:3085`, `buku:3097` `timestamp = str(int(time.time()))` written as
    `ADD_DATE=` / `LAST_MODIFIED=` — **HTML and XBEL export only**;
  - `buku:4084-4094` `gen_auto_tag()` uses `time.localtime()` — reached only when
    `importdb` is run **without** `--tacit` (`buku:2580-2581`).
- The schema has no timestamp column (`buku:501-507`), so no clock value ever lands in the DB.
- `--delete`, `--import file.md`, and `--replace` make no network call. `--add` and title-less
  `--update` **do** (`buku:626`, `buku:896`, `buku:1039` → `network_handler` at `buku:3887`) —
  avoid both.

**Refusal calls, stated up front:**

1. **`--lock` / `--unlock` will refuse.** `os.urandom` at `buku:220` and `buku:225` goes
   straight into the `.enc` file bytes. Also these paths call `getpass()` twice
   (`buku:203-204`), so they cannot be driven by argv alone. Do not queue them.
2. **HTML/XBEL export will refuse.** `time.time()` at `buku:3065`/`3085`/`3097` is embedded in
   the output. `--export out.md` and `--export out.org` should be clean — `convert_bookmark_set`
   for `markdown`/`org` is reached at `buku:2244-2252` and neither touches the timestamp
   block — but export writes a *new* file and does not modify the DB, so it is a weak target.
3. **`--import` without `--tacit` will refuse**, via `gen_auto_tag()`. Always pass `--tacit`.
4. **The one I cannot verify from this checkout:** SQLite's rollback journal header contains a
   randomly-seeded checksum initializer. If the engine's baseline covers only the settled state
   directory (where `bookmarks.db-journal` has been unlinked at commit) this never surfaces; if
   it captures transient files mid-operation, expect a refusal that is *SQLite's*, not buku's.
   SQLite is a stdlib C extension and is not in this checkout, so I am flagging this as an
   expectation (confidence ~75%) rather than a cited fact. buku never sets `journal_mode`
   (no PRAGMA anywhere in the file), so it is in default rollback-journal/delete mode, not WAL.

---

# Proposals

## P1 — range delete, one transaction, many row moves

- **argv:** `buku --nostdin --db $STATE/bookmarks.db --tacit --delete 2-4`
  (`--nostdin` **must** be `sys.argv[1]` — it is checked positionally at `buku:5323`.
  `--tacit` sets `chatty=False` via `not args.tacit` at `buku:5621`, which suppresses the
  `input('Delete these bookmarks? (y/n): ')` prompt at `buku:1588`.)
  Pre-state: a DB with ~8 bookmarks, ids 1..8, distinct URLs.
- **why:** This one operation deletes 3 rows and then performs up to 3 *moves* of unrelated
  high-id records into the vacated slots (`buku:1601-1602` → `buku:1463-1473`), all inside a
  single transaction that commits only at `buku:1605`. Each move is a `DELETE` of a record the
  user never named followed by an `INSERT` of it elsewhere. If the transaction tears anywhere
  between those two statements — or if SQLite's journal replay is incomplete after the crash —
  the user loses bookmark #8 while having asked to delete #2–#4. The bookmark that disappears
  is not the bookmark that was deleted, and there is no repair command (§4) to notice.
- **what property:** *Conservation of bookmarks.* In every crash world, after any recovery the
  tool performs on next open, the multiset of `URL` values in the DB must equal **either** the
  original 8 URLs **or** the original 8 minus exactly the 3 URLs that had ids 2, 3, 4 in the
  pre-state. Nothing in between; and in particular **no URL that was never targeted may be
  missing**. Secondary assertion, valid in every world regardless: ids are contiguous
  `1..COUNT(*)` (the point of compaction, `buku.1:60`) and every `tags` value is
  comma-wrapped, lowercase, deduplicated and sorted (`buku.1:45`).
- **where from:** `buku.1:60` ("When a record is deleted, the last record is moved to the
  index") and `buku.1:610`; implementation `buku:1566-1605` (range branch) and `buku:1445-1477`
  (`compactdb`); tag normalisation promised at `buku.1:45`.

## P2 — multi-index delete: two committed transactions with no envelope

- **argv:** `buku --nostdin --db $STATE/bookmarks.db --tacit --delete 2 5`
  Pre-state: same ~8-bookmark DB.
- **why:** This takes a *different* code path from P1. `buku:5963-5974` sorts the indices
  descending and calls `bdb.delete_rec(int(idx))` once per index **without** `delay_commit`,
  so each delete commits independently at `buku:1631-1632`. There is no outer transaction.
  A crash between the two commits leaves a durably half-applied operation: index 5 gone,
  index 2 still present, and — because compaction already ran for 5 — the record that used to
  be id 8 now sits at id 5. The user's next `--print` shows a consistent-looking but wrong
  numbering, and re-running the same command deletes *the wrong bookmark*, because index 2 now
  means something different than it did. This is buku's own atomicity gap, not SQLite's, so it
  is reachable even if journaling is perfect.
- **what property:** *No unrelated bookmark is lost, and the survivor set is explainable.*
  In every world the set of URLs must be exactly one of: all 8; all 8 minus the id-5 URL; or
  all 8 minus the id-5 and id-2 URLs. Any other set — in particular one missing the id-8 URL —
  is a violation. Additionally ids must remain contiguous `1..COUNT(*)` in every world, since
  compaction is documented as maintaining exactly that.
- **where from:** CLI loop `buku:5963-5974`; per-call commit `buku:1631-1632` with
  `delay_commit` defaulted `False` at `buku:1485`; the descending-order and
  "auto-DB compaction" promise at `buku.1:61`.

## P3 — import containing one already-present URL: the hidden mid-loop commit

- **argv:** `buku --nostdin --db $STATE/bookmarks.db --tacit --import $STATE/in.md`
  where `in.md` holds ~6 lines of `[title](url) <!-- TAGS: a,b -->` and **line 4's URL is
  already in the DB**. Pre-state: DB with that one URL present.
- **why:** The import loop looks atomic — every `add_rec` is called with `delay_commit=True`
  (`buku:3212`) and there is one `conn.commit()` at `buku:2669`. But the duplicate line makes
  `add_rec` return −1 (`buku:619-621`), and the fallback
  `self.append_tag_at_index(rec_id, item[2])` (`buku:2665-2667`) runs with its default
  `delay_commit=False` (`buku:665`) and **commits at `buku:709`**. So the transaction boundary
  is placed by the *content of the input file*, not by the code's intent. A crash after that
  accidental commit but before `buku:2669` durably persists lines 1–4 and silently drops 5–6,
  with exit status never observed by the user. Re-running the import then hits *more*
  duplicates and takes the same accidental-commit path again.
- **what property:** *An import is all-or-nothing, and re-running it converges.* In every crash
  world the DB must contain either none of the new URLs or all of them; and the `tags` value on
  the pre-existing duplicate URL must be a valid normalised tagset (comma-wrapped, lowercase,
  sorted, no empty element) rather than a half-applied append — `append_tag_at_index` builds
  the new string in Python and writes it as one `UPDATE` (`buku:690-709`), so a torn value here
  would indicate the row write itself was not atomic. Weaker but still checkable fallback if
  all-or-nothing is judged undocumented: no URL may appear twice (the schema declares
  `URL TEXT NOT NULL UNIQUE`, `buku:502`), and every `tags` value must satisfy `buku.1:45`.
- **where from:** `buku:2662-2669` (import loop and final commit), `buku:3212` (the
  `delay_commit=True, fetch=False` tuple), `buku:665` + `buku:709`
  (`append_tag_at_index`'s defaulted commit), schema uniqueness at `buku:502`, tag
  normalisation at `buku.1:45`.

---

## Not proposed, but the most interesting thing I found

**`--lock` / `--unlock` can brick the database with no way back.**

`encrypt_file` writes the whole ciphertext to `bookmarks.db.enc` and *then*, as a separate
step, `os.remove(dbfile)` (`buku:234-253`). A crash in that gap leaves **both files on disk**.
And every subsequent buku invocation dies immediately:

```
elif db_exists and enc_exists:
    LOGERR('Both encrypted and flat DB files exist!')
    sys.exit(1)
```

— `initdb`, `buku:484-486`; the same guard is repeated in `encrypt_file` (`buku:198-201`) and
`decrypt_file` (`buku:305-308`). So *no* buku command works, including any that might repair
it, and §4 says there is no repair command anyway. `decrypt_file` has the mirror-image gap:
it writes `dbfile`, verifies the embedded hash, and only then `os.remove(encfile)`
(`buku:335-351`) — crash in between and you are in the same both-files state, this time with a
*plaintext* database sitting next to the encrypted one, which is also a confidentiality
failure given `buku.1:85` says the file is only unencrypted "between these 2 operations".

I am not proposing it because it fails two of the engine's preconditions, and I would rather
say so than let it be discovered:

1. **Recording will refuse** — `os.urandom` at `buku:220` and `buku:225` is written into the
   `.enc` header at `buku:236-237`.
2. **It cannot be driven by argv** — `getpass()` at `buku:203-204` and `buku:310`.

If the engine ever grows urandom pinning and a stdin channel, this is the first thing to
queue: a documented two-file invariant, an unguarded window between the two filesystem
operations that maintain it, a fatal-on-startup check that detects the violation, and no
repair path.
