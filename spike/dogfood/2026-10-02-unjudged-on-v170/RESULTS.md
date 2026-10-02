# Results — 2026-10-02 unjudged-on-v170

The released v1.7.0 on the 28 targets no campaign had carried to a verdict, and on three newer
releases the morning's run left unmeasured: 31 rows (`LEDGER.md`), 33 defines (zstd in two
forms, one revision). Each row was run two ways in one box — the page's path (`run.sh`) and
every observation mode by name (`modes.sh`).

**Under the page's path v1.7.0 judges 12 of the 31 rows: 9 FAIL and 3 PASS.** PHP CS Fixer is
one row and one of the nine: run bare it PASSes over a run that never wrote the PHP file, and
with its rules named it FAILs. Under the modes asked for by name it judges 13 (lefthook joins
under supervised). The other 18 rows stand behind the walls the earlier engines named — ten of
them one wall, two writing threads of one process. 9 + 3 + 1 + 18 = 31.

The four A rows are verdicts this project had not seen. For the D rows none is: what is new is
that a **released** engine reaches them — as far as `spike/outcome-funnel.tsv` and
`docs/target-classes.md` record, which is where this run looked. The three PASSes on static
images judge little (below the table). mutool FAILs
under syscalls — `a.pdf` gone between the `unlink` and the `open` — as an unreleased build
measured on 2026-09-08; the three static images PASS under supervised, as the unreleased
2026-09-27 build said; metaflac and fontforge reach the verdicts of 2026-09-07. Three of the
nine FAILs were reported upstream (below).

Every FAIL replayed twice and reproduced; every PASS and FAIL `oracle_verified`. All 33 under
all three modes: `transcripts/modes/*/summary.txt`; the page's path: `transcripts/page/`.
Versions: `transcripts/versions.txt`.

## The 31 rows

"Page" is what `run.sh` ended on — the default mode, or the mode a refusal's own next step named
and the script followed (`[s]` syscalls, `[sv]` supervised). The three modes are `modes.sh`.

| Row | Page | wrappers | syscalls | supervised | Where (page), before → done; crashed |
|---|---|---|---|---|---|
| **A: cleared the 2026-09-22 gate** | | | | | |
| git-cliff 2.14.2 `--prepend` | **FAIL** 1/3 | FAIL | FAIL | FAIL | `CHANGELOG.md`, open → write, 52 → 143; **0** |
| js-beautify 2.0.3 `-r` | **FAIL** 1/4 | FAIL | FAIL | FAIL | `a.js`, open → write (3 ops), 41 → 70; **0** |
| ktlint 1.8.0 `-F` | **FAIL** 1/3 | FAIL | FAIL | FAIL | `Main.kt`, open → write, 25 → 32; **0** |
| ormolu 0.7.2.0 `--mode inplace` | **FAIL** 1/4 | FAIL | FAIL | FAIL | `A.hs`, truncate → write, 23 → 28; **0** |
| **B: newer releases** | | | | | |
| oxfmt 0.71.0 | **FAIL** 1/3 | FAIL | FAIL | FAIL | `a.js`, open → write, 48 → 60; **0** — as 0.70.0 |
| pg_format v5.11 (upstream) | **FAIL** 1/3 | FAIL | FAIL | FAIL | `a.sql`, open → write, 29 → 49; **0** — as Debian's 5.6 |
| PHP CS Fixer 3.95.27, its own phar | PASS 5/5 | PASS | PASS | PASS | **`a.php` never written**: with no config file it asks whether to create one, writes `.php-cs-fixer.dist.php` and `.gitignore`, and never opens `a.php` for writing (below) |
| … revision 1, `--rules=@PSR12 --no-interaction` | **FAIL** 1/7 | FAIL | FAIL | FAIL | `a.php`, open → write, 39 → 45; **0** — as the v3.95.25 inside pint |
| **D: refused by an earlier engine** | | | | | |
| chezmoi 2.72.1 `apply --force` | **PASS** 6/6 [sv] | `no_shim_marker` | `no_shim_marker` | PASS | the image named by path, so the bare-name sentence did not apply. **Judges no path** (`0 path(s) judged`): the destination starts empty and the built-in rule judges only a file present before and after |
| gopass 1.17.0 `rm -f` | **PASS** 4/4 [sv] | `no_shim_marker` | `no_shim_marker` | PASS | the same; judges one path, `.age-recipients`, which `rm` leaves alone |
| lefthook 1.13.6 `install` | UNKNOWN `oracle_missed_operation` [s] | `oracle_missed_operation` | `oracle_missed_operation` | **PASS** 5/5 | the page's path follows to syscalls, which refuses with no mode named; only the mode asked for by name reaches supervised. Judges the 14 `*.sample` hooks git put there, not a file lefthook wrote |
| joplin 3.7.1 `mknote` | UNKNOWN `multiple_threads_detected` | same | same | same | the fourth campaign to meet this wall on joplin |
| Bitwarden CLI 2026.8.0 `config server` | UNKNOWN `multiple_threads_detected` | same | same | same | |
| beets 2.1.0 `import` | UNKNOWN `multiple_threads_detected` | same | same | same | |
| zstd 1.5.7 `--rm` (two defines) | UNKNOWN `multiple_threads_detected` [s] | `oracle_missed_operation` | `multiple_threads_detected` | `multiple_threads_detected` | an `open` on one thread and a `write` on another |
| lz4 1.10.0 `-T2 --rm` | UNKNOWN `multiple_threads_detected` [s] | `oracle_missed_operation` | `multiple_threads_detected` | `multiple_threads_detected` | two `write`s on two threads |
| prettier 3.9.7 `--write` | UNKNOWN `multiple_threads_detected` | same | same | same | |
| svgo 4.1.0 | UNKNOWN `multiple_threads_detected` | same | same | same | |
| npm 9.2.0 `pkg set` | UNKNOWN `multiple_threads_detected` | same | same | same | |
| eslint 10.11.0 `--fix` | UNKNOWN `multiple_threads_detected` | same | same | same | |
| stylelint 17.15.0 `--fix` | UNKNOWN `multiple_threads_detected` | same | same | same | |
| metaflac 1.5.0 `--set-tag` | **PASS** 13/13 [s] | `oracle_missed_operation` | PASS | PASS | as 2026-09-07's unreleased build |
| fontforge 20230101 `Generate` | **FAIL** 183/185 [s] | `oracle_missed_operation` | FAIL | FAIL | `f.ttf`, open → write, 759,720 → 743,316; **0** — as 2026-09-07 |
| mutool 1.25.1 `clean a.pdf a.pdf` | **FAIL** 2/4 [s] | `oracle_missed_operation` | FAIL | FAIL | **`a.pdf` gone**: `unlink` → `open(O_CREAT\|O_EXCL)`, 537 → 563; crashed between them, no file. As the unreleased build of 2026-09-08 (16 of 16); the first on a release |
| ocrmypdf 16.7.0 `--force-ocr` | UNKNOWN `baseline_violates_invariant` | same | same | same | the output differs between two clean runs |
| bat 0.25.0 `cache --build` | UNKNOWN `baseline_violates_invariant` | same | same | same | `metadata.yaml`, with the clock pinned |
| meson 1.7.0 `setup --reconfigure` | UNKNOWN `baseline_violates_invariant` | same | same | same | |
| ccache 4.11.2 | UNKNOWN `kill_did_not_land` | same | same | same | |
| fish 4.0.2 `set -U` | UNKNOWN `unsupported_syscall_observed` | same | same | same | `inotify_add_watch` |
| vim 9.1 `-es … wq` | UNKNOWN `unsupported_syscall_observed` | same | same | same | `getxattr` |
| rrdtool 1.7.2 `update` | UNKNOWN `unsupported_syscall_observed` | same | same | same | `mmap(PROT_WRITE\|MAP_SHARED)` |
| git 2.47.3 `commit` with auto-maintenance | UNKNOWN `child_touched_state_dir` | same | same | same | the detached `gc` writes `.git/gc.pid.lock` while the parent is still writing; supervised orders a child that leaves the group, not two writers at once |

Sizes are each FAIL's evidence bundle (`transcripts/page/<t>/*.evidence.md`); `old_bytes_elsewhere`
is `no` for the rewritten file in every one of the nine.

**What the three static PASSes are.** As on 2026-09-27, each is a PASS over files the tool did
not write: chezmoi's judges no path at all, gopass's one file its `rm` does not touch,
lefthook's the sample hooks. They say supervised reaches a verdict on these images on a release,
not that their writes survive a crash — that needs a checker, and lefthook's 2026-09-21 checker
was found not falsifiable on 2026-09-27. chezmoi was run twice under supervised here (once on
each path); on 2026-09-27 one of five preflights of this form refused
`multiple_threads_detected`, and two runs do not say that is gone.

### The same without a kill

Each FAIL's operation run once under `ulimit -f 0` — output through a pipe, the file compared
byte for byte with a copy taken before (`apparatus/ulimit.sh`, `transcripts/probes/ulimit.txt`):

| Target | Result |
|---|---|
| git-cliff, js-beautify, ktlint, ormolu, oxfmt 0.71.0, pg_format v5.11, PHP CS Fixer r1, **mutool** | **0 bytes**, not the bytes it had before |
| fontforge | **not reproduced this way**: the bytes it had before, exit 153 — the limit kills it writing its script argument to an `O_TMPFILE` under `/tmp`, before `f.ttf` is opened (`transcripts/probes/write-paths.txt`) |

The limit lands on the first regular-file write past zero bytes, which for a tool that writes
something else first (fontforge here, pint this morning) is not the target. The FAIL stands on
the kill.

## Against the prediction

`PREDICTION.md`, committed as `6a631ed` at 07:48:14Z; the first explore started at 07:48:29Z
(`transcripts/page/first-explore-started.txt`), the last nine after `110c92f`. Thirty-two defines
(zstd's two counted apart, the PHP CS Fixer revision not counted) predicted under the page's
path and under supervised: **26 as predicted, 6 not** (`transcripts/prediction-check.txt`):

- **php-cs-fixer** — predicted FAIL, is PASS, because it did not write the PHP file. The prediction read the
  writer and not the way in. Revision 1 FAILs as predicted for the writer.
- **chezmoi, gopass** — predicted UNKNOWN under the page's path because "the bare name is
  refused with no mode named"; the 2026-09-27 defines these were copied from name the image by
  path, so the detail did name supervised and `run.sh` followed it to PASS. The prediction did
  not read the defines it was predicting.
- **lefthook** — predicted UNKNOWN `no_shim_marker`; is UNKNOWN `oracle_missed_operation`,
  because its first refusal under wrappers names syscalls (the 2026-09-21 wall) and `run.sh`
  follows that one, which then refuses with no mode named. Supervised, asked for by name, PASSes
  as predicted. A user on the page's path never learns that.
- **mutool** — predicted UNKNOWN `unresolvable_path` in every mode, "sure". Judged under
  syscalls and FAILs — **and the record said it would**: `docs/target-classes.md`'s mutool row
  ends with the fix of 2026-09-08 (an unplaceable `close` is no ground for refusal) and the same
  FAIL, 16 of 16, on that day's build. The prediction was written from the head of that row and
  from the funnel, which holds only the 2026-09-06 refusal because the 2026-09-08 measurement
  was not a campaign. This record's first draft then called today's FAIL the first verdict on
  the target; it is the first on a released engine.
- **git** — predicted "may be judged under supervised"; is not. Supervised orders a child that
  leaves the process group; git's detached maintenance child writes `.git/gc.pid.lock` while the
  parent is still writing, two processes at once, which no mode orders.

Five of the six misses are the predictor not reading what was on record — the defines, the
writer's way in, a row to its end; one (git) is a guess about a mode that did not hold. Twenty-six hits
over rows marked "sure" is what the record said it would be, and says little.

## What stands, by wall

| Wall | Rows | Moved by v1.7.0? |
|---|---|---|
| two writing threads, no join the shim sees | 10 rows, 11 defines (joplin, Bitwarden, beets, zstd ×2, lz4, prettier, svgo, npm, eslint, stylelint) | no, in any mode — Node's libuv pool, a compressor's workers, Python's pipeline siblings |
| output not byte-repeatable | 3 (ocrmypdf, bat, meson) | no — a property of the target |
| a syscall the shim does not interpose | 3 (fish, vim, rrdtool) | no |
| two processes writing at once | 1 (git) | no — supervised is for a child that leaves, not one that overlaps |
| the kill not landing where recorded | 1 (ccache) | no |
| static image, bare name on the page's path | 0 here — but lefthook's path shows the shape: a refusal that does not name supervised is followed somewhere else | — |
| static image | 3 (chezmoi, gopass, lefthook) | **yes**, supervised, as 2026-09-27 found on an unreleased build |
| a write past the flush boundary | 2 (metaflac, fontforge) | **yes**, syscalls, as 2026-09-07 found on an unreleased build |
| an operation on an unlinked path | 1 (mutool) | **yes**, syscalls, as 2026-09-08 found on an unreleased build |

## mutool at the latest release

The box's mutool is Debian's 1.25.1; the latest is 1.28.5, and 1.27.0 dropped `O_EXCL` from the
re-creating open on Linux. Built from the project's source tarball (sha256 `98a5c10c…`,
`transcripts/mutool-1285-build.txt`). The prediction (`PREDICTION-mutool-latest.md`) is commit
`b97de04`, 11:30:26Z; the image that carries the built mutool was created at 11:31:15Z
(`transcripts/probes/host.txt`). **FAIL 2 of 4 at the same point, replayed twice**
(`transcripts/page/mutool-1285/`). Without Sideeye, both versions side by side
(`apparatus/mutool-latest.sh`, `transcripts/probes/mutool-latest.txt`): 1.25.1 shows `unlinkat`,
`openat(O_RDWR|O_CREAT|O_EXCL|O_TRUNC)`, `write`, and 1.28.5 the same without `O_EXCL`; under
`ulimit -f 0` the file is 0 bytes on both; a SIGKILL on entry to the creating `openat` — its
ordinal counted on a copy of the seed, the killed run's own trace kept and ending
`unlinkat … = 0`, `openat(… O_CREAT …) = ?`, `killed by SIGKILL` — leaves the directory without
`a.pdf` on both. All three as predicted. The first version of that script picked the last
`openat` of a counting run that had consumed the seed and kept no trace; its conclusion held and
its method did not, and its output is kept as `transcripts/mutool-latest-first-attempt.txt`.

## Novelty and reporting

Read after the explores (`SELECTION.md`): `transcripts/receipts/after-the-fail.txt`, each writer
line re-read at the commit it names and the two MuPDF bugs re-read through Bugzilla's REST API.
One reading there was wrong and is corrected in the receipts: the agent said MuPDF's bug 701797
introduced the remove-before-open; its reporter's own sentence says the `remove()` was already
there.

No tracker holds a report of this shape for the five whose trackers were read (fontforge's was
not). The owner's ruling, 2026-10-02, on
those receipts — each text shown in full first:

- **ktlint: filed as ktlint/ktlint#3409** (`report-ktlint.md`, posted unchanged). A formatter
  rewriting a working tree, the reason tombi was filed on this morning; 1.8.0 is the latest
  stable; the maintainer answered seven of the last ten issues.
- **git-cliff: filed as orhun/git-cliff#1650** (`report-git-cliff.md`, posted unchanged). The
  report says itself that a changelog is usually committed and what is lost is what was not.
  Its no-kill steps carry one line this run had to find: on a first run in a fresh home
  git-cliff writes an update-check cache file, and under `ulimit -f 0` that write is the one
  that dies — 57 bytes kept, the dying write shown, in the control at the head of
  `transcripts/probes/report-evidence-git-cliff.txt`; 0 bytes once the cache file exists — so
  the steps run it once first (`apparatus/report-evidence.sh`). What ktlint's report quotes,
  the debug lines included, is `transcripts/probes/report-evidence-ktlint.txt`.
- **mutool: to be filed by the owner on Artifex's Bugzilla** (`report-mutool.md`), which is
  where MuPDF takes bugs — the GitHub repository is a mirror with issues off — and which needs
  an account this run does not have. Not in `spike/upstream-reports.tsv` until it has a number.
  The 2026-09-08 row had left this "not reported upstream — the owner's call"; that call is now
  made. What it has that the other formatters do not: the file is gone, not emptied, and it is a
  document, not source.

Not filed:

| Target | Why not |
|---|---|
| js-beautify | a member commented on one of the last ten issues, after 150 days |
| ormolu | measured at Debian's 0.7.2.0 (2023); 0.9.0.0 came out the day before, writes the same way by reading, and has no linux/arm64 asset to measure |
| fontforge | no tracker was read for it, in this run or on 2026-09-07 |
| oxfmt, pg_format, PHP CS Fixer | not new: the newer releases FAIL as the versions the gate-cleared-twelve run measured, and that run's reasons stand. Its three "not measured" are now measured |

## PHP CS Fixer: a PASS over a run that did not write the file

The latest phar, run as `php php-cs-fixer.phar fix a.php` in a directory with no
`.php-cs-fixer.php`, prints "Do you want to create the config file?", writes `.php-cs-fixer.dist.php` and
`.gitignore`, and exits without opening `a.php` for writing (`transcripts/probes/write-paths.txt`;
the explore's 4 crash points are on those two files). The engine judged what the run wrote,
which was not the PHP file. Pint bundles a rule set and never asks, which
is why the morning's pint define wrote. Revision 1 names the rules and turns interaction off;
the same transcript then shows the same `openat(O_WRONLY|O_CREAT|O_TRUNC)` and `write` as pint's v3.95.25,
and the explore FAILs 1 of 7 at the same point. A PASS is a search record over the writes the run
made; a define has to make the target write the thing the question is about.

## Found in passing

- **`run.sh` follows one refusal, and which one depends on which wall is met first.** For a
  static image whose first refusal is `oracle_missed_operation` (lefthook: the shim recorded
  nothing, the oracle saw an `openat`), the next step names syscalls, syscalls refuses the same
  way with no mode named, and the path ends. The same image named by path with a
  `no_shim_marker` first refusal (chezmoi, gopass) is sent to supervised and judged. Which
  refusal a static image gets first was not traced; both are on record here. On `main`, ADR 0090
  changed the bare-name case; whether it changes lefthook's is not measured.
- **`ulimit -f 0` reproduces 8 of the 9 FAILs without an engine**, and the ninth (fontforge)
  dies on a write that is not the target's. Two of this project's "no-crash routes" today (pint,
  fontforge) did not reach the file, which is what makes the kill the measurement and the limit
  a demonstration.
- **The mutool row was read to its first sentence** (above, under the prediction), and the
  reading agent's account of bug 701797 was taken into a report draft before the bug was opened;
  both were caught by opening the source, the second before anything was posted.
- **The first review, and what it changed.** A reader with no context checked about 150
  claims against the transcripts and upstream. Nothing false in the two posted reports. In this
  record: the bare PHP CS Fixer run was called "no write" where it wrote two other files; the
  wall count was 17 where every way of counting gives 18 (one row counted twice); five strace
  readings were cited with no output committed; and the SIGKILL probe chose its `openat` badly.
  The probes were made scripts with their docker commands (`apparatus/probes-host.sh`,
  `write-paths.sh`) and re-run, and `transcripts/probes/` is that run.
- **This run's own first attempts, not all kept**: `ulimit.sh` was first given `mu/a.pdf` and
  `ff/f.ttf` where the state root already ends in `mu`/`ff`, and printed empty sizes; the two
  lines were corrected and the whole script re-run, and that first output was overwritten. The 23 rows ran before the nine (two commits,
  `6a631ed` and `110c92f`), with the prediction unchanged between them.
