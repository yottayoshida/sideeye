# Devtodo (0.1.20) — Crash-Consistency Proposals

## State Location
- **Primary**: `.todo` file in current or parent directories (or `~/.todo` by default)
  - Binary or XML format (configurable via `~/.todorc` "database-loaders" directive)
- **Config**: `~/.todorc` and `/etc/todorc` (read-only during operation)

## Determinism Expectation
**MEDIUM RISK** — Devtodo supports both binary and XML loaders. The binary format may include timestamps or platform-specific details (byte order, padding). XML format is text-based and more deterministic. Test should specify loader type explicitly or use XML-only.

## Proposals (ranked by richness)

### P1: Binary database save with partial write
- **argv**: `devtodo --add "new task"` (or via UI: `a`, type text, Enter) followed by exit or explicit save
  - Triggers `todo.save(database)` in main.cc
- **why**: TodoDB::save() (TodoDB.cc, implied from main.cc pattern "save if modified") writes the entire todo tree to the `.todo` file. If using binary loader (default for existing files), the write is sequential binary serialization without intermediate checkpoints. A crash mid-write leaves the file partially written, unreadable by the parser. Invariant: `.todo` file is either fully readable before save, or fully readable after save, never partially written.
- **what property**: "After save, .todo file can be parsed as valid binary/XML (format-specific parser); all entries from memory are present, or file reverts to previous state; never contains partial/corrupted entries"
  - Test fixture: load `.todo` file with N tasks, add task, save, verify parser can read entire file and N+1 tasks present; verify no parse errors mid-file
- **where from**:
  - main.cc lines 65–73: `todo.load(database)` then `if (options.mode != TodoDB::View) { todo.save(database) }`
  - TodoDB.cc: save() method (implementation details in binary/XML loaders)
  - Loaders.h declares loader interface; Loaders.cc implements binary and XML serialization

### P2: Multi-entry tree structure rearrange
- **argv**: `devtodo --reparent 3,5` (make entry 3 a child of entry 5) or UI equivalent
  - Modifies tree structure (parent-child relationships) across entries
- **why**: Reparenting changes pointers/references in multiple entries. If the save is interrupted, some entries' parent pointers may point to stale data or incomplete entries. The tree is inconsistent (cycles, orphans, or dangling refs). Invariant: tree is acyclic and fully connected after save, or unchanged.
- **what property**: "After reparent save, tree structure is consistent: no cycles, no orphaned entries, all parent refs are valid; or reparent is rolled back entirely"
  - Test fixture: create tree with entries 1, 2, 3, 5; reparent 3 to 5; save; verify tree can be fully traversed without cycles or segfaults; verify all entries have valid parent/child pointers
- **where from**:
  - main.cc TodoDB::Reparent operation
  - TodoDB tree structure is maintained in memory; save() serializes entire tree
  - Binary format likely uses offsets or indices for tree links

### P3: Delete and reclaim disk space
- **argv**: `devtodo -R 1` (remove entry 1)
  - Removes entry and triggers save
- **why**: Deleting an entry removes it from the tree in memory. On save, the binary file size shrinks (deleted entry's bytes are not written). If crash occurs during write, the file may be shorter but incomplete, or still contain deleted entry's data in orphaned regions. Invariant: file length matches serialized tree size exactly; no orphaned data; deleted entries don't reappear on load.
- **what property**: "After delete and save, .todo file has no trace of deleted entry; file size matches serialized tree; load produces tree without deleted entry"
  - Test fixture: load `.todo`, delete one entry, save, verify entry absent on reload; verify file size matches parser's expected size (no orphaned blocks)
- **where from**:
  - main.cc TodoDB::Remove operation
  - Serialize to file with new size (shorter); compare file size to parsed tree size

## Baseline Recording Notes
- Use XML loader only for determinism: set `database-loaders xml` in `~/.todorc`
- Pre-populate `.todo` with known tasks (XML format for readability)
- Disable interactive mode; use command-line arguments only for deterministic replay
- Freeze filesystem timestamps if possible (or accept variance in mtime)
