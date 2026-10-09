# Results — 2026-10-09 follow-ups 3

The third "おわり？" of the day. The second recount (`2026-10-09-followups-2`) had left 49 unjudged targets
as "behind walls v1.10.0 does not move", and two kinds of them were measurable after all: the threads
wall had never been asked whether the target's own switch for one thread moves it, and five targets that
cleared a gate in earlier campaigns had been set aside before their explore for reasons about filing, not
about measuring. Released **v1.10.0** in one box (`apparatus/Dockerfile`, built five times). Predictions
were committed before each run (`7033f95`, `b4f5f27`, `7a74533`, `56b7e20`, `8d52929`, `3704d22`, `bf9e550`, `67cd268`, `d071e97`).

**41 targets: 18 FAIL, 11 PASS, 12 still behind a wall.** One filed upstream with the owner's approval:
**dotenvx/dotenvx#1012**. And SubtitleEdit/subtitleedit#15829 was closed by its maintainer's fix (PR #15833,
merged as a merge commit whose parent is the head this project measured in `2026-10-09-followups-2`; the
seven commits beside it touch only the GUI), so that PASS is the landed fix's.

## The threads wall, with each tool's switch for one thread

`UV_THREADPOOL_SIZE=1` puts libuv's file calls on one thread; for yarn and trash-cli the gate stopped
answering `multiple_threads_detected` (`transcripts/lab-1.txt`). Then for every Node target the wall had
refused, and `GOMAXPROCS=1` for the Go ones, the documented switches for zstd (`--single-thread
--no-asyncio`), lz4 (`-T1`) and beets (`threaded: no`), and `RAYON_NUM_THREADS=1 TOKIO_WORKER_THREADS=1`
for the Rust ones:

| target | result |
|---|---|
| yarn 4.18.1 `config set` | **FAIL** 1/3 — `.yarnrc.yml` truncated before its write |
| trash-cli 7.2.0 `trash` | **PASS** 9/9 |
| bibtex-tidy 1.15.1 | **FAIL** 1/3 — `refs.bib` |
| dotenvx 2.32.4 `encrypt` (`.env` and `.env.keys` scratch, `dotenvx get` as checker) | **FAIL** 1/5 — `.env` emptied after `.env.keys` is written: the values gone. Reproduced without Sideeye (`lab-2.txt`); **filed: dotenvx/dotenvx#1012** |
| glTF-Transform 4.5.1 `weld` onto its input | **FAIL** 1/3 — `terrain.glb` |
| cspell 10.3.6 `link add` (Node 22) | **FAIL** 1/4 — `cspell.json` |
| capacitor 8.5.2 `telemetry off` (Node 22) | **FAIL** 1/4 — `sysconfig.json` |
| eslint 10.11.0 `--fix` | **FAIL** 1/3 — `a.js` |
| prettier 3.9.7 `--write` | **FAIL** 1/3 — `a.js` |
| stylelint 17.15.0 `--fix` | **PASS** 6/6 |
| svgo 4.1.0 | **FAIL** 1/4 — `a.svg` |
| npm 9.2.0 `pkg set` | **FAIL** 1/3 — `package.json` |
| joplin 3.7.1 `mknote` (`database.sqlite`, `log.txt` and `tmp` scratch, `joplin ls` as checker) | **PASS** 49/49. The first checker passed `TestBook` to `ls`, a note pattern there, and refused the finished state; the second form FAILed on the profile's `tmp` directory alone |
| gemini-cli 0.62.0, vercel 62.2.0, Bitwarden CLI 2026.8.0 | **UNKNOWN `multiple_threads_detected`** with one libuv thread too |
| lingui 6.9.0 `extract` (Node 22) | `child_touched_state_dir`, with `--workers 1` too: `lingui.js` runs `lingui-extract.js` as a child node, and the child writes (`lab-3.txt`). With that script invoked directly, **FAIL** 3/7 — the English `messages.po` truncated before its write. Its dependencies as npm resolves them today need Node 22 (`fs.globSync`), which 2026-10-05 did not |
| doctl 1.177.0 (supervised, `GOMAXPROCS=1`) | **FAIL** 1/3 — `config.yaml` |
| infracost 0.10.46 (supervised, `GOMAXPROCS=1`, `.state.json` scratch) | **FAIL** 1/5 — `credentials.yml` |
| plakar 1.1.7 (supervised, `GOMAXPROCS=1`, the state files scratch, `plakar` as checker) | **PASS** 6/6 |
| OpenTofu 1.13.1 (supervised, `GOMAXPROCS=1`) | **UNKNOWN `multiple_threads_detected`** |
| zstd 1.5.7 `--rm` | `--single-thread` alone still met threads: zstd writes through an I/O thread by default. With `--no-asyncio` too it was `nothing_could_fail` (a new file, the input removed), and with a checker on the data **PASS** 8/8 |
| lz4 1.10.0 `-T1 --rm` | **UNKNOWN `multiple_threads_detected`**: no switch for its I/O |
| beets 2.1.0 `import` (`threaded: no`, `library.db` scratch, 2026-10-02's checker) | **PASS** 43/43 |
| rustic 0.11.4, prek 0.5.5, codex 0.160.0, steamguard-cli 0.18.4 | **UNKNOWN `multiple_threads_detected`**: one rayon and one tokio worker leave the blocking pool |

Not tried: electrum and basic-memory (Python threads with no switch for one).

## The last walls, one switch or one filesystem further

| target | step | result |
|---|---|---|
| vim 9.1 `%s` and `wq` (`nowritebackup`) | the state on a FAT filesystem: no ACL there, so no `setxattr` (`lab-4.txt`) | **FAIL** 1/12 — `a.txt` truncated before its write |
| Kvantum 1.1.4 `--set` | FAT: Qt's `O_TMPFILE` open fails `EOPNOTSUPP` and it saves through a named temporary | **PASS** |
| Hydrogen 1.2.2 `h2cli -u` | FAT, `drumkit.xml` scratch (its attribute order varies), a checker reading the kit | **FAIL** 1/9 — `drumkit.xml` truncated before its write; the dated backup h2cli writes first holds the old bytes |
| flatpak 1.16 `override --user`, ostree (Debian) `remote add` | FAT: libglnx's named-temporary fallback | **UNKNOWN `unsupported_syscall_observed`** on `fallocate`, which the fallback calls |
| ccache 4.11 `gcc -c` | `CCACHE_NOSTATS=1`: no stats file in a random subdirectory | **UNKNOWN `nothing_could_fail`**: the operation only creates cache files, and the checker on its objects was `checker_not_falsified` — ccache rebuilds a damaged entry itself, so nothing about its output can fail |
| astropy 8.0.1 `fitscheck -w` | `use_memmap = False` in astropy's configuration | **FAIL** 1/6 — `obs.fits` torn between two writes of its header |
| ROOT 6.40.04 `rootrm data.root:h2` | `--observe supervised` named (the shim breaks it, #753), `data.root` scratch (a random UUID in every run), `rootls` as checker | **PASS** 11/11 |

## Five that cleared a gate and were never explored

| target | result |
|---|---|
| DokuWiki 2026-07-14c page save | **FAIL** 5/31 — `pages/wiki/start.txt` truncated before its write. Not filed: its tracker's #677 is this |
| Lighthouse 8.2.3 validator definitions | **PASS** 8/8 |
| jump 0.69.0 (supervised) | **PASS** 13/13 |
| keyring 25.7.0 with keyrings.alt 5.0.2's plaintext file | **FAIL** 1/3 — `keyring_pass.cfg`. Not filed: the write is keyrings.alt's (29 stars) |
| git-lfs 3.8.0 `install` | **PASS** 18/18 — not the `git config` child's wall predicted |

## Not filed, with the reason

yarn, cspell, capacitor, doctl, infracost: settings and keys a user re-issues. eslint, prettier, svgo, npm,
bibtex-tidy: files that live under version control. glTF-Transform: in place only when the output names
the input. DokuWiki: known. keyring: below rule 1. vim: no backup was the user's choice. Hydrogen: its backup holds the old bytes. fitscheck: the default path, a shared mapping, is not what was measured. lingui: catalogs under version control.

## What the round says about Sideeye v1.10.0

- **`multiple_threads_detected`'s next step names the README's limit and nothing a user can try**, and for
  nineteen targets a switch the tool or its runtime documents was enough to get past it: libuv's thread pool for Node,
  `GOMAXPROCS` for three Go tools of four, zstd's `--no-asyncio`, beets' `threaded: no`. The step could
  say that a pool size or an I/O thread is often the second writer.
- **`fallocate` is a wall of its own**: flatpak and ostree, moved off `O_TMPFILE` by a FAT filesystem, reserve space with it in libglnx's fallback.
- **A tool that repairs its own cache leaves nothing to judge**, and Sideeye says so: ccache with its stats off is `nothing_could_fail`, and a checker on its output was refused as not falsifiable.
- **Three more of my own checkers were wrong**: joplin's, xmake's (#756) and ccache's (refused as not falsifiable). joplin's was caught as
  `baseline_violates_invariant`, since it refused the finished state; xmake's refused only the untouched
  one and read as a FAIL.
