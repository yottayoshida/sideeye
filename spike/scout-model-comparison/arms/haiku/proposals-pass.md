# Pass (password-store) 1.7.4 — Crash-Consistency Proposals

## State Location
- **Primary**: `$PASSWORD_STORE_DIR` (default `~/.password-store/`)
  - Tree of `.gpg` files (one per password entry)
  - Directory structure mirrors password hierarchy
  - Optional: `.git/` if store is version-controlled
  - Optional: `.gpg-id` files (keys for encrypting passwords at each level)

## Determinism Expectation
**HIGH RISK of recording refusal** — Pass uses `RANDOM` in temporary filenames:
- Line 120 in password-store.sh: `passfile_temp="${passfile}.tmp.${RANDOM}.${RANDOM}.${RANDOM}.${RANDOM}.--"`
- Line 119 in cmd_insert: temp file for edit also uses randomization
- Recording will fail unless RANDOM is mocked or seeded; each run produces different temp file paths

## Proposals (ranked by richness)

### P1: Reencrypt tree with atomic moves
- **argv**: `pass init -r gpg-key-id` (reinitialize password store with new encryption key, or `pass init gpg-key-id ~/.password-store/path`)
  - Calls `cmd_init()` which calls `reencrypt_path()` for all password files
- **why**: `reencrypt_path()` (lines 110–145+) processes all `.gpg` files under the store, reading each with the old key, re-encrypting with the new key, writing to `.tmp.RANDOM...--` temporary file, then `mv` to replace the original. A crash mid-reencrypt leaves some files with old key, others with new key, and temp files orphaned. The invariant is: all files use the same encryption key set, or none are modified.
- **what property**: "After reencrypt, all .gpg files in tree use new key ID exclusively; no temp files remain; tree is fully consistent or entirely unchanged"
  - Test fixture: create store with 3 passwords encrypted with key1, re-encrypt to key2, verify all files decrypt with key2 only (not key1); verify no `.tmp.*` files remain; verify tree traversal succeeds
- **where from**:
  - password-store.sh lines 110–145: reencrypt_path() loops via `find "$PREFIX" ... -exec {...} {} \;` and calls `mv "$passfile_temp" "$passfile"`
  - Line 120: temp file naming pattern
  - Line 137: `mv` command that completes the atomic swap (but can crash before it)
  - cmd_init() line 364: `reencrypt_path "$PREFIX/$id_path"`

### P2: Insert with parent directory creation and GPG encryption
- **argv**: `pass insert path/to/new/password` (enter password twice)
  - Calls `cmd_insert()` which creates directories and encrypts password
- **why**: `cmd_insert()` (lines 436–485) calls `mkdir -p` to create parent directories, then encrypts password to `.gpg` file via `echo $password | $GPG -e ... -o "$passfile"`. If crash occurs after `mkdir` but before GPG writes the `.gpg` file, the directory tree exists but the entry is missing. If crash occurs during GPG write (large password), the `.gpg` file may be incomplete/unreadable. Invariant: parent directories and password file are created together, or not at all.
- **what property**: "After insert, password file exists and is decryptable; parent directories exist; or entire operation is rolled back (no orphaned directories)"
  - Test fixture: insert password into new deep path (e.g., `org/example/mail/password`), verify all dirs created and `.gpg` file decrypts to correct password; on simulated crash, verify no orphaned directories
- **where from**:
  - password-store.sh lines 436–485: cmd_insert() calls `mkdir -p` (line 461) then `$GPG -e ... -o "$passfile"` (line 475–481)
  - git_add_file() (line 483) calls git to track the new file (optional, may have separate crash window)
  
### P3: Edit with atomic file replacement
- **argv**: `pass edit path/to/password` (opens EDITOR, modifies text, closes editor)
  - Calls `cmd_edit()` which decrypts to temp file, opens editor, re-encrypts
- **why**: `cmd_edit()` (lines 487–510) decrypts to tmp file, opens editor, then re-encrypts the modified file back to `.gpg`, overwriting the original. A crash during the final GPG encryption leaves the original `.gpg` intact (good) but the edit is lost (bad — invariant broken if user sees no error). Alternatively, if crash mid-GPG-write, the `.gpg` file becomes unreadable (worst case). Invariant: password file remains readable and unchanged, or is updated completely with new value; temp file is always cleaned up.
- **what property**: "After edit, .gpg file is decryptable to old value (unchanged) or new value (updated); temp file is deleted; no partial .gpg rewrites"
  - Test fixture: edit a password, change value, verify decrypt shows new value; crash scenario: verify old .gpg is recoverable if crash mid-reencrypt
- **where from**:
  - password-store.sh lines 487–510: cmd_edit() creates tmp file, opens EDITOR, then re-encrypts with `$GPG -e ... "$tmp_file"` (line 507)
  - Encryption may overwrite `.gpg` atomically (depends on `fsync` behavior) or leave partial writes

## Baseline Recording Notes
- **CRITICAL**: Mock `RANDOM` to fixed values or seed, or recording will fail deterministically
  - Option: modify password-store.sh to use counter instead of RANDOM for temp files
  - Or: set `$SHELLOPTS` and `$RANDOM` to fixed values before each run
- Use a single fixed GPG key for all operations
- Pre-populate store with known passwords in known locations
- Disable git integration (`PASSWORD_STORE_GIT=` empty) for simplicity
