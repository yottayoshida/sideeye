# Cohort 4 — the scout's candidate rows

Produced against `SCOUT-BRIEF.md`, for the slate the owner signed off on
2026-08-22 (himalaya + vdirsyncer, two targets, no exception clause).

**This is not a decision.** It is the measured conformance of the two
targets on that slate, plus the rejection those measurements produce. The
owner's sign-off on the final list closes the step (`PREP.md` §9, step 5),
and one of the measurements below is a reason to reopen it.

**Provenance: assisted, and named.** What was read: both repositories'
public sources, their GitHub metadata through the REST API, their issue
trackers through the Search API (novelty pre-scan) and the REST API (rule
11 receipts), the `io-maildir` crate as published on crates.io, and the
host's CPython `tempfile` module. **Neither target was executed.** No
failure of either target was observed in execution, no traces of one were
read, and no crash surgery was performed — the criterion-1 provenance line
(`SCOUT-BRIEF.md`) is intact. Reading the tracker is reading reports, which
the criterion permits and which this file records rather than hides.

## What was measured, and where the transcript is

| Measurement | Command | Transcript |
|---|---|---|
| Novelty pre-scan, himalaya | `sh spike/cohort4/novelty-prescan.sh pimalaya/himalaya` | `novelty-prescan-himalaya.txt` |
| Novelty pre-scan, vdirsyncer | `sh spike/cohort4/novelty-prescan.sh pimutils/vdirsyncer` | `novelty-prescan-vdirsyncer.txt` |
| Rule 11/17 receipts | `python3 spike/cohort4/rule11-receipts.py <owner/repo> 12` | `rule11-himalaya.txt`, `rule11-vdirsyncer.txt` |
| Write paths, both | `sh spike/cohort4/write-path-evidence.sh <workdir>` | `write-path-evidence.txt` |
| Stars, pushes, releases, contributors | `gh api repos/<owner/repo>` and `.../releases`, `.../contributors` | inline below |
| Commit activity in the 6-month window | `gh api --paginate "repos/<r>/commits?since=2026-02-23T00:00:00Z&per_page=100"` | inline below |

Two notes on how to read those numbers, both measured rather than assumed:

- The commit counts are **paginated**. A single `per_page=100` page answered
  `100` for himalaya, which is a page cap and not a count; the paginated
  figure is 184. A number taken off one page would have understated it and
  looked precise doing so.
- The novelty pre-scan **cannot prove absence** (`novelty-prescan.sh`'s own
  header). Both scans ran their controls green — `psf/black + disk` returned
  30 hits containing both known issues, the nonsense token returned 0 — and
  neither scan saturated on any of its 51 terms, so the counts below are
  counts. A clean scan still only asserts *not already known*.

## Candidate row — himalaya

| Field | Value |
|---|---|
| Repository | `pimalaya/himalaya`, Rust, Apache-2.0 |
| Version read | **v2.1.0**, tag `ca88bee`, published 2026-08-16 (`gh api repos/pimalaya/himalaya/releases/latest`) |
| Operation proposed | **`himalaya maildir messages copy -m <src> -t <dst> <id>`** — one message file copied into another Maildir |
| Stars | 7,079 |
| Last push | 2026-08-16T19:58:59Z |
| Releases | v2.1.0 2026-08-16, v2.0.0 2026-07-26, v1.2.0 2026-02-19, v1.1.0 2025-01-11, v1.0.0 2024-12-09 |
| Commits in the 6-month window | **184**, by 8 authors: soywod 174, andrewfurman 3, Bowen951209 2, then yobert / metrovoc / knownasnaffy / a-stevan / 4paulpak at 1 each |
| Contributors, all time | soywod 1057, prmadev 26, KoviRobi 7, TornaxO7 6, AckslD 5, remche 4, toastal 4, andrewfurman 3 |

**State root and shapes.** A Maildir tree: `<root>/<folder>/{tmp,new,cur}/`,
one plain file per message, flags encoded in the filename's `:2,` suffix.
Ordinary files in a directory tree — no database, no own transaction engine.

**Non-interactive mutating commands.** The `maildir` subcommand tree carries
`messages save`, `messages copy`, `messages move`, `flags add|set|remove`,
`create`, `delete`, `rename`, `list` (`src/maildir/cli.rs`, which sets
`rename_all = "kebab-case"`, so the `Messages` variant spells `messages`;
`msgs` and `msg` are its aliases and there is no singular `message` form).
`messages copy` takes its ids positionally and both Maildirs as `-m/--maildir`
and `-t/--target` (`src/maildir/arg.rs`); it prints one line on success and
nothing on its path prompts.

**Write path.** All Maildir I/O goes through `io-maildir` 0.3.0, pinned in
`Cargo.lock` with checksum `b02306d3…c060d`. The crate was fetched from
crates.io and **its SHA-256 matched that checksum**, so the source read is
the source that gets built (`write-path-evidence.txt`). Its driver
(`src/client.rs`) imports `use std::{fs, io, path::Path, process, thread, …}`
and issues `fs::write`, `fs::rename`, `fs::copy`, `fs::remove_file`,
`fs::create_dir_all`, `fs::remove_dir_all`. **`sync_all` / `sync_data` /
`fsync` occur 0 times in the crate**; the control for that zero is in the
same run — `fs::rename` occurs, so the grep was capable of matching.

**Wall forecast (rule 16): one arm has a wall, the other arms do not, and
the wall costs one symbol to lift.** This row was wrong in the first draft
of this file, which read "no wall predicted" from `std::fs` alone. `std::fs`
is not one routing decision; it is several.

Start with what is not a wall. cargo's refusal is a *routing* wall, not a
Rust one — `docs/target-classes.md` records its manifest rename as a raw
syscall while the binary imports libc `rename`, and rustfmt, also Rust,
gave the class its first clean verdict. himalaya's `fs::rename`, `fs::write`
and `fs::remove_file` all route through libc, and the `Cargo.lock` reverse
lookup shows `rustix` reaching the binary only through `crossterm`,
`gethostname`, `tempfile` and `terminal_size` — **none on the Maildir write
path**. Read-only rustix is already tolerated (the omamori precedent). Those
arms are visible.

**`fs::copy` is the exception, and it is the arm this row proposes to
measure.** On Linux `std::fs::copy` has no body of its own: it opens both
files and calls `io::copy`
(`library/std/src/sys/fs/unix.rs:2393`), which specialises into the kernel
copy path and tries **`copy_file_range`, then `sendfile`, then a read/write
loop** (`library/std/src/sys/io/kernel_copy/linux.rs:210-251`). Against the
shim's export list (`shim/src/linux.zig`, 52 symbols) neither
`copy_file_range` nor `sendfile` nor `ioctl` nor `syscall` is interposed,
while `write`, `writev` and `pwrite` are. **So as the engine stands, the
bytes of a copied message reach disk unseen: `oracle_missed_operation`.**

The apparatus, named as rule 16 requires, is **one exported symbol**. std
calls `copy_file_range` through its `syscall!` macro, whose implementation
carries the decisive comment
(`library/std/src/sys/pal/unix/weak/syscall.rs`):

    // Use a weak symbol from libc when possible, allowing `LD_PRELOAD`
    // interposition, but if it's not found just use a raw syscall.

The weak lookup runs first, glibc has provided `copy_file_range` since 2.27
(Ubuntu 22.04 ships 2.35), and `dlsym`'s global search order finds a
preloaded definition before libc's. **Exporting `copy_file_range` from the
shim therefore captures this call**, which is precisely what cargo's inline
syscall instruction made impossible. Adding `sendfile` as well covers the
second fallback.

Two ways forward, both legal under rule 16 and both cheap:

- **Extend the shim by one symbol** (`copy_file_range`, plus `sendfile` for
  insurance) and measure `messages copy` as proposed. `preflight.sh
  visibility` confirms the capture before a define is spent.
- **Measure a different arm.** `messages save` (`fs::write` + `fs::rename`)
  and `messages move` / `flags *` (`fs::rename`) touch only interposed
  symbols and need no engine change — at the cost of the interior, since
  those are the papis shape.

This is a forecast in both directions and `preflight.sh visibility` is what
settles it.

**Threads (rule 10).** `io-maildir` spawns threads in exactly one place:
`read_entries_par`, via `thread::scope` and `available_parallelism`
(`src/client.rs:468,475`). That function is **read-only**, and himalaya
calls the non-parallel `read_entries` from two listing sites in
`src/maildir/backend.rs` only. `messages copy` runs `resolve_maildir` then
`client.copy` per id and does not reach it. Forecast: single-threaded on
the measured path — **to be confirmed by probe, because the refusal is
decided by the call site, not by the function's character**.

**Interior forecast (rule 15): present, and this is why this operation was
chosen over the others.** The arms differ in atomicity, and only one has an
interior:

- `messages copy` → `entry/copy.rs` mints a fresh Maildir id, builds the
  **final** target path with `build_target_path`, and yields a single
  `WantsCopy`, which the driver serves with `fs::copy(from, to)`. There is
  no staging file. `fs::copy` opens the destination and fills it, so a kill
  inside it leaves **a partial message at its final path in `cur/` or
  `new/`** — visible to any reader of the Maildir.
- `messages save` → `entry/store.rs`, documented as "write to `/tmp`, atomic
  rename into target". A kill leaves a partial file in `tmp/`, which Maildir
  treats as garbage to be swept; the final path never sees it.
- `messages move`, `flags add|set|remove` → a single `fs::rename`.

`save`, `move` and the flag commands are the papis shape — one atomic
mutation, a contrast measurement rather than a criterion-1 slot, which
`SCOUT-BRIEF.md` rule 15 exists to keep out. `copy` is not that shape.

**Determinism forecast, and the apparatus it needs.** Every new file
`io-maildir` creates is named by `mint_id`, which formats
`{secs}.#{counter:x}M{nanos}P{pid}.{hostname}` (`src/entry.rs:53-56`). Three
of those four inputs are fixable in the image: `secs`/`nanos` are wall clock
(faketime), `counter` is a process-local `AtomicU32` starting from zero in a
fresh process (`src/entry.rs:45`), and `hostname` comes from the `gethostname` crate and is
fixed by the container. **`pid` is not**: the driver answers `WantsPid` with
`process::id()` (`src/client.rs:239`), so two runs of the same command
produce different filenames and a baseline comparison splits structurally.
This is a determinism hazard of the same class as watson's
`baseline_violates_invariant`, and it must be lifted by apparatus named
before the probe — a `getpid` interposer via `ld.so.preload`, which works
here for the same reason the shim does: the call is routed through libc.
Named as a forecast; the probe is what confirms the interposer holds.

**Novelty pre-scan (rule 14): clears.** 51 terms, controls green, 0
saturated, 132 unique issues surfaced. Reading: **no issue describes this
write shape** — a copy landing partially at its final Maildir path, or any
crash-consistency defect in the Maildir writer. The nearest hits are
elsewhere in the tool: `#711` corrupts binary *attachments* on download
(an encoding defect, not a crash), `#59` asks to save an email *on error*
(a feature), the rest are UI, IMAP and parsing. Veto does not apply.

**Rule 11/17 receipts** (`rule11-himalaya.txt`, 12 most recent issues, PRs
excluded). 8 of 12 answered within a week by someone other than the author,
every responder `soywod` with `author_association=MEMBER`. Restricted to
**bug reports** as rule 17 requires — `#736`, `#732`, `#731`, `#730`,
`#729`, `#727`, `#726`, `#722` — the figure is 6 of 8 within a week
(`#727` never answered, `#726` answered at +11.4d). Fastest +0.1h, slowest
answered bug +11.4d.

**Checker sketch.** After a killed `messages copy`, the target's own reader
is the checker — but **it is not in the `maildir` subtree**. That subtree
carries only Save, Copy and Move (`src/maildir/message/cli.rs`), and its own
doc comment says rendering content "is the job of the shared `messages` and
`envelopes` commands". So the checker is the **top-level, backend-agnostic**
pair reaching the same Maildir through the account's backend:
`himalaya message read <id>` (`MessageCommand::Read`,
`src/shared/message/cli.rs:47`) and `himalaya envelope list`
(`src/shared/envelope/cli.rs:21`, visible alias `ls`).
This strengthens rule 9 rather than weakening it: the reader is a different
code path from the writer, so the checker is not asserting with the same
function that produced the state. Documented recovery step preceding the assert: **none is
documented for Maildir in himalaya's docs** — which is itself the honest
answer to that column, and it means the checker asserts on the state as
left, with no repair step to run first. The invariant candidate: every file
in `new/` and `cur/` parses as a message and the target folder's envelope
list does not error.

## Candidate row — vdirsyncer

| Field | Value |
|---|---|
| Repository | `pimutils/vdirsyncer`, Python, license `NOASSERTION` on the API (BSD-3-Clause in `LICENSE`) |
| Version | newest tag **v0.20.0**; PyPI 0.20.0 uploaded **2025-08-28** |
| Operation that would be proposed | `vdirsyncer sync` writing into a `filesystem` storage |
| Stars | 1,862 |
| Last push | 2026-08-20T09:18:17Z |
| GitHub Releases | **one, `0.16.8`, 2020-06-09** — the release list stopped being used; tags continued |
| Commits in the 6-month window | **3** — "fix typos in comment" (2026-08-15), "docs/tutorial: fix grammar" (2026-07-01), "Refresh SourceHut CI manifests" (2026-04-07) |
| Authors in that window | 1 (`bernardotorres`, 1 commit; the other 2 carry no GitHub author) |
| Contributors, all time | untitaker 1867, WhyNotHugo 135, pre-commit-ci[bot] 39, homu 15, t-8ch 13, geier 12, samm81 11, bernhardreiter 9 |

**State root and shapes.** A vdir: a directory of `.ics` / `.vcf` text
files, one item each. Sync state lives separately in
`~/.vdirsyncer/status/`, and it is **SQLite** (`sync/status.py:111`,
`sqlite3.connect`). Rule 7 reads on the *main* store, which is the vdir, so
this is not a rule-7 failure — but the engine's observation range would
include SQLite's own writes, which is worth naming before a probe.

**Write path.** Every local write goes through one helper,
`utils.py:atomic_write`, and the `overwrite` flag decides its shape:

- `overwrite=False` (used by `filesystem.py:_upload_impl`, i.e. new items):
  `tempfile.mkstemp` → write → `os.link(src, dest)` → `os.unlink(src)`.
  **Two mutating syscalls after the write** — an interior.
- `overwrite=True` (used by `update`, `set_meta`, `singlefile`,
  `cli/utils.py` status writes): `tempfile.mkstemp` → write → `os.rename`.
  The papis shape.

There is **no fsync on this path**. The one `os.fsync` in the package
(`utils.py:62`) is inside `get_etag_from_file` and guarded by
`sys.platform == "win32"`.

**Wall forecast (rule 16): the `mkstemp` row does not apply here, and that
matters.** `PREP.md` §3F and `SCOUT-BRIEF.md` record `mkstemp` + write +
rename as reaching cargo's wall, measured 2026-08-22 on a C toy: `mkstemp(3)`
opens from inside libc, past the PLT, so the interposer records no `open`.
**CPython's `tempfile.mkstemp` is not that function.** It is pure Python —
`inspect.getsourcefile(tempfile)` returns a `.py`, and `_mkstemp_inner`
generates candidate names in a Python loop and calls `_os.open(file, flags,
0o600)`. The `openat` is issued by the program, not from inside libc, so an
interposer sees it. Matching the wall on the *name* `mkstemp` would have
rejected this candidate for a property it does not have. **Not settled
here**: this was read on the host's CPython 3.14.7; the image's interpreter
is what `preflight.sh visibility` must confirm.

**Threads (rule 10).** `threading` appears twice: a lazily imported `Lock`
in `utils.py:166`, and `Thread` in `storage/google.py` for the OAuth
callback server. Neither is on a filesystem-to-filesystem sync. There is no
`run_in_executor`, `to_thread` or thread pool in the package. The CLI runs
on `asyncio.run`. Forecast: single-threaded on the measured path, to be
confirmed by probe — `aiohttp` is imported on paths that do not need it
(see below), and its resolver is the usual source of a surprise thread.

**Interior forecast (rule 15): present** — the `os.link` + `os.unlink` pair
on the upload path. A kill between them leaves the destination correct and
the temp file still present in the vdir, i.e. a second file for the same
item. Whether that counts as damage or as litter is a checker-design
question, and it is weaker than himalaya's partial-message-at-final-path.

**Novelty pre-scan (rule 14): clears.** 51 terms, controls green, 0
saturated, 190 unique issues. Reading: **no issue describes this write
shape**. `#70` ("Singlefile storage corrupts vcards", 2014) is a different
backend; `#552` is an error-message complaint about an already-corrupt
token file. Veto does not apply.

**Rule 11/17 receipts** (`rule11-vdirsyncer.txt`, 12 most recent issues,
PRs excluded). 4 of 12 answered within a week by someone other than the
author. **Rule 17 says to measure this on bug reports specifically, and
doing so changes the picture rather than refining it.** Of the 12, six are
bug reports — `#1223`, `#1222`, `#1212`, `#1209`, `#1208`, `#1207` — and
**one of the six** was answered within a week (`#1209`, +2.6h, WhyNotHugo,
MEMBER). Three received no comment from anyone but the author (`#1223`,
`#1222`, `#1212`, the last one closed without a reply), and `#1208` was
answered at **+106.2d by `author_association=NONE`** — another user, not a
maintainer. The four quick answers in the unrestricted figure are
documentation requests and a version question. The distinction rule 17
draws is exactly the one that separates them.

**Checker sketch, and a problem with it.** The obvious checker is
`vdirsyncer repair <collection>` followed by a re-read — but **`repair`
calls `click.confirm("Do you want to continue?", abort=True)`**
(`cli/__init__.py:268`) and so does not run non-interactively. This is the
papis-doctor shape from cohort 3, where the intended checker was rejected
by an argument-less invocation and never ran once. A checker for this
target would have to be built from `vdirsyncer sync`'s own re-read instead,
and rule 9 ("a checker can be written using the target itself") should be
re-argued on that basis, not assumed from `repair`'s existence.

## Rule-by-rule

Conjunctive: all must hold.

| Rule | himalaya | vdirsyncer |
|---|---|---|
| 1 ≥1,000 stars | PASS 7,079 | PASS 1,862 |
| 2 release or substantive development ≤6 months | PASS v2.1.0 2026-08-16; 184 commits | **FAIL** last release 2025-08-28 (~12 months); **3 commits**, all typo / grammar / CI |
| 3 multiple sustained contributors | **GREY** 8 authors in window, but 174 of 184 are one person | **FAIL** 1 author in window |
| 4 CLI is the primary interface | PASS | PASS |
| 5 stores primary data locally | PASS Maildir | PASS vdir |
| 6 plain files / directory tree | PASS | PASS |
| 7 no SQLite/embedded DB as main store | PASS | PASS for the vdir; sync status *is* SQLite |
| 8 non-interactive mutating commands | PASS | PASS for `sync`; **not** for `repair` |
| 9 checker writable with the target itself | PASS — top-level `message read` / `envelope list`, a different path from the writer | **UNRESOLVED** — `repair` is interactive; needs re-argument |
| 10 dynamic linking, single-threaded-ish | forecast PASS, probe decides | forecast PASS, probe decides |
| 11 / 17 bug reports answered ≤1 week | PASS 6 of 8 bug reports | **FAIL** 1 of 6 bug reports |
| 12 currently used, not legacy-only | PASS | used, but development is near-stopped |
| 13 language diversity across the cohort | — cohort-level, see below | — |
| 14 novelty pre-scan clears | PASS | PASS |
| 15 interior forecast | PASS, `fs::copy` at the final path | PASS, `link`+`unlink`, weaker |
| 16 wall forecast with apparatus named | **CONDITIONAL** — the `fs::copy` arm is unseen today (`copy_file_range` not interposed); apparatus is one exported symbol, other arms are clean | PASS, `mkstemp` row does not apply |

## The rejection this produces

**vdirsyncer fails rules 2, 3 and 11/17 as measured**, and leaves rules 8
and 9 unresolved for the command a checker would use. The rules are
conjunctive, so on the text of `SCOUT-BRIEF.md` it does not enter.

The measurement that matters most is the cheapest one: three commits in six
months, none of them substantive, and one bug report in six answered inside
a week. Rules 2, 3, 11 and 12 exist together to keep the cohort off
projects nobody is maintaining, because a null result there says something
about the project rather than about crash-consistency.

This scout does not act on that. **The slate was signed off by the owner on
2026-08-22, and only the owner reopens it.** What the sign-off did not have
in front of it is the table above; the funnel that produced the slate
rejected 22 of its candidates with zero fetches (`PREP.md` §3, the E4
finding), and this row is what a fetch produces.

Two consequences the owner will want in view:

1. Dropping vdirsyncer leaves **one target**, and rule 13 forbids a
   single-language slate. A replacement is needed, not just a deletion.
2. `CANDIDATES-REJECTED.md` records that **neomutt and calcure are the only
   two candidates rejected on a reading of words rather than a
   measurement**, and names each one's remaining question as cheap
   (neomutt: does batch send write to the maildir; calcure: one wiki page).
   If a slot opens, those are the measured-cheapest revisits on record.

## Image pin data

For the freeze, independent of how the slate resolves:

- **himalaya v2.1.0** is confirmed newest (`releases/latest` → `v2.1.0`,
  2026-08-16). Self-build remains required: the project's Linux binaries are
  cross-built through nix and are musl-static, which is `no_shim_marker`.
- **vdirsyncer 0.20.0** on PyPI, uploaded 2025-08-28:
  `vdirsyncer-0.20.0-py3-none-any.whl` (61,423 bytes) and
  `vdirsyncer-0.20.0.tar.gz` (126,633 bytes), `requires_python >=3.8`.
  Runtime dependencies: `click<9.0,>=5.0`, `click-log<0.5.0,>=0.3.0`,
  `requests>=2.20.0`, `aiohttp<4.0.0,>=3.8.2`, `aiostream<0.8.0,>=0.4.3`.
  The one habit worth knowing: **`aiohttp` is a hard runtime dependency and
  is imported on command paths that never touch the network** — `repair`
  constructs an `aiohttp.TCPConnector` before doing anything, including for
  a purely local collection.

## What this scout did not do

It did not decide the list, write a define, run the engine, or file
anything upstream. Nothing here is labelled blind. Every belief above is
either a measurement with its command named, or a forecast explicitly
marked as one with the probe step that falsifies it.
