# Results — 2026-10-09 user-data-4

Twenty-two targets in four waves (`SELECTION.md`: the owner asked for five in each of four; the last
screen cleared five at once, and every target that cleared the gate was explored, so the fourth wave has
seven), each explored by `apparatus/run.sh` in a box of its own with **the released v1.10.0**
(`apparatus/explore.sh`; engine lines in `transcripts/explore/<t>/engine.txt`). Default mode first; where
the refusal's next step named `--observe supervised` or `--observe syscalls`, it was followed once. Every
FAIL was replayed twice and its evidence bundle written. Built-in atomicity rule unless a checker is named.
`transcripts/verdicts.txt` is `apparatus/verdicts.py`'s reading of the engine's own JSON.

**14 FAIL, 7 PASS, 1 UNKNOWN on the page's path** (iconvert: FAIL with `--observe supervised` named).
Ten FAILs are the truncating open and the kill before the write, eight of them in a user config file a
command rewrites (scw, nmctl, stack, carapace, zvm, fly, kafkactl, CKAN's compatible versions) and two in a
user's document written back over its input (seconv's subtitle, otiotool's timeline). The other FAILs:
MCA Selector and iconvert remove the original before renaming its replacement in, cabal renames the original
aside first, f2 leaves a half-renamed batch, chdman a CHD with an unreferenced tail. Five of the seven PASSes
write a temporary file and rename it (cookcli, buildx, ifcpatch, atac, rpk); libdeflate-gzip writes a new
file and removes its input, and hunspell appends.

**Two reports filed upstream, with the owner's approval of each full text.** The bar is 2026-09-07's, as
2026-10-07 applied it: a report goes out only for data the user cannot get back, from the tool's own
documented command. Two FAILs meet it. Subtitle Edit's `seconv --overwrite` (the documented in-place option,
the codespell and rubocop axis of 2026-09-16) empties the subtitle it converts. MCA Selector's chunk deletion
leaves the region file absent and its replacement only in the system temp directory — though its README's
first warning is to back up the world, the reading that closed `oxipng#873`. Both are reproduced without
Sideeye by strace's `inject`, against the current upstream source, and filed as SubtitleEdit/subtitleedit#15829
(`report-seconv.md`) and Querz/mcaselector#613 (`report-mcaselector.md`). The rest lose settings and keys a user re-issues (2026-10-05's precedent for
`config set`), or nothing a rename, a reader or the tool's own command does not restore.

The run also found a defect in Sideeye itself (below), filed as #753: the shim answers -1 for calls made before
its own initialisation, which is what aborted iconvert and ROOT.

## Wave 1

| target | verdict | where | report |
|---|---|---|---|
| scw 2.65.1 `config set default-region=fr-par` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `config.yaml` opened truncating and the kill before its write: 140 → 0 bytes; the file where scw keeps a profile's access and secret keys | not filed: settings and keys a user re-issues (2026-10-05's precedent for `config set`) |
| f2 2.2.2 `-f IMG_ -r trip_ -x` | **FAIL** 2/4, crash point 2 of 3 (supervised, checker) | killed between the first and second rename: `trip_1.jpg` beside `IMG_2.jpg` and `IMG_3.jpg`, a half-renamed batch. Its undo record is written after the renames (`lab-1.txt`), so a batch killed part-way leaves none for `f2 -u` | not filed: every photo's bytes are whole under one name or the other |
| SeConv (Subtitle Edit) 5.2.0 `subs.srt subrip --offset:-2000 --overwrite` | **FAIL** 1/4, crash point 3 of 3 | `subs.srt` opened, `ftruncate` to 0 and the kill before its write: 175 → 0 bytes, the old text nowhere. Reproduced without Sideeye by `strace -P … -e inject=pwrite64:signal=KILL` (`lab-19.txt`, `lab-21.txt`); `main` writes the same way (`File.WriteAllText` in `SaveTextFormat`) | **SubtitleEdit/subtitleedit#15829** (`report-seconv.md`) |
| OpenTimelineIO 0.18.1 `otiotool -i cut.otio --redact -o cut.otio` | **FAIL** 1/3, crash point 2 of 2 | `cut.otio` opened truncating and the kill before its write: 5,208 → 0 bytes | not filed: in place only when `-o` names the input, which the tutorial does not do (2026-10-07's TiddlyWiki reading) |
| cookcli 0.38.0 `pantry add dairy eggs --quantity 6` | **PASS** 6/6 (supervised) | `.pantry.conf.<pid>.tmp` written, `fsync`ed and renamed over `pantry.conf` — the shape its tracker's `#431` moved the shopping list to | — |

## Wave 2

| target | verdict | where | report |
|---|---|---|---|
| MCA Selector 2.9 `--mode delete --query "InhabitedTime < 1000"` | **FAIL** 1/3, crash point 2 of 2 | the new region written to `/tmp`, then `unlink` of `region/r.0.0.mca`, and the kill before the rename: the region file absent (32,768 bytes before), its replacement only in `/tmp/r.0.0.mca<digits>.tmp`. The JDK's `Files.move(…, REPLACE_EXISTING)` unlinks the target before it renames (OpenJDK's `UnixFileSystem.move`), and copies instead when `/tmp` is another filesystem. Reproduced without Sideeye (`lab-20.txt`, `lab-21.txt`); `master` saves the same way | **Querz/mcaselector#613** (`report-mcaselector.md`); the README's first warning asks for a backup of the world, and the report says closing it is fine |
| netmaker's nmctl 1.7.0 `context set c1 …` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `config.yml` opened truncating and the kill before its write: 75 → 0 bytes, every context and its master key | not filed: endpoints and keys a user re-issues |
| libdeflate 1.26 `libdeflate-gzip notes.txt` | **PASS** 4/4 with a checker (`defines/libdeflate/check.sh`: the text survives in `notes.txt` or inside `notes.txt.gz`) | `notes.txt.gz` created `O_EXCL`, one write, close, then `unlink` of the input; no `fsync`. Without the checker it was `nothing_could_fail` (`explore/libdeflate-nocheck/`): no path exists before and after | — |
| stack 3.11.1 `config set install-ghc false --global` | **FAIL** 1/117, crash point 116 of 116 (supervised; the SQLite caches scratch) | `config.yaml` opened without `O_TRUNC`, truncated and the kill before its write: 255 → 0 bytes | not filed: settings |
| cabal-install 3.18.2.0 `user-config update -a 'jobs: 4'` | **FAIL** 2/4, crash point 2 of 3 (supervised) | `config` renamed to `config.backup`, and the kill before the new file is renamed in from TMPDIR: `config` absent, its old bytes whole in `config.backup` | not filed: a rename restores it |

## Wave 3

| target | verdict | where | report |
|---|---|---|---|
| carapace-bin 1.8.0 `--style carapace.Error=red` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `styles.json` opened truncating and the kill before its write: 77 → 0 bytes | not filed: styles |
| chdman (MAME 0.276, Debian) `addmeta -i d.chd -t NOTE -vt hello` | **FAIL** 2/5, crash point 3 of 4 | the metadata entry appended past the end, and the kill before the header's pointer is rewritten: `d.chd` 1,052,688 bytes, neither old nor new | not filed: the same state made by `strace -P … -e inject=pwrite64:signal=KILL:when=2` (1,052,688 bytes) still opens in `chdman info`, and `chdman extractraw` returns the raw data byte for byte (`lab-22.txt`) |
| hunspell 1.7.5 `-a -d en_US -p my.dic` (through `sh -c` and a file of commands) | **PASS** 3/3 | `my.dic` opened `O_APPEND`; the report's atomicity line: "1 file(s) judged by the history form (appended tails not judged)" | — |
| buildx 0.38.0 `create --append --name b1 --node b1x …` (remote driver) | **PASS** 14/14 (supervised; `activity` scratch) | `instances/b1` through `.tmp-b1<n>` created `O_EXCL`, `fsync`ed and renamed | — |
| zvm 0.9.1 `vmu zls https://example.org/zls-index.json` | **FAIL** 2/5, crash point 2 of 4 (supervised) | `settings.json` opened truncating, twice, and the kill before the first write: 331 → 0 bytes | not filed: settings |

## Wave 4

| target | verdict | where | report |
|---|---|---|---|
| OpenImageIO 2.5.18 (Debian) `iconvert --inplace --caption hello --keyword k photo.jpg` | **UNKNOWN** `recording_run_failed` on the page's path (SIGABRT; with only the shim preloaded, by hand, iconvert and oiiotool both end `std::system_error` "Unknown error -1" and abort, `--threads 1` or not; `lab-3.txt`); **FAIL** 1/7, crash point 6 of 6 with `--observe supervised` named (`explore/iconvert/probe-supervised.*`) | `photo.jpg.tmp.jpg` written, `photo.jpg` removed, and the kill before the rename: `photo.jpg` absent, the new image whole beside it. Upstream `main`'s `iconvert.cpp` removes and renames in the same order | not filed: a rename restores the image the run was writing |
| IfcOpenShell's ifcpatch 0.9.0 `-i model.ifc -r Optimise` (clock pinned) | **PASS** 48/48 | `model.ifc.<n>.tmp` opened truncating and renamed over `model.ifc`; no `fsync` | — |
| Concourse's fly 8.3.1 `-t ci edit-target --team-name t2` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `.flyrc` opened truncating and the kill before its write: 185 → 0 bytes, every target and its token | not filed: targets and tokens a user logs in again for |
| ATAC 0.23.1 `request new demo/pong …` | **PASS** 8/8 (supervised; `atac.log` scratch) | `demo.json_` written and renamed over `demo.json`, twice; no `fsync` | — |
| CKAN 1.36.4 `compat add 1.7` (Mono) | **FAIL** 1/3, crash point 2 of 2 | `compatible_ksp_versions.json` opened truncating and the kill before its write: 81 → 0 bytes | not filed: the versions a user lists again |
| rpk (Redpanda) 26.2.2 `profile use a` | **PASS** 4/4 (supervised) | a temporary name written and renamed over `rpk.yaml`; no `fsync` | — |
| kafkactl 5.20.0 `config use-context b` | **FAIL** 1/4, crash point 2 of 3 (supervised) | `current-context.yml` opened truncating and the kill before its write: 19 → 0 bytes | not filed: a setting |

## Walls at the gate

| target | refusal | where |
|---|---|---|
| arkenfox prefsCleaner.sh 2.1 (through `setpriv`) | `child_process_detected` | the script refuses root and root-owned files, so the define drops to a user; the shim's chain through that exec breaks. Under `--observe supervised`, `--twice` ended differently (owners, #678) |
| yarn 4.18.1 `config set` (Node 20) | `multiple_threads_detected` | — |
| sindresorhus's trash-cli 7.2.0 `trash` (Node 20) | `multiple_threads_detected` | — |
| softhsm2-util 2.6.1 `--import` | `--twice` differs | each object and lock named by a random UUID |
| Kvantum 1.1.4 `kvantummanager --set` | `unresolvable_path` | an unlinked-fd write: Qt's save through `O_TMPFILE` |
| Hydrogen 1.2.2 `h2cli -u` | `unresolvable_path` | the same |
| ROOT 6.40.04 `rootrm` | `recording_run_failed` (SIGABRT) | the shim defect below; under `--observe supervised`, `--twice` differs (a random UUID written into the file) |

iconvert met the same refusal as rootrm on the page's path and is in the slate, judged with supervised named.

## What the run says about Sideeye v1.10.0

- **The shim breaks a target whose libraries call an interposed function from their own constructors.**
  Filed as #753. OpenImageIO's iconvert and conda-forge's ROOT both abort under the shim and exit 0 by hand. Ten lines of
  C++ reproduce it (`apparatus/lab-24.sh`, `transcripts/lab-24.txt`): a `std::thread` started from a shared
  library's static constructor ends `std::system_error` "Unknown error -1" with the shim preloaded, and a
  `std::ifstream` of `/dev/urandom` read from one fails; started from `main`, the thread runs. Under the
  shim, iconvert's abort comes with no `clone` reaching the kernel (`lab-23.txt`). The shim resolves the
  real functions in its own `.init_array` (`resolveAll` in `shim/src/common.zig`), and its call-through
  sites answer -1 while a symbol is unresolved — 39 of them `orelse return -1`, `pthread_create` among
  them, whose callers expect an error number, not -1. Another library's constructor can run first. Not in
  the tracker before #753 (searched by `init_array`, `constructor`, `Unknown error -1`). On the page's path the target
  reads `recording_run_failed` whose next step is to run the operation by hand — which succeeds, so the
  step cannot lead past it; `--observe supervised`, which loads no shim, judged iconvert.
- **Qt's save is refused by a class wall.** Kvantum's manager and Hydrogen's h2cli both end
  `unresolvable_path` on "an unlinked-fd write": Qt writes an `O_TMPFILE` and gives it a name afterwards.
  Any Qt application saving its settings or documents this way meets the same refusal.
- **The `nothing_could_fail` next step led to the fix twice.** f2 (a batch rename) and libdeflate-gzip
  (an input replaced by its `.gz`) leave no path that exists before and after; v1.10.0's next step says to
  declare a check or a marker, and a checker turned each into a verdict (FAIL and PASS). f2's first
  checker read names only and was refused `checker_not_falsified` — the falsification gate doing its job.
- **The `reproduce` line runs as printed** (#709): seconv's, pasted twice into a fresh seed, left
  `subs.srt` at 0 bytes both times (`lab-25.txt`).
- **`preload:` takes a basename prefix**, and the refusal says so: a path in `apparatus` was a SETUP ERROR
  naming the form to use (`entry-candidates-11.txt`).
- **The restore does not rebuild owners** (#678): prefsCleaner refuses root, so its define drops to a user
  through `setpriv`; under `--observe supervised` the second run of `--twice` found its files root's and
  refused, and the next step said so.

## Screening, and what it cost

Seven scouts (two of them, 6 and 7, on the model the session moved to after scout 5 hit its usage limit) and
the run's own screens. By the scouts' own counts about 970 names were seen (scout 5's report was cut before its
count; at least 124 are in what arrived); the run's transcripts (`fresh-screen-*.txt`, `word-recheck-*.txt`)
carry the names it checked itself, which is the number the campaign line records. 29 defines reached the gate,
39 gate runs in all (a define fixed and run again counts twice). The box was built eleven times
(`transcripts/build-*.txt`; one more attempt died on a TLS handshake to Docker Hub, `build-fourth-timeout.txt`).
Twenty-five labs (`apparatus/lab-*.sh` where a script was kept, `transcripts/lab-*`), five of them on Sideeye
rather than on a target (16, 17, 23, 24, 25).
