# Calcurse (4.7.1) — Crash-Consistency Proposals

## State Location
- **Primary**: `~/.local/share/calcurse/` (or legacy `~/.calcurse/`)
  - `todo`: appointments/todos in text format
  - `apts`: events in text format
  - `notes/`: directory containing note files
  - `hooks/`: directory for custom hooks
  - `.calcurse.pid`: PID file for daemon mode

## Determinism Expectation
**LOW RISK** — State files are human-readable text. Timestamps are present (event start times), but file modification times should be stable under fixed test conditions. No random IDs or UUIDs observed.

## Proposals (ranked by richness)

### P1: Multi-file save with hash corruption
- **argv**: `calcurse --save` (or exit interactive mode after adding/editing an event or todo)
  - Trigger the `io_save_cal()` function which atomically saves both todo and appointment files
- **why**: `io_save_cal()` (io.c lines 498–539) calls `io_save_todo()` then `io_save_apts()` sequentially, then computes SHA1 hashes of both files, then clears the modified flag. If crash occurs between the two save operations, one file is updated but the other is stale. If crash occurs after one file is saved but before hash computation, the hash becomes invalid (used to detect external file changes). Invariant: both files are updated together, and both hashes are recomputed, OR neither.
- **what property**: "All todos and appointments persist consistently; hash file stamps both or neither; modified flag and file state are synchronized"
  - Test fixture: add one todo and one event, save, verify both files written; verify hash SHA1 values match both files
- **where from**:
  - io.c lines 525–531: sequential `io_save_todo(path_todo) && io_save_apts(path_apts)` with hash computation lines 530–531
  - Line 498 docstring: "IO_SAVE_CTINUE: save operation on next sync" implies atomicity expectation
  - Line 533: `io_unset_modified()` should only execute if both saves complete

### P2: Periodic save with hook side effects
- **argv**: `calcurse -s periodic` or run daemon (`calcurse -d`) and wait for periodic save interval
  - Triggers `io_save_cal(periodic)` which runs pre-save and post-save hooks
- **why**: Lines 520 and 535 call `run_hook("pre-save")` and `run_hook("post-save")`. If a hook modifies the state directory during the save, or if crash occurs between pre-hook and post-hook, the hook's side effects may be orphaned or the save may be incomplete. Additionally, the hook may have created files that interfere with recovery. Invariant: hooks should not corrupt state; if hook fails, save should be aborted.
- **what property**: "Pre-save and post-save hooks complete successfully, or save is rolled back; state directory has no orphaned or partial hook artifacts"
  - Test fixture: add event, install hook that logs start/end, save, verify hook outputs are paired and no temp files remain
- **where from**:
  - io.c lines 520, 535: `run_hook("pre-save")` and `run_hook("post-save")`
  - contrib/ directory contains example hooks; hooks can modify the state directory

### P3: New-data conflict resolution
- **argv**: Add an event via UI, trigger save while external process modifies the todo/apts files, then save again
  - Exercises `new_data()` check and `resolve_save_conflict()` decision logic
- **why**: Lines 510–519 check `new_data()` (which computes SHA1 hashes and detects external changes). If files are modified externally after hashes are computed but before save, the conflict resolution may choose wrong action or leave state inconsistent. Invariant: if external files have changed, user is prompted to decide; applied decision is atomic.
- **what property**: "External file changes are detected; conflict is interactively resolved; resolution is applied atomically to both files or rolled back"
  - Test fixture: modify todo file externally after loading, add event, save, verify prompt shown (if in interactive mode) or conflict detected
- **where from**:
  - io.c lines 508–519: `new_data()` call and `resolve_save_conflict()` handling
  - io_compute_hash() computes SHA1 of files for change detection (line 1518–1535)

## Baseline Recording Notes
- Set fixed date/time for event timestamps (use environment or fixture setup)
- Pre-populate state directory with known todo and event files
- Disable daemon mode for deterministic recording (no time-based saves)
- Hooks should be no-op or append to log file (avoid side effects)
