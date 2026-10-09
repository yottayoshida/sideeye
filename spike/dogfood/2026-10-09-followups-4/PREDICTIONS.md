# Predictions — 2026-10-09 follow-ups 4

Written before each run. The fourth "おわり？": the three targets left waiting on #678 (the restore does not
rebuild modes or owners) were said to be beyond any define on 2026-10-03, but a FAT filesystem has no
per-file mode or owner — its mount gives every file the same ones — so the restore cannot change what the
target sees.

| target | step | prediction |
|---|---|---|
| upx 5.2.1 `-q prog` | state on FAT, `fmask=0022` (every file 0755) | past `recording_run_failed`; FAIL or PASS by how upx replaces its input (it writes a temporary and renames: PASS) |
| argocd 3.5.3 `context work` | state on FAT, `fmask=0177` (every file 0600) | past it; FAIL (the config rewritten with `os.WriteFile`) |
| arkenfox prefsCleaner.sh 2.1, `--observe supervised` named | state on FAT, `uid=1000` (every file the user's) | past the second run's owner difference; FAIL (prefs.js moved to the backup, then written; a crash between leaves no prefs.js, though the backup holds it) |
| lz4 1.10.0 | its full help read for a switch beside `-T#` | none |
| lz4 `-T1 -BD` (dependent blocks cannot be compressed in parallel) | the page's path | still `multiple_threads_detected` (a guess: the I/O may have its own thread) |

## Round 2: who the second writer is, behind the threads wall

Follow-ups 3 left seven targets at `multiple_threads_detected` with their one-thread switch set, and two
Python ones with none tried. The README judges threads "where a creation or a join the shim saw orders
their writes", so the question for each is which threads write the state and whether a switch the tool
documents stops one of them. Measured with `strace -f` on the state's paths, outside Sideeye
(`apparatus/writers.sh`); a switch found is then explored on the page's path.

| target | prediction |
|---|---|
| gemini-cli 0.62.0, vercel 62.2.0, Bitwarden CLI 2026.8.0 (`UV_THREADPOOL_SIZE=1`) | two writers: the main thread with Node's synchronous calls, and libuv's one pool thread with the asynchronous ones. No switch moves one to the other: still a wall |
| OpenTofu 1.13.1 (`GOMAXPROCS=1`) | the state's writes spread over several of the Go runtime's threads, as a blocking call hands its P on. No switch: still a wall |
| electrum 4.8.2 `--offline` | the wallet written from the asyncio loop's own thread, beside the main one. No switch |
| basic-memory 0.23.2 | the note from one thread, the SQLite index from aiosqlite's connection thread. No switch |
| goaccess 1.12 `--persist` (read, not run) | the shared mapping is the tpl library's, which writes every database file through one: no switch |
| rrdtool 1.9 `update` (read, not run) | the mapping is compiled in (`HAVE_MMAP`); no switch at run time |

After the first measurement (`transcripts/writers.txt`): gemini-cli's second thread writes only the home's
registry (`projects.json` with its lock, `tmp/`, `history/`), and `mcp add` at its default scope, project,
writes the project's `.gemini/settings.json` from the main thread alone. On the way, an untrusted folder
(the default) had that file wiped down to the new server: gemini-cli #29465, known, fixed on its main by
#29583 after 0.63.0 (`transcripts/lab-2.txt`). So the define trusts the folder, in the home, outside the state.
OpenTofu's writes stayed on one thread in four strace runs, where follow-ups 3's supervised run had two.

| target | step | prediction |
|---|---|---|
| gemini-cli 0.62.0 `mcp add` at the project scope, folder trusted | the page's path | past the threads wall; FAIL (`settings.json` truncated before its write, on the main thread) |
| OpenTofu 1.13.1 `state rm`, `GOMAXPROCS=1` | `--observe supervised` twice more | `multiple_threads_detected` both times: each call waits on the engine long enough for the runtime to hand its P to another thread |

Follow-ups 3 wrote that the four Rust targets' second writer is tokio's blocking pool, but never measured
who writes. If it is a log writer, a switch that turns logging off would remove it, so they are measured too.

| target | prediction |
|---|---|
| rustic 0.11.4, prek 0.5.5, codex 0.160.0, steamguard-cli 0.18.4 (`RAYON_NUM_THREADS=1 TOKIO_WORKER_THREADS=1`) | the state written from a tokio blocking-pool thread beside the main thread (or a worker); no log writer among them, and no switch |

After measuring them (`transcripts/writers.txt`): no log writer. rustic deletes on rayon's one worker while
the main thread writes the new index; prek renames the old hook aside on one thread and writes the new one
on another; steamguard writes the manifest and the account file from two. codex writes `config.toml` from
one thread, and the other two make and clear `tmp/arg0`, its directory of command-name links.

| target | step | prediction |
|---|---|---|
| codex 0.160.0 `mcp add` | `tmp` declared scratch | still `multiple_threads_detected`: a guess that the gate counts every write in the judged directory, scratch or not |

## Round 3: easy-rsa under supervised

The recount before the PR found one wall with a step never tried. easy-rsa 3.2.7 `revoke` was refused
`child_touched_state_dir` (openssl, sed and mv write the PKI), and the next step, `--observe syscalls`, ended
`recording_run_failed` with the clock pinned: libfaketime's preload met that mode's `SIGSYS` trap. Under
`--observe supervised` no shim is loaded and the filter notifies the engine instead of trapping, and this round's
prefsCleaner FAILed there with `mv` children writing, so children are counted.

| target | step | prediction |
|---|---|---|
| easy-rsa 3.2.7 `revoke c1`, the clock pinned (2026-10-07's define) | `--observe supervised` named | past both walls; FAIL — `openssl ca` renames `index.txt` to `index.txt.old` and then `index.txt.new` in, and a kill between leaves no `index.txt`, its old bytes whole in `index.txt.old` |
