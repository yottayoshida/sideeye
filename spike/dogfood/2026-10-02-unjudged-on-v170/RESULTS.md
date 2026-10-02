# Results — 2026-10-02 unjudged-on-v170

The released v1.7.0 on the 28 targets no campaign had carried to a verdict, and on three newer
releases the morning's run left unmeasured: 31 rows (`LEDGER.md`), 33 defines (zstd in two
forms, one revision). Each row was run two ways in one box — the page's path (`run.sh`) and
every observation mode by name (`modes.sh`).

**Under the page's path v1.7.0 judges 13 of the 31 rows: 9 FAIL, 3 PASS, and one PASS over a
run that did not write.** Under the modes asked for by name it judges 14 (lefthook joins under
supervised). The other 17 stand behind the same walls the earlier engines named — eleven of
them one wall, two writing threads of one process. Three things in the table are new to this
project: **mutool is judged for the first time and FAILs** (the window an earlier run read off
`strace` but no engine could enter), the three static images are judged on a released engine
for the first time (PASS, as the unreleased 2026-09-27 build said), and metaflac and fontforge
reach on a released engine the verdicts an unreleased one gave on 2026-09-07.

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
| PHP CS Fixer 3.95.27, its own phar | PASS 4/4 | PASS | PASS | PASS | **over no write**: with no config file it asks whether to create one and never opens `a.php` (below) |
| … revision 1, `--rules=@PSR12 --no-interaction` | **FAIL** 1/7 | FAIL | FAIL | FAIL | `a.php`, open → write, 39 → 45; **0** — as the v3.95.25 inside pint |
| **D: refused by an earlier engine** | | | | | |
| chezmoi 2.72.1 `apply --force` | **PASS** 6/6 [sv] | `no_shim_marker` | `no_shim_marker` | PASS | the image named by path, so the bare-name sentence did not apply |
| gopass 1.17.0 `rm -f` | **PASS** 4/4 [sv] | `no_shim_marker` | `no_shim_marker` | PASS | the same |
| lefthook 1.13.6 `install` | UNKNOWN `oracle_missed_operation` [s] | `oracle_missed_operation` | `oracle_missed_operation` | **PASS** 5/5 | the page's path follows to syscalls, which refuses with no mode named; only the mode asked for by name reaches supervised |
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
| mutool 1.25.1 `clean a.pdf a.pdf` | **FAIL** 2/4 [s] | `oracle_missed_operation` | FAIL | FAIL | **`a.pdf` gone**: `unlink` → `open(O_CREAT\|O_EXCL)`, 537 → 563; crashed between them, no file. The first verdict on this target |
| ocrmypdf 16.7.0 `--force-ocr` | UNKNOWN `baseline_violates_invariant` | same | same | same | the output differs between two clean runs |
| bat 0.25.0 `cache --build` | UNKNOWN `baseline_violates_invariant` | same | same | same | `metadata.yaml`, with the clock pinned |
| meson 1.7.0 `setup --reconfigure` | UNKNOWN `baseline_violates_invariant` | same | same | same | |
| ccache 4.11.2 | UNKNOWN `kill_did_not_land` | same | same | same | |
| fish 4.0.2 `set -U` | UNKNOWN `unsupported_syscall_observed` | same | same | same | `inotify_add_watch` |
| vim 9.1 `-es … wq` | UNKNOWN `unsupported_syscall_observed` | same | same | same | `getxattr` |
| rrdtool 1.7.2 `update` | UNKNOWN `unsupported_syscall_observed` | same | same | same | `mmap(PROT_WRITE\|MAP_SHARED)` |
| git 2.47.3 `commit` with auto-maintenance | UNKNOWN `child_touched_state_dir` | same | same | same | the detached `gc` writes `.git/gc.pid.lock` while the parent is still writing; supervised orders a child that leaves the group, not two writers at once |

Sizes are each FAIL's evidence bundle (`transcripts/page/<t>/*.evidence.md`); `old_bytes_elsewhere`
is `no` in every one of the nine.

### The same without a kill

Each FAIL's operation run once under `ulimit -f 0` — output through a pipe, the file compared
byte for byte with a copy taken before (`apparatus/ulimit.sh`, `transcripts/ulimit.txt`):

| Target | Result |
|---|---|
| git-cliff, js-beautify, ktlint, ormolu, oxfmt 0.71.0, pg_format v5.11, PHP CS Fixer r1, **mutool** | **0 bytes**, not the bytes it had before |
| fontforge | **not reproduced this way**: the bytes it had before, exit 153 — the limit kills it writing its script argument to an `O_TMPFILE` under `/tmp`, before `f.ttf` is opened (`strace` in the transcript's tail) |

The limit lands on the first regular-file write past zero bytes, which for a tool that writes
something else first (fontforge here, pint this morning) is not the target. The FAIL stands on
the kill.

## Against the prediction

`PREDICTION.md`, committed as `6a631ed` at 07:48:14Z; the first explore started at 07:48:3xZ
(`transcripts/page/first-explore-started.txt`), the last nine after `110c92f`. Thirty-two rows
predicted under the page's path and under supervised (zstd's two defines as one): **26 as
predicted, 6 not** (`transcripts/prediction-check.txt`):

- **php-cs-fixer** — predicted FAIL, is PASS, because it did not write. The prediction read the
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
  syscalls and FAILs. The 2026-09-07 follow-up found the unplaceable operation to be a `close`
  on the unlinked descriptor, under both modes of that build; the released v1.7.0 under syscalls
  places everything and judges. Which change between contract v14 and v18 did that was not
  traced here — the engine's history is the place to read it, not this record.
- **git** — predicted "may be judged under supervised"; is not. Supervised orders a child that
  leaves the process group; git's detached maintenance child writes `.git/gc.pid.lock` while the
  parent is still writing, two processes at once, which no mode orders.

Four of the six misses are the predictor reading its records and not the defines or the engine;
two (mutool, git) are the engine doing something other than the record said. Twenty-six hits
over rows marked "sure" is what the record said it would be, and says little.

## What stands, by wall

| Wall | Rows | Moved by v1.7.0? |
|---|---|---|
| two writing threads, no join the shim sees | 11 (joplin, Bitwarden, beets, zstd ×2, lz4, prettier, svgo, npm, eslint, stylelint) | no, in any mode — Node's libuv pool, a compressor's workers, Python's pipeline siblings |
| output not byte-repeatable | 3 (ocrmypdf, bat, meson) | no — a property of the target |
| a syscall the shim does not interpose | 3 (fish, vim, rrdtool) | no |
| two processes writing at once | 1 (git) | no — supervised is for a child that leaves, not one that overlaps |
| the kill not landing where recorded | 1 (ccache) | no |
| static image, bare name on the page's path | 0 here — but lefthook's path shows the shape: a refusal that does not name supervised is followed somewhere else | — |
| static image | 3 (chezmoi, gopass, lefthook) | **yes**, supervised, as 2026-09-27 found on an unreleased build |
| a write past the flush boundary | 2 (metaflac, fontforge) | **yes**, syscalls, as 2026-09-07 found on an unreleased build |
| an operation on an unlinked path | 1 (mutool) | **yes**, syscalls — new |

## PHP CS Fixer: a PASS over no write

The latest phar, run as `php php-cs-fixer.phar fix a.php` in a directory with no
`.php-cs-fixer.php`, prints "Do you want to create the config file?" and exits without opening
`a.php` (`strace`, `transcripts/page/php-cs-fixer/`; 4 crash points, all elsewhere). The engine
judged what the run wrote, which was not the file. Pint bundles a rule set and never asks, which
is why the morning's pint define wrote. Revision 1 names the rules and turns interaction off;
`strace` then shows the same `openat(O_WRONLY|O_CREAT|O_TRUNC)` and `write` as pint's v3.95.25,
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
- **This run's own first attempts, kept**: `ulimit.sh` was first given `mu/a.pdf` and
  `ff/f.ttf` where the state root already ends in `mu`/`ff`, and printed empty sizes; the two
  lines were corrected and the whole script re-run. The 23 rows ran before the nine (two commits,
  `6a631ed` and `110c92f`), with the prediction unchanged between them.
