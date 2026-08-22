# devtodo 0.1.20 — scouting report

Checkout: `targets/devtodo/`. C++, ~3.4k lines across `src/`. Line numbers are in
`targets/devtodo/` paths as given.

## 1. Where the persistent state lives

**A single file per directory, `.todo`**, holding an XML (default) or binary serialisation of
a *hierarchical* item tree. There is no state directory — the "database" is the one file.

- Default name `.todo`; `doc/devtodo.1.in:367` lists it under FILES.
- **Selectable with `--database <file>`** (`src/support.cc:229-230`, dispatched at
  `src/support.cc:314-316`; documented at `doc/devtodo.1.in:78-79`: "Change the database from
  whatever the default is (typically '.todo') to the file specified"). Explicit path flag,
  no environment plumbing needed. Used as both load and save target in `src/main.cc:33`,
  `src/main.cc:44`, `src/main.cc:54`.
- `~/.todorc` is **configuration and is read-only** to the tool, but note it is parsed as
  *extra argv* (`parseRC()` at `src/main.cc:29`, joined ahead of the real argv in
  `joinArgs`). Point `$TODORC` at an empty file or the engine's runs inherit the host user's
  options.
- **`.todo.1`, `.todo.2`, … are state, not scratch.** The manual tells the user to recover
  from them by hand (`doc/devtodo.1.in:126-127`, quoted in §3). They are the only recovery
  mechanism this tool has.
- Linked databases: a `<link filename="…">` element points at *another* `.todo` file which is
  loaded (`src/Loaders.cc:96-100`) and saved (`src/TodoDB.cc:330-331`) as part of the same
  operation. So one logical database can span several files. See §2.

The checkout ships a real 16 KB `.todo` at `targets/devtodo/.todo` — devtodo's own task list,
`version="0.1.19"`, with `done=` timestamps and nested notes. `checkVersion`
(`src/Loaders.cc:44-49`) only requires major.minor to match, so 0.1.19 loads under 0.1.20.
It is a ready-made realistic fixture and I would use it as the pre-state.

## 2. Which commands write that state

`src/main.cc:52-55`: **every mode except `View` saves**, unconditionally, at the end of the
run. The writing verbs are `--add`, `--remove`, `--done`, `--not-done`, `--edit`, `--link`,
`--reparent`, `--title`, `--purge` (mode table at `src/TodoDB.cc:78-93`).

The save path, `TodoDB::save(string const &file)` at `src/TodoDB.cc:363-430`, is where
everything interesting lives. It has three distinct phases:

**Phase A — backup rotation** (`src/TodoDB.cc:365-383`), only when `dirty && options.backups`:

```c
for (int i = options.backups - 1; i > 0; i--) {
    newname = file + "." + stringify(i + 1);
    chmod(newname.c_str(), 0600);
    ::unlink(newname.c_str());
    rename((file + "." + stringify(i)).c_str(), newname.c_str());
    chmod(newname.c_str(), 0400);
}
newname = file + ".1";
chmod(newname.c_str(), 0600);
::unlink(newname.c_str());
rename(file.c_str(), newname.c_str());   // <-- the live database is MOVED AWAY
chmod(newname.c_str(), 0400);
```

Two things to notice. First, each generation is shifted by an **unlink-then-rename pair**,
and there are `2 * backups` such syscalls with nothing joining them: a crash between the
`unlink` and the `rename` **destroys a backup generation outright**, leaving a hole in the
chain (`.todo.1` and `.todo.3` present, `.todo.2` gone). Second, and worse, line 381 renames
the **live** `.todo` to `.todo.1`. From that instant until phase B finishes, **`.todo` does
not exist**.

**Phase B — write the new file** (`src/TodoDB.cc:384-424`) via the selected saver. Both
savers open the target with a plain truncating `ofstream`:

- `xmlSave`: `ofstream of(file.c_str());` — `src/Loaders.cc`, in `bool xmlSave(TodoDB const&, string const&)`
- `binarySave`: `ofstream of(file.c_str());` — same file, `bool binarySave(TodoDB const&, string const&)`

No temp file, no `rename`, no `fsync`, no `flush` check. **With `--backup` absent — which is
the default, `backups(0)` at `src/support.cc:26` — phase A is skipped entirely and this
truncating write is the *only* thing that happens.** A crash then leaves a prefix of the new
XML in `.todo` and no copy of the old content anywhere.

**Phase C — the empty-database special case** (`src/TodoDB.cc:425-429`): if the item list is
empty and there is no title, the file is simply `unlink`ed.

**The nested-database case is the richest window in the tool.** The XML streamer
`TodoDB::save(multiset<Todo> const&, ostream&, int)` (`src/TodoDB.cc:318-361`) writes the
parent's `<link .../>` element and then, *while the parent's `ofstream` is still open and
half-written*, recurses into a **full file-level save of the child**:

```c
if (i->type == Todo::Link) {
    of << … "<link" … "/>" << endl;
    if (i->db)
        i->db->save(i->todofile);      // full save(): rotation + truncate + write
    …
}
```

— `src/TodoDB.cc:323-331`. So the child's backup rotation and truncating rewrite happen
*inside* the parent's write. Two files are in flight simultaneously, and their write
sequences are interleaved rather than ordered. There is no scheme anywhere that could make
that pair recoverable.

Determinism-relevant split of the writing verbs (detail in §5):

- **Deterministic**: `--remove`, `--purge`, `--reparent`, `--title`.
- **Not deterministic**: `--add`, `--done` (both stamp the wall clock into the file).

## 3. What the documentation promises

- **`doc/devtodo.1.in:126-127`** — the backup contract, and it is explicit about the files
  being usable databases:
  > "**--backup [<n>]** Backup the database up to *<n>* times, **just before it is written
  > to**. If *<n>* is not specified, one backup will be made. The filenames used to store the
  > backups are the default database name with their revision appended like so: .todo.1,
  > .todo.2, etc. **To actually use one of these backups, you can either mv it to .todo or
  > use --database .todo.<n> to explicitly specify its use.**"

  This is the strongest checker material in devtodo. It promises (a) that the backups exist
  after a save, (b) that they are numbered contiguously from 1, and (c) that each one is a
  loadable database. It is also, read against `src/TodoDB.cc:381`, an unintentionally exact
  description of the hazard: the backup is made by *moving the live file away*.

- **`doc/devtodo.1.in:52`** — the linked-database conservation promise:
  > "Use --remove (or tdr) to remove linked databases — this does **not** remove the database
  > itself, only the link."

  So an operation on the parent must leave the child file intact. That is a cross-file
  property stated in the manual.

- **`doc/devtodo.1.in:78-79`** — `--database` semantics, quoted in §1.
- **`doc/devtodo.1.in:124`** — "Try the database formats in the given order. Valid formats are
  *xml* and *binary*… The default format is XML." Relevant because the loader *falls through*
  the list on failure (§4), which changes what a corrupt file does.
- `src/support.cc:280` (`--help` text) — "Purge items marked as done. Optionally only purge
  completed items older than ARG days." A scoping promise: only *done* items may disappear.

## 4. fsck / doctor / verify / undo / repair

**None.** No `--check`, no `--verify`, no `--repair`. The backups of §3 are the entire
recovery story, and applying them is a manual `mv` the user has to know about.

What happens to a damaged file is worth stating precisely, because it decides the checker:

- `TodoDB::load` (`src/TodoDB.cc:266-316`) tries each configured loader in turn, catching
  failures, and if all fail throws
  `exception("no database loaders for database format or database corrupt (last error was …)")`
  — `src/TodoDB.cc:315`.
- `main` catches that and exits non-zero: `cerr << "todo: error, " << e.what(); return 1;`
  — `src/main.cc:59-62`.

So a truncated `.todo` does not degrade gracefully: **every subsequent devtodo command fails**,
including the ones a user would try in order to inspect or fix the situation. There is a
narrower and nastier variant — because the loader list is tried in order and the XML parser
is lenient about a missing tail in some shapes, a truncated file may instead load as a
*silently shorter* list. Either outcome is a violation; the checker should distinguish them
because they are different bugs.

**Checker readout:** `View` is the one mode that does not save (`src/main.cc:52-55`), so
`todo --database <f> --all` (`-A` = filter `+done,+children`, `src/support.cc:232-233`) dumps
the full tree without touching anything. Use it, and treat a non-zero exit as a violation.
Do **not** use `--stats`, which is a non-View mode and therefore takes the save path.

## 5. Determinism expectation

**Expectation: `--remove`, `--purge` and `--reparent` are byte-deterministic in the file.
`--add` and `--done` will refuse. There is one stdout-only hazard.**

Basis, in the checkout:

- Items carry two epoch timestamps, serialised straight into the XML:
  `time="<added>"` and, when done, `done="<doneTime>"` — `src/TodoDB.cc:341-346`, mirrored in
  `src/Loaders.cc:189-193`; fields declared at `src/Todo.h:56`.
- **`--done` refuses**: `t->doneTime = getCurrentDate();` — `TodoDB::done()`, and
  `getCurrentDate()` is `return time(0);` at `src/support.cc:676-678`. Fresh wall clock into
  the file on every run. `--done` is *also* interactive — it calls
  `readText("comment> ", t->comment)` unconditionally in the same loop — so it cannot be
  driven by argv anyway.
- **`--add` refuses**: `TodoDB::add()` builds a fresh `Todo` and stamps it the same way. With
  `-a "text"` the body comes from argv, but the timestamp does not.
- **`--remove` is clean**: `TodoDB::remove()` (`src/TodoDB.cc:738-761`) only calls
  `erase(todo, *j)` and `setDirty(true)`. Surviving items keep their stored timestamps and are
  re-serialised verbatim.
- **`--purge` is clean in the file, with a caveat**: the cutoff is computed from the clock —
  `purge(todo, now - options.purgeage * 86400)` at `src/TodoDB.cc:943` — but with `--purge`
  and no argument `purgeage` is 0, so the cutoff is "now" and every already-done item
  qualifies on every run. The *decision* is therefore stable and only stored timestamps are
  written. **Caveat: `src/TodoDB.cc:949` contains a leftover debug line**
  `cout << last->doneTime << " < " << age << endl;` which prints the clock-derived `age` to
  stdout. If the engine's baseline covers stdout, `--purge` refuses on that alone; if it
  covers only the state directory, it is fine. I would default to P1/P3 over `--purge` for
  that reason. (Relatedly, `src/TodoDB.cc:322` has `cerr << "saving: " << i->text << endl;`
  firing for every item on every save — deterministic content, but noisy.)
- Ordering: items live in a `multiset<Todo>` with a comparator over priority/time/text
  (`src/Todo.cc:36-80`), so serialisation order is a deterministic function of content.
- No network, no random, no PID, no temp names anywhere in the save path.
- `src/TodoDB.cc:273` reads `_stat.st_atime`, but only under `options.timeout` in `View` mode
  — not on any write path. Leave `--timeout` unset.

**Pre-state requirement:** set `$TODORC` to an empty file. `parseRC()` (`src/main.cc:29`)
splices `~/.todorc` contents in as extra argv, so a host-user rc file would silently change
the argv under test — including possibly turning `--backup` on or changing
`database-loaders`.

## 6. A note on the code's maintenance state

`src/TodoDB.cc:322` and `src/TodoDB.cc:949` are unguarded debug prints on hot paths, and
`src/TodoDB.cc:423-424` has an unreachable duplicated `throw`. I mention it only because it
affects expectations: this is not code with a maintained durability story, so findings here
are likely to be "never designed for it" rather than "regressed".

---

# Proposals

## P1 — remove one item with backups on: the live database is renamed away before the replacement exists

- **argv:** `todo --database $STATE/.todo --backup 3 --remove 2`
  Pre-state: `$STATE/.todo` = a copy of the shipped `targets/devtodo/.todo` fixture;
  `$STATE/.todo.1` and `$STATE/.todo.2` = two earlier generations (any valid databases), so
  the rotation loop actually has work to do; `$TODORC` pointed at an empty file.
- **why:** This one command performs, in order: `unlink(.todo.3)`, `rename(.todo.2 → .todo.3)`,
  `unlink(.todo.2)`, `rename(.todo.1 → .todo.2)`, `unlink(.todo.1)`,
  **`rename(.todo → .todo.1)`**, then `ofstream(.todo)` and a streaming write
  (`src/TodoDB.cc:367-383` then `src/Loaders.cc` `xmlSave`). Seven filesystem operations with
  no atomicity joining any two of them, on the file set that constitutes both the user's data
  *and* the user's only backup. Two qualitatively different losses are reachable: a crash
  between an `unlink` and its paired `rename` deletes a whole backup generation, breaking the
  contiguous `.todo.1…n` numbering the manual tells users to rely on; and a crash after
  `src/TodoDB.cc:381` leaves **no `.todo` at all**, so the next devtodo invocation finds no
  database, reports nothing, and cheerfully starts a fresh empty list — the failure is silent,
  which is worse than the corrupt-file case that at least errors out.
- **what property:** *A save with `--backup n` never leaves the user without a loadable copy
  of their list, and the backup chain stays contiguous.* Concretely, in every crash world:
  (a) at least one of `.todo`, `.todo.1`, `.todo.2`, `.todo.3` must load successfully via
  `todo --database <that file> --all` with exit status 0; (b) the union of item texts across
  whichever of those files load must contain **every item from the pre-state except possibly
  item 2** — no other item may be absent from all of them; and (c) the surviving backup
  numbering must have no hole, i.e. if `.todo.k` exists then `.todo.j` exists for all
  `1 ≤ j < k`, since the manual documents them as a contiguous revision series.
- **where from:** promise — `doc/devtodo.1.in:126-127` (backups are made "just before it is
  written to", are named `.todo.1, .todo.2, etc.`, and "To actually use one of these backups,
  you can either mv it to .todo or use --database .todo.<n>"); implementation —
  `src/TodoDB.cc:365-383` (the rotation), `src/TodoDB.cc:381` (the live-file rename),
  `src/Loaders.cc` `xmlSave` (truncating `ofstream`), `src/main.cc:52-55` (save on any
  non-View mode); failure behaviour — `src/TodoDB.cc:315` and `src/main.cc:59-62`.

## P2 — remove an item from a *linked* database: two files written, interleaved

- **argv:** `todo --database $STATE/parent.todo --remove 1.1`
  Pre-state: `parent.todo` containing a `<link filename="child.todo" priority="medium"
  time="980645036"/>` element plus two ordinary notes; `child.todo` a valid database with
  three notes; index `1.1` addressing a note **inside the child**. No `--backup`, so neither
  file has any backup at all.
- **why:** This is the only operation in the tool that writes two files, and it does so in the
  worst possible arrangement. `TodoDB::save(…, ostream&, int)` emits the parent's `<link/>`
  element into the parent's still-open, already-truncated `ofstream`, and then calls
  `i->db->save(i->todofile)` — a complete file-level save of the child, truncation and all —
  before returning to finish the parent (`src/TodoDB.cc:323-339`). So at the moment the child
  is being truncated, the parent is *also* truncated and only partly rewritten. A crash
  anywhere in that region can destroy **both** files at once, which no ordering or
  write-then-rename discipline is even attempting to prevent here. The manual explicitly
  promises the child survives operations on the parent, which makes this a documented
  violation rather than an unspecified one.
- **what property:** *Removing an item never destroys a linked database.* In every crash
  world, `child.todo` must exist and must load — `todo --database $STATE/child.todo --all`
  exits 0 — and its item set must be either the pre-state's three notes or those three minus
  the one addressed by `1.1`. It may never be absent, empty, or unloadable. Separately, and
  from the same documented sentence, if the operation had instead targeted the *link* item
  itself, `child.todo` would have to be **completely unchanged**, since removing a link "does
  not remove the database itself, only the link" — worth queuing as a second world if the
  engine has budget.
- **where from:** promise — `doc/devtodo.1.in:52` ("Use --remove (or tdr) to remove linked
  databases — this does **not** remove the database itself, only the link"); implementation —
  `src/TodoDB.cc:323-339` (the mid-stream recursive file save), `src/TodoDB.cc:330-331` (the
  recursive `save(todofile)` call), `src/Loaders.cc:88-108` (link loading, which establishes
  that the child is a full independent database), `src/TodoDB.cc:363-430` (the child's own
  rotation-and-truncate).

## P3 — remove one item with backups off (the default): truncate in place, nothing held back

- **argv:** `todo --database $STATE/.todo --remove 2`
  Pre-state: `$STATE/.todo` = a copy of the shipped fixture. **No `--backup`**, matching the
  shipped default `backups(0)` (`src/support.cc:26`). `$TODORC` empty.
- **why:** This is what the overwhelming majority of devtodo users actually run, and it is the
  bare case: phase A is skipped entirely, so the whole operation is
  `ofstream of(".todo")` — truncate to zero — followed by a streamed XML write of the entire
  tree (`src/Loaders.cc` `xmlSave`, reached from `src/TodoDB.cc:397`). There is no second
  copy anywhere on disk. A crash at any boundary during that write leaves a prefix of the new
  document, and since the fixture is 16 KB of nested `<note>` elements, almost every boundary
  lands mid-document. The user asked to delete one item out of dozens and can lose all of
  them. P3 is deliberately the *simplest* argv in this set: if the engine finds a violating
  world here, the report needs no discussion of backup rotation or linked files at all, which
  makes it the most persuasive single result devtodo can produce.
- **what property:** *Removing one item leaves the other items intact and the database
  loadable.* In every crash world, `todo --database $STATE/.todo --all` must exit 0, and the
  set of item texts it prints must be either the pre-state's full set or the pre-state's set
  minus exactly the item at index 2 (and its children — `erase` removes the subtree,
  `src/TodoDB.cc:755`). A non-zero exit, a "database corrupt" message
  (`src/TodoDB.cc:315`), a missing file, or any *third* item set is a violation.
  Note the two failure shapes are worth reporting separately: an unloadable file is loud,
  whereas a truncation that happens to land on an element boundary can produce a **silently
  shorter list**, which is the same data loss with none of the warning.
- **where from:** default — `src/support.cc:26` (`backups(0)`), so `--backup` is opt-in;
  save path — `src/main.cc:52-55`, `src/TodoDB.cc:384-424`, `src/Loaders.cc` `xmlSave`
  (`ofstream of(file.c_str())`); operation — `src/TodoDB.cc:738-761` (`TodoDB::remove`,
  no timestamp writes, hence deterministic per §5); failure behaviour —
  `src/TodoDB.cc:266-316` and `src/main.cc:59-62`.
