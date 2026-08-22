# calcurse 4.7.1 — scouting notes

Checkout: `targets/calcurse`. Primary file read closely: `src/io.c` (1651
lines — all storage I/O). Also read `src/note.c` (note file handling,
in full for the relevant section), targeted sections of `src/args.c` (CLI
dispatch), `src/todo.c` / `src/apoint.c` (serialization format), and
`doc/save.txt`.

## 1. Persistent state

- **State root**: two separate directory trees, both read AND written:
  - `datadir` (default `$XDG_DATA_HOME/calcurse`, override via `--datadir`):
    contains `apts` (appointments + events), `todo` (todo list), and a
    `notes/` subdirectory (one file per long-form note, content-addressed —
    see §2/§5).
  - `confdir` (default `$XDG_CONFIG_HOME/calcurse`, override via
    `--confdir`): contains `conf` (settings), `keys` (keybindings), and a
    `hooks/` subdirectory (external hook scripts).
  This exact 7-object layout (2 dirs, 2 top-level dirs really, 2 data files,
  1 notes dir, 1 config file, 1 keys file, 1 hooks dir) is documented
  explicitly in a source comment (`src/io.c:1176-1188`, the docblock above
  `io_check_data_files`) and in `doc/save.txt:1-14` (user-facing).
  Not state: `$TMPDIR`/`get_tempdir()`-rooted scratch files used transiently
  by `edit_note()` (`src/note.c:80-112`) and periodic-save locking.
- A separate PID-based **lock file** (`path_cpid`, e.g.
  `.../calcurse.pid`) exists purely for single-instance enforcement
  (`io_set_lock`, `src/io.c:1506-1535`) — not calendar state, but relevant
  to §4 as a crash-artifact concern: it's written unconditionally with
  `fopen(path, "w")` (`io_dump_pid`, `:1541-1555`) and only removed on clean
  exit, so a crash leaves it behind and the *next* invocation must tell "the
  crashed run's stale lock" apart from "a genuinely still-running instance"
  (it does, via `kill(pid, 0)` at `:1515`, but that's exactly the kind of
  post-crash-recovery logic worth exercising).

## 2. Commands that write state, especially multi-file

Two direct, **non-atomic, truncating** low-level writers underlie everything:
`io_save_apts(path)` (`src/io.c:268-303`) and `io_save_todo(path)`
(`:317-341`) both do `fopen(path, "w")` — which truncates the file to zero
bytes *before* any new content is written — then stream the in-memory item
lists out with `fprintf`/custom `_write()` calls, then close. **There is no
write-to-temp-file-then-rename anywhere in this path.** A process
interrupted after the `fopen("w")` but before the writes complete (or before
`fclose`) leaves that file truncated or partially written — not merely
"the old version," but potentially **shorter than either the old or new
correct content**.

Multi-file operations built on top of these two:

- **`calcurse --import <file>` / `-i <file>`** (`src/args.c:946-971`): the
  single richest, and only fully **non-interactive**, write path found.
  Sequence: `io_check_file` × 2 → `io_load_data(NULL, FORCE)` (read existing
  apts/todo into memory) → `io_import_data(IO_IMPORT_ICAL, ifile, ...)`
  (parse the ICS file, appending new in-memory items — and, if any imported
  VEVENT/VTODO carries an ICS `DESCRIPTION`, calling `generate_note()`
  *during parsing*, which writes a brand-new file under `notes/`, see §5) →
  `io_save_apts(path_apts)` → `io_save_todo(path_todo)`
  (`src/args.c:968-969`). One invocation can therefore touch **three
  independent files across two directories** (a new `notes/<hash>` file,
  `apts`, `todo`), each write direct and non-atomic, with zero synchronization
  between them.
- **`io_save_cal()`** (`src/io.c:498-538`), the save path used when quitting
  interactively or from the periodic-autosave thread
  (`io_psave_thread`, `:1457-1481`): `io_save_todo(path_todo)` then
  `io_save_apts(path_apts)` (note: opposite file order from `--import`'s
  apts-then-todo), followed by recomputing and caching SHA1 hashes of both
  files (`io_compute_hash`, `:528-529`) used later for staleness/conflict
  detection (`new_data()`, `:463-487`). This path additionally has a
  documented conflict-merge branch, `io_merge_data()` (`:373-418`), which
  itself calls `io_save_apts`/`io_save_todo` a *second* time against
  `.new`-suffixed sibling files before invoking an external merge tool.
- **`calcurse -G --purge`** / grep-and-purge (`src/args.c:900-907`): loads
  data, filters, and if `--purge` (or a filter is active) is given, calls
  `io_save_todo` then `io_save_apts` — the same non-atomic pair, reachable
  from yet another non-interactive flag combination.
- **First-run bootstrap** (`io_check_data_files`, `src/io.c:1190-1208`,
  reached from `src/args.c:893-896` at the top of *every* non-interactive
  command, and from `src/calcurse.c:737` for interactive startup): creates,
  independently and in a fixed order, `datadir/` → `datadir/notes/` →
  `datadir/todo` → `datadir/apts` → `confdir/` → `confdir/conf` →
  `confdir/hooks/` → (if missing) `confdir/keys` populated with default
  bindings via `keys_dump_defaults`. Seven filesystem objects, seven
  independent syscalls, no grouping.

## 3. Documented promises (checker material)

- **`doc/save.txt:1-19`**: explicitly enumerates the four data files
  (`conf`, `apts`, `todo`, `keys`) and their directories — the canonical,
  user-facing statement of what "the state" is.
- **Note-reference format** (`src/todo.c:103-115`, `todo_tostr`): a todo
  line with a note is serialized as `[<priority>]>` immediately followed by
  the note's SHA1 hex hash, e.g. `[3]>a94a8fe5...deadbeef Buy milk`. The
  `>hash` token is only ever written *after* `generate_note()`
  (`src/note.c:59-75`) has already created `notes/<hash>` — see the call
  sites at `src/ical.c:1544` and `:1770`, both of which assign
  `vevent.note`/`vtodo.note` from `generate_note()`'s return value before
  that note pointer is ever handed to a `*_write()` function. This ordering
  is an implicit but load-bearing conservation promise: **every `>hash`
  token that appears in `apts`/`todo` must have a corresponding file in
  `notes/`** — the interactive UI has no fallback rendering for a dangling
  note reference; per `src/note.c:157-164` (`note_read_contents`) it simply
  reads whatever bytes are (or aren't) at that path.
- **`src/note.c:179-256`** (`note_gc`, doc'd in-line as *"Spot and unlink
  unused note files"*): implicitly promises the converse — a note file that
  **is** referenced by any loaded appointment, event, recurring item, or
  todo must never be deleted by garbage collection, even when interrupted
  (see P2, below, for why this is checkable as a crash-consistency
  invariant rather than just a logic-bug invariant).
- **`src/io.c:1503-1504`** (comment above `io_set_lock`): *"When creating
  the lock file, the interactive mode is not initialized yet"* — a hint that
  lock-file handling is deliberately kept simple/first, i.e. the project's
  own model of "what could go wrong at startup" is scoped narrowly to
  "is another instance running," not to a stale lock from a crash — worth
  testing whether that assumption holds when the *lock* itself is what gets
  interrupted mid-write.

## 4. fsck / doctor / verify / undo

**No dedicated `calcurse --fsck`/`--check`/`--repair` subcommand exists** in
the option table read in `src/args.c`. The closest built-in mechanisms:

- **`calcurse --gc`** (args.c `gc` branch, `:941-945`): loads data then runs
  `note_gc()` (§2/§3) — a real, if narrowly-scoped, "clean up orphaned state"
  operation, but it only prunes `notes/`; it does not validate `apts`/`todo`
  syntax or cross-check anything else.
- **`new_data()` / SHA1 staleness check** (`src/io.c:463-487`, used by
  `io_save_cal`'s `resolve_save_conflict`, `:421-452`): not a general
  integrity checker, but a targeted "did the files on disk change since I
  last read them" detector, which is precisely a crash/external-write
  detection mechanism — a natural fit for a checker that wants to confirm
  "the tool itself can tell its own files got clobbered."
  `io_files_equal` (`:1584-1605`) is the underlying byte-comparison
  primitive, also usable directly by an external checker.
- **No dedicated `undo`.** Recovery relies on the data files being
  plain, hand-editable text (`doc/save.txt`, `doc/manual.txt` both describe
  the file formats), so an external checker/repair tool (or a person) is the
  implied recovery path, not anything calcurse ships.

## 5. Determinism expectation

**Expect good determinism, better than most targets in this batch, with one
narrow exception.** The write content itself has no embedded timestamps,
random IDs, or PIDs in the *calendar data* — item identity is either
user/ICS-file-supplied (event start times, todo text) or, for notes,
**content-derived via SHA1** (`generate_note`, `src/note.c:59-75`,
`sha1_digest(str, sha1)` — the note's filename is a pure function of its
text content, so re-running the identical `--import` against identical
input is expected to produce byte-identical `notes/<hash>`, `apts`, and
`todo` files across repeated baseline recordings). This is a meaningfully
different determinism profile from `pass` (where GPG's own randomized
session-key encryption makes every write nondeterministic by construction)
and closer to how sideeye-style engines want a target to behave.

**Exception**: `io_dump_pid` (`src/io.c:1541-1555`) writes the *current
process's PID* into the lock file — nondeterministic by construction across
runs/recordings. This only matters if a proposal's crash window includes
process startup (lock acquisition); none of the three below do, since they
all target the save/import/gc operations after startup has already
completed successfully in the fixture setup. If the engine's boundary
instrumentation happens to start before `io_set_lock()` on the *measured*
invocation itself (as opposed to fixture setup), that would need flagging
separately.

## Proposals

### P1 — `calcurse --import` of an ICS file with a DESCRIPTION field

- **argv**: `calcurse --datadir <state-dir>/data --confdir <state-dir>/conf --import <state-dir>/fixture.ics`, where `fixture.ics` contains one `VTODO`
  with a `DESCRIPTION:` property (triggering note generation) and the
  datadir/confdir already exist with a valid, non-empty `apts`/`todo` pair
  from prior (pre-recorded, outside the crash window) use.
- **why**: per §2, this single non-interactive invocation drives
  `generate_note()` (new file under `notes/`) followed by two independent,
  non-atomic, truncating rewrites of the *entire* `todo` file and the
  *entire* `apts` file (`src/args.c:966-969`) — three files, two
  directories, zero coordination between them, in one process.
- **what property**: the note-reference conservation promise from §3 — after
  recovery, every `>hash` token appearing anywhere in `todo` or `apts` must
  resolve to an existing file at `notes/<hash>` with the exact content that
  was in the source ICS file's `DESCRIPTION`. The specific failure this
  targets: a crash after `generate_note()` returns a hash but before (or
  mid-way through) the `todo`/`apts` rewrite that's supposed to reference it
  would either (a) lose the reference entirely (imported item silently drops
  its note — a silent data-loss, not a crash), or — the more interesting
  case — a crash *during* the truncating `fopen("w")` rewrite of `todo`
  could leave `todo` shorter than either its pre-import or post-import
  correct length, potentially truncated mid-line, right at the `>hash`
  token, which downstream parsing (`src/apoint.c` around `apoint_scan`,
  same shape in `todo.c`) has no documented behavior for.
- **where from**: `src/args.c:946-971` (import command flow),
  `src/ical.c:1544` and `:1770` (`generate_note()` call sites during
  parsing), `src/note.c:59-75` (`generate_note`), `src/todo.c:103-115`
  (`todo_tostr`, the `>hash` serialization), `src/io.c:268-341`
  (`io_save_apts`/`io_save_todo`, the non-atomic `fopen("w")` writers),
  `doc/save.txt:1-14` (documented file layout).

### P2 — `calcurse --gc` interrupted mid-cleanup

- **argv**: `calcurse --datadir <state-dir>/data --confdir <state-dir>/conf --gc`, run against a fixture `notes/` directory containing at least 5 files:
  3 referenced by items currently in `apts`/`todo`, and 2 genuinely orphaned
  (not referenced anywhere).
- **why**: `note_gc()` (`src/note.c:179-256`) computes the "referenced"
  set once (by walking every loaded list and removing matching hashes from a
  hash table seeded from `notes/`'s directory listing, `:193-248`), then
  unlinks whatever remains, one `unlink()` call per orphan, in a plain
  `HTABLE_FOREACH` loop (`:251-255`) — no batching, no transaction. A crash
  after 1 of 2 orphans has been unlinked is the expected, harmless case; the
  proposal is really testing the *other* side.
- **what property**: the conservation half of §3's `note_gc` promise —
  across every possible crash point in this loop, **none of the 3
  referenced note files may ever be missing**, because they were never in
  the deletion set in the first place (removed from the hash table at
  `:210-248`, *before* the deletion loop even starts). This is a good
  contrast to P1: P1's property is about a *write* landing in the wrong
  order; P2's is about proving a *deletion loop* can never touch data it
  wasn't supposed to touch, purely from reading the two-phase
  compute-then-delete structure — a defect here would mean the "removed
  from hash table" step and the "walk loaded lists" step disagree (e.g. a
  hash-collision or truncation bug in `note_gc_cmp`/`note_gc_extract_key`,
  `:167-178`), not merely an interrupted-transaction question, so this
  proposal is as much a structural-invariant probe as a crash probe.
- **where from**: `src/note.c:179-256` (full function, read in this pass),
  specifically the two-phase structure (build-set-of-all `:190-207`,
  remove-referenced `:209-248`, delete-remainder `:250-255`).

### P3 — first-run bootstrap via any non-interactive command on empty dirs

- **argv**: `calcurse --datadir <fresh-empty-dir>/data --confdir <fresh-empty-dir>/conf -Q --days 1` (query mode; any non-interactive flag reaching
  `src/args.c:893-896` works equally well, `-Q`/`--query` is chosen because
  it performs no further writes of its own beyond the bootstrap, isolating
  the bootstrap sequence as the entire crash window), run against
  directories that do not yet exist at all.
- **why**: per §2's last bullet, `io_check_dir`/`io_check_file` are called 7
  times in a fixed sequence (`src/io.c:1190-1208` for the interactive path;
  the equivalent inline sequence at `src/args.c:893-903` for this
  non-interactive path) to lay down the entire directory/file skeleton from
  nothing. Each call is independently idempotent (`io_check_file`,
  `src/io.c:1153-1174`: creates only `if (!io_file_exists(file))`), which is
  exactly what makes this a good idempotent-recovery probe rather than a
  pure corruption probe.
- **what property**: after a crash at any of the 7 boundaries and a
  recovery re-run of the *same* command, the final directory tree must be
  byte-for-byte/structurally identical to what a single uninterrupted run
  would have produced from the same empty starting point — same 2
  directories present, same 2 zero-byte data files present, same `notes/`
  and `hooks/` present, same default-populated `keys` file (content compared
  against `keys_dump_defaults`'s output, which is static/version-derived,
  not random). The interesting failure mode: an interrupted run that created
  `datadir/todo` but crashed before `datadir/apts`, followed by a recovery
  run — does `io_check_file` correctly leave the already-created,
  zero-byte `todo` alone (per its `if exists, no-op` logic) and only create
  the missing `apts`, or does anything downstream assume "if the directory
  exists, all 7 objects exist" and mis-load state from the still-incomplete
  tree?
- **where from**: `src/io.c:1091-1208` (`io_check_dir`, `io_check_file`,
  `io_check_data_files`, read in full), `src/args.c:893-903` (the
  non-interactive equivalent sequence), `src/io.c:1176-1188` (the docblock
  comment enumerating the exact 7-object structure being built).
