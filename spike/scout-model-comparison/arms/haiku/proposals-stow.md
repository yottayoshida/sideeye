# Stow (2.3.1) — Crash-Consistency Proposals

## State Location
- **Primary**: Target directory (e.g., `/usr/local`, or `~/mysoft-install/`) containing symlinks created by stow
  - Stow directory (e.g., `/usr/local/stow/package-1.0/`) contains source files (untouched by stow)
- **No persistent metadata**: Stow stores no database or hash files; state is implicit in filesystem (symlinks present/absent)

## Determinism Expectation
**LOW RISK** — Stow only reads the source directories and writes symlinks/directories to the target. No timestamps, random IDs, or nondeterministic writes observed.

## Proposals (ranked by richness)

### P1: Multi-symlink stow with partial completion
- **argv**: `stow -d /tmp/stow-dir -t ~/target package-1`
  - Stow a package with multiple files/directories, creating symlinks in target
- **why**: `process_tasks()` (Stow.pm.in line 1462) iterates through a task list and executes each task (mkdir, symlink creation) sequentially. If crash occurs mid-iteration, some symlinks are created, others are not. The invariant is: all symlinks for a stowed package are present, or none are (atomic stow).
- **what property**: "After stow, target contains all expected symlinks pointing to correct sources, or no stow artifacts; tree traversal succeeds without dangling links"
  - Test fixture: stow package with 5+ files/subdirs into target, verify all symlinks created or all rolled back on crash; verify no dangling symlinks; `stow --redo` or `stow --unstow` should succeed
- **where from**:
  - Stow.pm.in lines 1462–1481: process_tasks() loops `for my $task (@{$self->{tasks}}) { $self->process_task($task) }`
  - process_task() lines 1495–1520: `mkdir($task->{path})` or `symlink $task->{source}, $task->{path}`
  - Plan phase (plan_stow()) builds task list; execute phase (process_tasks()) runs tasks one at a time without bundling

### P2: Unstow with partial removal
- **argv**: `stow -d /tmp/stow-dir -t ~/target -D package-1` (unstow package)
  - Removes symlinks previously created by stow
- **why**: `process_tasks()` again iterates through tasks. For unstow, tasks remove symlinks (`unlink` / `rmdir`). A crash mid-unstow leaves some symlinks removed, others present. The invariant is: target is either fully stowed or fully unstowed for a given package (no partial state).
- **what property**: "After unstow, target contains no symlinks to unstowed package, or all symlinks remain; no orphaned symlinks; tree is cleanly unstowed or untouched"
  - Test fixture: stow package, unstow it, verify no symlinks remain for that package; verify target tree is clean; re-stow should succeed without conflicts
- **where from**:
  - Stow.pm.in lines 1495–1525: process_task() handles action 'remove' for symlinks and directories
  - unlink(), rmdir() calls in process_task()

### P3: Folding/unfolding directories with cascading operations
- **argv**: `stow -d /tmp/stow-dir -t ~/target --no-folding package-1`
  - Stow with directory folding disabled; alternatively, stow a package that replaces target directories with symlinks to source directories
- **why**: When a package's subdirectory structure mirrors the target, stow can either:
  1. Create individual symlinks for each file (no folding), or
  2. Replace the entire target directory with a symlink to the source directory (folding)
  
  This is multi-step: create parent dir, create child links/dirs. If crash occurs mid-fold, the directory structure is partially created, or mix of symlinks and real directories. Invariant: the directory structure is consistent (all files under a directory are either all symlinks-to-source or all real files), never mixed.
- **what property**: "After stow with folding, directory tree is consistent: subdirectories are either fully replaced by symlinks (folded) or contain individual symlinks/directories (unfolded); no mixed states; all files accessible"
  - Test fixture: stow multi-level package structure, verify directory tree is coherent (can be traversed and all files found); verify folding strategy is applied consistently; unstow should reverse all changes atomically
- **where from**:
  - Stow.pm.in lines 480–560: stow_contents() handles folding logic and creates task list
  - do_link(), do_mkdir(), do_unlink() methods enqueue operations
  - Task execution is sequential without transaction semantics

## Baseline Recording Notes
- Use explicit stow and target directories (avoid `$HOME`-relative paths for reproducibility)
- Pre-populate stow directory with known package structure
- Disable adopting (`--adopt` not used) to keep stow directory clean
- Verify symlink targets after each operation (use `readlink`, `ls -la`)
- File system must support symlinks and multiple hard links (not FAT32)
