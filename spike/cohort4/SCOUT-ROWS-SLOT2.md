# Cohort 4 — slot 2, re-scouted

Produced after the owner's ruling of 2026-08-22: **vdirsyncer is dropped**,
and **the cohort is not frozen at one target** — slot 2 is to be filled
before the freeze, with no promotion clause. Rule 13 forbids a
single-language slate, and himalaya is Rust, so a non-Rust candidate was
preferred.

**This is not a decision.** As with `SCOUT-ROWS.md`, the owner's sign-off
closes the step. Provenance is **assisted**: public sources, GitHub REST
and Search APIs, and the engine's own shim source. **No target was
executed.**

## Method: apply the cheapest disqualifier to everyone first

vdirsyncer was not lost on its write path — it was lost on three commits in
six months and one bug report in six answered inside a week. Both are one
API call each. Reading a write path costs an order of magnitude more, so
every candidate was put through rules 1, 2, 3 and 11 **before** anyone's
source was opened. Two candidates fell there and their write paths were
never read; that is the intended saving, not a gap.

Two properties of the yardstick, kept identical to the run that dropped
vdirsyncer:

- Commit counts are **paginated**. `per_page=100` alone returns a page cap.
- Rule 11 is read on **bug reports specifically** (rule 17). For
  vdirsyncer the unrestricted figure was 4 of 12 and the bug-only figure 1
  of 6; the difference is the whole point of rule 17, and it decides at
  least one row below too.

## The pool, and a hole in the record

From `CANDIDATES-REJECTED.md`: the two rows set aside on probe cost (brew,
CocoaPods) and the unread remainder. Per the owner's ruling, **neomutt and
calcure were not revisited**.

One thing the rejection log does not contain, and should: its §"the basis
is weaker than the word read implies" names five candidates whose READMEs
*were* fetched — trash-cli, vdirsyncer, pipx, unison, himalaya — as coming
"from the recall list, not from this pool". Two of those five became the
slate. **The other three have no verdict row anywhere in the repository.**
They were read and then dropped without a recorded reason, which is exactly
the auditability gap the rejection table exists to close. All three are
measured below, so the hole is now filled rather than merely noted.

## The funnel

| Candidate | ★ | Lang | Commits in 6-month window | Distinct authors in window | Rule 11 (bug-only) | Outcome |
|---|---|---|---|---|---|---|
| bcpierce00/unison | 5,453 | OCaml | 67 | 4 — tleedjarv 34, gdt 31, bcourbage 1, OnkV 1 | **4 of 7** `defect`-labelled | **survivor, with one wall** |
| Homebrew/brew | 49,236 | Ruby | 3,839 | 129 | 6 of 11 unrestricted | reject, rule 5 |
| andreafrancia/trash-cli | 4,547 | Python | 64 | 4 — andreafrancia 46, SOV710 2, wadeio 1, timoteostewart 1 | **1 of 12** | reject, rule 11/17 |
| pypa/pipx | 12,940 | Python | 262 | 49 — gaborbernat 141, then bots | **2 of 11** (2 of 5 `bug`-labelled) | reject, rules 11/17 and 5 |
| CocoaPods/CocoaPods | 14,834 | Ruby | 25 | **1** — amorde 25 | not measured | reject, rule 3 |

Commands: `gh api repos/<r>`, `gh api --paginate
"repos/<r>/commits?since=2026-02-23T00:00:00Z&per_page=100"`, and
`python3 spike/cohort4/rule11-receipts.py <r> <n>`. CocoaPods' rule 11 was
not measured because rule 3 already settled it — recorded so the blank is
read as "not needed", not as "missing".

## Survivor — unison

| Field | Value |
|---|---|
| Repository | `bcpierce00/unison`, OCaml |
| Version | **v2.54.0**, released 2026-05-01; newest tag |
| Operation that would be proposed | one file updated during `unison -batch <dirA> <dirB>` on one host |
| Stars | 5,453 |
| Last push | 2026-08-06 |
| Distribution | release assets include **`unison-2.54.0-ubuntu-22.04-x86_64.tar.gz`, dynamically linked**, alongside a separate `-static` build. Unlike himalaya, a self-build is not forced by the distribution |

**Rule 3 is its strongest row, and it is stronger than himalaya's.** Two
contributors carry the window at comparable weight (tleedjarv 34, gdt 31),
where himalaya is 174 of 184 by one person.

**Rule 11/17 receipts** (`rule11-unison.txt`, 12 most recent issues, PRs
excluded). 6 of 12 unrestricted. Restricted to the `defect` label as rule 17
requires, **4 of 7** were answered inside a week — `#1201` +1.2h, `#1199`
+1.9h, `#1169` +1.8h, `#1164` +0.4h, every one of them by `gdt`
(`COLLABORATOR`). Of the remaining three, `#1182` came at +15.0d, `#1186`
has no reply, and `#1200` has none either but was **filed by gdt himself**,
so it is not a report anyone owed an answer to. This is the label-driven
version of the measurement; unison is the only candidate in the pool whose
tracker labels make it possible without reading each title.

**State root and shapes.** Two replicas, each an ordinary directory tree of
the user's own files — the data a user would not want to lose, and not
derived from anything else. Sync metadata lives separately under the unison
directory (`archiveName`, `update.ml:225`), in unison's own marshalled
format. Main store is the tree; the archive is the other one, the same
shape of caveat SQLite was for vdirsyncer.

**Non-interactive.** `batch` is a first-class preference,
`Prefs.createBool "batch" false` (`src/globals.ml:225`), and `-batch` is the
documented way to run without prompting.

**Write path, and why it has a real interior.** Local updates go through
`renameLocal` in `src/files.ml`. Its `moveFirst` branch does, in order:
`Stasher.backup`, then `writeCommitLog source target temp'`
(`files.ml:343`), then `Os.rename "renameLocal(1)"` moving the existing
target aside to a temp (`files.ml:347`), then `Os.rename "renameLocal(2)"`
moving the new content into place (`files.ml:358`), then `clearCommitLog`,
then `Os.delete temp`. **Five mutating steps with the final path exposed
between two of them** — not the papis shape. The other branch is a single
`Os.rename "renameLocal(3)"` (`files.ml:367`).

**`sync_all` / `fsync` / `fdatasync`: 0 occurrences in `src/`.**

**Threads (rule 10), with the one thing left open.** `Thread.create` and
`Lwt_preemptive` do not occur in `src/*.ml`; `create_process` appears only
in `fswatch.ml`, `remote.ml` (the ssh transport) and `terminal.ml`
(Windows), none of which a local two-directory run reaches. The open point
is in the C stub: `copy_stubs.c` includes `caml/threads.h` and brackets its
reflink with `caml_release_runtime_system()` / `caml_acquire_runtime_system()`
(`copy_stubs.c:143,145`). That is the standard way to release the OCaml
runtime lock and is not itself a thread, but `#1148` reports the macOS GUI
driving unison from several threads. The CLI is the measured surface here;
the probe confirms.

**Rule 9, and unison's own recovery step — the best-documented of any
candidate so far.** The commit log is `DANGER.README` in the unison
directory (`files.ml:28`), written before the rename pair and cleared
after. `processCommitLog ()` (`files.ml:70`) runs it back **on the next
startup**, and `processCommitLogs ()` (`files.ml:84`) does so for every
root. So the checker has a documented recovery step to run first — start
unison again — and then asserts with the target's own re-scan that the two
replicas agree and each file's content is whole. This is what rule 9 asks
for, and it is a different code path from the writer.

**Rule 15: present**, per the five-step sequence above.

**Rule 14: clears.** 51 terms, controls green, 217 unique issues. The
nearest hits were opened and read rather than judged by title:
`#618` "On Redhat, lost data with Unison" is a user's deletion-propagation
question, closed, not a crash; `#570`/`#571` "Local sync does not resume
partial transfer" is about *efficiency* after an interruption — it reports
that a partially transferred file is **restarted**, which is the safe
behaviour, not a corruption. Nothing on the tracker describes the write
shape above failing. `#1148` reports `fpcache` corruption but attributes it
to the macOS GUI invoking unison from multiple threads, i.e. concurrency,
not a crash point.

### Rule 16 — a wall is forecast, and the apparatus that lifts it is an engine change

This is the row that decides whether unison can enter, and it is measured
rather than guessed.

unison's file copy is a C stub, `src/copy_stubs.c`, and it tries four
mechanisms in order:

1. a reflink — `ioctl(out_fd, FICLONE, in_fd)` on Linux
   (`copy_stubs.c:144`), `clonefile()` on macOS (`copy_stubs.c:80`) —
   reached from `copy.ml:424` via `Fs.clone_file`;
2. **`syscall(__NR_copy_file_range, …)`** — issued through the raw
   `syscall` entry point, `copy_stubs.c:199`;
3. **`sendfile`** (`copy_stubs.c:204`, and again at :260);
4. only then a `read`/`write` loop.

Against the shim's actual export list (`shim/src/linux.zig`, 51 symbols):

| Mechanism | Interposed? |
|---|---|
| `ioctl` (FICLONE) | **no** |
| `syscall` | **no** |
| `copy_file_range` | **no** |
| `sendfile` | **no** |
| `write` / `writev` / `pwrite` | yes |

So on a filesystem where any of the first three succeeds, the bytes of a
copied file reach disk without the shim seeing them: `oracle_missed_operation`,
the same refusal cargo produced. **The mechanism is not the same as
cargo's, and the difference matters for what would fix it.** cargo's
manifest rename is a syscall instruction emitted inline by
rustix/linux-raw-sys, past everything a `LD_PRELOAD` shim can define.
unison calls libc's `syscall(3)` — a real, interposable PLT symbol. The
wall here is therefore a property of *the shim's symbol list*, not of the
target, and that makes it liftable in a way cargo's was not.

Two apparatus options, named as rule 16 requires:

- **(a) Extend the shim** with `ioctl` (filtered to `FICLONE`),
  `copy_file_range`, `sendfile`, and a `syscall` wrapper that dispatches on
  its first argument. This is an engine change of roughly #231's size, and
  it is out of the scope cohort 4 was scheduled with.
- **(b) Choose an operation that never copies.** Deletion propagation and
  in-place renames reach `Os.delete` / `Os.rename`, both interposed. The
  risk is `Stasher.backup`, which runs `` `ByCopying `` on the same path
  (`files.ml:342`, and the other branch at :366) and would re-enter the copy stub; it is controlled by
  unison's own `backup` preferences, so this needs one probe reading, not a
  guess.

**Option (b) is the one worth a probe**, because it costs no engine work
and `preflight.sh visibility` settles it without spending a define. But
rule 16's text is strict — a forecast wall enters only *with* its apparatus
named before the probe — and (b) is a hypothesis about which operation
avoids the wall, not yet a measurement. That is the owner's call, and it is
the single open question on this row.

## Rejections, with the measurement that failed each

**andreafrancia/trash-cli — rule 11/17.** 1 of 12 recent issues answered
inside a week by anyone other than the author. Restricted to bug reports it
does not improve: `#379` +102.0d, `#375` +216.4d, `#376` +38.5d (by a
`NONE`), `#377` and `#378` never answered. Its other rows were promising
and are recorded here so the next scout does not re-derive them: 64 commits
in the window; a genuinely two-step write in `janitor.py` (`persister.persist`
writes the `.trashinfo` first, then `trash_dir.try_trash` moves the file
via `shutil.move` — an orphaned `.trashinfo` is the visible failure); no
`threading`, `subprocess` or `fsync` anywhere in `trashcli/`; and
`RealAtomicWrite.atomic_write` is **not** rename-based —
`os.open(O_WRONLY|O_CREAT|O_EXCL)` + `os.write` + `os.close`
(`fslib/real_fs_operations.py:89`), so its name refers to exclusive
creation, not to content atomicity. Its novelty pre-scan is committed
(`novelty-prescan-trash-cli.txt`, 109 unique issues, nothing of this
shape). **Only rule 11 failed.** Worth revisiting if maintainer
responsiveness changes. Its PyPI release is also stale — 0.24.5.26,
uploaded 2024-05-26 — though rule 2 is satisfied by development activity
rather than by releases.

**pypa/pipx — rules 11/17 and 5.** 2 of 11 answered within a week, and 9 of
the 11 had no reply from anyone but the author. On the `bug` label the
figure is 2 of 5, and one of those two answers came from a `NONE` — another
user, not a maintainer (`#2005`, +6.1d). Rule 5 fails independently: pipx's state is
installed virtualenvs, which are re-creatable from their specs — the same
basis on which `bob` and `proto` were rejected.

**Homebrew/brew — rule 5.** Rule 11 passes (6 of 11, MikeMcQuaid at +0.1h
and +0.4h; brew's tracker carries no bug label, so this figure is
unrestricted and its rows were read by title) and rules 1, 2, 3 pass overwhelmingly. What fails is rule 5: the
Cellar is re-installable from formulae, and the taps are git clones — the
part a user would not want to lose is not what brew stores. The taps also
bring the `child_touched_state_dir` forecast, since brew drives git as a
child process, which is the wall yadm was rejected on.

**CocoaPods/CocoaPods — rule 3.** One author in the six-month window
(amorde, all 25 commits). The Xcode-shaped environment that made it a cost
concern in the first pass is no longer the deciding factor; the rule is.

## What this leaves

**Slot 2 is not filled by a candidate that passes every rule outright.**
unison passes 1–15 with rule 4 grey (a GUI exists, but the Linux release
carries the CLI only) and stops at rule 16, where the wall is real but its
apparatus is nameable. Every other candidate in the pool fails a rule that
no apparatus lifts.

The owner therefore has, as this scout reads it, three shapes of choice —
and none of them is this scout's to make:

1. **Enter unison on apparatus (b)** — an operation chosen to avoid the copy
   stub — and let `preflight.sh visibility` refuse it early if the choice is
   wrong. Cheapest, and the refusal is free.
2. **Enter unison on apparatus (a)** — extend the shim by four symbols.
   Buys a whole class (every tool that copies through `copy_file_range` or
   reflink, which is most modern file-copying tools) and costs an engine
   change before the cohort runs.
3. **Widen the pool.** The measured-cheapest revisits on record remain
   neomutt and calcure, both excluded by the current ruling; beyond them a
   fresh enumeration would be needed, and selection is the owner's gate.

## What this scout did not do

It did not decide the list, write a define, run the engine, or file
anything upstream. Nothing here is labelled blind. Every rejection above
names the measurement that produced it, and the one forecast that decides
the survivor is marked as a forecast with the probe step that settles it.
