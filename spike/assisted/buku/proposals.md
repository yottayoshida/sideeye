# buku — scout proposals (assisted, #118)

T0 (scout start): 20260814T135403Z. Scout sources: `buku --help` (pinned
container), DeepWiki Q&A on jarun/buku, behavior probes (normal runs).
Scout correction on record: DeepWiki described `BUKU_DEFAULT_DBDIR` as the
first resolution step; the pinned 4.7 build ignores it and honors
`XDG_DATA_HOME` (measured) — external repo-understanding answers must be
re-measured against the pinned version.

## P1 — `--add` (IMPLEMENTED)

- argv: `buku --nostdin --np --tacit --add <fixed URL> <tags> --title <fixed>`
- **why**: adding a bookmark commits into a single sqlite db through
  python's sqlite3 with default journal mode; the crash window is the
  db + `-journal` two-file dance. If buku (or its sqlite usage) breaks
  atomicity anywhere — partial commit, journal left behind that replays
  wrongly — existing bookmarks are what gets lost.
- **what property**: *bookmarks you already had survive a crash during a
  new add* (conservation of the bystander record), and the db file stays a
  well-formed sqlite database (PRAGMA integrity_check).
- **where from**: DeepWiki-cited code path (`BukuDb` commits via
  `conn.commit()`, no explicit journal_mode/synchronous configuration =
  sqlite defaults carry the atomicity); the tool's core purpose (a
  bookmark keeper's one job). Determinism measured: add over the same
  pre-state is byte-identical (probe, this file's directory).

## P2 — `--delete --tacit <index>` (recorded, not implemented first)

- **why**: the deletion path also rewrites the db (and `cleardb()` drops
  the whole table when unscoped) — the complementary write path to P1.
- **what property**: deleting one bookmark must not damage the others.
- **where from**: help text (`-d ... remove bookmarks from DB`; unscoped
  delete removes all — hence `--tacit` + explicit index in any define).
- Deferred: P1 covers the same store with a simpler pre-state; implement
  if P1's exploration returns quickly.

## P3 — `--lock` / `--unlock` (EXCLUDED: interactive channel)

- **why**: the richest cross-file transaction in the tool — encrypt writes
  `bookmarks.db.enc` (size+salt+IV+SHA256, chunked) and DELETES the
  original db on success; decrypt mirrors and deletes the `.enc`. An
  interrupted lock/unlock is exactly where a user could lose the only
  intact copy.
- **what property**: *an interrupted lock/unlock never leaves you without
  one intact copy* (either a complete db or the `.enc` still present).
- **where from**: DeepWiki-cited `BukuCrypt.encrypt_file`/`decrypt_file`
  flow (write-new-then-delete-old, hash-verified).
- **excluded because**: the passphrase channel is interactive-only in the
  pinned build (getpass; measured: EOF stdin produced rc=0 once against a
  HOME-resolved db and rc=1 against the XDG db — not reliably drivable),
  and `--lock`'s salt/IV are random, so even if drivable its baseline
  would carry a refusal expectation. Recorded as experiment data: the
  most interesting window found by the scout is unreachable by the engine
  today.
