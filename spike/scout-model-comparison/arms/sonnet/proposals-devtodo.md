# devtodo 0.1.20 — scouting notes

Checkout: `targets/devtodo`. Read in detail: `src/TodoDB.cc` (1536 lines —
targeted reading of `load`/`save`/`link`, not full linear read),
`src/Loaders.cc` (348 lines, the XML/binary `Saver`/`Loader`
implementations, read in full), `src/main.cc` (67 lines, read in full —
this is where the most serious finding lives), and targeted `grep`s of
`src/support.cc` (CLI option table) and `README`.

## 1. Persistent state

- **State root**: a single per-directory file, default name `.todo`
  (`support.cc:23`, `database(".todo")`), resolved relative to the current
  working directory unless overridden with `--database <path>`
  (`support.cc:229-230`, long-flag only, no short form). There is no
  XDG-style central data directory — devtodo is explicitly designed to
  scatter one state file per directory a user runs it in (the README's
  shell-integration pitch: `cd`/`pushd`/`popd` wrappers that show a
  directory's `.todo` contents on entry, `README:4-8`).
- **Format is pluggable**: `Loaders.cc` implements at least an XML writer
  (`ofstream of(file.c_str())` at `:216`) and a binary writer (`:334`),
  selected via a configurable, ordered list (`options.loaders`, default
  order set by `~/.todorc`'s `database-loaders` directive per
  `README:26-29`) — both loader/saver functions are plain functions
  registered into `Loader`/`Saver` maps (`getLoaders()`/`getSavers()`,
  `Loaders.cc:18` on).
- **Numbered backups** (`file.1`, `file.2`, ... `file.N`) are an *optional*,
  disabled-by-default feature (`support.cc:26`, `backups(0)` — the
  constructor default is explicitly zero) enabled via `--backup [N]`
  (`support.cc:273-274`, defaults to keeping 1 backup if the flag is given
  with no argument). This default-off state is itself significant — see §5.
- Not state: nothing resembling a cache or lock file was found in this
  codebase (no `mkstemp`, no `.lock`, no PID file anywhere in `TodoDB.cc`/
  `Loaders.cc`/`main.cc`).

## 2. Commands that write state, especially multi-file

Every state-changing devtodo invocation funnels through one function,
`TodoDB::save(string const &file)` (`TodoDB.cc:363-421`), called exactly
once at the end of `main()` when the requested mode isn't a pure view
(`main.cc:56-59`). Its structure, read in full:

1. **Backup rotation** (`TodoDB.cc:365-383`), gated by `if (dirty &&
   options.backups)` — **skipped entirely at default settings** since
   `options.backups` defaults to `0`. When enabled: for `i` from
   `backups-1` down to `1`, `unlink(file.(i+1))` then `rename(file.i,
   file.(i+1))` (`:371-374`) — an in-place shift of the whole numbered
   chain, oldest-first-evicted — followed by one more `unlink(file.1)` +
   `rename(file, file.1)` (`:378-381`) that moves the *current live
   database* out of the way to become the newest backup. For `--backup 3`
   this is 3 separate `unlink`+`rename` pairs (6 syscalls), fully
   sequential, no grouping.
2. **Content write** (`TodoDB.cc:384-421`, dispatching into
   `Loaders.cc`'s `Saver` functions): `ofstream of(file.c_str())`
   (`Loaders.cc:216` for XML, `:334` for binary) — a **plain, truncating,
   temp-file-free open of the final path**, exactly like `calcurse`'s
   `io_save_apts`/`io_save_todo` and unlike `pass`'s `mv`-into-place
   pattern. This step runs *after* step 1 has already renamed the old
   `file` away (when backups are on) — meaning **`file` does not exist at
   all** for the entire span between the last `rename()` in step 1 and the
   first byte the `ofstream` in step 2 actually flushes.
3. **Metadata restore** (`TodoDB.cc:398-413`): on success, `chmod`/`chown`
   the freshly-written file back to the `stat()`'d owner/mode captured at
   `load()` time (`_stat`, populated at `TodoDB.cc:272`), or (first-run
   case) a "paranoia check" warning if group/world-readable.
4. **Recursive child saves** (`TodoDB.cc:330-331`, inside the
   XML-serialization helper `save(multiset<Todo> const&, ostream&, int)`
   at `:318-361`): a `Todo` item of `type == Link` can carry a live child
   `TodoDB *db` pointer; if set, `i->db->save(i->todofile)` recurses into
   **the entire save() sequence above, for a second, independent file** —
   invoked from *inside* the still-open parent `ofstream`. (Scoped out of
   the proposals below for lack of a verified, non-interactive way to
   populate `i->db` in one invocation without deeper investigation than
   this pass allowed — flagged here as a real multi-file mechanism worth a
   follow-up pass, not a proposal, per the honesty requirement in §5/task.)

## 3. Documented promises (checker material)

- **`README` examples 3 and 4** (`README:19-23`): `tdr 1-10` (remove a
  range) and `todo -R 10.1,13` (re-parent an item) are presented as
  supported, ordinary usage — i.e. bulk mutation and hierarchy
  restructuring are first-class, not edge cases.
- **`support.cc:274`**: *"Enable backups of the database. The optional
  argument is the number of backups to keep."* — the backup feature's own
  stated purpose is protecting against exactly this class of loss; whether
  it delivers on that under a crash mid-rotation is directly testable.
- **The `.todo`-per-directory contract** (`README:1-8`): the shell
  integration scripts assume that entering a directory and finding no (or
  an empty) `.todo` is a normal, silent "nothing to show" state, not an
  error condition — which is precisely what makes the finding in §5/P1
  dangerous: the tool's own UX design trains the rest of the system to
  treat "file unreadable" and "file legitimately empty" as visually and
  behaviorally identical, with no forced surfacing of the distinction.

## 4. fsck / doctor / verify / undo

**None.** There is no `--check`/`--verify`/`--repair` mode in the option
table (`support.cc`'s enum and `addArgument` calls were scanned; nothing
resembling integrity checking exists). The closest thing to graceful
degradation is `TodoDB::load()`'s multi-loader fallback
(`TodoDB.cc:296-315`): it tries each configured loader in turn
(`options.loaders`) and only throws if *all* of them fail to parse the
file — but per §5/P1, this safety net is bypassed entirely by a *shorter*
failure path that fires first. There is no `undo`; the numbered backups
(§2, opt-in) are the only built-in recovery mechanism, and they are not
consulted automatically by anything — a user would have to manually
`cp .todo.1 .todo` themselves.

## 5. Determinism expectation

**Expect good determinism.** No randomness anywhere in the save/load path
read in this pass — no UUIDs, no salts, no `/dev/urandom`. `TodoDB.cc:662`
(`t.added = getCurrentDate()`) embeds a wall-clock timestamp into newly
*added* items specifically, which is a generic "pin the clock" caveat for
any proposal involving `--add`, not a structural nondeterminism risk (the
byte content is fully reproducible given a pinned clock/faketime, unlike
`pass`'s or `buku --lock`'s per-run-random ciphertext). Two ordering
notes, not correctness risks, worth pinning deliberately in a fixture
rather than discovering by surprise: (a) `multiset<Todo>` ordering is
determined by `Todo`'s comparison operator (not read in this pass — not
verified to be a stable, content-derived total order vs. potentially
insertion-order-dependent for equal-priority items); (b) no items carry a
stored numeric ID (§background note below) — the "10.1"-style indices
users see are recomputed by enumeration position at display/save time,
never persisted, so a proposal must never assert "item N" by number across
a crash boundary — only by content.

## Proposals

### P1 — default config (no backups): a crash-truncated `.todo` gets silently discarded and overwritten on next use

- **argv**: two-step probe, both against the same fixture directory with
  `--database <state-dir>/fixture.todo` (backups left at the default `0`
  — i.e. `--backup` is *not* passed):
  1. The crash-window operation: `todo --database <state-dir>/fixture.todo -a "new item"`, run against a pre-existing, non-trivial
     `fixture.todo` (5+ items, valid XML, produced once outside the crash
     window).
  2. The **recovery step the checker must perform**, in *every* resulting
     crash world, not just inspect statically: run the exact same command
     again (or any non-View-mode command) against whatever
     `fixture.todo` the crash left behind.
- **why**: step 1's crash window is the plain truncating `ofstream`
  write (§2, step 2) with zero backup protection — a crash anywhere during
  it can leave `fixture.todo` empty, truncated mid-tag, or otherwise
  unparseable XML. That alone would be a normal "the write wasn't atomic"
  finding. The *reason* this is P1 and not merely one of several similar
  findings: `TodoDB::load()`'s corruption check (`TodoDB.cc:292`,
  `if (in.bad()||in.fail()||in.eof()) throw quit();`) fires on **any**
  unreadable-or-empty file — a genuinely-missing `.todo` (first run) and a
  crash-truncated `.todo` (data loss in progress) hit the exact same
  `throw quit()` path with no distinction. `main.cc:46-49` catches
  `TodoDB::quit` specifically to make first-run "no database yet" silent
  and non-fatal (*"Quit is thrown if the .todo file can't be accessed...
  continuing"*) — but that same silence swallows the corrupt-file case
  too. Execution then falls through to `todo(options.mode)` against an
  **empty in-memory database** (§, `main.cc:50-57`), performs the
  requested add, and unconditionally calls `todo.save(database)` — which,
  with backups off, truncate-overwrites `fixture.todo` with just the one
  new item, permanently destroying whatever of the original 5+ items had
  survived the first crash.
- **what property**: recoverability under a second, ordinary invocation —
  after step 1's crash, does step 2 either (a) error out loudly (the
  honest outcome — "database corrupt, please recover from backup/manual
  inspection"), or (b) silently proceed and overwrite, permanently losing
  any content that a byte-level inspection of the crash-truncated file
  shows was still recoverable (e.g. the crash landed after 4 of 5 `<note>`
  elements had already been flushed, so 4 items were genuinely salvageable
  moments before step 2 ran)? Outcome (b), which the code as read predicts,
  is the finding — a checker whose "recovery" step is only "does the file
  still parse" would miss this entirely; it has to specifically compare
  pre-crash item content against post-*second*-invocation item content.
- **where from**: `main.cc:36-59` (read in full — the `try`/`catch
  (TodoDB::quit&)` swallow, the fallthrough to `todo(options.mode)`, the
  unconditional `todo.save(database)`), `TodoDB.cc:266-316` (`load()`,
  specifically the `throw quit()` condition at `:292`), `TodoDB.cc:363-421`
  (`save()`, specifically that step 1's backup-skip and step 2's
  truncating `ofstream` are the *only* things standing between "corrupt
  file" and "silently replaced file" when backups are off).

### P2 — backup rotation enabled: does the safety net actually catch the P1 failure mode, and can the live file vanish entirely mid-rotation?

- **argv**: `todo --database <state-dir>/fixture.todo --backup 3 -a "new item"`, against the same kind of 5+-item fixture as P1, this time with
  no pre-existing `fixture.todo.1`/`.2`/`.3` (a clean first backup cycle) —
  and a second variant reusing P1's two-step "crash then recover" pattern
  to test whether `--backup` closes the P1 gap or not.
- **why**: per §2 step 1, this exercises all 3 `unlink`+`rename` pairs
  before the same truncating `ofstream` from P1 runs. Two distinct crash
  sub-windows worth distinguishing: (i) mid-rotation (e.g. crash between
  renaming `.2`→`.3` and `.1`→`.2`) — does the backup chain end up
  self-consistent (no generation duplicated across two numbers, none
  silently dropped) rather than merely "no crash occurred"; (ii) the
  narrower, sharper window right after the final `rename(file, file.1)`
  (`TodoDB.cc:381`) but before the `ofstream` in step 2 has written
  anything — during this window `fixture.todo` **does not exist on disk at
  all**, even though a backup (`fixture.todo.1`, byte-identical to the
  pre-save state) does. Any process reading `fixture.todo` in this instant
  sees a plain "file not found," structurally identical to a legitimate
  first run.
- **what property**: two, layered on P1's: (a) backup-chain integrity —
  after any crash point in the rotation loop and a recovery re-run, the
  numbered backups `.1..N` must form a contiguous, non-duplicated,
  content-correct history (checkable by comparing each `.i` against what a
  clean, uninterrupted N-generation rotation would have produced from the
  same input history); (b) **does `--backup` actually prevent P1's
  data-loss amplifier?** Per `main.cc`'s logic, the answer implied by the
  code is *no* — the `throw quit()`/silent-continue path in step 2 of P1
  doesn't consult backups at all, so if the *live* file transiently
  doesn't exist (sub-window ii above) or is mid-rotation-truncated when
  the *next* invocation runs, that next invocation still falls into the
  same "treat as empty, then overwrite" trap — backups would contain the
  lost data, but nothing in the code path read in this pass auto-recovers
  from them. Confirming or refuting that inference under an actual
  interrupted run is the point of this proposal.
- **where from**: `TodoDB.cc:363-383` (backup rotation loop, read in
  full), `support.cc:273-274` (`--backup` flag definition and stated
  purpose), plus the same `main.cc:36-59` / `TodoDB.cc:266-316` citations
  as P1 for part (b).

### P3 — `--remove` of a range, testing content conservation for survivors

- **argv**: `todo --database <state-dir>/fixture.todo --remove 3-5`, against a fixture with 8 items (matching the README's own `tdr 1-10`-style
  range-removal example), backups left at the default off (isolating the
  same unprotected-write mechanism as P1, but for a deletion rather than
  an addition).
- **why**: reuses the identical `save()` mechanism (§2) but stresses a
  different property: because devtodo items carry **no persisted ID**
  (§5) — only priority/time/text/children, re-serialized in
  `multiset`-defined order every save — a crash during this write is the
  right place to check whether the *content* of surviving items (not
  their transient display-index numbers, which are meaningless across a
  crash boundary) is conserved exactly, with none of the removed items'
  text reappearing and none of the retained items' text/priority/children
  silently mutated as a side effect of re-serialization.
- **what property**: after the crash and (per P1's methodology) a
  recovery re-run, the surviving item set's `(text, priority, comment,
  children)` tuples must be byte-identical to their pre-removal values for
  every item *not* in the removed range, and the removed range's items
  must not reappear — checked by content comparison, never by positional
  index (per §5's warning that indices are recomputed, not stored). This
  is the direct devtodo analogue of `buku`'s P3 (compaction after ranged
  delete) and `calcurse`'s P2 (note garbage collection after item
  removal) — same shape of question (does bulk removal ever touch data it
  wasn't supposed to touch), different underlying storage model (no
  transaction log, no database, just one flat serialized tree, so there is
  *no* SQLite-style safety net to fall back on the way `buku`'s P3 has).
- **where from**: `README:19-20` (`tdr 1-10`, the documented bulk-removal
  usage pattern), `support.cc:217-218` (`--remove` flag definition),
  `TodoDB.cc:318-361` (the recursive XML-serialization function that
  re-emits the full surviving tree on every save, read in full), and the
  same `TodoDB.cc:363-421` `save()` mechanism cited in P1/P2.
