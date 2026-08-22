# GNU Stow 2.3.1 — scouting notes

Checkout: `targets/stow`. Read in full: `bin/chkstow.in` (128 lines). Read in
detail (targeted sections, function-by-function): `lib/Stow.pm.in` (2136
lines total — the engine) and `bin/stow.in` (CLI option parsing, ~850 lines).
Read relevant sections of `doc/stow.texi` (the Texinfo manual).

## 1. Persistent state

- **State is the target tree itself** — there is no separate "stow database."
  The stow directory (default: cwd, set via `-d/--dir`, e.g.
  `/usr/local/stow`) holds the real package files (read-only from Stow's
  perspective once a package is unpacked there) and the **target directory**
  (`-t/--target`, default: parent of the stow directory, e.g. `/usr/local`)
  is what Stow actually reads AND writes: it creates/removes symlinks and
  directories there. `doc/stow.texi:194-201` is explicit about this design
  choice: *"Stow stores no extra state between runs, so there's no danger...
  of mangling directories when file hierarchies don't match [a] database."*
  So the crash-consistency target for this tool is squarely the target tree
  (symlinks + directories it creates), not any config/db file.
- Nothing resembling a cache directory exists in this codebase.

## 2. Commands that write state, especially multi-file

Stow has a two-phase design: a `plan_stow`/`plan_unstow` pass walks the
package tree(s) purely in memory, building an ordered `{tasks}` array
(`init_state`, `lib/Stow.pm.in:211-252`; each element is `{action: create|
remove|move, type: link|dir|file, path, source|dest}`), and only afterward
does `process_tasks` (`lib/Stow.pm.in:1462-1481`) walk that list and call
`process_task` (`:1493-1537`) to actually `mkdir`/`symlink`/`rmdir`/`unlink`/
`move` each one, **in order, with no rollback and no fsync/rename-into-place
staging** — each syscall is issued directly against its final path
(`:1499, 1504, 1515, 1520, 1529`). A single CLI invocation can enqueue and
then execute dozens of these low-level ops before returning, which is exactly
the shape of operation this kind of engine is built to interrupt.

Three specific multi-op sequences stand out:

- **Unfolding a shared directory** (`lib/Stow.pm.in:487-509`, inside
  `stow_node`): when stowing package B into a target where the same relative
  path is currently a *directory symlink* into package A (a "folded" tree),
  Stow does, in order: `do_unlink($target)` (drop the old symlink) →
  `do_mkdir($target)` (create a real directory in its place) →
  `stow_contents(...)` for package A's files (re-link each, one `do_link`
  per file) → `stow_contents(...)` for package B's files (same). This is a
  named, documented scenario — see §3.
- **Refolding on unstow** (`fold_tree`, `lib/Stow.pm.in:1124-1145`, invoked
  from `unstow_node` at `:877-880` whenever removing a package's symlinks
  leaves a directory containing only symlinks to one *other* remaining
  package): for every remaining node, `do_unlink` it, then `do_rmdir($target)`,
  then `do_link($source, $target)` to collapse the directory back into a
  single directory symlink. Symmetric inverse of the unfold case, also
  documented — see §3.
- **`--adopt`** (`lib/Stow.pm.in:537-539`, `do_mv` at `:2052-2088`): when a
  target path is already a plain file not owned by Stow, `--adopt` does
  `do_mv($target, $path)` — moving the **real file content** out of the
  target tree into the stow package's installation image via
  `File::Copy::move` (`process_task`'s `move` branch, `:1525-1533`, explicit
  comment that plain `rename()` isn't used because the two trees may be on
  different filesystems, i.e. this can be copy+unlink, not a single atomic
  syscall) — then `do_link($source, $target)` puts a symlink back. This is
  the only operation in the tool that relocates actual user data rather than
  just symlink/directory bookkeeping.

Note on **task ordering determinism**: both `stow_contents` (`:389`,
`readdir $DIR` with no `sort`) and `fold_tree` (`:1132`, same) build their
per-directory task order from raw `readdir` results, unsorted. This is a
determinism concern in its own right — see §5.

## 3. Documented promises (checker material)

- **`doc/stow.texi:199-201`**: *"Stow will never delete any files,
  directories, or links that appear in a Stow directory... so it's always
  possible to rebuild the target tree."* — a strong recoverability claim:
  after any crash, the stow directory's package trees are the ground truth,
  and re-deriving the target tree from them (e.g. by re-running `stow`) must
  be possible and must reproduce full coverage.
- **`doc/stow.texi:684-690` ("Ownership")**: *"Stow will never delete
  anything that it doesn't own... Anything Stow owns, it can recompute if
  lost: symlinks that point into a package in the stow directory, or
  directories that only contain symlinks that stow 'owns'."* This is close
  to a self-healing/idempotency claim and is directly checkable: after a
  crash, does the *set of things Stow claims to own* (per `chkstow --list`,
  §4) match reality, and can `chkstow --badlinks`/`--aliens` findings all be
  driven to zero simply by re-running the same `stow` invocation?
- **`doc/stow.texi:670-678`**: a fully worked example of the exact unfold
  sequence from §2 (emacs+perl sharing `/usr/local/bin`), narrated
  step-by-step: *"the symlink `/usr/local/bin` is deleted; the directory
  `/usr/local/bin` is created; links are made from `/usr/local/bin` to
  `.../emacs/bin/emacs` and `etags`; and links are made from
  `/usr/local/bin` to `.../perl/bin/perl` and `a2p`."* This sentence is
  effectively a specification of intermediate states a crash could freeze
  the tree in.
- **`doc/stow.texi:729-740` ("Refolding")**: the symmetric documented
  sequence for `fold_tree`: *"Stow will refold the tree by removing the
  symlinks to the surviving package, removing the directory, then linking
  the directory back to the surviving package."*
- **`doc/stow.texi:372-393` (`--adopt`)**: *"the file becomes adopted by the
  stow package, without its contents changing"* — an explicit content-
  conservation promise for the one operation (§2, third bullet) that moves
  real data.
- **`doc/stow.texi:706-707` (deleting packages)**: *"Stow will not delete
  anything it doesn't 'own'."* — same ownership invariant from the unstow
  side, checkable via `chkstow --aliens` finding zero regressions after a
  crashed `-D`.

## 4. fsck / doctor / verify / undo

**`bin/chkstow.in` is exactly this** — a small (128-line), standalone Perl
tool, read in full. Three modes (`process_options`, `:43-51`):
`-b/--badlinks` (default): walk the target tree and report any symlink whose
target doesn't exist (`bad_links`, `:102-104`, `-l && !-e`) — directly
detects the "dangling symlink" failure mode of an interrupted `do_link`/
`do_unlink` sequence. `-a/--aliens`: report any non-symlink, non-directory
node in the target tree (`aliens`, `:107-109`) — directly detects the
`--adopt` failure mode (§2/§3) where a plain file was supposed to have been
replaced by a symlink but wasn't. `-l/--list`: enumerate which package each
symlink belongs to, by parsing `readlink` output (`list`, `:113-120`).
`doc/stow.texi:832-875` documents `chkstow` explicitly as the "Target
Maintenance" tool for "cleaning up mistakes" after the fact — i.e. the
project's own stated position is that recovery from a bad target tree is
"run chkstow, then fix by hand or re-run stow," not any transactional/undo
mechanism inside `stow` itself. There is no separate `undo`/`repair`
subcommand; `-R/--restow` (`bin/stow.in:603`) unstows then re-stows a package
in one invocation, which is the closest thing to a repair action, but it
shares the same non-atomic `process_tasks` machinery as everything else
(confirmed via `bin/stow.in:598-618`: `-R` just pushes the package onto both
`@pkgs_to_unstow` and `@pkgs_to_stow`, which get planned and executed through
the identical code path).

## 5. Determinism expectation

**Expect good determinism for the filesystem-tree side, with one caveat.**
Stow's mutations are pure filesystem metadata operations — `mkdir`,
`symlink`, `unlink`, `rmdir`, and (for `--adopt`) a content-preserving `mv` —
with no randomness, no timestamps embedded in written data, and no network
or environment-dependent values in what gets written (symlink targets are
computed from static relative paths, e.g. `join_paths('..', $existing_source)`
at `lib/Stow.pm.in:501,507`). This should be one of the more
byte-reproducible targets in the set.

**Caveat**: per §2, the order in which sibling files within one directory
are turned into tasks comes from raw, unsorted `readdir` (`lib/Stow.pm.in:389`,
`:1132`). On most POSIX filesystems, `readdir` order for an unmodified
directory tends to be stable across repeated reads within one recording run,
but it is not something the tool sorts or otherwise pins, and is not
guaranteed by any filesystem's documented contract to be identical across
independently-created (even identically-populated) directories — e.g. if a
fixture is rebuilt between a baseline recording and a later comparison run.
**Recommendation**: if the engine's baseline recording is sensitive to *task
ordering* (i.e., which specific mkdir/symlink/unlink happens at which numbered
I/O boundary) rather than just final-state bytes, build the fixture stow/
target directories once and reuse the same on-disk directories for every
recording rather than recreating them, to avoid a readdir-order-driven
recording mismatch that has nothing to do with a real defect.

## Proposals

### P1 — unfolding a shared directory (stow into an already-folded target)

- **argv**: `stow -d <stow-dir> -t <target-dir> perl`, where `<stow-dir>`
  contains two packages, `emacs/bin/{emacs,etags}` and `perl/bin/{perl,a2p}`,
  `emacs` has already been stowed (so `<target-dir>/bin` is currently a
  symlink to `../stow/emacs/bin`), and `perl` has not yet been stowed.
- **why**: per §2/§3, this exact scenario (`lib/Stow.pm.in:487-509`) drives
  Stow through `do_unlink($target)` → `do_mkdir($target)` →
  `stow_contents()` × 2 (re-linking emacs's 2 files, then linking perl's 2
  files) — 6 underlying filesystem syscalls issued one at a time with no
  rollback (`process_tasks`, `:1462-1481`). It is `doc/stow.texi`'s own
  worked example (lines 670-678), so the "correct" intermediate narrative is
  spelled out in the manual, making deviations from it unambiguous.
- **what property**: from `doc/stow.texi:684-690` — every file that was
  reachable through `<target-dir>/bin/*` before the operation started must,
  after the crash and after re-running the same `stow`/`stow -R perl`
  invocation to let Stow "recompute what it owns," be reachable again at the
  same relative path, resolving to the same underlying package file it did
  before (emacs's 2 files) or the newly-requested one (perl's 2 files) — and
  `chkstow -b -t <target-dir>` (badlinks) must report zero dangling symlinks
  once recovery is complete. The failure this targets: a crash caught between
  `do_unlink` and `do_mkdir` (or mid-`stow_contents`) leaves `<target-dir>/bin`
  either completely absent or only partially repopulated — i.e., emacs's
  `etags`, which was perfectly fine and untouched by the user's request to
  stow `perl`, becomes unreachable purely as a side effect of an unrelated
  package's installation.
- **where from**: `lib/Stow.pm.in:487-509` (unfold logic), `:1802-1869`
  (`do_link`, showing tasks are simply appended/executed, no grouping),
  `doc/stow.texi:670-690` (worked example + Ownership section).

### P2 — refolding on unstow (removing the "newer" of two co-located packages)

- **argv**: starting from the P1 end-state (both `emacs` and `perl` stowed
  into the same `<target-dir>/bin`, now a real directory containing 4
  symlinks), run `stow -d <stow-dir> -t <target-dir> -D perl`.
- **why**: `unstow_node` (`lib/Stow.pm.in:799-888`) removes `perl`'s two
  symlinks via `unstow_contents`, notices `<target-dir>/bin` now contains
  only symlinks into `emacs` (`foldable($target)`, `:878`), and calls
  `fold_tree($target, $parent)` (`:1124-1145`): `do_unlink` each of emacs's 2
  remaining symlinks, `do_rmdir($target)`, then `do_link($source, $target)`
  collapsing the directory back into one symlink to `../stow/emacs/bin`. A
  crash inside this sequence is the doc's own §3 "Refolding" scenario, run
  for real.
- **what property**: `doc/stow.texi:729-740`'s explicit 3-step promise —
  *"removing the symlinks to the surviving package, removing the directory,
  then linking the directory back to the surviving package"* — checked as:
  after recovery, `<target-dir>/bin/emacs` and `<target-dir>/bin/etags` must
  both still resolve (emacs's files must never become collateral damage of
  unstowing perl), and the end state must converge to *either* the pre-unstow
  4-symlink directory *or* the fully-refolded single directory-symlink —
  never a state with some but not all of emacs's 2 files reachable, and never
  a state where perl's 2 (supposedly-removed) symlinks still resolve. This is
  the direct inverse check of P1 and specifically exercises the
  `do_rmdir` step, which P1's unfold path never calls.
- **where from**: `lib/Stow.pm.in:799-888` (`unstow_node`, the `foldable`/
  `fold_tree` call at `:877-880`), `:1124-1145` (`fold_tree` body),
  `doc/stow.texi:729-740` (Refolding section, quoted above).

### P3 — `stow --adopt` on a pre-existing plain file

- **argv**: `stow -d <stow-dir> -t <target-dir> --adopt dotfiles`, where
  `<stow-dir>/dotfiles/.bashrc` exists (the package's version) and
  `<target-dir>/.bashrc` already exists as an ordinary (non-symlink) file
  with different, real content (simulating a user's existing dotfile Stow
  doesn't yet own).
- **why**: this is the one Stow operation that moves real file *content*,
  not just symlink metadata. `stow_node`'s adopt branch
  (`lib/Stow.pm.in:536-539`) does `do_mv($target, $path)` then
  `do_link($source, $target)`; `do_mv` (`:2052-2088`) queues a `move` task
  whose execution (`process_task`, `:1525-1533`) explicitly uses
  `File::Copy::move` rather than `rename()` — the code comment at `:1527-1528`
  says this is *because* the stow directory and target directory may be on
  different filesystems, which makes the move a non-atomic copy-then-unlink
  in the cross-filesystem case. A crash between the copy landing in
  `<stow-dir>/dotfiles/.bashrc` and the subsequent `do_link` leaves
  `<target-dir>/.bashrc` gone entirely — no plain file, no symlink — with the
  user's original content now sitting *only* inside the stow package tree.
- **what property**: `doc/stow.texi:372-393`'s explicit promise — *"the file
  becomes adopted by the stow package, without its contents changing"* —
  checked as content equality (the bytes originally at
  `<target-dir>/.bashrc` before the command ran must be recoverable byte-for-
  byte from wherever they end up, whether that's still at the original path,
  moved into `<stow-dir>/dotfiles/.bashrc`, or (post-recovery) reachable via
  the completed symlink) plus reachability (after a `stow -R dotfiles` repair
  pass, `<target-dir>/.bashrc` must resolve to content-identical data — never
  a state where the file is simply missing from both locations).
- **where from**: `lib/Stow.pm.in:536-539` (adopt branch of `stow_node`),
  `:2052-2088` (`do_mv`), `:1525-1533` (`process_task`'s `move` action and
  the cross-filesystem `File::Copy::move` comment), `doc/stow.texi:372-393`
  (`--adopt` documentation, including its own explicit warning that this
  option is "specifically intended to alter the contents of your stow
  directory").
- **caveat**: cross-filesystem behavior (copy+unlink vs. a same-filesystem
  `rename()`, which `File::Copy::move` uses transparently when possible) is
  filesystem-topology-dependent — the crash window is wider (more I/O
  boundaries) if the fixture's stow-dir and target-dir are deliberately
  placed on different mounts/filesystems than if they share one, which is
  worth pinning deliberately rather than leaving to the test host's layout.
