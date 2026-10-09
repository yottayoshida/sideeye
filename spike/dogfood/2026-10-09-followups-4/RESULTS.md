# Results — 2026-10-09 follow-ups 4

The fourth "おわり？" of the day, in two rounds. The first takes the three targets left waiting on #678 (the
restore does not rebuild modes or owners) onto a FAT filesystem, whose mount gives every file one mode and one
owner, so the restore cannot change what the target sees; and lz4 once more. The second asks, for every target
still behind the threads wall, which threads write the state — measured with `strace -f` outside Sideeye
(`apparatus/writers.sh`, `writers.py`) — and whether a switch the tool honours stops one of them; the
shared-mapping and `fallocate` walls are read in their sources. Released **v1.10.0** in one box
(`apparatus/Dockerfile`, built three times). Predictions were committed before each run (`2abe13a`, `60e1298`,
`2852e4b`, `c6f4547`, `ac34121`, `d7e3b53`).

**Seven targets run through Sideeye: 5 FAIL, 2 still behind a wall; none filed.** Seven more measured only with
strace, and four read in their sources (easy-rsa is unchanged), each with the reason no switch moves them.

## Round 1: #678's three on FAT, and lz4

| target | step | result |
|---|---|---|
| upx 5.2.1 `-q prog` (static; `--observe supervised`, the next step) | FAT, `fmask=0022`: every file 0755 | **FAIL** 1/35, crash point 34 of 34 — `prog` unlinked, and the kill before `prog.upx` is renamed in: `prog` absent, the packed program whole in `prog.upx` (564416 bytes). Replayed twice. The prediction (PASS) missed: upx renames into place, but removes the original first |
| argocd 3.5.3 `context work` (static Go; supervised, the next step) | FAT, `fmask=0177`: every file 0600 | **FAIL** 1/3 — `config` truncated before its write (412 → 0 bytes). Replayed twice |
| arkenfox prefsCleaner.sh 2.1 `-s -d` through `setpriv` (`--observe supervised` named) | FAT, `uid=1000,gid=1000`: every file the user's | **FAIL** 5/8, crash point 3 of 7 — `prefs.js` renamed into `prefsjs_backups/`, and the kill before the new one is opened: `prefs.js` absent, its old bytes whole in the backup. Replayed twice (`apparatus/replay-supervised.sh`) |
| lz4 1.10.0 | its full help read for a switch beside `-T#` (`transcripts/lab-1.txt`) | none |
| lz4 `-T1 -BD` (dependent blocks are not compressed in parallel) | the page's path | **UNKNOWN `multiple_threads_detected`** under syscalls (`oracle_missed_operation` by default, the next step). Round 2 names the writer |

## Round 2: who writes behind the threads wall

`transcripts/writers.txt` per target. `writers/<target>/writers.state.strace` keeps the capture's lines that
name the state or make a thread, and `writers.py` reads the same account from it as from the whole capture (all
sixteen compared); the whole captures went out of the tree with the explores' work directories
(`apparatus/keep-cases.sh`, the five FAILs' cases kept). The second writer is what the README asks about:
threads are judged "where a creation or a join the shim saw orders their writes".

| target | the writers | a switch | result |
|---|---|---|---|
| gemini-cli 0.62.0 `mcp add -s user` (`UV_THREADPOOL_SIZE=1`) | the main thread writes `settings.json` in place; libuv's pool thread writes only the home's registry: `projects.json` under a lock directory, `tmp/`, `history/` | `mcp add` at its **default scope, project**, writes the project's `.gemini/settings.json` from the main thread, and the registry stays in the home, outside the state | **FAIL** 1/3 at the project scope, folder trusted — `settings.json` truncated before its write (87 → 0 bytes), the old bytes nowhere. Replayed twice |
| vercel 62.2.0 `telemetry disable` | the main thread writes everything; the pool thread's one call is `mkdirp(VERCEL_DIR)` at the top of `main`, for every command, failing `EEXIST` | `NO_UPDATE_NOTIFIER` stops the version-check child, not that call (`dist/index.js`, traced with a `--require` hook: `apparatus/trace-mkdir.cjs`, `transcripts/lab-4.txt`) | wall |
| Bitwarden CLI 2026.8.0 `config server` | the main thread writes `data.json`; the pool thread makes and removes `data.json.lock`, proper-lockfile's lock | none: the CLI constructs its storage with `requireLock` true (`transcripts/lab-5.txt`) | wall |
| OpenTofu 1.13.1 `state rm` (`GOMAXPROCS=1`) | one Go thread wrote the state in four of four strace runs; under supervised, two in follow-ups 3 and in one run of two here (`transcripts/tofu-supervised.txt`) | none | **FAIL** 1/10, crash point 7 of 9, on the run where one thread wrote — `terraform.tfstate` truncated before its write, its old bytes whole in the timestamped `.backup` written first. **Both replays refused `multiple_threads_detected`**: another thread wrote on those runs. With strace's injection on the state's first `write` the same state comes back without Sideeye; `tofu state list` then reports no state, and copying the backup back restores all three resources (`transcripts/lab-3.txt`) |
| electrum 4.8.2 `--offline setlabel` | the main thread writes a read/write test file beside the wallet (`test_read_write_permissions`); the `EventLoop` thread writes the wallet (temporary, `fsync`, rename) | none: the event loop runs on a thread of its own (`lab-5.txt`) | wall |
| basic-memory 0.23.2 `edit-note` | aiofiles' executor thread writes `Plans.tmp`; the event loop renames it in (`lab-5.txt`) | none | wall |
| rustic 0.11.4 `forget --prune` (`RAYON_NUM_THREADS=1`) | the main thread writes the new index (temporary, `fsync`, rename); rayon's one worker deletes the old snapshot and index files | none | wall |
| prek 0.5.5 `install` | one thread renames the hand-written hook to `pre-commit.legacy`, another writes the new one | none | wall |
| codex 0.160.0 `mcp add` (supervised) | one thread writes `config.toml` (temporary, rename); two others make and clear `tmp/arg0`, the links codex sets up at every start | `tmp` declared scratch | **UNKNOWN `multiple_threads_detected`**: the pair named was a link in `tmp/arg0` and the config thread's `mkdir` of the state root, failing `EEXIST` |
| steamguard-cli 0.18.4 `decrypt` | `manifest.json` from the main thread, `alice.maFile` from another | none | wall |
| lz4 1.10.0 `-T1 -BD --rm` | the main thread writes the frame header; an I/O thread writes the blocks | none: `-T#` is its only thread switch | wall |

**On the way:** at the project scope in a folder not trusted — the default — `gemini mcp add` wiped the
project's `.gemini/settings.json` down to the new server, with no crash (`transcripts/lab-2.txt`; trusted, with
folder trust off, or at the user scope it merges). Known: gemini-cli #29465 (2026-09-23, another reporter),
fixed on its main by #29583 (2026-10-06), which neither 0.62.0 nor the stable 0.63.0 contains. Hence the
define trusts the folder, in the home, outside the state.

## Read in the sources, not run

The lines read are in `transcripts/sources.txt`.

| target | why no switch moves it |
|---|---|
| goaccess 1.12 `--persist` | every database goes through `close_tpl`: tpl's `tpl_dump` maps a `.tmp` file `PROT_READ\|PROT_WRITE, MAP_SHARED`, writes, `msync`s, and goaccess renames it in. The shared mapping is the only path |
| rrdtool 1.9.0 `update` | `rrd_open` maps the file `MAP_SHARED` with `PROT_WRITE` whenever built with `HAVE_MMAP`, and reads no environment; `--daemon` hands the write to rrdcached, which opens it the same way |
| flatpak 1.16, ostree (libglnx) | `glnx_file_replace_contents_with_perms_at` calls `glnx_try_fallocate` for every non-empty file on every filesystem, ignoring only `ENOSYS` and `EOPNOTSUPP` — so Sideeye meets the call whatever it returns |
| easy-rsa 3.2.7 | unchanged: openssl, sed and mv write the PKI as children |

## The predictions, against what was measured

Missed: upx (PASS predicted; it removes the original before the rename); gemini-cli (no switch predicted; its
default scope is one); OpenTofu under strace (writes spread over threads predicted; one thread in four runs) and
under supervised (refused both times predicted; one run of two reached a FAIL); basic-memory (an SQLite index
predicted as the second writer; the index lives outside the state, and the second writer is aiofiles').
Held: argocd and prefsCleaner FAIL; lz4 still threads; vercel, Bitwarden and electrum as predicted; no log
writer among the Rust four, and no switch; codex refused with its scratch; gemini-cli FAILs at the project
scope; goaccess and rrdtool as read.

## Not filed, with the reason

upx: a rename restores the program the run was writing (iconvert's shape). argocd and gemini-cli: settings a
user re-enters (its tracker's #29307 is the same class for `state.json`). prefsCleaner and OpenTofu: a backup
written first holds the old bytes.

## What the round says about Sideeye v1.10.0

- **The threads gate counts a call that failed and changed nothing**: vercel's only second-thread call is a
  `mkdir` of the state root that returns `EEXIST`, and codex's named pair included the same call. A failed
  `mkdir` leaves the state as it was, so its order against another thread's writes cannot change a world.
- **The threads gate counts a scratch path's writes**: codex with `tmp` declared scratch is refused on a
  link in `tmp/arg0`.
- **A FAIL can be reached on a schedule that does not come back**: OpenTofu's explore judged on a run where
  one thread wrote, and both replays refused. The FAIL's state is real (strace's injection), and the replays
  said why they could not repeat it — the README's limit at work, not a wrong verdict.
- **Behind the threads wall, the second writer is the tool's design, not a pool size**: a lock, a registry,
  a test write, a delete pool, an I/O thread. Of eleven targets one moved, by writing a different file
  (gemini-cli's project scope), and OpenTofu reached a verdict only on a schedule that did not repeat, where
  follow-ups 3 moved nineteen by sizing a pool.
