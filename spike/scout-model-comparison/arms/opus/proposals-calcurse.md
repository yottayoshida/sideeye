# calcurse 4.7.1 — scouting report

Checkout: `targets/calcurse/`. C, ncurses TUI plus a genuinely usable non-interactive CLI.
Line numbers are in `targets/calcurse/` paths as given.

## 1. Where the persistent state lives

calcurse splits **data** from **configuration**, and says so (`doc/calcurse.1.txt:611-625`):

```
$XDG_DATA_HOME/calcurse/        $XDG_CONFIG_HOME/calcurse/
          |___apts                          |___conf
          |___notes/                        |___hooks/
          |___todo                          |___keys
```

- **Data directory** (`path_ddir`) — read **and** written. Contains `apts`, `todo`, `notes/`.
  Constants at `src/calcurse.h:87-97`. **Selectable with `-D`/`--datadir`**
  (`src/args.c:447`), a plain path argument — exactly what the engine wants.
- **Config directory** (`path_cdir`) — `conf`, `keys`, `hooks/`. Selectable with
  `-C`/`--confdir` (`src/args.c:445-446`). Written only by the TUI (`io_save_keys`,
  `src/io.c:344-358`) — for the CLI operations below it is read-only, but note
  `io_check_data_files` will *create* `keys` from defaults if absent
  (`src/io.c:1202-1205`), so seed it in the pre-state.
- **Not state**: `.calcurse.pid`, `.daemon.pid`, `daemon.log` (documented as present only
  while running, `doc/calcurse.1.txt:626-629`). The **import log is outside the state
  directory entirely** — `io_log_init` puts it in `get_tempdir()` (`src/io.c:1396`),
  i.e. `$TMPDIR`. Good news for baseline recording; see §5.
- `notes/` is genuinely part of the database, not a cache: "One text file is created per
  note, whose name is the SHA1 message digest of the note itself"
  (`doc/calcurse.1.txt:640-641`).

## 2. Which commands write that state

There are exactly three non-interactive CLI verbs that write, and **two of them write two
files in one operation**:

| argv | writes | code |
|---|---|---|
| `-P` / `--purge` | `todo` **then** `apts` | `src/args.c:905-907` |
| `-i` / `--import` | `apts` **then** `todo` | `src/args.c:966-969` |
| `-g` / `--gc` | unlinks files in `notes/` | `src/args.c:941-945` → `note_gc`, `src/note.c:176-254` |

**The central finding: calcurse rewrites its live data files in place, by truncation.**

```c
if ((fp = fopen(aptsfile, "w")) == NULL)
```
— `io_save_apts`, `src/io.c:277`; identically `io_save_todo`, `src/io.c:326`; and
`io_save_keys`, `src/io.c:351`.

`"w"` truncates the existing file to zero length *before the first byte of new content is
written*. There is **no** temp-file-and-`rename`, **no** `fsync`, and **no** backup copy
anywhere in the save path. `file_close` (`src/io.c:300`) is a `fclose` wrapper. So for the
entire duration of a save, `apts` on disk is a prefix of the new content — and at the very
start of it, `apts` is empty.

Two independent failure windows follow, and they are worth testing separately:

1. **Intra-file**: a crash while `io_save_apts` is streaming leaves `apts` truncated, very
   likely mid-line. calcurse's loader treats a malformed line as fatal — `io_load_error`
   calls `EXIT()` (`src/io.c:540-544`), reached from the appointment parser. So the next
   invocation of *any* calcurse command dies at load.
2. **Inter-file**: `todo` and `apts` are saved sequentially with nothing tying them
   together. A crash in the gap leaves one purged and the other stale.

Also note the **ordering is inconsistent between the two callers** — purge does
todo-then-apts (`src/args.c:906-907`), import does apts-then-todo (`src/args.c:968-969`).
Not a bug by itself, but it means a recovery heuristic keyed on "the second file is the
stale one" cannot be written.

`note_gc` (`src/note.c:176-254`) is the mild one: it builds a hash table of every filename in
`notes/`, removes the entries referenced by any loaded item, then `unlink`s the remainder
(`src/note.c:249-254`). Only *unreferenced* files are unlinked, and the unlinks are
independent, so a crash mid-loop just leaves some garbage behind. I do not propose it as a
primary target — see §4 for the one way it becomes dangerous.

## 3. What the documentation promises

The purge documentation is unusually explicit, and it is a conservation promise:

- **`src/args.c:129`** (the `--help` text): `"-P, --purge   Read items and write them back"`.
- **`doc/calcurse.1.txt:239-243`**: "*-P*, *--purge*:: Load items from the data files and
  save them back; the items are described by suitable filter options… The matching items are
  (silently) 'removed' from the data files."

Read together: purge is *defined* as load-then-store, and the only items that may disappear
are the ones the filter selected. Everything else must survive. That is precisely a
checkable invariant.

Other promises worth mining:

- **`doc/calcurse.1.txt:635-637`** — "The calendar file +apts+ contains **all** of the user's
  appointments and events, and the +todo+ file contains the todo list." A totality claim.
- **`doc/calcurse.1.txt:640-641`** — "One text file is created per note, whose name is the
  SHA1 message digest of the note itself." A cheap, total, *always-valid* invariant: for
  every file in `notes/`, `sha1(contents) == basename`. Assert it in every crash world
  regardless of which operation was interrupted.
- **`doc/calcurse.1.txt:630-632`** — "The data files constitute the calcurse database and are
  independent of the calcurse release version."
- **`doc/calcurse.1.txt:707-710`** — hooks: "*pre-save*:: Executed before the data files are
  saved. *post-save*:: Executed after the data files are saved."
- **`doc/calcurse.1.txt:252-256`** — the manual's own hedge: "'Warning:' Be careful with this
  option, specifying the wrong filter options may result in data loss… In any case, make a
  backup of the data files in advance." Worth quoting in a report, because it shows the
  authors already know purge is the sharp edge — but it is aimed at *filter* mistakes, not
  at crashes.

**A doc/code mismatch I noticed while checking the above** (not a crash property, but it
undercuts the obvious mitigation): the hooks are run by `io_save_cal` only
(`run_hook("pre-save")` at `src/io.c:525`, `run_hook("post-save")` at `src/io.c:533`). The
CLI purge and import paths call `io_save_todo`/`io_save_apts` **directly**
(`src/args.c:906-907`, `src/args.c:968-969`) and therefore run **no hooks at all**. The
shipped example hook `contrib/hooks/post-save` is a git-commit backup. So a user who
followed the manual's "make a backup" advice by installing that hook gets no backup and no
commit for `calcurse -P` or `calcurse -i` — the two commands most able to destroy data.

## 4. fsck / doctor / verify / undo / repair

**None.** There is no `--check`, no `--repair`, no undo, no journal, no `.bak`. The nearest
things, and why each falls short:

- `io_check_data_files` (`src/io.c:1190-1208`) only tests **existence** and creates what is
  missing. A zero-length `apts` passes it happily.
- `new_data()` (`src/io.c:463-487`) SHA1s `apts` and `todo` and compares against the digests
  taken at load, to detect *external* modification before an interactive save
  (`src/io.c:506-517`). It is detection for a merge prompt, not repair, and it is
  unreachable from the CLI paths.
- `io_merge_data` (`src/io.c:373-418`) shells out to `conf.mergetool` (vimdiff) — interactive,
  TUI-only.
- **`-G`/`--grep` is the natural checker readout**: `doc/calcurse.1.txt:212-213` — "Print
  appointments, events and TODO items in calcurse data file format", with `%(raw)` defaults
  (`src/args.c:912-916`). One process, no mutation, no network, and it emits the same
  serialisation the files use, so a checker can diff item sets directly.

The absence of repair is what makes finding 1 in §2 severe rather than annoying: a truncated
`apts` is fatal at load (`src/io.c:540-544`) and there is nothing shipped that can get the
user back.

The one way `--gc` turns dangerous: it runs `io_load_data(NULL, FORCE)` and then deletes
every note not referenced *by what loaded*. If a previous crash truncated `apts`, the
appointments past the truncation point are gone from memory, so their notes are now
"unreferenced" and `-g` **permanently deletes the note bodies** — destroying the one
remaining copy of that text. That is a cascade across two operations rather than a property
of one, so it is out of scope for a single-operation engine, but it is the reason a
truncated `apts` should be treated as unrecoverable rather than merely damaged.

## 5. Determinism expectation

**Expectation: fully deterministic. I do not expect a recording refusal for any of the three
proposals.**

Basis, in the checkout:

- I grepped `src/ical.c src/io.c src/utils.c src/apoint.c src/todo.c src/recur.c` for
  `time(NULL)`, `now()`, `get_today`, `DTSTAMP`, `random`, `getpid`, `mkstemp`. Every hit
  that could reach persistent state resolves as follows:
  - `src/io.c:564` `t = time(NULL)` — seeds a `struct tm` used for *parsing* in
    `io_load_app`; never serialised.
  - `src/ical.c:475` `date = date_sec2date_str(now(), fmt)` — written into the **import log
    header**, and that log lives in `get_tempdir()` (`src/io.c:1396`), outside the data dir.
  - `src/utils.c:792` `mkstemp` — same temp log, same reasoning; also `edit_note`'s scratch
    file (`src/note.c:85-88`), which is TUI-only.
  - `src/io.c:1549` `getpid()` — the daemon pid file, only under `--daemon`.
  - `src/utils.c:693-699` `get_today()` — used for `from`/`to` defaults (`src/args.c:883-886`),
    which are consumed by the **query** branch (`date_arg_from_to`, `src/args.c:935`), not by
    the grep/purge branch. Keep date filters out of the argv and the clock cannot reach the
    output.
- The serialisers write only stored fields: `apoint_write`, `event_write`, `todo_write`,
  `recur_*_write` (called from `src/io.c:283-297` and `src/recur.c` `recur_save_data`).
- Write order inside `apts` is fixed and documented in the function comment
  (`src/io.c:263-267`): "the appointments first, and then the events. Recursive items are
  written first" — implemented as `recur_save_data` → `alist_p` → `eventlist`
  (`src/io.c:283-297`). Deterministic given deterministic list order.
- No network anywhere in these paths. No UUIDs in the native format (`--export-uid` affects
  iCal *export* only, `src/args.c:493`).

**Two pre-state requirements** rather than refusals, both easy to satisfy:

1. Seed `conf` and `keys`, or the run will create them — `io_check_file`/`keys_dump_defaults`
   (`src/io.c:1196-1205`), and `io_check_dir` for `notes/`, `hooks/` (`src/args.c:893-896`).
2. For the byte-equality assertions in P1, the pre-state `apts` must already be in calcurse's
   canonical output order. Get that for free by letting the engine's own baseline run settle
   first, then using its output as the pre-state; a hand-written `apts` in a different order
   would make a *correct* rewrite look like a change.

## 6. One correctness note on the argv, before the proposals

`-P` sets `filter.invert = 1` **itself** (`src/args.c:581-583`), and passing
`--filter-invert` alongside it is rejected (`src/args.c:878`). The doc says invert "is used
internally by the purge option" (`doc/calcurse.1.txt:246-248`).

That inversion is applied per item type, and **the type-specific `cond` expressions do not
all test the same criteria**. `--filter-completed` appears only in the todo predicate
(`src/io.c:808`); the appointment predicate has no completed/uncompleted term at all
(`src/apoint.c:234-241`). With the default `type_mask = TYPE_MASK_ALL` (`src/args.c:870-871`),
an appointment under `calcurse -P --filter-completed` gets `cond == false`, so
`filter->invert && !cond` fires at `src/apoint.c:250` and the appointment is **skipped —
i.e. deleted**. `calcurse -P --filter-completed` erases every appointment in the file.

So the type mask must be pinned: **`--filter-type todo`** makes
`!(filter->type_mask & TYPE_MASK_APPT)` true, giving `cond == true`, so appointments are
kept. All three proposals below pin it. (This is also, incidentally, a live footgun worth a
sentence in any upstream report — but it is a *filter-semantics* bug, not a crash bug, and I
am not proposing it as a crash target.)

---

# Proposals

## P1 — purge completed todos: `apts` is rewritten as collateral and must not change

- **argv:**
  `calcurse -D $STATE/data -C $STATE/config -q -P --filter-type todo --filter-completed`
  Pre-state: `apts` holding a mix of ~10 appointments, events and recurring items;
  `todo` holding ~8 items of which 3 are completed; `notes/` holding note files for two of
  the appointments; `conf` and `keys` seeded (§5). `-q` suppresses dialogs
  (`doc/calcurse.1.txt:258-259`).
- **why:** The user asked to drop three *todo* items. calcurse honours that by rewriting
  `todo` — and then rewrites `apts` too (`src/args.c:906-907`), by truncation
  (`src/io.c:277`), even though not one appointment is affected. Every appointment in the
  database is therefore destroyed and recreated on an operation that has nothing to do with
  appointments, with no temp file, no rename and no fsync. Crash in the middle of the second
  write and `apts` is a prefix of itself, almost certainly ending mid-record; the next
  calcurse invocation hits `io_load_error` → `EXIT()` (`src/io.c:540-544`) and the tool will
  not start. Crash in the gap between the two writes and the user has a purged `todo` beside
  an un-purged `apts`, with no marker anywhere that the operation was half-done. There is no
  repair command (§4) and, because the CLI path bypasses `io_save_cal`, no `pre-save` hook
  fired to leave a backup (§3).
- **what property:** *Purge removes the filtered items and nothing else.* Two assertions,
  both from the documented definition of `-P`:
  1. **`apts` must be byte-identical to the pre-state in every crash world.** No filter term
     in this argv can select an appointment, event or recurring item (`src/apoint.c:234-241`,
     `src/event.c`, `src/recur.c:544`, with `type_mask` pinned to todo), so the only correct
     content is the content that was already there.
  2. **`todo` must be either exactly the pre-state or exactly the pre-state minus the three
     completed entries** — never a prefix, never missing an uncompleted item.
  Plus the standing invariant, valid in every world: every file in `notes/` has a name equal
  to the SHA1 of its own contents (`doc/calcurse.1.txt:640-641`), and no note referenced by a
  surviving item is missing.
  A practical readout for the checker: `calcurse -D … -G --filter-type todo` and
  `calcurse -D … -G --filter-type cal` print the two sets in the data-file format
  (`doc/calcurse.1.txt:212-213`), and a non-zero exit or a fatal load message is itself a
  violation.
- **where from:** promise — `src/args.c:129` ("Read items and write them back") and
  `doc/calcurse.1.txt:239-243`; implementation — `src/args.c:905-907` (both saves, purge
  branch), `src/io.c:268-303` and `src/io.c:317-341` (the `fopen(…, "w")` truncation),
  `src/io.c:540-544` (fatal load on a malformed line); filter semantics —
  `src/io.c:804-822` (todo predicate) vs `src/apoint.c:234-241` (appointment predicate).

## P2 — purge that removes nothing: a pure identity rewrite of two live files

- **argv:**
  `calcurse -D $STATE/data -C $STATE/config -q -P --filter-type todo --filter-priority 9`
  Pre-state: same as P1, but **no todo item has priority 9**.
- **why:** This is P1 with the ambiguity removed. The filter selects nothing, so the entire
  operation is defined to be a no-op — and calcurse still truncates and rewrites both `todo`
  and `apts` end to end. Every I/O boundary in this operation is therefore a boundary at
  which a *no-op* can lose user data, which is the cleanest possible statement of the defect
  and the easiest to explain to a maintainer. It also isolates the write path from the filter
  path: if P1 shows loss and P2 does not, the fault is in filtering, not in saving. Priority
  is a first-class filter term (`filter->priority && id != filter->priority`, `src/io.c:807`),
  so this stays on the ordinary code path rather than being a degenerate case.
- **what property:** *A purge that matches nothing changes nothing.* In every crash world,
  both `apts` and `todo` must be byte-identical to the pre-state. There is no "or" branch,
  no ordering question and no canonicalisation caveat beyond the one in §5 — any difference
  at all, in either file, is a violation. Same standing `notes/` SHA1 invariant as P1.
- **where from:** `doc/calcurse.1.txt:239-243` ("Load items from the data files and save them
  back") and `src/args.c:129`; save path `src/args.c:905-907` → `src/io.c:277` / `src/io.c:326`;
  priority filter term `src/io.c:807`; type-mask pinning per §6 (`src/args.c:870-871`,
  `src/apoint.c:235`).

## P3 — import: two files written in the opposite order, and written even on failure

- **argv:**
  `calcurse -D $STATE/data -C $STATE/config -q -i $STATE/in.ics`
  Pre-state: a populated `apts` and `todo` as in P1; `in.ics` containing ~6 `VEVENT`s and
  ~3 `VTODO`s, **including one malformed component** so that `ical_import_data` reports a
  failure.
- **why:** Import exercises a different caller of the same unsafe primitive, in the opposite
  order — `io_save_apts(path_apts); io_save_todo(path_todo);` (`src/args.c:968-969`) — so a
  crash between the two writes leaves the *other* file stale than in P1/P2. It also has a
  sequencing quirk worth pinning: the saves happen **before** the return code is examined —
  `if (!ret) exit_calcurse(EXIT_FAILURE);` sits at `src/args.c:970-971`, after both writes.
  So a failed import has already overwritten both live data files by the time it announces
  failure, and the user who reads "failure" and re-runs is operating on data that was already
  replaced. Crash anywhere in that window and the pre-existing calendar is gone, replaced by
  a prefix of a merge the tool itself considered unsuccessful.
- **what property:** *Import is additive and all-or-nothing: no pre-existing item is lost,
  whatever happens to the imported ones.* In every crash world, the set of items present must
  be a **superset of the pre-state item set** — every appointment, event, recurring item and
  todo that existed before must still be there — and the file must still load (a fatal
  `io_load_error` at `src/io.c:540-544` is a violation). Whether the *imported* items are
  present may legitimately differ between worlds; the pre-existing ones may not. Same
  standing `notes/` SHA1 invariant.
- **where from:** `doc/calcurse.1.txt:216-217` ("Import the icalendar data contained in
  'file'") and the totality claim at `doc/calcurse.1.txt:635-637` ("The calendar file +apts+
  contains **all** of the user's appointments and events"); implementation
  `src/args.c:946-971` (load, import, both saves, then the failure check),
  `src/io.c:1280-1334` (`io_import_data`), `src/io.c:277` / `src/io.c:326` (truncating saves).

---

## Summary judgement

calcurse is the strongest target of the five for this engine. It has a documented
conservation contract (`-P` is *defined* as "read items and write them back"), a
non-interactive argv that reaches it with explicit `-D`/`-C` path flags, two files written in
one operation with nothing joining them, in-place truncation as the write primitive, a loader
that treats damage as fatal, no repair command, and full determinism. The one thing I would
want the engine operator to know before the run is §6: get the `--filter-type` right, or a
*correct* calcurse will delete every appointment and the result will look like a crash bug.
