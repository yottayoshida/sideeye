# Buku (4.7) — Crash-Consistency Proposals

## State Location
- **Primary**: `~/.local/share/buku/bookmarks.db` (SQLite database)
- **Optional encrypted**: `~/.local/share/buku/bookmarks.db.enc` (parallel encryption file)

## Determinism Expectation
**HIGH RISK of recording refusal** — Buku uses timestamps in metadata fields. The bookmarks table stores `metadata` (visited timestamp) and `flags` that may include timestamp-like values. Repeated runs may produce different DB checksums unless:
- All bookmarks use fixed timestamps, or
- The test fixture explicitly freezes time during recording

## Proposals (ranked by richness)

### P1: Multi-file export with transaction break
- **argv**: `buku -e ~/test-export.db`
  - Export entire DB to a new SQLite file
- **why**: `exportdb()` deletes the destination file if it exists, then creates a new database connection and writes bookmarks one at a time via INSERT. If crash occurs mid-INSERT loop, the exported file exists but is incomplete/partially written. The invariant is: "exported DB contains all bookmarks from source" OR "exported file doesn't exist" — partial states violate this.
- **what property**: "An exported buku DB file contains all bookmarks in source, or export is atomic (file absent or complete)"
  - Test fixture: create bookmark(s) in source DB, export, verify all records copied OR file missing; never partially populated
- **where from**: 
  - `buku` lines 2186–2240 (exportdb function): loops over resultset calling `outdb.cur.execute(INSERT...)` then `outdb.conn.commit()`, with early `os.remove(filepath)` if target exists
  - "Export DB bookmarks to file" docstring; export contract implies all-or-nothing

### P2: Encryption state pair (db + enc files)
- **argv**: `buku -e` (via Python API: `BukuCrypt.encrypt_file(iterations=1)`)
  - Encrypt the plaintext database to `.enc` file
- **why**: Encryption creates a parallel `.enc` file while the plaintext `.db` remains. The function checks for race conditions (both files existing is an error) but doesn't atomically rename. If crash occurs during large file reads/writes (CHUNKSIZE=0x80000), the `.enc` file may be partially written or corrupt, yet the plaintext `.db` is untouched. Invariant: either plaintext OR encrypted file exists, never both partial states.
- **what property**: "After encryption, .db is replaced by .enc, or encryption fails with db unchanged; never both files partially complete"
  - Test fixture: encrypt a known DB, verify `.enc` exists and `.db` either gone or intact; verify encrypted file is readable
- **where from**:
  - `buku` lines 161–290 (encrypt_file, decrypt_file static methods)
  - Line 187: `encfile = dbfile + '.enc'`; line 224: `os.remove(filepath)` happens after reading
  - Error handling at line 193 checks "both encrypted and flat DB files exist" as an error case

### P3: Delete with tag update atomicity
- **argv**: `buku -d 1` (delete bookmark 1)
- **why**: Deletes a bookmark by ID from the DB table. The DELETE happens in a single SQL statement, but the SQLite transaction may span multiple pages if the table is large. A crash mid-transaction could leave the row logically deleted but physically present, or vice versa. The invariant is: "deleted ID never appears in queries" OR "ID is present with all fields intact".
- **what property**: "After deletion, bookmark ID does not appear in list/search results, or deletion fails with ID intact"
  - Test fixture: add bookmark(s), delete one, query; verify deleted ID absent or all fields present (no partial row)
- **where from**:
  - `buku` line 1464: `query2 = 'DELETE FROM bookmarks WHERE id = ?'` in delete_rec() method
  - SQLite ACID property should guarantee, but testing confirms it even under crash injection

## Baseline Recording Notes
- Must set `XDG_DATA_HOME` or `$HOME` before run to pin DB location
- Consider using `PRAGMA synchronous=FULL` for deterministic writes, or accept timing variance
- Each fixture state: empty DB vs. pre-populated with N bookmarks
