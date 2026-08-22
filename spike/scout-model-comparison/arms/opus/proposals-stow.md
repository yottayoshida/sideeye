# GNU Stow 2.3.1 — scouting report

Checkout: `targets/stow/`. Perl: `lib/Stow.pm.in` (2136 lines) is the engine,
`bin/stow.in` (850) the CLI, `doc/stow.texi` the manual. Line numbers are in
`targets/stow/` paths as given.

## 1. Where the persistent state lives

Stow is unusual among these five: **its state is a directory shape, not a file format.**
There are two directories and only one of them is written.

- **Target directory** — read **and** written. This is the state. It holds symlinks pointing
  into the stow directory, plus real directories that contain them. Selected with
  **`-t DIR` / `--target=DIR`** (`bin/stow.in:149-153`); defaults to the parent of the stow
  directory (`bin/stow.in:146-147`).
- **Stow directory** — the package store, read-only during a normal stow/unstow. Selected
  with **`-d DIR` / `--dir=DIR`** (`bin/stow.in:141-147`); defaults to `$STOW_DIR` or the
  current directory (`bin/stow.in:124-125`). Both flags are explicit paths, so no environment
  plumbing is needed — with one exception, below.
- **`--adopt` inverts that**: it writes *into* the stow directory, moving a real file out of
  the target and into the package (`lib/Stow.pm.in:537-540`, documented at
  `bin/stow.in:189-201`). It is the only mode in which the stow directory is not read-only,
  and the only one in which real file content moves.

Control files, all read-only to stow:

- `.stow` and `.nonstow` markers, used to identify stow directories that must not be stowed
  into (`lib/Stow.pm.in:596`, `marked_stow_dir`).
- `.stow-local-ignore` in the package, and **`~/.stow-global-ignore` in `$HOME`**
  (`lib/Stow.pm.in:64-65`, resolved at `lib/Stow.pm.in:1284-1285`). **Pin `$HOME` to a
  controlled directory** or a host user's global ignore file changes which nodes get stowed
  and the pre-state stops being reproducible. This is the one unavoidable environment
  dependency.

**Nothing here is a cache.** There is no database, no manifest, no journal — stow derives
everything by walking both trees at run time. That is a deliberate design choice and it is
what the recovery promise in §3 rests on.

## 2. Which commands write that state

Every mutating run goes through the same two-phase pipeline, and phase 2 is where the crash
windows live.

**Phase 1 (planning)** — `plan_stow` (`lib/Stow.pm.in:303`) / `plan_unstow`
(`lib/Stow.pm.in:264`) walk both trees and *accumulate* a task list. The `do_link`,
`do_unlink`, `do_mkdir`, `do_rmdir`, `do_mv` functions (`lib/Stow.pm.in:1802`, `1879`, `1936`,
`1998`, `2052`) are **planners, not actors** — they push and reconcile entries in
`$self->{tasks}`, `{link_task_for}` and `{dir_task_for}`, and touch nothing on disk. This is
worth knowing before reading the call sites, because names like `do_unlink` read like syscalls
and are not.

**Phase 2 (execution)** — `process_tasks` (`lib/Stow.pm.in:1462-1481`):

```perl
$self->within_target_do(sub {
    for my $task (@{ $self->{tasks} }) {
        $self->process_task($task);
    }
});
```

A flat loop. `process_task` (`lib/Stow.pm.in:1493-1537`) is a dispatch to a bare
`mkdir` / `symlink` / `rmdir` / `unlink` / `move`, each with `or error(...)`. **There is no
rollback, no journal, no ordering constraint beyond insertion order, and no way to resume.**
An interruption leaves the task list half-applied with nothing recording how far it got.

The two operations that make this interesting are folding and unfolding, because both
temporarily destroy the path a user's files were reachable through.

**Unfolding** — `stow_node`, `lib/Stow.pm.in:487-509`:

```perl
debug(2, "--- Unfolding $target which was already owned by $existing_package");
$self->do_unlink($target);
$self->do_mkdir($target);
$self->stow_contents($existing_stow_path, $existing_package, $target, ...);  # OLD package
$self->stow_contents($self->{stow_path},   $package,          $target, ...); # NEW package
```

Emitted task order: `unlink(bin)`, `mkdir(bin)`, then one `symlink` per entry of the **old**
package, then one per entry of the **new**. For a `bin` directory with 40 executables that is
82 independent syscalls, and **from the first one until the last, some or all of the old
package's files are not reachable at their installed paths.**

**Refolding** — `fold_tree`, `lib/Stow.pm.in:1124-1155`:

```perl
for my $node (@listing) { ... $self->do_unlink(join_paths($target, $node)); }
$self->do_rmdir($target);
$self->do_link($source, $target);
```

The mirror image, run during unstow when a directory is left containing only one package's
links. Task order: unlink every remaining symlink, `rmdir` the directory, then create the
folded symlink. There is a window after the `rmdir` in which **the directory does not exist
at all** — not empty, absent.

`stow_contents` reads entries with a bare `readdir` and does **not sort**
(`lib/Stow.pm.in:388-390`); same in `foldable` (`lib/Stow.pm.in:1064-1066`) and `fold_tree`
(`lib/Stow.pm.in:1131-1133`). See §5 for what that does and does not affect.

## 3. What the documentation promises

Stow's manual is the most explicit of the five about this exact subject, and it gives both a
promise to test and a piece of framing worth quoting back.

**The recovery contract** — `doc/stow.texi:682-690`, the Ownership section:

> "When splitting open a folded tree, Stow makes sure that the symlink it is about to remove
> points inside a valid package in the current stow directory. *Stow will never delete
> anything that it doesn't own.* Stow 'owns' everything living in the target tree that points
> into a package in the stow directory. **Anything Stow owns, it can recompute if lost**:
> symlinks that point into a package in the stow directory, or directories that only contain
> symlinks that stow 'owns'."

"**Anything Stow owns, it can recompute if lost**" is a self-healing guarantee, stated
without qualification. It is precisely a crash-recovery contract: whatever state an
interruption leaves behind, re-running stow must be able to reconstruct the correct result.
That is the checker.

**The two-phase claim** — `doc/stow.texi:766-776`, Deferred Operation:

> "Since version 2.0, Stow now adopts a two-phase algorithm, first scanning for any potential
> conflicts before any stowing or unstowing operations are performed. If any conflicts are
> found, they are displayed and then Stow terminates without making any modifications to the
> filesystem. This means that there is **much less risk of a package being partially stowed or
> unstowed** due to conflicts.
>
> Prior to version 2.0, if a conflict was discovered, the stow or unstow operation could be
> aborted mid-flow, **leaving the target tree in an inconsistent state**."

Note the scope carefully, and be fair about it in any report: the promise is about
*conflicts*, not crashes. Phase 1 genuinely removes the conflict-abort failure mode. It does
nothing for an interruption during phase 2, and the manual does not claim otherwise.

**The window is acknowledged** — `doc/stow.texi:794-798`, Mixing Operations:

> "…all the operations are calculated and merged before being executed (…Deferred
> Operation…), so **the amount of time in which GNU Emacs is unavailable is minimised**."

Stow's authors are explicitly reasoning about a window during which an installed package is
unavailable, and optimising its *size*. A crash-consistency engine is the tool that asks what
happens when execution stops inside it.

**The unfold sequence is documented step by step** — `doc/stow.texi:660-678`: "the symlink
`/usr/local/bin` is deleted; the directory `/usr/local/bin` is created; links are made from
`/usr/local/bin` to `../stow/emacs/bin/emacs` and `../stow/emacs/bin/etags`; and links are
made from `/usr/local/bin` to `../stow/perl/bin/perl` and `../stow/perl/bin/a2p`." The old
package's links are restored **last** — so the doc's own worked example tells you which
package a mid-unfold crash strands.

**`--adopt`'s narrower promise** — `bin/stow.in:189-201`: the existing target file is moved
into the package and replaced by a link, "**without its contents changing**".

## 4. fsck / doctor / verify / undo / repair

Stow ships **`chkstow`** (`bin/chkstow.in`, 128 lines), a target-tree checker — the only
purpose-built verifier among the five targets. Its modes are worth knowing:

- `--badlinks` — report symlinks pointing to non-existent files.
- `--aliens` — report files in the target tree **not owned by stow**.
- `--list` — list packages installed in the target.

`--badlinks` is close to a ready-made checker for a dangling-link outcome, but it does **not**
detect the failure this engine is most likely to produce: a *missing* link. A file that
should be installed and simply is not there leaves nothing for `chkstow` to find. So the
checker still has to be written; `chkstow --badlinks --aliens` is a useful **secondary**
assertion to run in every world, not a primary one.

The real repair mechanism is **re-running stow**, which the design intends
(`doc/stow.texi:688`, "Anything Stow owns, it can recompute if lost") and `-R`/`--restow`
formalises (`bin/stow.in:181-186`: unstow then restow, "useful for pruning obsolete symlinks
from the target tree"). There is no undo log and no `--repair`; recomputation *is* the repair.
This makes stow the one target here where the primary checker should be
**"re-run the command and see whether the world heals"** rather than "inspect the wreckage".

Also useful: **`-n` / `--no` / `--simulate`** (`bin/stow.in:134-140`) performs planning and
prints the plan without touching the filesystem — a safe way to materialise the expected
task list for a pre-state, and a way to confirm a recovered world is clean (a healed world
should plan **zero** tasks).

## 5. Determinism expectation

**Expectation: deterministic. I do not expect a recording refusal.**

Basis, in the checkout:

- The only things written are symlinks, directories, and (under `--adopt`) a file move. A
  symlink's content is its target string, computed purely from relative path arithmetic
  (`join_paths`, `parent` in `lib/Stow/Util.pm.in`); directories have no content.
- I grepped `lib/Stow.pm.in` and `lib/Stow/Util.pm.in` for write-side operations: the complete
  set reaching the filesystem is `mkdir`, `symlink`, `rmdir`, `unlink`, `move` in
  `process_task` (`lib/Stow.pm.in:1499-1531`). Stow opens no file for writing anywhere — the
  only `opendir`/`open` calls are reads (`lib/Stow.pm.in:387`, `1063`, `1130`, and the ignore
  file readers at `lib/Stow.pm.in:1303-1366`).
- No clock, no random, no PID, no temp names, no network anywhere in the module.

Three caveats, none of them refusals:

1. **`readdir` is not sorted** (`lib/Stow.pm.in:388-390`, `1064-1066`, `1131-1133`), so task
   *order* follows directory order. The **final state is order-independent** — the same set of
   symlinks results either way — so a byte-reproducible baseline is unaffected. What it does
   affect is *which* intermediate world sits at boundary *k*. For a state directory restored
   identically each time, the order should be stable; if the engine ever observes boundary
   counts drifting between runs, this is why, and it is stow's, not the engine's.
2. **Pin `$HOME`.** `~/.stow-global-ignore` is read at `lib/Stow.pm.in:1285` and changes which
   nodes are stowed at all. A host user's file would silently alter the plan.
3. **Directory mtimes change** as entries are added and removed. If the engine's baseline
   compares directory metadata rather than tree shape, expect noise; the shape itself is
   deterministic.

`--adopt` deserves one extra note: `process_task` uses `File::Copy::move`
(`lib/Stow.pm.in:1529`) with the comment "rename() not good enough, since the stow directory
might be on a different filesystem to the target". Within one filesystem this is a `rename`
and is atomic; across filesystems it degrades to copy-then-unlink and is not. **Keep the stow
and target directories on the same filesystem** unless the cross-device behaviour is the
thing being tested — and if it is, say so deliberately, because it is a different bug.

---

# Proposals

## P1 — unfold a folded tree: the installed package goes missing while the new one is added

- **argv:** `stow -d $STATE/stow -t $STATE/target emacs`
  Pre-state: `$STATE/stow/perl/bin/` with ~8 files and `$STATE/stow/perl/man/man1/` with ~4;
  `$STATE/stow/emacs/bin/` with ~6 files. `$STATE/target/bin` is currently a **folded
  symlink** to `../stow/perl/bin` (the state left by having stowed `perl` into an empty
  target), and `target/man` likewise. `$HOME` pinned to an empty directory (§5).
- **why:** Stowing `emacs` forces `target/bin` to be split open. The planner emits, in this
  order, `unlink(bin)`, `mkdir(bin)`, eight `symlink`s restoring **perl**, then six restoring
  **emacs** (`lib/Stow.pm.in:494-508`, executed by the flat loop at
  `lib/Stow.pm.in:1474-1478`). From the moment `unlink(bin)` runs until the eighth symlink is
  created, **perl's binaries are not reachable at their installed paths** — an operation whose
  purpose is to *install* a second package makes the first one disappear. The manual's own
  worked example (`doc/stow.texi:672-678`) confirms this ordering, and the Mixing Operations
  section is explicit that minimising exactly this unavailability window is a design goal
  (`doc/stow.texi:794-798`). The engine's question is what survives when execution stops
  inside it. `bin` is the ideal node because it has the highest fan-out and is the most
  consequential to lose.
- **what property:** *Everything stow owns is recomputable.* The primary assertion is a
  **recovery** one, taken straight from `doc/stow.texi:688`: in every crash world, re-running
  the identical command `stow -d $STATE/stow -t $STATE/target emacs` must (a) exit 0 with no
  conflict reported, and (b) leave the target tree in the fully correct final state — every
  one of perl's 12 files and emacs's 6 reachable through `target/`, each resolving to the
  right package. A world in which the re-run reports a conflict, or exits 0 while leaving a
  file unreachable, falsifies the documented guarantee. Two secondary assertions to run in
  every world before the re-run: `chkstow -t $STATE/target --badlinks` must report nothing
  (no dangling links were created), and no path under `target/` may resolve outside
  `$STATE/stow` (nothing unowned was touched — `doc/stow.texi:684`, "Stow will never delete
  anything that it doesn't own"). A healed world should also plan zero tasks under
  `stow -n` (§4).
- **where from:** promise — `doc/stow.texi:682-690` (Ownership; "Anything Stow owns, it can
  recompute if lost", "Stow will never delete anything that it doesn't own"),
  `doc/stow.texi:660-678` (the documented unfold sequence), `doc/stow.texi:794-798` (the
  window is acknowledged and minimised); implementation — `lib/Stow.pm.in:487-509`
  (`stow_node`'s unfold branch), `lib/Stow.pm.in:1462-1481` (`process_tasks`, the
  no-rollback loop), `lib/Stow.pm.in:1493-1537` (`process_task`, the raw syscalls);
  checker tool — `bin/chkstow.in`.

## P2 — `--adopt`: the one path that moves a real file, in two non-atomic steps

- **argv:** `stow -d $STATE/stow -t $STATE/target --adopt myconf`
  Pre-state: `$STATE/stow/myconf/` containing ~5 config files; `$STATE/target/` containing
  **real files** (not links) at three of those five paths, with contents differing from the
  package's. Stow and target on the **same filesystem** (§5). `$HOME` pinned.
- **why:** `--adopt` is the only stow operation in which real user data moves, and it does so
  in two separately-scheduled tasks per file: `do_mv($target, $path)` followed by
  `do_link($source, $target)` (`lib/Stow.pm.in:537-540`). Executed, that is
  `move(target/f → stow/myconf/f)` then `symlink(../stow/myconf/f → target/f)`. Between them
  the file exists **only inside the package** and nothing at the target path refers to it —
  and with three files being adopted, the plan interleaves six such tasks with no envelope.
  This matters more than the folding cases because the Ownership guarantee explicitly does
  **not** cover it: stow does not own a real file sitting in the target tree, so "it can
  recompute if lost" (`doc/stow.texi:688`) offers nothing here. The documented promise is
  instead the narrow one at `bin/stow.in:199-201` — the file "becomes adopted by the stow
  package, **without its contents changing**" — and content that is unreachable, duplicated,
  or truncated all violate it.
- **what property:** *An adopted file's content is never lost and never altered.* In every
  crash world, for each of the three adopted files, the original content must be present
  **exactly once** and byte-identical, at either `target/f` or `stow/myconf/f`; never absent
  from both, never truncated, and never replaced by the package's differing version. After
  re-running the same command, all five files must be reachable at their target paths and
  resolve into the package, with the three adopted contents preserved — the package's original
  versions of those three are *expected* to be overwritten by adoption, so the checker must
  compare against the **target's** pre-state content, not the package's. Secondary:
  `chkstow -t $STATE/target --aliens` after recovery should report nothing left stranded.
- **where from:** promise — `bin/stow.in:189-201` (`--adopt`: "the file becomes adopted by
  the stow package, without its contents changing"), and the *absence* of coverage in
  `doc/stow.texi:686-690` (ownership excludes real files in the target);
  implementation — `lib/Stow.pm.in:536-548` (`stow_node`'s adopt branch),
  `lib/Stow.pm.in:2052` (`do_mv`, planner), `lib/Stow.pm.in:1525-1533` (`process_task`'s
  `move`, with the cross-filesystem comment at `lib/Stow.pm.in:1527-1528`).

## P3 — refold on unstow: `rmdir` before `symlink`, so the directory briefly ceases to exist

- **argv:** `stow -d $STATE/stow -t $STATE/target -D emacs`
  Pre-state: the *correct* post-state of P1 — `target/bin` a real directory holding 8 links
  into `perl` and 6 into `emacs`, `target/man/man1` similar. `$HOME` pinned.
- **why:** Unstowing `emacs` removes its 6 links, which leaves `bin` containing only perl's —
  so `foldable` returns true (`lib/Stow.pm.in:1054-1112`) and `fold_tree` runs
  (`lib/Stow.pm.in:1124-1155`). The plan then contains: unlink emacs's 6, unlink perl's
  remaining 8, `rmdir(bin)`, `symlink(bin → ../stow/perl/bin)`. **Fourteen deletions and a
  directory removal precede the single symlink that restores access to any of it.** The
  window here is strictly worse than P1's: in P1 the target path was at least being rebuilt
  incrementally, whereas here everything is torn down first and there is a boundary at which
  `target/bin` does not exist as a directory, a symlink, or anything else. And this is the
  path a user takes to remove a package they no longer want — an operation they would not
  expect to endanger a package they are keeping. It also exercises `plan_unstow`
  (`lib/Stow.pm.in:264`) and the `unstow_contents`/`unstow_node` pair
  (`lib/Stow.pm.in:741`, `799`), which are entirely separate code from P1's planner.
- **what property:** *Unstowing one package never loses another.* In every crash world:
  (a) re-running `stow -d $STATE/stow -t $STATE/target -D emacs` must exit 0 without conflict,
  after which all 12 of **perl's** files must be reachable through `target/` and none of
  emacs's; (b) at no point may any path under `target/` resolve to something outside
  `$STATE/stow` (`doc/stow.texi:684`); (c) `chkstow -t $STATE/target --badlinks` must report
  nothing after recovery. The interesting failure to watch for is a world where `bin` was
  emptied and `rmdir`'d but the folded symlink never created — the re-run must then reconstruct
  perl's installation from scratch, which is exactly the claim at `doc/stow.texi:688`, and
  is the case where I would least bet on it holding.
- **where from:** promise — `doc/stow.texi:729-740` (Refolding: "Stow will refold the tree by
  removing the symlinks to the surviving package, removing the directory, then linking the
  directory back to the surviving package"), `doc/stow.texi:682-690` (Ownership and
  recomputability); implementation — `lib/Stow.pm.in:1124-1155` (`fold_tree`, the
  unlink-all → rmdir → link sequence), `lib/Stow.pm.in:1054-1112` (`foldable`),
  `lib/Stow.pm.in:264` / `741` / `799` (`plan_unstow`, `unstow_contents`, `unstow_node`),
  `lib/Stow.pm.in:1462-1481` (`process_tasks`).

---

## Summary judgement

stow is the most *interesting* of the five and not necessarily the one most likely to yield a
violation. It is fully deterministic, it has explicit path flags for both directories, its
execution phase is a rollback-free loop of raw syscalls, and its manual states an unconditional
self-healing guarantee — "Anything Stow owns, it can recompute if lost" — that a crash engine
can test directly. Because stow stores no state of its own and recomputes everything from the
two trees, I would expect many worlds to heal cleanly on a re-run; that makes a *null* result
here informative rather than wasted, and it makes any world that does **not** heal a
high-quality finding against a documented sentence.
